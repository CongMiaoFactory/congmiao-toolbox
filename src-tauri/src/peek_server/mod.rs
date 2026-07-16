use active_win_pos_rs::{ActiveWindow, WindowPosition};
use axum::{
    body::Body, http::StatusCode, response::IntoResponse, response::Response, routing::get, Json,
    Router,
};
use screenshots::Screen;
use serde::{Deserialize, Serialize};
#[cfg(target_os = "windows")]
use std::collections::HashMap;
use std::fs;
use std::io::Cursor;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};
use sysinfo::System;
use tauri::{AppHandle, Manager};
use tokio::sync::{oneshot, Mutex as AsyncMutex};
use tower_http::cors::{Any, CorsLayer};

#[cfg(target_os = "windows")]
use windows::core::BOOL;
#[cfg(target_os = "windows")]
use windows::Win32::{
    Foundation::{CloseHandle, HWND, LPARAM, RECT},
    System::Threading::{
        OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32,
        PROCESS_QUERY_LIMITED_INFORMATION,
    },
    UI::WindowsAndMessaging::{
        EnumWindows, GetForegroundWindow, GetWindowRect, GetWindowTextLengthW, GetWindowTextW,
        GetWindowThreadProcessId, IsWindowVisible,
    },
};

const DEFAULT_SCREENSHOT_PROFILE: ScreenshotProfile = ScreenshotProfile {
    blur_radius: 10.0,
    quality: 75,
    scale: 0.5,
};

const CLEAR_SCREENSHOT_PROFILE: ScreenshotProfile = ScreenshotProfile {
    blur_radius: 0.0,
    quality: 75,
    scale: 0.5,
};

const PRIVACY_SCREENSHOT_PROFILE: ScreenshotProfile = ScreenshotProfile {
    blur_radius: 30.0,
    quality: 75,
    scale: 0.25,
};

const SCREENSHOT_CACHE_TTL: Duration = Duration::from_millis(500);
const WINDOW_SNAPSHOT_CACHE_TTL: Duration = Duration::from_millis(250);
#[cfg(target_os = "windows")]
const PROCESS_NAME_CACHE_TTL: Duration = Duration::from_secs(10);
const SENSITIVE_WINDOW_MARGIN: f64 = 12.0;

#[derive(Serialize)]
struct MemoryInfo {
    total: f64,
    used: f64,
    available: f64,
    used_percent: f64,
}

#[derive(Serialize)]
struct ForegroundWindowInfo {
    title: String,
    process_name: String,
    process_id: u64,
    is_masked: bool,
}

#[derive(Clone, Serialize)]
pub struct DetectedApplication {
    title: String,
    process_name: String,
    process_id: u64,
    #[serde(skip)]
    window: Option<SensitiveWindow>,
}

#[derive(Serialize)]
struct StatusResponse {
    status: &'static str,
    cpu: f32,
    memory: MemoryInfo,
    foreground_window: Option<ForegroundWindowInfo>,
    media: Option<crate::media_module::MediaInfo>,
}

#[derive(Serialize)]
struct PrivacyStatus {
    enabled: bool,
    message: &'static str,
}

#[derive(Clone, Copy, PartialEq)]
struct ScreenshotProfile {
    blur_radius: f32,
    quality: u8,
    scale: f32,
}

struct ScreenshotCache {
    profile: ScreenshotProfile,
    privacy_mode: bool,
    sensitive_windows: Vec<SensitiveWindow>,
    captured_at: Instant,
    bytes: Vec<u8>,
}

#[derive(Clone)]
struct WindowSnapshotCache {
    captured_at: Instant,
    applications: Vec<DetectedApplication>,
}

struct PrivacyImageCache {
    path: String,
    bytes: Vec<u8>,
}

