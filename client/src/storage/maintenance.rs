use serde::{Deserialize, Serialize};
use serde_json::json;
use std::{
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    sync::OnceLock,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use crate::storage::paths::{app_paths, ProfilePaths};

const SETTINGS_FILE: &str = "storage_settings.json";
const PENDING_CLEANUP_FILE_PREFIX: &str = "pending_storage_cleanup-";
const DEFAULT_CACHE_LIMIT_MB: u64 = 1024;
const MIN_CACHE_LIMIT_MB: u64 = 64;
const MAX_DOWNLOAD_BYTES: usize = 100 * 1024 * 1024;

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct StoragePreferences {
    #[serde(default)]
    pub auto_cleanup_days: u32,
    #[serde(default = "default_cache_limit_mb")]
    pub cache_limit_mb: u64,
    #[serde(default)]
    pub downloads_dir: String,
    #[serde(default = "default_true")]
    pub auto_load_images: bool,
    #[serde(default = "default_true")]
    pub auto_load_videos: bool,
}

#[derive(Serialize, Clone, Debug, Default)]
pub struct StorageStats {
    pub sqlite_bytes: u64,
    pub event_cache_bytes: u64,
    pub media_bytes: u64,
    pub total_cache_bytes: u64,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
struct PendingStorageCleanup {
    #[serde(default)]
    clear_sqlite: bool,
    #[serde(default)]
    clear_event_cache: bool,
    #[serde(default)]
    scheduled_by_process: String,
}

#[derive(Clone, Debug, Default)]
pub struct CleanupResult {
    pub removed_files: u64,
    pub freed_bytes: u64,
    pub restart_required: bool,
    pub warnings: Vec<String>,
}

fn process_instance_id() -> &'static str {
    static INSTANCE_ID: OnceLock<String> = OnceLock::new();
    INSTANCE_ID
        .get_or_init(|| {
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos();
            format!("{}-{nanos}", std::process::id())
        })
        .as_str()
}

fn default_cache_limit_mb() -> u64 {
    DEFAULT_CACHE_LIMIT_MB
}

fn default_true() -> bool {
    true
}

impl Default for StoragePreferences {
    fn default() -> Self {
        Self {
            auto_cleanup_days: 0,
            cache_limit_mb: DEFAULT_CACHE_LIMIT_MB,
            downloads_dir: default_downloads_dir().to_string_lossy().into_owned(),
            auto_load_images: true,
            auto_load_videos: true,
        }
    }
}

fn settings_path() -> Result<PathBuf, String> {
    Ok(app_paths()?.config_root.join(SETTINGS_FILE))
}

fn pending_cleanup_path(profile_id: &str) -> Result<PathBuf, String> {
    crate::storage::paths::validate_profile_id(profile_id)?;
    Ok(app_paths()?
        .config_root
        .join(format!("{PENDING_CLEANUP_FILE_PREFIX}{profile_id}.json")))
}

pub fn discard_pending_cleanup(profile_id: &str) -> Result<(), String> {
    let path = pending_cleanup_path(profile_id)?;
    if path.exists() {
        fs::remove_file(path)
            .map_err(|error| format!("Не удалось удалить задание очистки: {error}"))?;
    }
    Ok(())
}

fn default_downloads_dir() -> PathBuf {
    dirs::download_dir().unwrap_or_else(|| {
        app_paths()
            .map(|paths| paths.data_root.join("downloads"))
            .unwrap_or_else(|_| PathBuf::from("downloads"))
    })
}

fn normalize_preferences(mut preferences: StoragePreferences) -> StoragePreferences {
    preferences.auto_cleanup_days = preferences.auto_cleanup_days.min(3650);
    preferences.cache_limit_mb = preferences
        .cache_limit_mb
        .clamp(MIN_CACHE_LIMIT_MB, 1024 * 1024);
    if preferences.downloads_dir.trim().is_empty() {
        preferences.downloads_dir = default_downloads_dir().to_string_lossy().into_owned();
    }
    preferences
}

pub fn load_preferences() -> StoragePreferences {
    normalize_preferences(
        settings_path()
            .ok()
            .and_then(|path| fs::read_to_string(path).ok())
            .and_then(|contents| serde_json::from_str::<StoragePreferences>(&contents).ok())
            .unwrap_or_default(),
    )
}

pub fn save_preferences(preferences: &StoragePreferences) -> Result<(), String> {
    let preferences = normalize_preferences(preferences.clone());
    let path = settings_path()?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("Не удалось создать папку настроек хранилища: {error}"))?;
    }
    let json = serde_json::to_string_pretty(&preferences)
        .map_err(|error| format!("Не удалось сериализовать настройки хранилища: {error}"))?;
    crate::storage::secure_store::write_private_atomic(&path, json.as_bytes())
        .map_err(|error| format!("Не удалось сохранить настройки хранилища: {error}"))
}

