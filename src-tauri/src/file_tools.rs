use blake3::Hasher;
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use std::{
    collections::{HashMap, HashSet},
    fs::{self, File},
    io::{Read, Seek, SeekFrom},
    path::{Component, Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tauri::{AppHandle, Emitter, Manager, State};
use uuid::Uuid;

const PLAN_TTL: Duration = Duration::from_secs(600);
const JOURNAL_LIMIT: usize = 10;
const SAMPLE_SIZE: usize = 64 * 1024;
const HASH_BUFFER: usize = 1024 * 1024;

#[derive(Default)]
pub struct FileToolState {
    plans: Mutex<HashMap<String, StoredPlan>>,
    jobs: Mutex<HashMap<String, Arc<AtomicBool>>>,
}

#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct FilePlanEntry {
    pub source_path: String,
    pub target_path: String,
    pub original_name: String,
    pub target_name: String,
    pub size: u64,
    pub status: String,
    pub reason: Option<String>,
}

#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct FilePlan {
    pub plan_id: String,
    pub kind: String,
    pub created_at: u64,
    pub entries: Vec<FilePlanEntry>,
    pub ready_count: usize,
    pub invalid_count: usize,
}

#[derive(Clone)]
struct StoredEntry {
    public: FilePlanEntry,
    size: u64,
    modified_ms: u64,
}

#[derive(Clone)]
struct StoredPlan {
    public: FilePlan,
    entries: Vec<StoredEntry>,
    created: SystemTime,
}

#[derive(Clone, Deserialize, Debug)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum RenameRule {
    Prefix {
        value: String,
    },
    Suffix {
        value: String,
    },
    Replace {
        find: String,
        replacement: String,
        case_sensitive: bool,
    },
    Sequence {
        start: i64,
        step: i64,
        padding: usize,
        position: String,
        separator: String,
    },
    Case {
        mode: String,
    },
    ModifiedDate {
        format: String,
        position: String,
        separator: String,
    },
}

#[derive(Clone, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct RenamePreviewRequest {
    pub source_dir: String,
    #[serde(default)]
    pub recursive: bool,
    #[serde(default)]
    pub include_extension: bool,
    pub rules: Vec<RenameRule>,
}

#[derive(Clone, Deserialize, Debug)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum OrganizeMode {
    Extension,
    ModifiedDate { granularity: String },
    Size { small_bytes: u64, large_bytes: u64 },
}

#[derive(Clone, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ExtensionMapping {
    pub extension: String,
    pub folder: String,
}

#[derive(Clone, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct OrganizePreviewRequest {
    pub source_dir: String,
    pub target_dir: String,
    #[serde(default)]
    pub recursive: bool,
    pub mode: OrganizeMode,
    #[serde(default)]
    pub custom_mappings: Vec<ExtensionMapping>,
}

#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct OperationMove {
    pub source_path: String,
    pub target_path: String,
    pub size: u64,
    pub modified_ms: u64,
}

#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct FileOperationRecord {
    pub id: String,
    pub kind: String,
    pub created_at: u64,
    pub undone: bool,
    pub moves: Vec<OperationMove>,
}

#[derive(Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct OperationJournal {
    schema_version: u8,
    operations: Vec<FileOperationRecord>,
}

#[derive(Clone, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct DuplicateScanRequest {
    pub source_dir: String,
    #[serde(default)]
    pub recursive: bool,
    #[serde(default)]
    pub include_zero_byte: bool,
}

#[derive(Clone, Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct FileJobProgress {
    pub job_id: String,
    pub stage: String,
    pub processed_files: usize,
    pub total_files: usize,
    pub processed_bytes: u64,
    pub total_bytes: u64,
    pub error_count: usize,
}

#[derive(Clone, Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct DuplicateGroup {
    pub hash: String,
    pub size: u64,
    pub paths: Vec<String>,
    pub reclaimable_bytes: u64,
}

#[derive(Clone, Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct DuplicateScanComplete {
    pub job_id: String,
    pub cancelled: bool,
    pub groups: Vec<DuplicateGroup>,
    pub errors: Vec<String>,
    pub scanned_files: usize,
    pub reclaimable_bytes: u64,
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn modified_ms(metadata: &fs::Metadata) -> u64 {
    metadata
        .modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as u64)
        .unwrap_or_default()
}

fn path_key(path: &Path) -> String {
    let value = path.to_string_lossy().to_string();
    if cfg!(any(target_os = "windows", target_os = "macos")) {
        value.to_lowercase()
    } else {
        value
    }
}

fn canonical_dir(value: &str) -> Result<PathBuf, String> {
    let path = fs::canonicalize(value).map_err(|e| format!("无法访问目录：{e}"))?;
    if path.is_dir() {
        Ok(path)
    } else {
        Err("选择的路径不是目录".into())
    }
}