#[derive(Serialize, Deserialize)]
struct PrivacyImageConfig {
    path: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
struct SensitiveWindow {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

#[derive(Clone, Copy)]
struct ScreenGeometry {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
}

pub static PRIVACY_MODE: AtomicBool = AtomicBool::new(false);
pub static GLOBAL_BLUR_ENABLED: AtomicBool = AtomicBool::new(true);
pub static IS_RUNNING: AtomicBool = AtomicBool::new(false);
pub static PRIVACY_IMAGE_PATH: OnceLock<Mutex<Option<String>>> = OnceLock::new();

static SHUTDOWN_TX: OnceLock<Mutex<Option<oneshot::Sender<()>>>> = OnceLock::new();
static SCREENSHOT_CACHE: OnceLock<Mutex<Option<ScreenshotCache>>> = OnceLock::new();
static STATUS_SYSTEM: OnceLock<Mutex<System>> = OnceLock::new();
static SENSITIVE_APP_RULES: OnceLock<Mutex<Vec<String>>> = OnceLock::new();
static SENSITIVE_RULES_PATH: OnceLock<PathBuf> = OnceLock::new();
static PRIVACY_IMAGE_CONFIG_PATH: OnceLock<PathBuf> = OnceLock::new();
static PRIVACY_IMAGE_CACHE: OnceLock<Mutex<Option<PrivacyImageCache>>> = OnceLock::new();
static WINDOW_SNAPSHOT_CACHE: OnceLock<Mutex<Option<WindowSnapshotCache>>> = OnceLock::new();
#[cfg(target_os = "windows")]
static PROCESS_NAME_CACHE: OnceLock<Mutex<HashMap<u32, (Instant, String)>>> = OnceLock::new();
static SCREENSHOT_SINGLEFLIGHT: OnceLock<AsyncMutex<()>> = OnceLock::new();

fn get_privacy_image_path() -> &'static Mutex<Option<String>> {
    PRIVACY_IMAGE_PATH.get_or_init(|| Mutex::new(None))
}

fn get_privacy_image_cache() -> &'static Mutex<Option<PrivacyImageCache>> {
    PRIVACY_IMAGE_CACHE.get_or_init(|| Mutex::new(None))
}

fn get_window_snapshot_cache() -> &'static Mutex<Option<WindowSnapshotCache>> {
    WINDOW_SNAPSHOT_CACHE.get_or_init(|| Mutex::new(None))
}

#[cfg(target_os = "windows")]
fn get_process_name_cache() -> &'static Mutex<HashMap<u32, (Instant, String)>> {
    PROCESS_NAME_CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn get_screenshot_singleflight() -> &'static AsyncMutex<()> {
    SCREENSHOT_SINGLEFLIGHT.get_or_init(|| AsyncMutex::new(()))
}

fn get_tx() -> &'static Mutex<Option<oneshot::Sender<()>>> {
    SHUTDOWN_TX.get_or_init(|| Mutex::new(None))
}

fn get_screenshot_cache() -> &'static Mutex<Option<ScreenshotCache>> {
    SCREENSHOT_CACHE.get_or_init(|| Mutex::new(None))
}

fn get_status_system() -> &'static Mutex<System> {
    STATUS_SYSTEM.get_or_init(|| {
        let mut sys = System::new_all();
        sys.refresh_cpu_usage();
        sys.refresh_memory();
        Mutex::new(sys)
    })
}

fn get_sensitive_app_rules_state() -> &'static Mutex<Vec<String>> {
    SENSITIVE_APP_RULES.get_or_init(|| Mutex::new(Vec::new()))
}

pub fn init(app_handle: &AppHandle) {
    let Ok(app_data_dir) = app_handle.path().app_data_dir() else {
        return;
    };
    let _ = fs::create_dir_all(&app_data_dir);
    let path = app_data_dir.join("peek_sensitive_apps.json");
    let _ = SENSITIVE_RULES_PATH.set(path.clone());
    let privacy_config_path = app_data_dir.join("peek_privacy_image.json");
    let _ = PRIVACY_IMAGE_CONFIG_PATH.set(privacy_config_path.clone());

    if let Ok(contents) = fs::read_to_string(path) {
        if let Ok(rules) = serde_json::from_str::<Vec<String>>(&contents) {
            *get_sensitive_app_rules_state().lock().unwrap() = normalize_rules(rules);
        }
    }

    if let Ok(contents) = fs::read_to_string(privacy_config_path) {
        if let Ok(config) = serde_json::from_str::<PrivacyImageConfig>(&contents) {
            *get_privacy_image_path().lock().unwrap() = config.path;
        }
    }
}

pub fn get_sensitive_app_rules() -> Vec<String> {
    get_sensitive_app_rules_state().lock().unwrap().clone()
}

pub fn get_privacy_image() -> Option<String> {
    get_privacy_image_path().lock().unwrap().clone()
}