fn directory_size(path: &Path) -> u64 {
    let Ok(entries) = fs::read_dir(path) else {
        return 0;
    };
    entries
        .filter_map(Result::ok)
        .map(|entry| {
            let path = entry.path();
            match entry.file_type() {
                Ok(file_type) if file_type.is_dir() => directory_size(&path),
                Ok(file_type) if file_type.is_file() => {
                    entry.metadata().map(|metadata| metadata.len()).unwrap_or(0)
                }
                // Do not follow symlinks outside the application cache.
                _ => 0,
            }
        })
        .sum()
}

pub fn storage_stats(profile_id: &str) -> Result<StorageStats, String> {
    let paths = app_paths()?.profile_paths(profile_id)?;
    let sqlite_bytes = directory_size(&paths.sqlite_dir);
    let event_cache_bytes = directory_size(&paths.sqlite_cache_dir);
    let media_bytes = directory_size(&paths.media_cache_dir);
    Ok(StorageStats {
        sqlite_bytes,
        event_cache_bytes,
        media_bytes,
        total_cache_bytes: sqlite_bytes
            .saturating_add(event_cache_bytes)
            .saturating_add(media_bytes),
    })
}

fn remove_directory_contents(path: &Path, result: &mut CleanupResult) {
    let Ok(entries) = fs::read_dir(path) else {
        return;
    };
    for entry in entries.filter_map(Result::ok) {
        let entry_path = entry.path();
        let file_type = entry.file_type().ok();
        let is_directory = file_type.as_ref().is_some_and(|value| value.is_dir());
        let size = if is_directory {
            directory_size(&entry_path)
        } else if file_type.as_ref().is_some_and(|value| value.is_file()) {
            entry.metadata().map(|metadata| metadata.len()).unwrap_or(0)
        } else {
            0
        };
        let removal = if is_directory {
            fs::remove_dir_all(&entry_path)
        } else {
            fs::remove_file(&entry_path)
        };
        match removal {
            Ok(()) => {
                result.removed_files += 1;
                result.freed_bytes = result.freed_bytes.saturating_add(size);
            }
            Err(error) => result
                .warnings
                .push(format!("{}: {}", entry_path.display(), error)),
        }
    }
}

fn load_pending_cleanup(profile_id: &str) -> PendingStorageCleanup {
    pending_cleanup_path(profile_id)
        .ok()
        .and_then(|path| fs::read_to_string(path).ok())
        .and_then(|contents| serde_json::from_str::<PendingStorageCleanup>(&contents).ok())
        .unwrap_or_default()
}

fn save_pending_cleanup(profile_id: &str, pending: &PendingStorageCleanup) -> Result<(), String> {
    let path = pending_cleanup_path(profile_id)?;
    if !pending.clear_sqlite && !pending.clear_event_cache {
        if path.exists() {
            fs::remove_file(path)
                .map_err(|error| format!("Не удалось удалить задание очистки: {error}"))?;
        }
        return Ok(());
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("Не удалось создать папку задания очистки: {error}"))?;
    }
    let json = serde_json::to_string_pretty(pending)
        .map_err(|error| format!("Не удалось сериализовать задание очистки: {error}"))?;
    crate::storage::secure_store::write_private_atomic(&path, json.as_bytes())
        .map_err(|error| format!("Не удалось сохранить задание очистки: {error}"))
}