fn gather_files(
    root: &Path,
    recursive: bool,
    excluded: Option<&Path>,
    errors: &mut Vec<String>,
) -> Vec<PathBuf> {
    let mut output = Vec::new();
    let mut dirs = vec![root.to_path_buf()];
    while let Some(dir) = dirs.pop() {
        let entries = match fs::read_dir(&dir) {
            Ok(v) => v,
            Err(e) => {
                errors.push(format!("{}: {e}", dir.display()));
                continue;
            }
        };
        for entry in entries {
            let entry = match entry {
                Ok(v) => v,
                Err(e) => {
                    errors.push(e.to_string());
                    continue;
                }
            };
            let path = entry.path();
            let kind = match entry.file_type() {
                Ok(v) => v,
                Err(e) => {
                    errors.push(format!("{}: {e}", path.display()));
                    continue;
                }
            };
            if kind.is_symlink() {
                continue;
            }
            if kind.is_file() {
                output.push(path);
            } else if recursive && kind.is_dir() && !excluded.is_some_and(|x| path.starts_with(x)) {
                dirs.push(path);
            }
        }
    }
    output.sort_by_key(|p| path_key(p));
    output
}

fn split_name(path: &Path, include_extension: bool) -> (String, String) {
    let filename = path
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    if include_extension {
        return (filename, String::new());
    }
    let stem = path
        .file_stem()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let ext = path
        .extension()
        .map(|e| format!(".{}", e.to_string_lossy()))
        .unwrap_or_default();
    (stem, ext)
}

fn replace_insensitive(input: &str, find: &str, replacement: &str) -> String {
    if find.is_empty() {
        return input.to_string();
    }
    // Unicode-safe enough for common filenames: match on lowercase byte boundaries, otherwise keep input unchanged.
    let lower = input.to_lowercase();
    let needle = find.to_lowercase();
    let mut result = String::new();
    let mut cursor = 0;
    while let Some(offset) = lower[cursor..].find(&needle) {
        let start = cursor + offset;
        let end = start + needle.len();
        if !input.is_char_boundary(start) || !input.is_char_boundary(end) {
            return input.to_string();
        }
        result.push_str(&input[cursor..start]);
        result.push_str(replacement);
        cursor = end;
    }
    result.push_str(&input[cursor..]);
    result
}

fn apply_rules(
    path: &Path,
    index: usize,
    include_extension: bool,
    rules: &[RenameRule],
) -> Result<String, String> {
    let (mut name, extension) = split_name(path, include_extension);
    let metadata = fs::metadata(path).map_err(|e| e.to_string())?;
    for rule in rules {
        match rule {
            RenameRule::Prefix { value } => name = format!("{value}{name}"),
            RenameRule::Suffix { value } => name.push_str(value),
            RenameRule::Replace {
                find,
                replacement,
                case_sensitive,
            } => {
                name = if *case_sensitive {
                    name.replace(find, replacement)
                } else {
                    replace_insensitive(&name, find, replacement)
                }
            }
            RenameRule::Sequence {
                start,
                step,
                padding,
                position,
                separator,
            } => {
                let value = start.saturating_add(step.saturating_mul(index as i64));
                let token = if *padding > 0 {
                    format!("{value:0width$}", width = (*padding).min(12))
                } else {
                    value.to_string()
                };
                name = if position == "prefix" {
                    format!("{token}{separator}{name}")
                } else {
                    format!("{name}{separator}{token}")
                };
            }
            RenameRule::Case { mode } => {
                name = if mode == "upper" {
                    name.to_uppercase()
                } else {
                    name.to_lowercase()
                }
            }
            RenameRule::ModifiedDate {
                format,
                position,
                separator,
            } => {
                let date: DateTime<Local> = metadata.modified().map_err(|e| e.to_string())?.into();
                let token = date
                    .format(if format == "YYYYMMDD" {
                        "%Y%m%d"
                    } else {
                        "%Y-%m-%d"
                    })
                    .to_string();
                name = if position == "prefix" {
                    format!("{token}{separator}{name}")
                } else {
                    format!("{name}{separator}{token}")
                };
            }
        }
    }
    Ok(format!("{name}{extension}"))
}