pub fn set_privacy_image(path: Option<String>) -> Result<Option<String>, String> {
    let path = path
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty());

    if let Some(value) = path.as_ref() {
        image::ImageReader::open(value)
            .map_err(|error| format!("无法读取隐私图片：{error}"))?
            .with_guessed_format()
            .map_err(|error| format!("无法识别隐私图片格式：{error}"))?
            .decode()
            .map_err(|error| format!("隐私图片解码失败：{error}"))?;
    }

    if let Some(config_path) = PRIVACY_IMAGE_CONFIG_PATH.get() {
        let contents = serde_json::to_string_pretty(&PrivacyImageConfig { path: path.clone() })
            .map_err(|error| error.to_string())?;
        fs::write(config_path, contents).map_err(|error| error.to_string())?;
    }

    *get_privacy_image_path().lock().unwrap() = path.clone();
    *get_privacy_image_cache().lock().unwrap() = None;
    clear_screenshot_cache();
    Ok(path)
}

#[cfg(target_os = "windows")]
pub fn detect_running_apps() -> Vec<DetectedApplication> {
    unsafe extern "system" fn collect_window(hwnd: HWND, parameter: LPARAM) -> BOOL {
        if !unsafe { IsWindowVisible(hwnd) }.as_bool() {
            return true.into();
        }

        let title_length = unsafe { GetWindowTextLengthW(hwnd) }.max(0) as usize;
        if title_length == 0 {
            return true.into();
        }
        let mut title_buffer = vec![0u16; title_length.saturating_add(1)];
        let copied = unsafe { GetWindowTextW(hwnd, &mut title_buffer) }.max(0) as usize;
        let title = String::from_utf16_lossy(&title_buffer[..copied])
            .trim()
            .to_string();
        if title.is_empty() {
            return true.into();
        }

        let mut process_id = 0u32;
        unsafe { GetWindowThreadProcessId(hwnd, Some(&mut process_id)) };
        let process_name = get_process_name_cached(process_id);
        let mut rect = RECT::default();
        let window = unsafe { GetWindowRect(hwnd, &mut rect) }
            .ok()
            .map(|_| SensitiveWindow {
                x: rect.left.into(),
                y: rect.top.into(),
                width: (rect.right - rect.left).into(),
                height: (rect.bottom - rect.top).into(),
            })
            .filter(|window| window.width > 0.0 && window.height > 0.0);

        let applications = unsafe { &mut *(parameter.0 as *mut Vec<DetectedApplication>) };
        applications.push(DetectedApplication {
            title,
            process_name,
            process_id: process_id.into(),
            window,
        });
        true.into()
    }

    let mut applications: Vec<DetectedApplication> = Vec::new();
    let parameter = LPARAM((&mut applications as *mut Vec<DetectedApplication>) as isize);
    let _ = unsafe { EnumWindows(Some(collect_window), parameter) };
    applications.sort_by(|left, right| {
        left.process_name
            .to_lowercase()
            .cmp(&right.process_name.to_lowercase())
            .then_with(|| left.title.to_lowercase().cmp(&right.title.to_lowercase()))
    });
    applications.dedup_by(|left, right| {
        left.process_id == right.process_id
            && left.title.eq_ignore_ascii_case(&right.title)
            && left.process_name.eq_ignore_ascii_case(&right.process_name)
    });
    applications
}

fn detect_running_apps_cached() -> Vec<DetectedApplication> {
    {
        let cache = get_window_snapshot_cache().lock().unwrap();
        if let Some(cached) = cache.as_ref() {
            if cached.captured_at.elapsed() <= WINDOW_SNAPSHOT_CACHE_TTL {
                return cached.applications.clone();
            }
        }
    }

    let applications = detect_running_apps();
    *get_window_snapshot_cache().lock().unwrap() = Some(WindowSnapshotCache {
        captured_at: Instant::now(),
        applications: applications.clone(),
    });
    applications
}

#[cfg(not(target_os = "windows"))]
pub fn detect_running_apps() -> Vec<DetectedApplication> {
    let system = System::new_all();
    let mut applications: Vec<_> = system
        .processes()
        .iter()
        .map(|(pid, process)| DetectedApplication {
            title: String::new(),
            process_name: process.name().to_string_lossy().to_string(),
            process_id: pid.as_u32().into(),
            window: None,
        })
        .collect();
    applications.sort_by_key(|application| application.process_name.to_lowercase());
    applications
        .dedup_by(|left, right| left.process_name.eq_ignore_ascii_case(&right.process_name));
    applications
}

