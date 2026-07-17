use std::fs;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use sysinfo::System;
use tauri::Manager;
#[cfg(desktop)]
use tauri::{Emitter, WindowEvent};

mod file_tools;
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

#[cfg(desktop)]
fn show_main_window(app: &tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

#[cfg(desktop)]
fn setup_desktop_integration(app: &tauri::App) -> tauri::Result<()> {
    use tauri::menu::{Menu, MenuItem};
    use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};

    let show = MenuItem::with_id(app, "show", "显示 Congmiao Toolbox", true, None::<&str>)?;
    let palette = MenuItem::with_id(app, "palette", "打开快速搜索", true, None::<&str>)?;
    let privacy = MenuItem::with_id(app, "privacy", "切换 Peek PC 隐私模式", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &palette, &privacy, &quit])?;

    let mut tray = TrayIconBuilder::new()
        .menu(&menu)
        .show_menu_on_left_click(false)
        .tooltip("Congmiao Toolbox")
        .on_menu_event(|app, event| match event.id().as_ref() {
            "show" => show_main_window(app),
            "palette" => {
                show_main_window(app);
                let _ = app.emit("open-command-palette", ());
            }
            "privacy" => {
                let enabled = !peek_server::PRIVACY_MODE.load(std::sync::atomic::Ordering::SeqCst);
                peek_server::PRIVACY_MODE.store(enabled, std::sync::atomic::Ordering::SeqCst);
                peek_server::clear_screenshot_cache();
                let _ = app.emit("peek-privacy-changed", enabled);
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if matches!(
                event,
                TrayIconEvent::Click {
                    button: MouseButton::Left,
                    button_state: MouseButtonState::Up,
                    ..
                }
            ) {
                show_main_window(tray.app_handle());
            }
        });
    if let Some(icon) = app.default_window_icon() {
        tray = tray.icon(icon.clone());
    }
    tray.build(app)?;
    Ok(())
}

#[derive(serde::Serialize)]
struct SystemStats {
    cpu: f32,
    memory_used: u64,
    memory_total: u64,
}

fn peek_server_url(app: &tauri::AppHandle) -> String {
    let config = app
        .state::<peek_server::security::PeekSecurityState>()
        .config();
    let host = if config.listen_scope == "local" {
        "127.0.0.1".into()
    } else {
        local_ip_address::local_ip()
            .map(|ip| ip.to_string())
            .unwrap_or_else(|_| "127.0.0.1".into())
    };
    format!("http://{}:{}", host, config.port)
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
async fn start_peek_server(app: tauri::AppHandle) -> Result<String, String> {
    peek_server::run_server(app.clone()).await?;
    Ok(peek_server_url(&app))
}

#[tauri::command]
async fn stop_peek_server(app: tauri::AppHandle) -> Result<(), String> {
    peek_server::stop_server(&app).await;
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
fn get_peek_server_url(app: tauri::AppHandle) -> String {
    peek_server_url(&app)
}

#[tauri::command]
fn get_peek_monitor_status() -> peek_server::StatusResponse {
    peek_server::monitor_status()
}

#[tauri::command]
fn get_peek_security_state(
    state: tauri::State<'_, peek_server::security::PeekSecurityState>,
) -> peek_server::security::PeekSecuritySnapshot {
    state.snapshot()
}

#[tauri::command]
fn set_peek_server_config(
    config: peek_server::security::PeekServerConfig,
    state: tauri::State<'_, peek_server::security::PeekSecurityState>,
) -> Result<peek_server::security::PeekServerConfig, String> {
    if peek_server::IS_RUNNING.load(std::sync::atomic::Ordering::SeqCst) {
        return Err("请先停止 Peek PC 服务再修改监听配置".into());
    }
    state.set_config(config)
}

#[tauri::command]
fn generate_peek_api_key(
    state: tauri::State<'_, peek_server::security::PeekSecurityState>,
) -> Result<peek_server::security::IssuedApiKey, String> {
    state.generate_api_key()
}

#[tauri::command]
fn get_peek_connection_logs(
    state: tauri::State<'_, peek_server::security::PeekSecurityState>,
) -> Vec<peek_server::security::ConnectionLog> {
    state.logs()
}

#[tauri::command]
fn clear_peek_connection_logs(
    state: tauri::State<'_, peek_server::security::PeekSecurityState>,
) -> Result<(), String> {
    state.clear_logs()
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
            let security = peek_server::security::PeekSecurityState::load(app.handle())
                .map_err(std::io::Error::other)?;
            app.manage(security);
            peek_server::init(app.handle());
            usage_tracker::init(app.handle().clone());
            media_module::start_media_listener(app.handle().clone());
            #[cfg(desktop)]
            setup_desktop_integration(app)?;
            Ok(())
        })
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .manage(AppState {
            sys: Mutex::new(sys),
        })
        .manage(file_tools::FileToolState::default())
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
            get_peek_monitor_status,
            get_peek_security_state,
            set_peek_server_config,
            generate_peek_api_key,
            get_peek_connection_logs,
            clear_peek_connection_logs,
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
            media_module::media_prev,
            file_tools::preview_batch_rename,
            file_tools::preview_file_organize,
            file_tools::execute_file_plan,
            file_tools::list_file_operations,
            file_tools::undo_file_operation,
            file_tools::clear_file_operation_history,
            file_tools::start_duplicate_scan,
            file_tools::cancel_file_job
        ]);

    #[cfg(desktop)]
    let builder = builder
        .plugin(tauri_plugin_notification::init())
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_shortcut("Ctrl+Alt+Space")
                .expect("valid default global shortcut")
                .with_handler(|app, _, event| {
                    if event.state() == tauri_plugin_global_shortcut::ShortcutState::Pressed {
                        show_main_window(app);
                        let _ = app.emit("open-command-palette", ());
                    }
                })
                .build(),
        )
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(
            tauri_plugin_autostart::Builder::new()
                .app_name("Congmiao Toolbox")
                .build(),
        );

    builder
        .on_window_event(|window, event| {
            #[cfg(desktop)]
            if window.label() == "main" {
                if let WindowEvent::CloseRequested { api, .. } = event {
                    api.prevent_close();
                    let _ = window.hide();
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