fn filename_error(name: &str) -> Option<String> {
    if name.is_empty() || name == "." || name == ".." {
        return Some("文件名不能为空".into());
    }
    if name.chars().any(|c| c < ' ' || "<>:\"/\\|?*".contains(c)) {
        return Some("文件名包含非法字符".into());
    }
    if name.ends_with([' ', '.']) {
        return Some("文件名不能以空格或句点结尾".into());
    }
    let stem = name
        .split('.')
        .next()
        .unwrap_or_default()
        .to_ascii_uppercase();
    let reserved = [
        "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8",
        "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    ];
    reserved
        .contains(&stem.as_str())
        .then(|| "文件名是系统保留名称".into())
}

fn build_plan(kind: &str, raw: Vec<(PathBuf, PathBuf)>) -> Result<StoredPlan, String> {
    let source_keys: HashSet<_> = raw.iter().map(|(s, _)| path_key(s)).collect();
    let mut counts = HashMap::new();
    for (_, target) in &raw {
        *counts.entry(path_key(target)).or_insert(0usize) += 1;
    }
    let mut entries = Vec::new();
    for (source, target) in raw {
        let metadata = fs::metadata(&source).map_err(|e| format!("{}: {e}", source.display()))?;
        let target_name = target
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        let mut reason = filename_error(&target_name);
        if target.to_string_lossy().len() > 240 {
            reason = Some("目标路径过长".into());
        }
        if counts.get(&path_key(&target)).copied().unwrap_or_default() > 1 {
            reason = Some("多个文件使用同一目标名称".into());
        }
        if path_key(&source) != path_key(&target)
            && target.exists()
            && !(kind == "rename" && source_keys.contains(&path_key(&target)))
        {
            reason = Some("目标文件已存在".into());
        }
        let status = if source == target {
            "unchanged"
        } else if reason.is_some() {
            "invalid"
        } else {
            "ready"
        };
        let public = FilePlanEntry {
            source_path: source.to_string_lossy().to_string(),
            target_path: target.to_string_lossy().to_string(),
            original_name: source
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string(),
            target_name,
            size: metadata.len(),
            status: status.into(),
            reason,
        };
        entries.push(StoredEntry {
            public,
            size: metadata.len(),
            modified_ms: modified_ms(&metadata),
        });
    }
    let public_entries: Vec<_> = entries.iter().map(|e| e.public.clone()).collect();
    let public = FilePlan {
        plan_id: Uuid::new_v4().to_string(),
        kind: kind.into(),
        created_at: now_ms(),
        ready_count: public_entries
            .iter()
            .filter(|e| e.status == "ready")
            .count(),
        invalid_count: public_entries
            .iter()
            .filter(|e| e.status == "invalid")
            .count(),
        entries: public_entries,
    };
    Ok(StoredPlan {
        public,
        entries,
        created: SystemTime::now(),
    })
}

fn cache_plan(state: &FileToolState, plan: StoredPlan) -> Result<FilePlan, String> {
    let mut plans = state.plans.lock().map_err(|_| "预览缓存锁定失败")?;
    plans.retain(|_, p| p.created.elapsed().unwrap_or(PLAN_TTL) < PLAN_TTL);
    let public = plan.public.clone();
    plans.insert(public.plan_id.clone(), plan);
    Ok(public)
}

#[tauri::command]
pub async fn preview_batch_rename(
    request: RenamePreviewRequest,
    state: State<'_, FileToolState>,
) -> Result<FilePlan, String> {
    let plan = tauri::async_runtime::spawn_blocking(move || {
        let root = canonical_dir(&request.source_dir)?;
        let mut errors = Vec::new();
        let files = gather_files(&root, request.recursive, None, &mut errors);
        if files.is_empty() && !errors.is_empty() {
            return Err(errors.join("\n"));
        }
        let raw = files
            .into_iter()
            .enumerate()
            .map(|(index, source)| {
                let name = apply_rules(&source, index, request.include_extension, &request.rules)?;
                let target = source.parent().unwrap_or(&root).join(name);
                Ok((source, target))
            })
            .collect::<Result<Vec<_>, String>>()?;
        build_plan("rename", raw)
    })
    .await
    .map_err(|e| e.to_string())??;
    cache_plan(&state, plan)
}

fn relative_folder(value: &str) -> Result<PathBuf, String> {
    let path = Path::new(value.trim());
    if value.trim().is_empty()
        || path.is_absolute()
        || path
            .components()
            .any(|c| !matches!(c, Component::Normal(_)))
    {
        Err("自定义文件夹必须是目标目录下的相对路径，且不能包含 . 或 ..".into())
    } else {
        Ok(path.to_path_buf())
    }
}

fn ensure_target_is_not_symlink(root: &Path, relative: &Path) -> Result<(), String> {
    let mut current = root.to_path_buf();
    for component in relative.components() {
        current.push(component);
        if current.exists()
            && fs::symlink_metadata(&current)
                .map_err(|e| e.to_string())?
                .file_type()
                .is_symlink()
        {
            return Err(format!("目标路径包含符号链接：{}", current.display()));
        }
    }
    Ok(())
}

fn extension_category(ext: &str) -> &'static str {
    match ext {
        "jpg" | "jpeg" | "png" | "gif" | "webp" | "bmp" | "svg" | "heic" => "图片",
        "mp4" | "mkv" | "mov" | "avi" | "webm" | "flv" => "视频",
        "mp3" | "wav" | "flac" | "aac" | "ogg" | "m4a" => "音频",
        "pdf" | "doc" | "docx" | "xls" | "xlsx" | "ppt" | "pptx" | "txt" | "md" => "文档",
        "zip" | "7z" | "rar" | "tar" | "gz" | "bz2" => "压缩包",
        "rs" | "js" | "ts" | "tsx" | "jsx" | "py" | "java" | "c" | "cpp" | "h" | "css" | "html"
        | "json" | "toml" | "yaml" | "yml" => "代码",
        _ => "其他",
    }
}

