use std::fs;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use sysinfo::System;
use tauri::Manager;

mod heartrate;
#[cfg(target_os = "windows")]
mod media_module;
mod peek_server;
mod usage_tracker;

#[cfg(not(target_os = "windows"))]
mod media_module {
    use serde::Serialize;
    use tauri::AppHandle;

    #[derive(Clone, Serialize, Default, Debug)]
    pub struct MediaInfo {
        pub title: String,
        pub artist: String,
        pub is_playing: bool,
    }

    pub fn get_current_media_info() -> MediaInfo {
        MediaInfo::default()
    }

    pub fn start_media_listener(_: AppHandle) {}

    #[tauri::command]
    pub async fn media_play_pause() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn media_next() -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub async fn media_prev() -> Result<(), String> {
        Ok(())
    }
}

struct AppState {
    sys: Mutex<System>,
}

#[derive(serde::Serialize)]
struct SystemStats {
    cpu: f32,
    memory_used: u64,
    memory_total: u64,
}

fn peek_server_url() -> String {
    let my_local_ip = local_ip_address::local_ip()
        .map(|ip| ip.to_string())
        .unwrap_or_else(|_| "127.0.0.1".to_string());
    format!("http://{}:3000", my_local_ip)
}

#[tauri::command]
fn get_system_stats(state: tauri::State<'_, AppState>) -> SystemStats {
    let mut sys = state.sys.lock().unwrap();
    sys.refresh_cpu_usage();
    sys.refresh_memory();
    SystemStats {
        cpu: sys.global_cpu_usage(),
        memory_used: sys.used_memory() / 1024 / 1024,
        memory_total: sys.total_memory() / 1024 / 1024,
    }
}

#[tauri::command]
fn recover_workspace_store(app_handle: tauri::AppHandle) -> Result<Option<String>, String> {
    let app_data_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|error| error.to_string())?;
    let workspace_path = app_data_dir.join("workspace.json");
    if !workspace_path.exists() {
        return Ok(None);
    }

    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_secs();
    let backup_path = app_data_dir.join(format!("workspace.corrupt.{timestamp}.json"));
    fs::copy(&workspace_path, &backup_path).map_err(|error| error.to_string())?;
    fs::remove_file(&workspace_path).map_err(|error| error.to_string())?;
    Ok(Some(backup_path.to_string_lossy().to_string()))
}

#[tauri::command]
async fn start_peek_server() -> Result<String, String> {
    peek_server::run_server().await?;
    Ok(peek_server_url())
}

#[tauri::command]
async fn stop_peek_server() -> Result<(), String> {
    peek_server::stop_server();
    Ok(())
}

#[tauri::command]
fn get_peek_status() -> bool {
    peek_server::IS_RUNNING.load(std::sync::atomic::Ordering::SeqCst)
}

#[tauri::command]
fn toggle_privacy() -> bool {
    let current = peek_server::PRIVACY_MODE.load(std::sync::atomic::Ordering::SeqCst);
    let enabled = !current;
    peek_server::PRIVACY_MODE.store(enabled, std::sync::atomic::Ordering::SeqCst);
    peek_server::clear_screenshot_cache();
    enabled
}

#[tauri::command]
fn get_privacy_status() -> bool {
    peek_server::PRIVACY_MODE.load(std::sync::atomic::Ordering::SeqCst)
}

#[tauri::command]
fn toggle_global_blur() -> bool {
    let current = peek_server::GLOBAL_BLUR_ENABLED.load(std::sync::atomic::Ordering::SeqCst);
    let enabled = !current;
    peek_server::GLOBAL_BLUR_ENABLED.store(enabled, std::sync::atomic::Ordering::SeqCst);
    peek_server::clear_screenshot_cache();
    enabled
}

#[tauri::command]
fn get_global_blur_status() -> bool {
    peek_server::GLOBAL_BLUR_ENABLED.load(std::sync::atomic::Ordering::SeqCst)
}

#[tauri::command]
fn get_peek_server_url() -> String {
    peek_server_url()
}

#[tauri::command]
fn get_peek_privacy_image() -> Option<String> {
    peek_server::get_privacy_image()
}

#[tauri::command]
fn set_peek_privacy_image(path: Option<String>) -> Result<Option<String>, String> {
    peek_server::set_privacy_image(path)
}

#[tauri::command]
fn get_sensitive_app_rules() -> Vec<String> {
    peek_server::get_sensitive_app_rules()
}

#[tauri::command]
fn detect_peek_applications() -> Vec<peek_server::DetectedApplication> {
    peek_server::detect_running_apps()
}

#[tauri::command]
fn set_sensitive_app_rules(rules: Vec<String>) -> Result<Vec<String>, String> {
    peek_server::set_sensitive_app_rules(rules)
}

#[tauri::command]
fn start_hr_scan(app_handle: tauri::AppHandle) {
    heartrate::start_scan(app_handle);
}

#[tauri::command]
fn stop_hr_scan() {
    heartrate::stop_scan();
}

#[derive(serde::Serialize)]
struct HrStatus {
    bpm: u16,
    connected: bool,
}

#[tauri::command]
fn get_hr_status() -> HrStatus {
    HrStatus {
        bpm: heartrate::CURRENT_BPM.load(std::sync::atomic::Ordering::SeqCst),
        connected: heartrate::IS_CONNECTED.load(std::sync::atomic::Ordering::SeqCst),
    }
}

#[tauri::command]
fn set_hr_device_filter(filter: String) {
    heartrate::set_target_device(filter);
}

#[tauri::command]
fn get_hr_device_filter() -> String {
    heartrate::get_target_device()
}

#[tauri::command]
async fn open_hr_overlay(app_handle: tauri::AppHandle) -> Result<(), String> {
    use tauri::WebviewWindowBuilder;
    if app_handle.get_webview_window("hr-overlay").is_some() {
        return Ok(());
    }

    let url = tauri::WebviewUrl::App("index.html#/hr-overlay".into());

    WebviewWindowBuilder::new(&app_handle, "hr-overlay", url)
        .title("♥ Heart Rate Monitor")
        .inner_size(320.0, 200.0)
        .resizable(true)
        .build()
        .map_err(|e| format!("Failed to open overlay: {}", e))?;

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let mut sys = System::new_all();
    sys.refresh_cpu_usage();

    let builder = tauri::Builder::default()
        .setup(|app| {
            peek_server::init(app.handle());
            usage_tracker::init(app.handle().clone());
            media_module::start_media_listener(app.handle().clone());
            Ok(())
        })
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .manage(AppState {
            sys: Mutex::new(sys),
        })
        .invoke_handler(tauri::generate_handler![
            get_system_stats,
            recover_workspace_store,
            start_peek_server,
            stop_peek_server,
            get_peek_status,
            toggle_privacy,
            get_privacy_status,
            toggle_global_blur,
            get_global_blur_status,
            get_peek_server_url,
            get_peek_privacy_image,
            set_peek_privacy_image,
            get_sensitive_app_rules,
            detect_peek_applications,
            set_sensitive_app_rules,
            usage_tracker::get_app_usage,
            start_hr_scan,
            stop_hr_scan,
            get_hr_status,
            set_hr_device_filter,
            get_hr_device_filter,
            open_hr_overlay,
            media_module::media_play_pause,
            media_module::media_next,
            media_module::media_prev
        ]);

    #[cfg(desktop)]
    let builder = builder
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(
            tauri_plugin_autostart::Builder::new()
                .app_name("Congmiao Toolbox")
                .build(),
        );

    builder
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
