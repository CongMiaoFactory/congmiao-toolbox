use active_win_pos_rs::get_active_window;
use axum::{body::Body, http::StatusCode, response::IntoResponse, response::Response, routing::get, Json, Router};
use screenshots::Screen;
use serde::Serialize;
use std::io::Cursor;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};
use sysinfo::System;
use tokio::sync::oneshot;
use tower_http::cors::{Any, CorsLayer};

const DEFAULT_SCREENSHOT_PROFILE: ScreenshotProfile = ScreenshotProfile {
    blur_radius: 10.0,
    quality: 75,
    scale: 0.5,
};

const PRIVACY_SCREENSHOT_PROFILE: ScreenshotProfile = ScreenshotProfile {
    blur_radius: 30.0,
    quality: 75,
    scale: 0.25,
};

const SCREENSHOT_CACHE_TTL: Duration = Duration::from_millis(500);

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
    captured_at: Instant,
    bytes: Vec<u8>,
}

pub static PRIVACY_MODE: AtomicBool = AtomicBool::new(false);
pub static IS_RUNNING: AtomicBool = AtomicBool::new(false);
pub static PRIVACY_IMAGE_PATH: OnceLock<Mutex<Option<String>>> = OnceLock::new();

static SHUTDOWN_TX: OnceLock<Mutex<Option<oneshot::Sender<()>>>> = OnceLock::new();
static SCREENSHOT_CACHE: OnceLock<Mutex<Option<ScreenshotCache>>> = OnceLock::new();
static STATUS_SYSTEM: OnceLock<Mutex<System>> = OnceLock::new();

fn get_privacy_image_path() -> &'static Mutex<Option<String>> {
    PRIVACY_IMAGE_PATH.get_or_init(|| Mutex::new(None))
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

pub async fn run_server() {
    if IS_RUNNING.load(Ordering::SeqCst) {
        return;
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

    let (tx, rx) = oneshot::channel();
    *get_tx().lock().unwrap() = Some(tx);

    IS_RUNNING.store(true, Ordering::SeqCst);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();

    tokio::spawn(async move {
        axum::serve(listener, app)
            .with_graceful_shutdown(async move {
                rx.await.ok();
            })
            .await
            .unwrap();

        IS_RUNNING.store(false, Ordering::SeqCst);
        *get_tx().lock().unwrap() = None;
    });
}

pub fn stop_server() {
    if let Some(tx) = get_tx().lock().unwrap().take() {
        let _ = tx.send(());
    }
    IS_RUNNING.store(false, Ordering::SeqCst);
}

async fn status_handler() -> impl IntoResponse {
    let (cpu, memory) = {
        let mut sys = get_status_system().lock().unwrap();
        sys.refresh_cpu_usage();
        sys.refresh_memory();

        let total = sys.total_memory() as f64 / 1024.0 / 1024.0;
        let used = sys.used_memory() as f64 / 1024.0 / 1024.0;
        let available = sys.available_memory() as f64 / 1024.0 / 1024.0;
        let used_percent = if total > 0.0 { used / total * 100.0 } else { 0.0 };

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

    let foreground_window = get_active_window().ok().map(|window| ForegroundWindowInfo {
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

async fn screenshot_handler() -> impl IntoResponse {
    let is_privacy = PRIVACY_MODE.load(Ordering::SeqCst);
    let custom_path = get_privacy_image_path().lock().unwrap().clone();

    if let Some(path) = custom_path {
        if is_privacy {
            if let Ok(img) = image::open(path) {
                let mut bytes: Vec<u8> = Vec::new();
                if img.write_to(&mut Cursor::new(&mut bytes), image::ImageFormat::Jpeg).is_ok() {
                    return jpeg_response(bytes);
                }
            }
        }
    }

    let profile = if is_privacy {
        PRIVACY_SCREENSHOT_PROFILE
    } else {
        DEFAULT_SCREENSHOT_PROFILE
    };

    if let Some(bytes) = get_cached_screenshot(profile, is_privacy) {
        return jpeg_response(bytes);
    }

    let screens = match Screen::all() {
        Ok(screens) if !screens.is_empty() => screens,
        _ => return empty_error_response(),
    };

    let image = match screens.first().and_then(|screen| screen.capture().ok()) {
        Some(image) => image,
        None => return empty_error_response(),
    };

    let rgba = match image::RgbaImage::from_raw(image.width(), image.height(), image.into_raw()) {
        Some(image) => image,
        None => return empty_error_response(),
    };

    let bytes = match encode_screenshot(rgba, profile) {
        Some(bytes) => bytes,
        None => return empty_error_response(),
    };

    store_cached_screenshot(profile, is_privacy, bytes.clone());
    jpeg_response(bytes)
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
    Json(PrivacyStatus {
        enabled,
        message: privacy_message(enabled),
    })
}

fn get_cached_screenshot(profile: ScreenshotProfile, privacy_mode: bool) -> Option<Vec<u8>> {
    let cache = get_screenshot_cache().lock().unwrap();
    let cached = cache.as_ref()?;

    if cached.profile != profile || cached.privacy_mode != privacy_mode {
        return None;
    }

    if cached.captured_at.elapsed() > SCREENSHOT_CACHE_TTL {
        return None;
    }

    Some(cached.bytes.clone())
}

fn store_cached_screenshot(profile: ScreenshotProfile, privacy_mode: bool, bytes: Vec<u8>) {
    *get_screenshot_cache().lock().unwrap() = Some(ScreenshotCache {
        profile,
        privacy_mode,
        captured_at: Instant::now(),
        bytes,
    });
}

fn encode_screenshot(rgba: image::RgbaImage, profile: ScreenshotProfile) -> Option<Vec<u8>> {
    let mut dynamic = image::DynamicImage::ImageRgba8(rgba);
    let width = ((dynamic.width() as f32) * profile.scale).round().max(1.0) as u32;
    let height = ((dynamic.height() as f32) * profile.scale).round().max(1.0) as u32;

    dynamic = dynamic.resize_exact(width, height, image::imageops::FilterType::Lanczos3);

    let processed = if profile.blur_radius > 0.0 {
        image::DynamicImage::ImageRgba8(image::imageops::blur(&dynamic, profile.blur_radius))
    } else {
        dynamic
    };

    let processed_rgba = processed.to_rgba8();
    let mut bytes = Vec::new();
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut bytes, profile.quality)
        .encode_image(&image::DynamicImage::ImageRgba8(processed_rgba))
        .ok()?;
    Some(bytes)
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