#[tauri::command]
pub async fn preview_file_organize(
    request: OrganizePreviewRequest,
    state: State<'_, FileToolState>,
) -> Result<FilePlan, String> {
    let plan = tauri::async_runtime::spawn_blocking(move || {
        let source_root = canonical_dir(&request.source_dir)?;
        let target_root = canonical_dir(&request.target_dir)?;
        let mut mappings = HashMap::new();
        for item in request.custom_mappings {
            let ext = item.extension.trim().trim_start_matches('.').to_lowercase();
            if ext.is_empty() {
                return Err("自定义扩展名不能为空".into());
            }
            mappings.insert(ext, relative_folder(&item.folder)?);
        }
        let excluded = (target_root != source_root && target_root.starts_with(&source_root))
            .then_some(target_root.as_path());
        let mut errors = Vec::new();
        let files = gather_files(&source_root, request.recursive, excluded, &mut errors);
        if files.is_empty() && !errors.is_empty() {
            return Err(errors.join("\n"));
        }
        let mut raw = Vec::new();
        for source in files {
            let metadata = fs::metadata(&source).map_err(|e| e.to_string())?;
            let ext = source
                .extension()
                .map(|e| e.to_string_lossy().to_lowercase())
                .unwrap_or_default();
            let folder = if let Some(mapped) = mappings.get(&ext) {
                mapped.clone()
            } else {
                match &request.mode {
                    OrganizeMode::Extension => PathBuf::from(extension_category(&ext)),
                    OrganizeMode::ModifiedDate { granularity } => {
                        let date: DateTime<Local> =
                            metadata.modified().map_err(|e| e.to_string())?.into();
                        PathBuf::from(
                            date.format(if granularity == "year" { "%Y" } else { "%Y-%m" })
                                .to_string(),
                        )
                    }
                    OrganizeMode::Size {
                        small_bytes,
                        large_bytes,
                    } => {
                        if small_bytes >= large_bytes {
                            return Err("大小阈值必须从小到大".into());
                        }
                        PathBuf::from(if metadata.len() < *small_bytes {
                            "小文件"
                        } else if metadata.len() < *large_bytes {
                            "中等文件"
                        } else {
                            "大文件"
                        })
                    }
                }
            };
            ensure_target_is_not_symlink(&target_root, &folder)?;
            raw.push((
                source.clone(),
                target_root
                    .join(folder)
                    .join(source.file_name().unwrap_or_default()),
            ));
        }
        build_plan("organize", raw)
    })
    .await
    .map_err(|e| e.to_string())??;
    cache_plan(&state, plan)
}

fn verify_source(entry: &StoredEntry) -> Result<(), String> {
    let source = Path::new(&entry.public.source_path);
    let metadata =
        fs::metadata(source).map_err(|_| format!("源文件已不存在：{}", source.display()))?;
    if !metadata.is_file()
        || metadata.len() != entry.size
        || modified_ms(&metadata) != entry.modified_ms
    {
        Err(format!("源文件在预览后发生变化：{}", source.display()))
    } else {
        Ok(())
    }
}

fn safe_move(source: &Path, target: &Path) -> Result<(), String> {
    if target.exists() {
        return Err(format!("目标已存在：{}", target.display()));
    }
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    if fs::rename(source, target).is_ok() {
        return Ok(());
    }
    let temp = target
        .parent()
        .ok_or("目标目录无效")?
        .join(format!(".congmiao-copy-{}", Uuid::new_v4()));
    fs::copy(source, &temp).map_err(|e| format!("跨磁盘复制失败：{e}"))?;
    File::open(&temp)
        .and_then(|f| f.sync_all())
        .map_err(|e| e.to_string())?;
    fs::rename(&temp, target).map_err(|e| {
        let _ = fs::remove_file(&temp);
        format!("完成跨磁盘移动失败：{e}")
    })?;
    fs::remove_file(source).map_err(|e| {
        let _ = fs::remove_file(target);
        format!("删除原文件失败：{e}")
    })
}