pub fn clear_screenshot_cache() {
    *get_screenshot_cache().lock().unwrap() = None;
}

pub fn set_sensitive_app_rules(rules: Vec<String>) -> Result<Vec<String>, String> {
    let rules = normalize_rules(rules);
    if rules.len() > 64 {
        return Err("Sensitive application rules cannot exceed 64 entries".to_string());
    }

    *get_sensitive_app_rules_state().lock().unwrap() = rules.clone();
    clear_screenshot_cache();

    if let Some(path) = SENSITIVE_RULES_PATH.get() {
        let json = serde_json::to_string_pretty(&rules).map_err(|error| error.to_string())?;
        fs::write(path, json).map_err(|error| error.to_string())?;
    }

    Ok(rules)
}

fn normalize_rules(rules: Vec<String>) -> Vec<String> {
    let mut normalized = Vec::new();
    for rule in rules {
        let rule = rule.trim();
        if rule.is_empty() || rule.len() > 128 {
            continue;
        }
        if !normalized
            .iter()
            .any(|existing: &String| existing.eq_ignore_ascii_case(rule))
        {
            normalized.push(rule.to_string());
        }
    }
    normalized
}

fn normalize_match_text(value: &str) -> String {
    value
        .to_lowercase()
        .chars()
        .filter(|character| character.is_alphanumeric())
        .collect()
}

fn window_matches_sensitive_rule(window: &ActiveWindow) -> bool {
    let process_file_name = window
        .process_path
        .file_name()
        .map(|name| name.to_string_lossy().to_string())
        .unwrap_or_default();
    let process_stem = window
        .process_path
        .file_stem()
        .map(|name| name.to_string_lossy().to_string())
        .unwrap_or_default();
    let candidates = [
        normalize_match_text(&window.app_name),
        normalize_match_text(&process_file_name),
        normalize_match_text(&process_stem),
        normalize_match_text(&window.title),
    ];

    candidates_match_rules(
        &candidates,
        &get_sensitive_app_rules_state().lock().unwrap(),
    )
}

fn candidates_match_rules(candidates: &[String], rules: &[String]) -> bool {
    rules.iter().any(|rule| {
        let rule = normalize_match_text(rule);
        !rule.is_empty()
            && candidates.iter().any(|candidate| {
                let candidate = normalize_match_text(candidate);
                candidate.contains(&rule)
                    || (candidate.chars().count() >= 4 && rule.contains(&candidate))
            })
    })
}

fn sensitive_window(window: &ActiveWindow) -> Option<SensitiveWindow> {
    if !window_matches_sensitive_rule(window)
        || window.position.width <= 0.0
        || window.position.height <= 0.0
    {
        return None;
    }

    Some(SensitiveWindow {
        x: window.position.x,
        y: window.position.y,
        width: window.position.width,
        height: window.position.height,
    })
}

fn detected_sensitive_windows() -> Vec<SensitiveWindow> {
    let mut windows: Vec<SensitiveWindow> = detect_running_apps_cached()
        .into_iter()
        .filter_map(|application| {
            let geometry = application.window?;
            let window = ActiveWindow {
                title: application.title,
                process_path: PathBuf::from(&application.process_name),
                app_name: application.process_name,
                window_id: String::new(),
                process_id: application.process_id,
                position: WindowPosition::new(
                    geometry.x,
                    geometry.y,
                    geometry.width,
                    geometry.height,
                ),
            };
            sensitive_window(&window)
        })
        .collect();

    // 非 Windows 或窗口枚举失败时，仍保留前台窗口检测作为兜底。
    if windows.is_empty() {
        if let Some(window) =
            get_active_window_resilient().and_then(|window| sensitive_window(&window))
        {
            windows.push(window);
        }
    }
    windows
}

fn get_active_window_resilient() -> Option<ActiveWindow> {
    get_active_window_fallback().or_else(|| active_win_pos_rs::get_active_window().ok())
}

#[cfg(not(target_os = "windows"))]
fn get_active_window_fallback() -> Option<ActiveWindow> {
    None
}

