use active_win_pos_rs::get_active_window;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tauri::{AppHandle, Manager};

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct AppUsage {
    pub app_name: String,
    pub seconds: u64,
}

pub struct TrackerState {
    pub data: Mutex<HashMap<String, u64>>,
    pub save_path: PathBuf,
}

pub fn init(app_handle: AppHandle) {
    let app_data_dir = app_handle
        .path()
        .app_data_dir()
        .unwrap_or_else(|_| PathBuf::from("./"));
    fs::create_dir_all(&app_data_dir).unwrap_or_default();
    let save_path = app_data_dir.join("app_usage.json");

    let mut initial_data = HashMap::new();
    if let Ok(json) = fs::read_to_string(&save_path) {
        if let Ok(parsed) = serde_json::from_str::<HashMap<String, u64>>(&json) {
            initial_data = parsed;
        }
    }

    let state = Arc::new(TrackerState {
        data: Mutex::new(initial_data),
        save_path,
    });

    app_handle.manage(state.clone());

    std::thread::spawn(move || {
        let mut save_tick = 0;
        loop {
            std::thread::sleep(Duration::from_secs(1));

            if let Ok(window) = get_active_window() {
                // Ignore empty app names
                if !window.app_name.trim().is_empty() {
                    let mut data = state.data.lock().unwrap();
                    let count = data.entry(window.app_name).or_insert(0);
                    *count += 1;
                }
            }

            save_tick += 1;
            if save_tick >= 10 {
                // Save every 10 seconds for robustness
                save_tick = 0;
                let data = state.data.lock().unwrap();
                if let Ok(json) = serde_json::to_string(&*data) {
                    let _ = fs::write(&state.save_path, json);
                }
            }
        }
    });
}

#[tauri::command]
pub fn get_app_usage(state: tauri::State<'_, Arc<TrackerState>>) -> Vec<AppUsage> {
    let data = state.data.lock().unwrap();
    let mut vec: Vec<AppUsage> = data
        .iter()
        .map(|(k, v)| AppUsage {
            app_name: k.clone(),
            seconds: *v,
        })
        .collect();

    vec.sort_by(|a, b| b.seconds.cmp(&a.seconds));
    vec
}
