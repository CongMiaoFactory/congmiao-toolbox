use serde::Serialize;
use std::sync::{Mutex, OnceLock};
use tauri::{AppHandle, Emitter};
use windows::Media::Control::{
    GlobalSystemMediaTransportControlsSessionManager,
    GlobalSystemMediaTransportControlsSessionPlaybackStatus,
};

#[derive(Clone, Serialize, Default, Debug)]
pub struct MediaInfo {
    pub title: String,
    pub artist: String,
    pub is_playing: bool,
}

static CURRENT_MEDIA_INFO: OnceLock<Mutex<MediaInfo>> = OnceLock::new();

pub fn get_current_media_info() -> MediaInfo {
    CURRENT_MEDIA_INFO
        .get_or_init(|| Mutex::new(MediaInfo::default()))
        .lock()
        .unwrap()
        .clone()
}

#[tauri::command]
pub async fn media_play_pause() -> Result<(), String> {
    if let Ok(manager_op) = GlobalSystemMediaTransportControlsSessionManager::RequestAsync() {
        if let Ok(manager) = manager_op.await {
            if let Ok(session) = manager.GetCurrentSession() {
                if let Ok(op) = session.TryTogglePlayPauseAsync() {
                    let _ = op.await;
                }
            }
        }
    }
    Ok(())
}

#[tauri::command]
pub async fn media_next() -> Result<(), String> {
    if let Ok(manager_op) = GlobalSystemMediaTransportControlsSessionManager::RequestAsync() {
        if let Ok(manager) = manager_op.await {
            if let Ok(session) = manager.GetCurrentSession() {
                if let Ok(op) = session.TrySkipNextAsync() {
                    let _ = op.await;
                }
            }
        }
    }
    Ok(())
}

#[tauri::command]
pub async fn media_prev() -> Result<(), String> {
    if let Ok(manager_op) = GlobalSystemMediaTransportControlsSessionManager::RequestAsync() {
        if let Ok(manager) = manager_op.await {
            if let Ok(session) = manager.GetCurrentSession() {
                if let Ok(op) = session.TrySkipPreviousAsync() {
                    let _ = op.await;
                }
            }
        }
    }
    Ok(())
}

pub fn start_media_listener(app_handle: AppHandle) {
    tauri::async_runtime::spawn(async move {
        let manager_result = GlobalSystemMediaTransportControlsSessionManager::RequestAsync();
        
        if let Ok(manager_op) = manager_result {
            if let Ok(manager) = manager_op.await {
                loop {
                    let mut info = MediaInfo::default();
                    if let Ok(session) = manager.GetCurrentSession() {
                        if let Ok(media_props) = session.TryGetMediaPropertiesAsync() {
                            if let Ok(props) = media_props.await {
                                info.title = props.Title().unwrap_or_default().to_string();
                                info.artist = props.Artist().unwrap_or_default().to_string();
                            }
                        }
                        if let Ok(playback_info) = session.GetPlaybackInfo() {
                            if let Ok(status) = playback_info.PlaybackStatus() {
                                info.is_playing = status == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing;
                            }
                        }
                    }
                    if let Some(mutex) = CURRENT_MEDIA_INFO.get() {
                        *mutex.lock().unwrap() = info.clone();
                    } else {
                        let _ = CURRENT_MEDIA_INFO.set(Mutex::new(info.clone()));
                    }
                    let _ = app_handle.emit("media-update", info);
                    tokio::time::sleep(std::time::Duration::from_millis(1000)).await;
                }
            }
        }
    });
}