fn schedule_persistent_cleanup(
    profile_id: &str,
    clear_event_cache: bool,
    clear_sqlite: bool,
) -> Result<bool, String> {
    if !clear_event_cache && !clear_sqlite {
        return Ok(false);
    }
    let mut pending = load_pending_cleanup(profile_id);
    pending.clear_event_cache |= clear_event_cache;
    pending.clear_sqlite |= clear_sqlite;
    pending.scheduled_by_process = process_instance_id().to_string();
    save_pending_cleanup(profile_id, &pending)?;
    Ok(true)
}

pub fn clear_cache(
    profile_id: &str,
    clear_media: bool,
    clear_event_cache: bool,
    clear_sqlite: bool,
) -> Result<CleanupResult, String> {
    if !clear_media && !clear_event_cache && !clear_sqlite {
        return Err("Не выбран ни один тип данных для очистки".to_string());
    }
    let paths = app_paths()?.profile_paths(profile_id)?;
    let mut result = CleanupResult::default();
    if clear_media {
        remove_directory_contents(&paths.media_cache_dir, &mut result);
    }
    // SQLite state/crypto and the persistent event cache are opened by the
    // Matrix SDK. Deleting them while the client is alive risks corruption,
    // so the selected directories are removed before the next client start.
    result.restart_required =
        schedule_persistent_cleanup(profile_id, clear_event_cache, clear_sqlite)?;
    Ok(result)
}

fn collect_files(path: &Path, files: &mut Vec<(PathBuf, u64, SystemTime)>) {
    let Ok(entries) = fs::read_dir(path) else {
        return;
    };
    for entry in entries.filter_map(Result::ok) {
        let entry_path = entry.path();
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_dir() {
            collect_files(&entry_path, files);
        } else if file_type.is_file() {
            let Ok(metadata) = entry.metadata() else {
                continue;
            };
            files.push((
                entry_path,
                metadata.len(),
                metadata.modified().unwrap_or(UNIX_EPOCH),
            ));
        }
    }
}

fn delete_expired(files: &[(PathBuf, u64, SystemTime)], days: u32, result: &mut CleanupResult) {
    if days == 0 {
        return;
    }
    let cutoff = SystemTime::now()
        .checked_sub(Duration::from_secs(u64::from(days) * 86_400))
        .unwrap_or(UNIX_EPOCH);
    for (path, size, modified) in files {
        if *modified >= cutoff {
            continue;
        }
        match fs::remove_file(path) {
            Ok(()) => {
                result.removed_files += 1;
                result.freed_bytes = result.freed_bytes.saturating_add(*size);
            }
            Err(error) => result
                .warnings
                .push(format!("{}: {}", path.display(), error)),
        }
    }
}

fn enforce_limit(paths: &[&Path], limit_bytes: u64, result: &mut CleanupResult) {
    if limit_bytes == 0 {
        return;
    }
    let mut files = Vec::new();
    for path in paths {
        collect_files(path, &mut files);
    }
    let mut total: u64 = files.iter().map(|(_, size, _)| *size).sum();
    if total <= limit_bytes {
        return;
    }
    files.sort_by_key(|(_, _, modified)| *modified);
    for (path, size, _) in files {
        if total <= limit_bytes {
            break;
        }
        match fs::remove_file(&path) {
            Ok(()) => {
                total = total.saturating_sub(size);
                result.removed_files += 1;
                result.freed_bytes = result.freed_bytes.saturating_add(size);
            }
            Err(error) => result
                .warnings
                .push(format!("{}: {}", path.display(), error)),
        }
    }
}

fn run_policy(paths: &ProfilePaths) -> CleanupResult {
    let preferences = load_preferences();
    let mut result = CleanupResult::default();
    let mut media_files = Vec::new();
    collect_files(&paths.media_cache_dir, &mut media_files);
    delete_expired(&media_files, preferences.auto_cleanup_days, &mut result);
    enforce_limit(
        &[&paths.media_cache_dir],
        preferences.cache_limit_mb.saturating_mul(1024 * 1024),
        &mut result,
    );
    result
}