#[cfg(target_os = "windows")]
fn get_active_window_fallback() -> Option<ActiveWindow> {
    let hwnd = unsafe { GetForegroundWindow() };
    if hwnd.0.is_null() {
        return None;
    }

    let mut rect = RECT::default();
    if unsafe { GetWindowRect(hwnd, &mut rect) }.is_err() {
        return None;
    }

    let title_length = unsafe { GetWindowTextLengthW(hwnd) }.max(0) as usize;
    let mut title_buffer = vec![0u16; title_length.saturating_add(1)];
    let copied = unsafe { GetWindowTextW(hwnd, &mut title_buffer) }.max(0) as usize;
    let title = String::from_utf16_lossy(&title_buffer[..copied]);

    let mut process_id = 0u32;
    unsafe { GetWindowThreadProcessId(hwnd, Some(&mut process_id)) };
    let process_path = get_process_path_fallback(process_id).unwrap_or_default();
    let app_name = process_path
        .file_stem()
        .map(|name| name.to_string_lossy().to_string())
        .unwrap_or_default();

    Some(ActiveWindow {
        title,
        process_path,
        app_name,
        window_id: format!("{:?}", hwnd),
        process_id: process_id.into(),
        position: WindowPosition::new(
            rect.left.into(),
            rect.top.into(),
            (rect.right - rect.left).into(),
            (rect.bottom - rect.top).into(),
        ),
    })
}

#[cfg(target_os = "windows")]
fn get_process_path_fallback(process_id: u32) -> Option<PathBuf> {
    if process_id == 0 {
        return None;
    }

    let handle =
        unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, process_id) }.ok()?;
    let mut buffer = vec![0u16; 32_768];
    let mut length = buffer.len() as u32;
    let result = unsafe {
        QueryFullProcessImageNameW(
            handle,
            PROCESS_NAME_WIN32,
            windows::core::PWSTR(buffer.as_mut_ptr()),
            &mut length,
        )
    };
    let _ = unsafe { CloseHandle(handle) };
    if result.is_err() || length == 0 {
        return None;
    }

    Some(PathBuf::from(String::from_utf16_lossy(
        &buffer[..length as usize],
    )))
}

#[cfg(target_os = "windows")]
fn get_process_name_cached(process_id: u32) -> String {
    {
        let cache = get_process_name_cache().lock().unwrap();
        if let Some((captured_at, name)) = cache.get(&process_id) {
            if captured_at.elapsed() <= PROCESS_NAME_CACHE_TTL {
                return name.clone();
            }
        }
    }

    let name = get_process_path_fallback(process_id)
        .and_then(|path| {
            path.file_name()
                .map(|file_name| file_name.to_string_lossy().to_string())
        })
        .unwrap_or_default();
    let mut cache = get_process_name_cache().lock().unwrap();
    if cache.len() > 512 {
        cache.retain(|_, (captured_at, _)| captured_at.elapsed() <= PROCESS_NAME_CACHE_TTL);
    }
    cache.insert(process_id, (Instant::now(), name.clone()));
    name
}

pub async fn run_server() -> Result<(), String> {
    if IS_RUNNING
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return Ok(());
    }

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/api/status", get(status_handler))
        .route("/api/screenshot", get(screenshot_handler))
        .route("/api/privacy", get(get_privacy).post(set_privacy))
        .layer(cors);

    let listener = match tokio::net::TcpListener::bind("0.0.0.0:3000").await {
        Ok(listener) => listener,
        Err(error) => {
            IS_RUNNING.store(false, Ordering::SeqCst);
            return Err(format!(
                "Failed to bind Peek PC server on port 3000: {error}"
            ));
        }
    };

    let (tx, rx) = oneshot::channel();
    *get_tx().lock().unwrap() = Some(tx);

    tokio::spawn(async move {
        if let Err(error) = axum::serve(listener, app)
            .with_graceful_shutdown(async move {
                rx.await.ok();
            })
            .await
        {
            eprintln!("Peek PC server error: {error}");
        }

        IS_RUNNING.store(false, Ordering::SeqCst);
        *get_tx().lock().unwrap() = None;
    });

    Ok(())
}

pub fn stop_server() {
    if let Some(tx) = get_tx().lock().unwrap().take() {
        let _ = tx.send(());
    }
}

