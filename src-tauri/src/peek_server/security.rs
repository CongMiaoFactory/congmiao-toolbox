use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
    sync::Mutex,
    time::{SystemTime, UNIX_EPOCH},
};
use subtle::ConstantTimeEq;
use tauri::{AppHandle, Manager};
use uuid::Uuid;

const SCHEMA_VERSION: u8 = 1;
const PAIRING_TTL_MS: u64 = 5 * 60 * 1000;
const ATTEMPT_WINDOW_MS: u64 = 60 * 1000;
const MAX_ATTEMPTS: usize = 5;
const MAX_DEVICES: usize = 20;
const MAX_LOGS: usize = 500;
const LOG_RETENTION_MS: u64 = 30 * 24 * 60 * 60 * 1000;
const ACCESS_WRITE_DEBOUNCE_MS: u64 = 30 * 1000;

#[derive(Clone, Serialize, Deserialize, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PeekServerConfig {
    pub listen_scope: String,
    pub port: u16,
}

impl Default for PeekServerConfig {
    fn default() -> Self {
        Self {
            listen_scope: "lan".into(),
            port: 3000,
        }
    }
}

#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct PairingSession {
    pub code: String,
    pub expires_at: u64,
}

#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct AuthorizedDevice {
    pub id: String,
    pub name: String,
    pub created_at: u64,
    pub last_seen_at: u64,
}

#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
struct StoredDevice {
    id: String,
    name: String,
    token_hash: String,
    created_at: u64,
    last_seen_at: u64,
}

impl From<&StoredDevice> for AuthorizedDevice {
    fn from(value: &StoredDevice) -> Self {
        Self {
            id: value.id.clone(),
            name: value.name.clone(),
            created_at: value.created_at,
            last_seen_at: value.last_seen_at,
        }
    }
}

#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ConnectionLog {
    pub id: String,
    pub timestamp: u64,
    pub device_id: Option<String>,
    pub device_name: Option<String>,
    pub ip: String,
    pub event: String,
    pub success: bool,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PersistedSecurity {
    schema_version: u8,
    config: PeekServerConfig,
    devices: Vec<StoredDevice>,
    logs: Vec<ConnectionLog>,
}

#[derive(Clone, Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct PeekSecuritySnapshot {
    pub config: PeekServerConfig,
    pub pairing: Option<PairingSession>,
    pub devices: Vec<AuthorizedDevice>,
    pub logs: Vec<ConnectionLog>,
}

#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct PairRequest {
    pub code: String,
    pub device_name: String,
}

#[derive(Clone, Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct PairResponse {
    pub token: String,
    pub device: AuthorizedDevice,
}

#[derive(Clone, Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct PairInfo {
    pub pairing_available: bool,
    pub expires_at: Option<u64>,
    pub server_name: String,
}

struct SecurityData {
    persisted: PersistedSecurity,
    pairing: Option<PairingSession>,
}