fn merge_cleanup(target: &mut CleanupResult, source: CleanupResult) {
    target.removed_files = target.removed_files.saturating_add(source.removed_files);
    target.freed_bytes = target.freed_bytes.saturating_add(source.freed_bytes);
    target.restart_required |= source.restart_required;
    target.warnings.extend(source.warnings);
}

fn apply_pending_cleanup(paths: &ProfilePaths) -> Result<CleanupResult, String> {
    let pending = load_pending_cleanup(&paths.profile_id);
    let mut result = CleanupResult::default();
    if pending.scheduled_by_process == process_instance_id() {
        return Ok(result);
    }
    if pending.clear_event_cache {
        remove_directory_contents(&paths.sqlite_cache_dir, &mut result);
    }
    if pending.clear_sqlite {
        remove_directory_contents(&paths.sqlite_dir, &mut result);
    }
    if pending.clear_event_cache || pending.clear_sqlite {
        // A stale incremental sync token cannot be reused with a fresh store.
        for filename in ["sync-v3.json", "sync-v3.json.tmp"] {
            let path = paths.profile_root.join(filename);
            if path.exists() {
                let size = fs::metadata(&path)
                    .map(|metadata| metadata.len())
                    .unwrap_or(0);
                match fs::remove_file(&path) {
                    Ok(()) => {
                        result.removed_files += 1;
                        result.freed_bytes = result.freed_bytes.saturating_add(size);
                    }
                    Err(error) => result
                        .warnings
                        .push(format!("{}: {}", path.display(), error)),
                }
            }
        }
        if result.warnings.is_empty() {
            save_pending_cleanup(&paths.profile_id, &PendingStorageCleanup::default())?;
        } else {
            return Err(format!(
                "Не удалось завершить очистку SQLite-хранилища: {}",
                result.warnings.join("; ")
            ));
        }
    }
    Ok(result)
}

pub fn run_startup_maintenance(profile_id: &str) -> Result<CleanupResult, String> {
    let paths = app_paths()?.profile_paths(profile_id)?;
    let mut result = apply_pending_cleanup(&paths)?;
    paths.ensure_dirs()?;
    merge_cleanup(&mut result, run_policy(&paths));
    Ok(result)
}

pub fn run_runtime_media_maintenance(profile_id: &str) -> Result<CleanupResult, String> {
    let paths = app_paths()?.profile_paths(profile_id)?;
    paths.ensure_dirs()?;
    Ok(run_policy(&paths))
}

fn safe_filename(filename: &str) -> String {
    let leaf = Path::new(filename)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("attachment");
    let cleaned: String = leaf
        .chars()
        .map(|character| {
            if character.is_control()
                || matches!(
                    character,
                    '<' | '>' | ':' | '"' | '/' | '\\' | '|' | '?' | '*'
                )
            {
                '_'
            } else {
                character
            }
        })
        .collect();
    if cleaned.trim().is_empty() {
        "attachment".to_string()
    } else {
        cleaned.trim().to_string()
    }
}

fn unique_download_path(directory: &Path, filename: &str) -> PathBuf {
    let filename = safe_filename(filename);
    let original = directory.join(&filename);
    if !original.exists() {
        return original;
    }
    let path = Path::new(&filename);
    let stem = path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("attachment");
    let extension = path.extension().and_then(|value| value.to_str());
    for index in 1..10_000 {
        let candidate = match extension {
            Some(extension) => directory.join(format!("{stem} ({index}).{extension}")),
            None => directory.join(format!("{stem} ({index})")),
        };
        if !candidate.exists() {
            return candidate;
        }
    }
    directory.join(format!("{}-{}", stem, unix_timestamp()))
}