async fn status_handler() -> impl IntoResponse {
    let (cpu, memory) = {
        let mut sys = get_status_system().lock().unwrap();
        sys.refresh_cpu_usage();
        sys.refresh_memory();

        let total = sys.total_memory() as f64 / 1024.0 / 1024.0;
        let used = sys.used_memory() as f64 / 1024.0 / 1024.0;
        let available = sys.available_memory() as f64 / 1024.0 / 1024.0;
        let used_percent = if total > 0.0 {
            used / total * 100.0
        } else {
            0.0
        };

        (
            sys.global_cpu_usage(),
            MemoryInfo {
                total,
                used,
                available,
                used_percent,
            },
        )
    };

    let foreground_window = get_active_window_resilient().map(|window| {
        let is_masked = window_matches_sensitive_rule(&window);
        ForegroundWindowInfo {
            title: window.title,
            process_name: if window.app_name.is_empty() {
                window
                    .process_path
                    .file_name()
                    .map(|name| name.to_string_lossy().to_string())
                    .unwrap_or_default()
            } else {
                window.app_name
            },
            process_id: window.process_id,
            is_masked,
        }
    });

    let media = {
        let info = crate::media_module::get_current_media_info();
        if info.title.is_empty() && info.artist.is_empty() {
            None
        } else {
            Some(info)
        }
    };

    Json(StatusResponse {
        status: "success",
        cpu,
        memory,
        foreground_window,
        media,
    })
}

async fn screenshot_handler() -> Response {
    let is_privacy = PRIVACY_MODE.load(Ordering::SeqCst);
    let _singleflight = get_screenshot_singleflight().lock().await;

    if is_privacy {
        if let Some(path) = get_privacy_image() {
            if let Ok(Some(bytes)) =
                tokio::task::spawn_blocking(move || get_privacy_image_bytes(&path)).await
            {
                return jpeg_response(bytes);
            }
        }
    }

    let profile = if is_privacy {
        PRIVACY_SCREENSHOT_PROFILE
    } else if GLOBAL_BLUR_ENABLED.load(Ordering::SeqCst) {
        DEFAULT_SCREENSHOT_PROFILE
    } else {
        CLEAR_SCREENSHOT_PROFILE
    };

    match tokio::task::spawn_blocking(move || capture_screenshot(profile, is_privacy)).await {
        Ok(Some(bytes)) => jpeg_response(bytes),
        _ => empty_error_response(),
    }
}

fn get_privacy_image_bytes(path: &str) -> Option<Vec<u8>> {
    {
        let cache = get_privacy_image_cache().lock().unwrap();
        if let Some(cached) = cache.as_ref() {
            if cached.path == path {
                return Some(cached.bytes.clone());
            }
        }
    }

    let image = image::open(path).ok()?;
    let mut bytes = Vec::new();
    image
        .write_to(&mut Cursor::new(&mut bytes), image::ImageFormat::Jpeg)
        .ok()?;
    *get_privacy_image_cache().lock().unwrap() = Some(PrivacyImageCache {
        path: path.to_string(),
        bytes: bytes.clone(),
    });
    Some(bytes)
}

fn capture_screenshot(profile: ScreenshotProfile, is_privacy: bool) -> Option<Vec<u8>> {
    let sensitive_windows = detected_sensitive_windows();

    if let Some(bytes) = get_cached_screenshot(profile, is_privacy, &sensitive_windows) {
        return Some(bytes);
    }

    let screens = Screen::all().ok()?;
    let screen = screens.first()?;
    let image = screen.capture().ok()?;
    let rgba = image::RgbaImage::from_raw(image.width(), image.height(), image.into_raw())?;

    let geometry = ScreenGeometry {
        x: screen.display_info.x,
        y: screen.display_info.y,
        width: screen.display_info.width,
        height: screen.display_info.height,
    };

    let bytes = encode_screenshot(rgba, profile, geometry, &sensitive_windows)?;

    store_cached_screenshot(profile, is_privacy, sensitive_windows, bytes.clone());
    Some(bytes)
}

async fn get_privacy() -> impl IntoResponse {
    let enabled = PRIVACY_MODE.load(Ordering::SeqCst);
    Json(PrivacyStatus {
        enabled,
        message: privacy_message(enabled),
    })
}

async fn set_privacy() -> impl IntoResponse {
    let enabled = !PRIVACY_MODE.load(Ordering::SeqCst);
    PRIVACY_MODE.store(enabled, Ordering::SeqCst);
    clear_screenshot_cache();
    Json(PrivacyStatus {
        enabled,
        message: privacy_message(enabled),
    })
}

