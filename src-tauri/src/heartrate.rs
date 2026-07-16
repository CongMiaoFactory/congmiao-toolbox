use btleplug::api::{Central, CentralEvent, Manager as _, Peripheral, ScanFilter};
use btleplug::platform::{Adapter, Manager};
use futures::StreamExt;
use std::sync::atomic::{AtomicBool, AtomicU16, Ordering};
use std::sync::OnceLock;
use tauri::Emitter;
use uuid::Uuid;

// Standard Bluetooth Heart Rate Service & Measurement UUIDs
const HR_SERVICE_UUID: Uuid = Uuid::from_u128(0x0000180d_0000_1000_8000_00805f9b34fb);
const HR_MEASUREMENT_UUID: Uuid = Uuid::from_u128(0x00002a37_0000_1000_8000_00805f9b34fb);

pub static CURRENT_BPM: AtomicU16 = AtomicU16::new(0);
pub static IS_CONNECTED: AtomicBool = AtomicBool::new(false);
static IS_SCANNING: AtomicBool = AtomicBool::new(false);
static SHOULD_STOP: AtomicBool = AtomicBool::new(false);

use std::sync::Mutex;
static TARGET_DEVICE: OnceLock<Mutex<String>> = OnceLock::new();

fn get_target() -> &'static Mutex<String> {
    TARGET_DEVICE.get_or_init(|| Mutex::new(String::new()))
}

pub fn set_target_device(filter: String) {
    *get_target().lock().unwrap() = filter;
}

pub fn get_target_device() -> String {
    get_target().lock().unwrap().clone()
}

static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

fn get_runtime() -> &'static tokio::runtime::Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("Failed to create tokio runtime for BLE")
    })
}

/// Parse the BLE Heart Rate Measurement characteristic value
fn parse_hr_value(data: &[u8]) -> Option<u16> {
    if data.is_empty() {
        return None;
    }
    let flags = data[0];
    let is_16bit = (flags & 0x01) != 0;

    if is_16bit {
        if data.len() >= 3 {
            Some(u16::from_le_bytes([data[1], data[2]]))
        } else {
            None
        }
    } else if data.len() >= 2 {
        Some(data[1] as u16)
    } else {
        None
    }
}

async fn find_adapter() -> Result<Adapter, String> {
    let manager = Manager::new()
        .await
        .map_err(|e| format!("BLE Manager init failed: {}", e))?;
    let adapters = manager
        .adapters()
        .await
        .map_err(|e| format!("No BLE adapters: {}", e))?;
    adapters
        .into_iter()
        .next()
        .ok_or_else(|| "No Bluetooth adapter found".to_string())
}

pub fn start_scan(app_handle: tauri::AppHandle) {
    if IS_SCANNING.load(Ordering::SeqCst) {
        return;
    }
    SHOULD_STOP.store(false, Ordering::SeqCst);
    IS_SCANNING.store(true, Ordering::SeqCst);

    let handle = app_handle.clone();

    get_runtime().spawn(async move {
        if let Err(e) = scan_and_connect(handle).await {
            eprintln!("HR scan error: {}", e);
        }
        IS_SCANNING.store(false, Ordering::SeqCst);
        IS_CONNECTED.store(false, Ordering::SeqCst);
        CURRENT_BPM.store(0, Ordering::SeqCst);
    });
}

pub fn stop_scan() {
    SHOULD_STOP.store(true, Ordering::SeqCst);
}

async fn scan_and_connect(app_handle: tauri::AppHandle) -> Result<(), String> {
    let adapter = find_adapter().await?;

    adapter
        .start_scan(ScanFilter::default())
        .await
        .map_err(|e| format!("Scan start failed: {}", e))?;

    let mut events = adapter
        .events()
        .await
        .map_err(|e| format!("Events failed: {}", e))?;

    // Look for a device with the HR service
    let mut target_peripheral = None;

    let scan_timeout = tokio::time::sleep(std::time::Duration::from_secs(15));
    tokio::pin!(scan_timeout);

    loop {
        if SHOULD_STOP.load(Ordering::SeqCst) {
            let _ = adapter.stop_scan().await;
            return Ok(());
        }

        tokio::select! {
            _ = &mut scan_timeout => {
                let _ = adapter.stop_scan().await;
                return Err("Scan timeout: no HR device found within 15s".to_string());
            }
            event = events.next() => {
                match event {
                    Some(CentralEvent::DeviceDiscovered(id)) | Some(CentralEvent::DeviceUpdated(id)) => {
                        if let Ok(peripheral) = adapter.peripheral(&id).await {
                            if let Ok(Some(props)) = peripheral.properties().await {
                                let has_hr = props.services.contains(&HR_SERVICE_UUID);
                                if has_hr {
                                    // Check device filter
                                    let filter = get_target().lock().unwrap().clone();
                                    if filter.is_empty() {
                                        // No filter set — take the first HR device
                                        target_peripheral = Some(peripheral);
                                        break;
                                    } else {
                                        let name = props.local_name.as_deref().unwrap_or("");
                                        let addr = props.address.to_string();
                                        let filter_lower = filter.to_lowercase();
                                        if name.to_lowercase().contains(&filter_lower)
                                            || addr.to_lowercase().contains(&filter_lower)
                                        {
                                            target_peripheral = Some(peripheral);
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                    None => break,
                    _ => {}
                }
            }
        }
    }

    let _ = adapter.stop_scan().await;

    let peripheral = target_peripheral.ok_or("No HR device found")?;

    peripheral
        .connect()
        .await
        .map_err(|e| format!("Connect failed: {}", e))?;
    IS_CONNECTED.store(true, Ordering::SeqCst);

    peripheral
        .discover_services()
        .await
        .map_err(|e| format!("Service discovery failed: {}", e))?;

    let chars = peripheral.characteristics();
    let hr_char = chars
        .iter()
        .find(|c| c.uuid == HR_MEASUREMENT_UUID)
        .ok_or("HR Measurement characteristic not found")?;

    peripheral
        .subscribe(hr_char)
        .await
        .map_err(|e| format!("Subscribe failed: {}", e))?;

    let mut notification_stream = peripheral
        .notifications()
        .await
        .map_err(|e| format!("Notification stream failed: {}", e))?;

    // Read notifications until stopped
    loop {
        if SHOULD_STOP.load(Ordering::SeqCst) {
            let _ = peripheral.unsubscribe(hr_char).await;
            let _ = peripheral.disconnect().await;
            IS_CONNECTED.store(false, Ordering::SeqCst);
            CURRENT_BPM.store(0, Ordering::SeqCst);
            return Ok(());
        }

        tokio::select! {
            notification = notification_stream.next() => {
                match notification {
                    Some(data) => {
                        if data.uuid == HR_MEASUREMENT_UUID {
                            if let Some(bpm) = parse_hr_value(&data.value) {
                                CURRENT_BPM.store(bpm, Ordering::SeqCst);
                                let _ = app_handle.emit("hr-update", bpm);
                            }
                        }
                    }
                    None => {
                        // Stream ended, device disconnected
                        IS_CONNECTED.store(false, Ordering::SeqCst);
                        CURRENT_BPM.store(0, Ordering::SeqCst);
                        let _ = app_handle.emit("hr-update", 0u16);
                        return Ok(());
                    }
                }
            }
            _ = tokio::time::sleep(std::time::Duration::from_secs(2)) => {
                // Periodic check for stop signal
            }
        }
    }
}