pub struct PeekSecurityState {
    path: PathBuf,
    data: Mutex<SecurityData>,
    attempts: Mutex<HashMap<String, Vec<u64>>>,
    last_access_write: Mutex<HashMap<String, u64>>,
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn token_hash(token: &str) -> String {
    blake3::hash(token.as_bytes()).to_hex().to_string()
}

fn push_log(
    data: &mut PersistedSecurity,
    ip: &str,
    event: &str,
    success: bool,
    device: Option<&StoredDevice>,
) {
    let now = now_ms();
    data.logs.insert(
        0,
        ConnectionLog {
            id: Uuid::new_v4().to_string(),
            timestamp: now,
            device_id: device.map(|v| v.id.clone()),
            device_name: device.map(|v| v.name.clone()),
            ip: ip.into(),
            event: event.into(),
            success,
        },
    );
    data.logs
        .retain(|item| now.saturating_sub(item.timestamp) <= LOG_RETENTION_MS);
    data.logs.truncate(MAX_LOGS);
}

fn save_atomic(path: &Path, value: &PersistedSecurity) -> Result<(), String> {
    let temp = path.with_extension("json.tmp");
    let backup = path.with_extension("json.bak");
    fs::write(
        &temp,
        serde_json::to_vec_pretty(value).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    if backup.exists() {
        let _ = fs::remove_file(&backup);
    }
    if path.exists() {
        fs::rename(path, &backup).map_err(|e| e.to_string())?;
    }
    if let Err(error) = fs::rename(&temp, path) {
        if backup.exists() {
            let _ = fs::rename(&backup, path);
        }
        return Err(error.to_string());
    }
    if backup.exists() {
        let _ = fs::remove_file(backup);
    }
    Ok(())
}

impl PeekSecurityState {
    pub fn load(app: &AppHandle) -> Result<Self, String> {
        let dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
        fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        let path = dir.join("peek-security.json");
        let backup = path.with_extension("json.bak");
        if !path.exists() && backup.exists() {
            fs::rename(&backup, &path).map_err(|e| e.to_string())?;
        }
        let default = PersistedSecurity {
            schema_version: SCHEMA_VERSION,
            config: PeekServerConfig::default(),
            devices: Vec::new(),
            logs: Vec::new(),
        };
        let persisted = if path.exists() {
            match fs::read(&path)
                .ok()
                .and_then(|bytes| serde_json::from_slice::<PersistedSecurity>(&bytes).ok())
                .filter(|v| v.schema_version == SCHEMA_VERSION)
            {
                Some(mut value) => {
                    value
                        .logs
                        .retain(|item| now_ms().saturating_sub(item.timestamp) <= LOG_RETENTION_MS);
                    value.logs.truncate(MAX_LOGS);
                    value.devices.truncate(MAX_DEVICES);
                    value
                }
                None => {
                    let backup = dir.join(format!("peek-security.corrupt.{}.json", now_ms()));
                    let _ = fs::copy(&path, backup);
                    let _ = fs::remove_file(&path);
                    default
                }
            }
        } else {
            default
        };
        Ok(Self {
            path,
            data: Mutex::new(SecurityData {
                persisted,
                pairing: None,
            }),
            attempts: Mutex::new(HashMap::new()),
            last_access_write: Mutex::new(HashMap::new()),
        })
    }

    fn save(&self, data: &SecurityData) -> Result<(), String> {
        save_atomic(&self.path, &data.persisted)
    }

    pub fn snapshot(&self) -> PeekSecuritySnapshot {
        let mut data = self.data.lock().unwrap_or_else(|e| e.into_inner());
        if data
            .pairing
            .as_ref()
            .is_some_and(|p| p.expires_at <= now_ms())
        {
            data.pairing = None;
        }
        PeekSecuritySnapshot {
            config: data.persisted.config.clone(),
            pairing: data.pairing.clone(),
            devices: data
                .persisted
                .devices
                .iter()
                .map(AuthorizedDevice::from)
                .collect(),
            logs: data.persisted.logs.clone(),
        }
    }

    pub fn config(&self) -> PeekServerConfig {
        self.data
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .persisted
            .config
            .clone()
    }

    pub fn set_config(&self, config: PeekServerConfig) -> Result<PeekServerConfig, String> {
        if !matches!(config.listen_scope.as_str(), "lan" | "local") {
            return Err("监听范围必须是 lan 或 local".into());
        }
        if config.port < 1024 {
            return Err("端口必须在 1024 到 65535 之间".into());
        }
        let mut data = self.data.lock().map_err(|_| "Peek 安全配置锁定失败")?;
        data.persisted.config = config.clone();
        self.save(&data)?;
        Ok(config)
    }

    pub fn create_pairing(&self) -> PairingSession {
        let mut data = self.data.lock().unwrap_or_else(|e| e.into_inner());
        let code = format!("{:06}", Uuid::new_v4().as_u128() % 1_000_000);
        let session = PairingSession {
            code,
            expires_at: now_ms() + PAIRING_TTL_MS,
        };
        data.pairing = Some(session.clone());
        session
    }

    pub fn ensure_pairing_for_first_device(&self) -> Option<PairingSession> {
        let snapshot = self.snapshot();
        if snapshot.devices.is_empty() && snapshot.pairing.is_none() {
            Some(self.create_pairing())
        } else {
            snapshot.pairing
        }
    }

    pub fn clear_pairing(&self) {
        self.data.lock().unwrap_or_else(|e| e.into_inner()).pairing = None;
    }

    pub fn pair_info(&self) -> PairInfo {
        let snapshot = self.snapshot();
        PairInfo {
            pairing_available: snapshot.pairing.is_some(),
            expires_at: snapshot.pairing.map(|p| p.expires_at),
            server_name: "Congmiao Toolbox".into(),
        }
    }

    fn allow_attempt(&self, ip: &str) -> bool {
        let now = now_ms();
        let mut attempts = self.attempts.lock().unwrap_or_else(|e| e.into_inner());
        let values = attempts.entry(ip.into()).or_default();
        values.retain(|time| now.saturating_sub(*time) < ATTEMPT_WINDOW_MS);
        if values.len() >= MAX_ATTEMPTS {
            false
        } else {
            values.push(now);
            true
        }
    }

    pub fn pair(&self, request: PairRequest, ip: &str) -> Result<PairResponse, String> {
        if !self.allow_attempt(ip) {
            self.log_denied(ip, "pair_rate_limit");
            return Err("配对尝试过于频繁，请稍后再试".into());
        }
        let name = request.device_name.trim();
        if name.is_empty() || name.chars().count() > 64 {
            self.log_denied(ip, "pair_invalid_name");
            return Err("设备名称长度必须为 1 到 64 个字符".into());
        }
        let mut data = self.data.lock().map_err(|_| "Peek 安全配置锁定失败")?;
        if data.persisted.devices.len() >= MAX_DEVICES {
            return Err("授权设备已达到 20 台上限".into());
        }
        let valid = data.pairing.as_ref().is_some_and(|p| {
            p.expires_at > now_ms()
                && p.code
                    .as_bytes()
                    .ct_eq(request.code.trim().as_bytes())
                    .into()
        });
        if !valid {
            push_log(&mut data.persisted, ip, "pair", false, None);
            self.save(&data)?;
            return Err("配对码无效或已过期".into());
        }
        let token = format!("{}{}", Uuid::new_v4().simple(), Uuid::new_v4().simple());
        let now = now_ms();
        let stored = StoredDevice {
            id: Uuid::new_v4().to_string(),
            name: name.into(),
            token_hash: token_hash(&token),
            created_at: now,
            last_seen_at: now,
        };
        let public = AuthorizedDevice::from(&stored);
        data.persisted.devices.push(stored.clone());
        data.pairing = None;
        push_log(&mut data.persisted, ip, "pair", true, Some(&stored));
        self.save(&data)?;
        Ok(PairResponse {
            token,
            device: public,
        })
    }

    pub fn authenticate(&self, token: &str, ip: &str, endpoint: &str) -> Option<AuthorizedDevice> {
        if token.len() != 64 {
            return None;
        }
        let hash = token_hash(token);
        let now = now_ms();
        let mut data = self.data.lock().ok()?;
        let index = data
            .persisted
            .devices
            .iter()
            .position(|device| device.token_hash.as_bytes().ct_eq(hash.as_bytes()).into())?;
        data.persisted.devices[index].last_seen_at = now;
        let device = data.persisted.devices[index].clone();
        let should_write = {
            let mut writes = self.last_access_write.lock().ok()?;
            let last = writes.entry(device.id.clone()).or_default();
            if now.saturating_sub(*last) >= ACCESS_WRITE_DEBOUNCE_MS {
                *last = now;
                true
            } else {
                false
            }
        };
        if should_write {
            push_log(&mut data.persisted, ip, endpoint, true, Some(&device));
            let _ = self.save(&data);
        }
        Some(AuthorizedDevice::from(&device))
    }

    pub fn devices(&self) -> Vec<AuthorizedDevice> {
        self.snapshot().devices
    }
    pub fn logs(&self) -> Vec<ConnectionLog> {
        self.snapshot().logs
    }

    pub fn revoke(&self, id: &str) -> Result<(), String> {
        let mut data = self.data.lock().map_err(|_| "Peek 安全配置锁定失败")?;
        let index = data
            .persisted
            .devices
            .iter()
            .position(|v| v.id == id)
            .ok_or("找不到授权设备")?;
        let device = data.persisted.devices.remove(index);
        push_log(&mut data.persisted, "local", "revoke", true, Some(&device));
        self.save(&data)
    }

    pub fn clear_logs(&self) -> Result<(), String> {
        let mut data = self.data.lock().map_err(|_| "Peek 安全配置锁定失败")?;
        data.persisted.logs.clear();
        self.save(&data)
    }

    pub fn log_server_event(&self, event: &str, success: bool) {
        if let Ok(mut data) = self.data.lock() {
            push_log(&mut data.persisted, "local", event, success, None);
            let _ = self.save(&data);
        }
    }

    pub fn log_denied(&self, ip: &str, event: &str) {
        let now = now_ms();
        let key = format!("denied:{ip}:{event}");
        let should_write = self
            .last_access_write
            .lock()
            .map(|mut writes| {
                let last = writes.entry(key).or_default();
                if now.saturating_sub(*last) >= ACCESS_WRITE_DEBOUNCE_MS {
                    *last = now;
                    true
                } else {
                    false
                }
            })
            .unwrap_or(false);
        if should_write {
            if let Ok(mut data) = self.data.lock() {
                push_log(&mut data.persisted, ip, event, false, None);
                let _ = self.save(&data);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn state() -> PeekSecurityState {
        let dir = tempfile::tempdir().unwrap().keep();
        PeekSecurityState {
            path: dir.join("peek-security.json"),
            data: Mutex::new(SecurityData {
                persisted: PersistedSecurity {
                    schema_version: 1,
                    config: PeekServerConfig::default(),
                    devices: Vec::new(),
                    logs: Vec::new(),
                },
                pairing: None,
            }),
            attempts: Mutex::new(HashMap::new()),
            last_access_write: Mutex::new(HashMap::new()),
        }
    }

    #[test]
    fn pairing_is_one_time_and_raw_token_is_not_persisted() {
        let state = state();
        let pairing = state.create_pairing();
        let response = state
            .pair(
                PairRequest {
                    code: pairing.code.clone(),
                    device_name: "Phone".into(),
                },
                "127.0.0.1",
            )
            .unwrap();
        assert!(state
            .pair(
                PairRequest {
                    code: pairing.code,
                    device_name: "Other".into()
                },
                "127.0.0.2"
            )
            .is_err());
        let persisted = fs::read_to_string(&state.path).unwrap();
        assert!(!persisted.contains(&response.token));
        assert!(state
            .authenticate(&response.token, "127.0.0.1", "status")
            .is_some());
    }

    #[test]
    fn rate_limits_pair_attempts() {
        let state = state();
        for _ in 0..MAX_ATTEMPTS {
            let _ = state.pair(
                PairRequest {
                    code: "bad".into(),
                    device_name: "Phone".into(),
                },
                "10.0.0.2",
            );
        }
        assert_eq!(
            state
                .pair(
                    PairRequest {
                        code: "bad".into(),
                        device_name: "Phone".into()
                    },
                    "10.0.0.2"
                )
                .unwrap_err(),
            "配对尝试过于频繁，请稍后再试"
        );
    }

    #[test]
    fn revoke_invalidates_token() {
        let state = state();
        let pairing = state.create_pairing();
        let response = state
            .pair(
                PairRequest {
                    code: pairing.code,
                    device_name: "Phone".into(),
                },
                "127.0.0.1",
            )
            .unwrap();
        state.revoke(&response.device.id).unwrap();
        assert!(state
            .authenticate(&response.token, "127.0.0.1", "status")
            .is_none());
    }

    #[test]
    fn expired_pairing_code_is_rejected_and_config_is_validated() {
        let state = state();
        let session = state.create_pairing();
        state
            .data
            .lock()
            .unwrap()
            .pairing
            .as_mut()
            .unwrap()
            .expires_at = now_ms().saturating_sub(1);
        assert!(state
            .pair(
                PairRequest {
                    code: session.code,
                    device_name: "Phone".into()
                },
                "127.0.0.1"
            )
            .is_err());
        assert!(state
            .set_config(PeekServerConfig {
                listen_scope: "public".into(),
                port: 3000
            })
            .is_err());
        assert!(state
            .set_config(PeekServerConfig {
                listen_scope: "local".into(),
                port: 1023
            })
            .is_err());
    }
}