fn get_cached_screenshot(
    profile: ScreenshotProfile,
    privacy_mode: bool,
    sensitive_windows: &[SensitiveWindow],
) -> Option<Vec<u8>> {
    let cache = get_screenshot_cache().lock().unwrap();
    let cached = cache.as_ref()?;

    if !screenshot_cache_matches(cached, profile, privacy_mode, sensitive_windows) {
        return None;
    }

    if cached.captured_at.elapsed() > SCREENSHOT_CACHE_TTL {
        return None;
    }

    Some(cached.bytes.clone())
}

fn screenshot_cache_matches(
    cached: &ScreenshotCache,
    profile: ScreenshotProfile,
    privacy_mode: bool,
    sensitive_windows: &[SensitiveWindow],
) -> bool {
    cached.profile == profile
        && cached.privacy_mode == privacy_mode
        && cached.sensitive_windows == sensitive_windows
}

fn store_cached_screenshot(
    profile: ScreenshotProfile,
    privacy_mode: bool,
    sensitive_windows: Vec<SensitiveWindow>,
    bytes: Vec<u8>,
) {
    *get_screenshot_cache().lock().unwrap() = Some(ScreenshotCache {
        profile,
        privacy_mode,
        sensitive_windows,
        captured_at: Instant::now(),
        bytes,
    });
}

fn encode_screenshot(
    rgba: image::RgbaImage,
    profile: ScreenshotProfile,
    screen: ScreenGeometry,
    sensitive_windows: &[SensitiveWindow],
) -> Option<Vec<u8>> {
    let width = ((rgba.width() as f32) * profile.scale).round().max(1.0) as u32;
    let height = ((rgba.height() as f32) * profile.scale).round().max(1.0) as u32;
    let resized =
        image::imageops::resize(&rgba, width, height, image::imageops::FilterType::Triangle);
    let mut processed_rgba = if profile.blur_radius > 0.0 {
        image::imageops::blur(&resized, profile.blur_radius)
    } else {
        resized
    };
    for window in sensitive_windows {
        blur_sensitive_window(&mut processed_rgba, screen, window);
    }
    let mut bytes = Vec::new();
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut bytes, profile.quality)
        .encode_image(&image::DynamicImage::ImageRgba8(processed_rgba))
        .ok()?;
    Some(bytes)
}

fn blur_sensitive_window(
    image: &mut image::RgbaImage,
    screen: ScreenGeometry,
    window: &SensitiveWindow,
) {
    if screen.width == 0 || screen.height == 0 {
        return;
    }

    let scale_x = image.width() as f64 / screen.width as f64;
    let scale_y = image.height() as f64 / screen.height as f64;
    let left = ((window.x - screen.x as f64 - SENSITIVE_WINDOW_MARGIN) * scale_x).floor();
    let top = ((window.y - screen.y as f64 - SENSITIVE_WINDOW_MARGIN) * scale_y).floor();
    let right =
        ((window.x - screen.x as f64 + window.width + SENSITIVE_WINDOW_MARGIN) * scale_x).ceil();
    let bottom =
        ((window.y - screen.y as f64 + window.height + SENSITIVE_WINDOW_MARGIN) * scale_y).ceil();

    let x1 = left.clamp(0.0, image.width() as f64) as u32;
    let y1 = top.clamp(0.0, image.height() as f64) as u32;
    let x2 = right.clamp(0.0, image.width() as f64) as u32;
    let y2 = bottom.clamp(0.0, image.height() as f64) as u32;
    if x2 <= x1 || y2 <= y1 {
        return;
    }

    let region = image::imageops::crop_imm(image, x1, y1, x2 - x1, y2 - y1).to_image();
    let blurred = image::imageops::blur(&region, 18.0);
    image::imageops::overlay(image, &blurred, x1.into(), y1.into());
}

fn jpeg_response(bytes: Vec<u8>) -> Response {
    Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", "image/jpeg")
        .header("Cache-Control", "no-cache")
        .header("Access-Control-Allow-Origin", "*")
        .body(Body::from(bytes))
        .unwrap()
}

fn empty_error_response() -> Response {
    Response::builder()
        .status(StatusCode::INTERNAL_SERVER_ERROR)
        .body(Body::empty())
        .unwrap()
}