fn execute_rename(entries: &[StoredEntry]) -> Result<Vec<(PathBuf, PathBuf)>, String> {
    let ready: Vec<_> = entries
        .iter()
        .filter(|e| e.public.status == "ready")
        .collect();
    let mut staged: Vec<(PathBuf, PathBuf, PathBuf)> = Vec::new();
    for entry in ready {
        let source = PathBuf::from(&entry.public.source_path);
        let temp = source
            .parent()
            .unwrap_or(Path::new("."))
            .join(format!(".congmiao-rename-{}", Uuid::new_v4()));
        if let Err(error) = fs::rename(&source, &temp) {
            for (original, staged_path, _) in staged.iter().rev() {
                let _ = fs::rename(staged_path, original);
            }
            return Err(format!("暂存重命名失败：{error}"));
        }
        staged.push((source, temp, PathBuf::from(&entry.public.target_path)));
    }
    let mut completed: Vec<(PathBuf, PathBuf)> = Vec::new();
    for index in 0..staged.len() {
        let (source, temp, target) = &staged[index];
        if let Err(error) = fs::rename(temp, target) {
            for (old, new) in completed.iter().rev() {
                let _ = fs::rename(new, old);
            }
            for (old, tmp, _) in staged[index..].iter().rev() {
                let _ = fs::rename(tmp, old);
            }
            return Err(format!("应用重命名失败并已尝试回滚：{error}"));
        }
        completed.push((source.clone(), target.clone()));
    }
    Ok(completed)
}

fn execute_organize(entries: &[StoredEntry]) -> Result<Vec<(PathBuf, PathBuf)>, String> {
    let mut completed: Vec<(PathBuf, PathBuf)> = Vec::new();
    for entry in entries.iter().filter(|e| e.public.status == "ready") {
        let source = PathBuf::from(&entry.public.source_path);
        let target = PathBuf::from(&entry.public.target_path);
        if let Err(error) = safe_move(&source, &target) {
            for (old, new) in completed.iter().rev() {
                let _ = safe_move(new, old);
            }
            return Err(format!("整理失败并已尝试回滚：{error}"));
        }
        completed.push((source, target));
    }
    Ok(completed)
}

fn rollback_record(record: &FileOperationRecord) -> Result<(), String> {
    if record.kind == "rename" {
        let inverse: Vec<_> = record
            .moves
            .iter()
            .map(|item| StoredEntry {
                public: FilePlanEntry {
                    source_path: item.target_path.clone(),
                    target_path: item.source_path.clone(),
                    original_name: String::new(),
                    target_name: String::new(),
                    size: item.size,
                    status: "ready".into(),
                    reason: None,
                },
                size: item.size,
                modified_ms: item.modified_ms,
            })
            .collect();
        execute_rename(&inverse).map(|_| ())
    } else {
        for item in record.moves.iter().rev() {
            safe_move(Path::new(&item.target_path), Path::new(&item.source_path))?;
        }
        Ok(())
    }
}

fn journal_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("file-operations.json"))
}

fn load_journal(app: &AppHandle) -> Result<OperationJournal, String> {
    let path = journal_path(app)?;
    let backup = path.with_extension("json.bak");
    if !path.exists() {
        if backup.exists() {
            fs::rename(&backup, &path).map_err(|e| e.to_string())?;
        } else {
            return Ok(OperationJournal {
                schema_version: 1,
                operations: Vec::new(),
            });
        }
    }
    serde_json::from_slice(&fs::read(path).map_err(|e| e.to_string())?)
        .map_err(|e| format!("操作日志损坏：{e}"))
}

