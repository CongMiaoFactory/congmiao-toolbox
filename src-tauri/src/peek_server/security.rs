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

const SCHEMA_VERSION: u8 = 2;
const ATTEMPT_WINDOW_MS: u64 = 60 * 1000;
const MAX_AUTH_FAILURES: usize = 10;
const MAX_LOGS: usize = 500;
const LOG_RETENTION_MS: u64 = 30 * 24 * 60 * 60 * 1000;
const ACCESS_LOG_DEBOUNCE_MS: u64 = 30 * 1000;

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
pub struct ConnectionLog {
    pub id: String,
    pub timestamp: u64,
    pub ip: String,
    pub event: String,
    pub success: bool,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PersistedSecurity {
    schema_version: u8,
    config: PeekServerConfig,
    api_key_hash: Option<String>,
    api_key_created_at: Option<u64>,
    logs: Vec<ConnectionLog>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacySecurityV1 {
    config: PeekServerConfig,
    #[serde(default)]
    logs: Vec<ConnectionLog>,
}

#[derive(Clone, Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct PeekSecuritySnapshot {
    pub config: PeekServerConfig,
    pub api_key_configured: bool,
    pub api_key_created_at: Option<u64>,
    pub logs: Vec<ConnectionLog>,
}

#[derive(Clone, Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct IssuedApiKey {
    pub api_key: String,
    pub created_at: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AuthOutcome {
    Granted,
    Denied,
    RateLimited,
}

pub struct PeekSecurityState {
    path: PathBuf,
    data: Mutex<PersistedSecurity>,
    failed_attempts: Mutex<HashMap<String, Vec<u64>>>,
    last_log_write: Mutex<HashMap<String, u64>>,
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

fn push_log(data: &mut PersistedSecurity, ip: &str, event: &str, success: bool) {
    let now = now_ms();
    data.logs.insert(
        0,
        ConnectionLog {
            id: Uuid::new_v4().to_string(),
            timestamp: now,
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
        serde_json::to_vec_pretty(value).map_err(|error| error.to_string())?,
    )
    .map_err(|error| error.to_string())?;
    if backup.exists() {
        let _ = fs::remove_file(&backup);
    }
    if path.exists() {
        fs::rename(path, &backup).map_err(|error| error.to_string())?;
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

fn default_security() -> PersistedSecurity {
    PersistedSecurity {
        schema_version: SCHEMA_VERSION,
        config: PeekServerConfig::default(),
        api_key_hash: None,
        api_key_created_at: None,
        logs: Vec::new(),
    }
}

fn read_security(path: &Path) -> Option<PersistedSecurity> {
    let bytes = fs::read(path).ok()?;
    if let Ok(mut current) = serde_json::from_slice::<PersistedSecurity>(&bytes) {
        if current.schema_version == SCHEMA_VERSION {
            current
                .logs
                .retain(|item| now_ms().saturating_sub(item.timestamp) <= LOG_RETENTION_MS);
            current.logs.truncate(MAX_LOGS);
            return Some(current);
        }
    }

    // v0.2.7 used one token per paired device. Those tokens are deliberately
    // invalidated during migration; only the harmless listener config and logs survive.
    let value = serde_json::from_slice::<serde_json::Value>(&bytes).ok()?;
    if value.get("schemaVersion").and_then(|item| item.as_u64()) == Some(1) {
        let legacy = serde_json::from_value::<LegacySecurityV1>(value).ok()?;
        let mut migrated = default_security();
        migrated.config = legacy.config;
        migrated.logs = legacy.logs;
        migrated.logs.truncate(MAX_LOGS);
        return Some(migrated);
    }
    None
}

impl PeekSecurityState {
    pub fn load(app: &AppHandle) -> Result<Self, String> {
        let dir = app
            .path()
            .app_data_dir()
            .map_err(|error| error.to_string())?;
        fs::create_dir_all(&dir).map_err(|error| error.to_string())?;
        let path = dir.join("peek-security.json");
        let backup = path.with_extension("json.bak");
        if !path.exists() && backup.exists() {
            fs::rename(&backup, &path).map_err(|error| error.to_string())?;
        }

        let persisted = if path.exists() {
            match read_security(&path) {
                Some(value) => {
                    if value.schema_version == SCHEMA_VERSION {
                        let _ = save_atomic(&path, &value);
                    }
                    value
                }
                None => {
                    let corrupt = dir.join(format!("peek-security.corrupt.{}.json", now_ms()));
                    let _ = fs::copy(&path, corrupt);
                    let _ = fs::remove_file(&path);
                    default_security()
                }
            }
        } else {
            default_security()
        };

        Ok(Self {
            path,
            data: Mutex::new(persisted),
            failed_attempts: Mutex::new(HashMap::new()),
            last_log_write: Mutex::new(HashMap::new()),
        })
    }

    fn save(&self, data: &PersistedSecurity) -> Result<(), String> {
        save_atomic(&self.path, data)
    }

    pub fn snapshot(&self) -> PeekSecuritySnapshot {
        let data = self.data.lock().unwrap_or_else(|error| error.into_inner());
        PeekSecuritySnapshot {
            config: data.config.clone(),
            api_key_configured: data.api_key_hash.is_some(),
            api_key_created_at: data.api_key_created_at,
            logs: data.logs.clone(),
        }
    }

    pub fn config(&self) -> PeekServerConfig {
        self.data
            .lock()
            .unwrap_or_else(|error| error.into_inner())
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
        data.config = config.clone();
        self.save(&data)?;
        Ok(config)
    }

    pub fn generate_api_key(&self) -> Result<IssuedApiKey, String> {
        let api_key = format!("{}{}", Uuid::new_v4().simple(), Uuid::new_v4().simple());
        let created_at = now_ms();
        let mut data = self.data.lock().map_err(|_| "Peek 安全配置锁定失败")?;
        data.api_key_hash = Some(token_hash(&api_key));
        data.api_key_created_at = Some(created_at);
        push_log(&mut data, "local", "api_key_regenerated", true);
        self.save(&data)?;
        self.failed_attempts
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clear();
        Ok(IssuedApiKey {
            api_key,
            created_at,
        })
    }

    pub fn has_api_key(&self) -> bool {
        self.data
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .api_key_hash
            .is_some()
    }

    fn is_rate_limited(&self, ip: &str, record_failure: bool) -> bool {
        let now = now_ms();
        let mut attempts = self
            .failed_attempts
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let values = attempts.entry(ip.into()).or_default();
        values.retain(|time| now.saturating_sub(*time) < ATTEMPT_WINDOW_MS);
        if values.len() >= MAX_AUTH_FAILURES {
            return true;
        }
        if record_failure {
            values.push(now);
        }
        false
    }

    pub fn authenticate(&self, token: &str, ip: &str, endpoint: &str) -> AuthOutcome {
        if self.is_rate_limited(ip, false) {
            self.log_debounced(ip, "auth_rate_limited", false);
            return AuthOutcome::RateLimited;
        }

        let valid = if token.len() == 64 {
            let hash = token_hash(token);
            self.data
                .lock()
                .ok()
                .and_then(|data| data.api_key_hash.clone())
                .is_some_and(|stored| stored.as_bytes().ct_eq(hash.as_bytes()).into())
        } else {
            false
        };

        if !valid {
            let limited = self.is_rate_limited(ip, true);
            self.log_debounced(ip, "unauthorized", false);
            return if limited {
                AuthOutcome::RateLimited
            } else {
                AuthOutcome::Denied
            };
        }

        self.failed_attempts
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .remove(ip);
        self.log_debounced(ip, endpoint, true);
        AuthOutcome::Granted
    }

    pub fn logs(&self) -> Vec<ConnectionLog> {
        self.snapshot().logs
    }

    pub fn clear_logs(&self) -> Result<(), String> {
        let mut data = self.data.lock().map_err(|_| "Peek 安全配置锁定失败")?;
        data.logs.clear();
        self.save(&data)
    }

    pub fn log_server_event(&self, event: &str, success: bool) {
        if let Ok(mut data) = self.data.lock() {
            push_log(&mut data, "local", event, success);
            let _ = self.save(&data);
        }
    }

    fn log_debounced(&self, ip: &str, event: &str, success: bool) {
        let now = now_ms();
        let log_group = if success { "access" } else { event };
        let key = format!("{ip}:{log_group}:{success}");
        let should_write = self
            .last_log_write
            .lock()
            .map(|mut writes| {
                let last = writes.entry(key).or_default();
                if now.saturating_sub(*last) >= ACCESS_LOG_DEBOUNCE_MS {
                    *last = now;
                    true
                } else {
                    false
                }
            })
            .unwrap_or(false);
        if should_write {
            if let Ok(mut data) = self.data.lock() {
                push_log(&mut data, ip, event, success);
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
            data: Mutex::new(default_security()),
            failed_attempts: Mutex::new(HashMap::new()),
            last_log_write: Mutex::new(HashMap::new()),
        }
    }

    #[test]
    fn generated_key_authenticates_and_raw_key_is_not_persisted() {
        let state = state();
        let issued = state.generate_api_key().unwrap();
        assert_eq!(
            state.authenticate(&issued.api_key, "127.0.0.1", "status"),
            AuthOutcome::Granted
        );
        assert!(!fs::read_to_string(&state.path)
            .unwrap()
            .contains(&issued.api_key));
    }

    #[test]
    fn regenerating_key_invalidates_the_previous_key() {
        let state = state();
        let first = state.generate_api_key().unwrap();
        let second = state.generate_api_key().unwrap();
        assert_eq!(
            state.authenticate(&first.api_key, "127.0.0.1", "status"),
            AuthOutcome::Denied
        );
        assert_eq!(
            state.authenticate(&second.api_key, "127.0.0.1", "status"),
            AuthOutcome::Granted
        );
    }

    #[test]
    fn repeated_auth_failures_are_rate_limited() {
        let state = state();
        state.generate_api_key().unwrap();
        for _ in 0..MAX_AUTH_FAILURES {
            let _ = state.authenticate("bad", "10.0.0.2", "status");
        }
        assert_eq!(
            state.authenticate("bad", "10.0.0.2", "status"),
            AuthOutcome::RateLimited
        );
    }

    #[test]
    fn server_config_is_validated() {
        let state = state();
        assert!(state
            .set_config(PeekServerConfig {
                listen_scope: "public".into(),
                port: 3000,
            })
            .is_err());
        assert!(state
            .set_config(PeekServerConfig {
                listen_scope: "local".into(),
                port: 1023,
            })
            .is_err());
    }

    #[test]
    fn legacy_v1_migration_discards_device_tokens() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("peek-security.json");
        fs::write(
            &path,
            r#"{"schemaVersion":1,"config":{"listenScope":"lan","port":3456},"devices":[{"tokenHash":"secret"}],"logs":[]}"#,
        )
        .unwrap();
        let migrated = read_security(&path).unwrap();
        assert_eq!(migrated.schema_version, 2);
        assert_eq!(migrated.config.port, 3456);
        assert!(migrated.api_key_hash.is_none());
    }
}