fn privacy_message(enabled: bool) -> &'static str {
    if enabled {
        "隐私模式已开启，不给看！"
    } else {
        "隐私模式已关闭，可以看"
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn normalizes_sensitive_rules() {
        let rules = normalize_rules(vec![
            " WeChat.exe ".to_string(),
            "wechat.exe".to_string(),
            "".to_string(),
            "KeePass".to_string(),
        ]);

        assert_eq!(rules, vec!["WeChat.exe", "KeePass"]);
    }

    #[test]
    fn matches_qq_ayugram_and_firefox_rules() {
        let rules = vec![
            "QQ".to_string(),
            "AyuGram Desktop".to_string(),
            "firefox.exe".to_string(),
        ];

        assert!(candidates_match_rules(&["QQ.exe".to_string()], &rules));
        assert!(candidates_match_rules(
            &["AyuGram Desktop".to_string(), "AyuGram.exe".to_string()],
            &rules
        ));
        assert!(candidates_match_rules(&["firefox.exe".to_string()], &rules));
        assert!(!candidates_match_rules(
            &["notepad.exe".to_string()],
            &rules
        ));
    }

    #[test]
    fn blur_is_limited_to_the_sensitive_window() {
        let mut image = image::RgbaImage::from_fn(100, 100, |x, y| {
            if (x + y) % 2 == 0 {
                image::Rgba([255, 255, 255, 255])
            } else {
                image::Rgba([0, 0, 0, 255])
            }
        });
        let outside_before = *image.get_pixel(0, 0);
        let center_before = *image.get_pixel(50, 50);

        blur_sensitive_window(
            &mut image,
            ScreenGeometry {
                x: 0,
                y: 0,
                width: 100,
                height: 100,
            },
            &SensitiveWindow {
                x: 40.0,
                y: 40.0,
                width: 20.0,
                height: 20.0,
            },
        );

        assert_eq!(*image.get_pixel(0, 0), outside_before);
        assert_ne!(*image.get_pixel(50, 50), center_before);
    }

    #[test]
    fn blur_supports_multiple_sensitive_windows() {
        let mut image = image::RgbaImage::from_fn(120, 80, |x, y| {
            if (x + y) % 2 == 0 {
                image::Rgba([255, 255, 255, 255])
            } else {
                image::Rgba([0, 0, 0, 255])
            }
        });
        let untouched = *image.get_pixel(60, 40);
        let first_before = *image.get_pixel(20, 20);
        let second_before = *image.get_pixel(100, 60);
        let screen = ScreenGeometry {
            x: 0,
            y: 0,
            width: 120,
            height: 80,
        };

        for window in [
            SensitiveWindow {
                x: 12.0,
                y: 12.0,
                width: 16.0,
                height: 16.0,
            },
            SensitiveWindow {
                x: 92.0,
                y: 52.0,
                width: 16.0,
                height: 16.0,
            },
        ] {
            blur_sensitive_window(&mut image, screen, &window);
        }

        assert_ne!(*image.get_pixel(20, 20), first_before);
        assert_ne!(*image.get_pixel(100, 60), second_before);
        assert_eq!(*image.get_pixel(60, 40), untouched);
    }

    #[test]
    fn privacy_image_loads_and_invalid_path_falls_back() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!("peek-privacy-{unique}.png"));
        image::RgbaImage::from_pixel(2, 2, image::Rgba([20, 40, 60, 255]))
            .save(&path)
            .unwrap();

        assert!(get_privacy_image_bytes(path.to_str().unwrap()).is_some());
        let _ = fs::remove_file(&path);
        assert!(get_privacy_image_bytes("missing-peek-privacy-image.png").is_none());
    }

    #[test]
    fn screenshot_cache_key_includes_privacy_and_window_geometry() {
        let window = SensitiveWindow {
            x: 10.0,
            y: 10.0,
            width: 100.0,
            height: 80.0,
        };
        let cached = ScreenshotCache {
            profile: DEFAULT_SCREENSHOT_PROFILE,
            privacy_mode: false,
            sensitive_windows: vec![window.clone()],
            captured_at: Instant::now(),
            bytes: vec![1, 2, 3],
        };

        assert!(screenshot_cache_matches(
            &cached,
            DEFAULT_SCREENSHOT_PROFILE,
            false,
            std::slice::from_ref(&window)
        ));
        assert!(!screenshot_cache_matches(
            &cached,
            DEFAULT_SCREENSHOT_PROFILE,
            true,
            std::slice::from_ref(&window)
        ));
        assert!(!screenshot_cache_matches(
            &cached,
            DEFAULT_SCREENSHOT_PROFILE,
            false,
            &[SensitiveWindow { x: 11.0, ..window }]
        ));
    }
}