fn save_journal(app: &AppHandle, journal: &OperationJournal) -> Result<(), String> {
    let path = journal_path(app)?;
    let temp = path.with_extension("json.tmp");
    let backup = path.with_extension("json.bak");
    fs::write(
        &temp,
        serde_json::to_vec_pretty(journal).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    if backup.exists() {
        fs::remove_file(&backup).map_err(|e| e.to_string())?;
    }
    if path.exists() {
        fs::rename(&path, &backup).map_err(|e| e.to_string())?;
    }
    if let Err(error) = fs::rename(&temp, &path) {
        if backup.exists() {
            let _ = fs::rename(&backup, &path);
        }
        return Err(error.to_string());
    }
    if backup.exists() {
        let _ = fs::remove_file(backup);
    }
    Ok(())
}

#[tauri::command]
pub async fn execute_file_plan(
    plan_id: String,
    app: AppHandle,
    state: State<'_, FileToolState>,
) -> Result<FileOperationRecord, String> {
    let plan = state
        .plans
        .lock()
        .map_err(|_| "预览缓存锁定失败")?
        .remove(&plan_id)
        .ok_or("预览已失效，请重新预览")?;
    if plan.created.elapsed().unwrap_or(PLAN_TTL) >= PLAN_TTL {
        return Err("预览已超过 10 分钟，请重新预览".into());
    }
    if plan.public.invalid_count > 0 || plan.public.ready_count == 0 {
        return Err("预览包含冲突或没有可执行项目".into());
    }
    tauri::async_runtime::spawn_blocking(move || {
        let mut journal = load_journal(&app)?;
        for entry in plan.entries.iter().filter(|e| e.public.status == "ready") {
            verify_source(entry)?;
        }
        let moved = if plan.public.kind == "rename" {
            execute_rename(&plan.entries)?
        } else {
            execute_organize(&plan.entries)?
        };
        let moves = moved
            .into_iter()
            .map(|(source, target)| {
                let metadata = fs::metadata(&target).map_err(|e| e.to_string())?;
                Ok(OperationMove {
                    source_path: source.to_string_lossy().to_string(),
                    target_path: target.to_string_lossy().to_string(),
                    size: metadata.len(),
                    modified_ms: modified_ms(&metadata),
                })
            })
            .collect::<Result<Vec<_>, String>>()?;
        let record = FileOperationRecord {
            id: Uuid::new_v4().to_string(),
            kind: plan.public.kind,
            created_at: now_ms(),
            undone: false,
            moves,
        };
        journal.schema_version = 1;
        journal.operations.insert(0, record.clone());
        journal.operations.truncate(JOURNAL_LIMIT);
        if let Err(error) = save_journal(&app, &journal) {
            rollback_record(&record)
                .map_err(|rollback| format!("写入撤销日志失败：{error}；回滚也失败：{rollback}"))?;
            return Err(format!("写入撤销日志失败，文件操作已回滚：{error}"));
        }
        Ok(record)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn list_file_operations(app: AppHandle) -> Result<Vec<FileOperationRecord>, String> {
    tauri::async_runtime::spawn_blocking(move || Ok(load_journal(&app)?.operations))
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn clear_file_operation_history(app: AppHandle) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || {
        save_journal(
            &app,
            &OperationJournal {
                schema_version: 1,
                operations: Vec::new(),
            },
        )
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn undo_file_operation(
    operation_id: String,
    app: AppHandle,
) -> Result<FileOperationRecord, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let mut journal = load_journal(&app)?;
        let index = journal
            .operations
            .iter()
            .position(|r| r.id == operation_id)
            .ok_or("找不到操作记录")?;
        let record = journal.operations[index].clone();
        if record.undone {
            return Err("该操作已经撤销".into());
        }
        let moved_target_keys: HashSet<_> = record
            .moves
            .iter()
            .map(|item| path_key(Path::new(&item.target_path)))
            .collect();
        for item in &record.moves {
            let target = Path::new(&item.target_path);
            let metadata = fs::metadata(target)
                .map_err(|_| format!("目标文件已不存在：{}", target.display()))?;
            if metadata.len() != item.size || modified_ms(&metadata) != item.modified_ms {
                return Err(format!("目标文件已被修改：{}", target.display()));
            }
            if Path::new(&item.source_path).exists()
                && !moved_target_keys.contains(&path_key(Path::new(&item.source_path)))
            {
                return Err(format!("原路径已被占用：{}", item.source_path));
            }
        }
        if record.kind == "rename" {
            let inverse: Vec<_> = record
                .moves
                .iter()
                .map(|item| StoredEntry {
                    public: FilePlanEntry {
                        source_path: item.target_path.clone(),
                        target_path: item.source_path.clone(),
                        original_name: String::new(),
                        target_name: String::new(),
                        size: item.size,
                        status: "ready".into(),
                        reason: None,
                    },
                    size: item.size,
                    modified_ms: item.modified_ms,
                })
                .collect();
            execute_rename(&inverse)?;
        } else {
            let mut restored: Vec<(PathBuf, PathBuf)> = Vec::new();
            for item in record.moves.iter().rev() {
                let old = PathBuf::from(&item.source_path);
                let new = PathBuf::from(&item.target_path);
                if let Err(error) = safe_move(&new, &old) {
                    for (source, target) in restored.iter().rev() {
                        let _ = safe_move(source, target);
                    }
                    return Err(format!("撤销失败并已尝试恢复：{error}"));
                }
                restored.push((old, new));
            }
        }
        journal.operations[index].undone = true;
        let result = journal.operations[index].clone();
        save_journal(&app, &journal)?;
        Ok(result)
    })
    .await
    .map_err(|e| e.to_string())?
}

fn sample_hash(path: &Path, size: u64) -> Result<String, String> {
    let mut file = File::open(path).map_err(|e| e.to_string())?;
    let mut hasher = Hasher::new();
    let first_len = size.min(SAMPLE_SIZE as u64) as usize;
    let mut first = vec![0; first_len];
    file.read_exact(&mut first).map_err(|e| e.to_string())?;
    hasher.update(&first);
    if size > SAMPLE_SIZE as u64 {
        let tail_len = size.min(SAMPLE_SIZE as u64);
        file.seek(SeekFrom::End(-(tail_len as i64)))
            .map_err(|e| e.to_string())?;
        let mut tail = vec![0; tail_len as usize];
        file.read_exact(&mut tail).map_err(|e| e.to_string())?;
        hasher.update(&tail);
    }
    Ok(hasher.finalize().to_hex().to_string())
}

fn full_hash(path: &Path, cancel: &AtomicBool) -> Result<String, String> {
    let mut file = File::open(path).map_err(|e| e.to_string())?;
    let mut hasher = Hasher::new();
    let mut buffer = vec![0; HASH_BUFFER];
    loop {
        if cancel.load(Ordering::Relaxed) {
            return Err("cancelled".into());
        }
        let count = file.read(&mut buffer).map_err(|e| e.to_string())?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }
    Ok(hasher.finalize().to_hex().to_string())
}

fn emit_progress(app: &AppHandle, progress: FileJobProgress) {
    let _ = app.emit("file-tool-progress", progress);
}

fn scan_duplicates(
    app: AppHandle,
    job_id: String,
    request: DuplicateScanRequest,
    cancel: Arc<AtomicBool>,
) -> DuplicateScanComplete {
    let empty = |errors: Vec<String>, cancelled| DuplicateScanComplete {
        job_id: job_id.clone(),
        cancelled,
        groups: Vec::new(),
        errors,
        scanned_files: 0,
        reclaimable_bytes: 0,
    };
    let root = match canonical_dir(&request.source_dir) {
        Ok(v) => v,
        Err(e) => return empty(vec![e], false),
    };
    let mut errors = Vec::new();
    let files = gather_files(&root, request.recursive, None, &mut errors);
    let scanned_files = files.len();
    let mut sizes: HashMap<u64, Vec<PathBuf>> = HashMap::new();
    for path in files {
        match fs::metadata(&path) {
            Ok(m) if request.include_zero_byte || m.len() > 0 => {
                sizes.entry(m.len()).or_default().push(path)
            }
            Ok(_) => {}
            Err(e) => errors.push(format!("{}: {e}", path.display())),
        }
    }
    let candidates: Vec<_> = sizes
        .into_iter()
        .filter(|(_, p)| p.len() > 1)
        .flat_map(|(s, p)| p.into_iter().map(move |path| (s, path)))
        .collect();
    let total_bytes = candidates.iter().map(|(s, _)| s).sum();
    let mut sampled: HashMap<(u64, String), Vec<PathBuf>> = HashMap::new();
    for (index, (size, path)) in candidates.iter().enumerate() {
        if cancel.load(Ordering::Relaxed) {
            return DuplicateScanComplete {
                job_id,
                cancelled: true,
                groups: Vec::new(),
                errors,
                scanned_files,
                reclaimable_bytes: 0,
            };
        }
        match sample_hash(path, *size) {
            Ok(hash) => sampled.entry((*size, hash)).or_default().push(path.clone()),
            Err(e) => errors.push(format!("{}: {e}", path.display())),
        }
        emit_progress(
            &app,
            FileJobProgress {
                job_id: job_id.clone(),
                stage: "sample".into(),
                processed_files: index + 1,
                total_files: candidates.len(),
                processed_bytes: 0,
                total_bytes,
                error_count: errors.len(),
            },
        );
    }
    let full: Vec<_> = sampled
        .into_iter()
        .filter(|(_, p)| p.len() > 1)
        .flat_map(|((s, _), p)| p.into_iter().map(move |path| (s, path)))
        .collect();
    let full_total_bytes: u64 = full.iter().map(|(size, _)| size).sum();
    let mut hashes: HashMap<(u64, String), Vec<PathBuf>> = HashMap::new();
    let mut bytes = 0;
    for (index, (size, path)) in full.iter().enumerate() {
        match full_hash(path, &cancel) {
            Ok(hash) => {
                hashes.entry((*size, hash)).or_default().push(path.clone());
            }
            Err(e) if e == "cancelled" => {
                return DuplicateScanComplete {
                    job_id,
                    cancelled: true,
                    groups: Vec::new(),
                    errors,
                    scanned_files,
                    reclaimable_bytes: 0,
                }
            }
            Err(e) => errors.push(format!("{}: {e}", path.display())),
        }
        bytes += size;
        emit_progress(
            &app,
            FileJobProgress {
                job_id: job_id.clone(),
                stage: "fullHash".into(),
                processed_files: index + 1,
                total_files: full.len(),
                processed_bytes: bytes,
                total_bytes: full_total_bytes,
                error_count: errors.len(),
            },
        );
    }
    let mut groups: Vec<_> = hashes
        .into_iter()
        .filter(|(_, p)| p.len() > 1)
        .map(|((size, hash), paths)| DuplicateGroup {
            reclaimable_bytes: size.saturating_mul(paths.len().saturating_sub(1) as u64),
            hash,
            size,
            paths: paths
                .into_iter()
                .map(|p| p.to_string_lossy().to_string())
                .collect(),
        })
        .collect();
    groups.sort_by_key(|g| std::cmp::Reverse(g.reclaimable_bytes));
    let reclaimable_bytes = groups.iter().map(|g| g.reclaimable_bytes).sum();
    DuplicateScanComplete {
        job_id,
        cancelled: false,
        groups,
        errors,
        scanned_files,
        reclaimable_bytes,
    }
}

#[tauri::command]
pub fn start_duplicate_scan(
    request: DuplicateScanRequest,
    app: AppHandle,
    state: State<'_, FileToolState>,
) -> Result<String, String> {
    canonical_dir(&request.source_dir)?;
    let job_id = Uuid::new_v4().to_string();
    let cancel = Arc::new(AtomicBool::new(false));
    state
        .jobs
        .lock()
        .map_err(|_| "扫描任务锁定失败")?
        .insert(job_id.clone(), cancel.clone());
    let task_id = job_id.clone();
    let running_job_id = job_id.clone();
    let task_app = app.clone();
    tauri::async_runtime::spawn(async move {
        let result = tauri::async_runtime::spawn_blocking(move || {
            scan_duplicates(task_app, task_id, request, cancel)
        })
        .await;
        let complete = result.unwrap_or_else(|e| DuplicateScanComplete {
            job_id: running_job_id.clone(),
            cancelled: false,
            groups: Vec::new(),
            errors: vec![e.to_string()],
            scanned_files: 0,
            reclaimable_bytes: 0,
        });
        let _ = app.emit("duplicate-scan-complete", complete);
        if let Some(state) = app.try_state::<FileToolState>() {
            if let Ok(mut jobs) = state.jobs.lock() {
                jobs.remove(&running_job_id);
            }
        }
    });
    Ok(job_id)
}

#[tauri::command]
pub fn cancel_file_job(job_id: String, state: State<'_, FileToolState>) -> Result<(), String> {
    let jobs = state.jobs.lock().map_err(|_| "扫描任务锁定失败")?;
    let flag = jobs.get(&job_id).ok_or("扫描任务不存在或已经结束")?;
    flag.store(true, Ordering::Relaxed);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn rename_rules_preserve_unicode_and_extension() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("照片.JPG");
        fs::write(&path, b"image").unwrap();
        let name = apply_rules(
            &path,
            0,
            false,
            &[
                RenameRule::Prefix {
                    value: "旅行-".into(),
                },
                RenameRule::Sequence {
                    start: 1,
                    step: 1,
                    padding: 3,
                    position: "suffix".into(),
                    separator: "_".into(),
                },
            ],
        )
        .unwrap();
        assert_eq!(name, "旅行-照片_001.JPG");
    }

    #[test]
    fn duplicate_targets_are_invalid() {
        let dir = tempdir().unwrap();
        let a = dir.path().join("a.txt");
        let b = dir.path().join("b.txt");
        fs::write(&a, b"a").unwrap();
        fs::write(&b, b"b").unwrap();
        let target = dir.path().join("same.txt");
        let plan = build_plan("rename", vec![(a, target.clone()), (b, target)]).unwrap();
        assert_eq!(plan.public.invalid_count, 2);
    }

    #[test]
    fn staged_hash_matches_equal_files() {
        let dir = tempdir().unwrap();
        let a = dir.path().join("a.bin");
        let b = dir.path().join("b.bin");
        let bytes = vec![42; SAMPLE_SIZE * 3];
        fs::write(&a, &bytes).unwrap();
        fs::write(&b, &bytes).unwrap();
        assert_eq!(
            sample_hash(&a, bytes.len() as u64).unwrap(),
            sample_hash(&b, bytes.len() as u64).unwrap()
        );
        assert_eq!(
            full_hash(&a, &AtomicBool::new(false)).unwrap(),
            full_hash(&b, &AtomicBool::new(false)).unwrap()
        );
    }

    #[test]
    fn relative_folders_cannot_escape() {
        assert!(relative_folder("../outside").is_err());
        assert!(relative_folder("images/2026").is_ok());
    }

    #[test]
    fn rename_exchange_uses_temporary_names() {
        let dir = tempdir().unwrap();
        let a = dir.path().join("a.txt");
        let b = dir.path().join("b.txt");
        fs::write(&a, b"A").unwrap();
        fs::write(&b, b"B").unwrap();
        let entry = |source: &Path, target: &Path| StoredEntry {
            public: FilePlanEntry {
                source_path: source.to_string_lossy().to_string(),
                target_path: target.to_string_lossy().to_string(),
                original_name: String::new(),
                target_name: String::new(),
                size: 1,
                status: "ready".into(),
                reason: None,
            },
            size: 1,
            modified_ms: 0,
        };
        execute_rename(&[entry(&a, &b), entry(&b, &a)]).unwrap();
        assert_eq!(fs::read(&a).unwrap(), b"B");
        assert_eq!(fs::read(&b).unwrap(), b"A");
    }
}