pub fn save_download(bytes: &[u8], filename: &str) -> Result<PathBuf, String> {
    if bytes.len() > MAX_DOWNLOAD_BYTES {
        return Err("Файл превышает лимит 100 МиБ".to_owned());
    }
    let preferences = load_preferences();
    let directory = PathBuf::from(preferences.downloads_dir);
    fs::create_dir_all(&directory)
        .map_err(|error| format!("Не удалось создать папку загрузок: {error}"))?;
    for _ in 0..10_000 {
        let target = unique_download_path(&directory, filename);
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&target)
        {
            Ok(mut file) => {
                if let Err(error) = file.write_all(bytes).and_then(|_| file.sync_all()) {
                    let _ = fs::remove_file(&target);
                    return Err(format!("Не удалось сохранить файл: {error}"));
                }
                return Ok(target);
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(format!("Не удалось создать файл загрузки: {error}")),
        }
    }
    Err("Не удалось подобрать свободное имя файла".to_owned())
}
pub fn clear_temporary_voice_files() -> CleanupResult {
    let mut result = CleanupResult::default();
    let temp_dir = std::env::temp_dir();
    let Ok(entries) = fs::read_dir(temp_dir) else {
        return result;
    };
    for entry in entries.filter_map(Result::ok) {
        let name = entry.file_name().to_string_lossy().into_owned();
        if !name.starts_with("prismchat-voice-") {
            continue;
        }
        let path = entry.path();
        let size = entry.metadata().map(|metadata| metadata.len()).unwrap_or(0);
        match fs::remove_file(&path) {
            Ok(()) => {
                result.removed_files += 1;
                result.freed_bytes = result.freed_bytes.saturating_add(size);
            }
            Err(error) => result
                .warnings
                .push(format!("{}: {}", path.display(), error)),
        }
    }
    result
}

fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

pub fn export_diagnostic_report(profile_id: Option<&str>, output_path: &str) -> Result<(), String> {
    let preferences = load_preferences();
    let stats = profile_id
        .and_then(|id| storage_stats(id).ok())
        .unwrap_or_default();
    let profiles_count = crate::storage::profiles::list_profiles()
        .map(|profiles| profiles.len())
        .unwrap_or(0);

    let report = json!({
        "report_format": "prismchat-diagnostics-v1",
        "created_at_unix": unix_timestamp(),
        "privacy": {
            "access_tokens_included": false,
            "refresh_tokens_included": false,
            "passwords_included": false,
            "room_keys_included": false,
            "message_contents_included": false
        },
        "runtime": {
            "app_version": option_env!("CARGO_PKG_VERSION").unwrap_or("unknown"),
            "os": std::env::consts::OS,
            "architecture": std::env::consts::ARCH,
            "profiles_count": profiles_count,
            "active_profile_present": profile_id.is_some()
        },
        "storage": {
            "sqlite_bytes": stats.sqlite_bytes,
            "event_cache_bytes": stats.event_cache_bytes,
            "media_cache_bytes": stats.media_bytes,
            "total_cache_bytes": stats.total_cache_bytes,
            "auto_cleanup_days": preferences.auto_cleanup_days,
            "cache_limit_mb": preferences.cache_limit_mb,
            "auto_load_images": preferences.auto_load_images,
            "auto_load_videos": preferences.auto_load_videos,
            "downloads_directory_configured": !preferences.downloads_dir.trim().is_empty()
        }
    });

    let output = PathBuf::from(output_path);
    let parent = output
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty() && parent.is_dir())
        .ok_or_else(|| "Папка диагностического отчёта не существует".to_owned())?;
    let _ = parent;
    let json = serde_json::to_string_pretty(&report)
        .map_err(|error| format!("Не удалось сформировать диагностический отчёт: {error}"))?;
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&output)
        .map_err(|error| format!("Не удалось создать диагностический отчёт: {error}"))?;
    file.write_all(json.as_bytes())
        .and_then(|_| file.sync_all())
        .map_err(|error| format!("Не удалось сохранить диагностический отчёт: {error}"))
}

#[cfg(test)]
mod tests {
    use super::safe_filename;

    #[test]
    fn download_filename_cannot_escape_directory() {
        assert_eq!(safe_filename("../secret.txt"), "secret.txt");
        assert_eq!(safe_filename("bad:name?.txt"), "bad_name_.txt");
    }
}
