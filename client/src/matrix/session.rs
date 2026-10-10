use matrix_sdk::{
    authentication::matrix::MatrixSession,
    config::RequestConfig,
    encryption::{BackupDownloadStrategy, EncryptionSettings},
    ruma::UserId,
    Client, SessionMeta, SessionTokens,
};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    sync::atomic::{AtomicU64, Ordering},
};
use tokio::sync::Mutex;
use zeroize::Zeroize;

use crate::storage::{
    paths::app_paths,
    profile_cache,
    profiles::{
        get_active_profile, list_profiles as list_saved_profiles, load_profile, remove_profile,
        resolve_profile_id, set_active_profile, touch_profile, update_profile_avatar, SavedProfile,
    },
    secure_store,
};

#[derive(Serialize, Deserialize, Clone, Default)]
pub struct SessionData {
    pub token: Option<String>,
    pub user_id: Option<String>,
    pub server: Option<String>,
    pub device_id: Option<String>,
    pub refresh_token: Option<String>,
}

#[derive(Clone, Default)]
pub struct Session {
    pub token: Option<String>,
    pub user_id: Option<String>,
    pub server: Option<String>,
    pub device_id: Option<String>,
    pub refresh_token: Option<String>,
    pub profile_id: Option<String>,
}

#[derive(Clone, Debug)]
pub struct ActiveProfileState {
    pub profile_id: String,
    pub user_id: String,
    pub server: String,
    pub avatar_url: Option<String>,
}

pub static SESSION: Mutex<Session> = Mutex::const_new(Session {
    token: None,
    user_id: None,
    server: None,
    device_id: None,
    refresh_token: None,
    profile_id: None,
});

pub static MATRIX_CLIENT: Mutex<Option<Client>> = Mutex::const_new(None);
static SESSION_EPOCH: AtomicU64 = AtomicU64::new(1);

impl SessionData {
    pub fn to_matrix_session(&self) -> Result<MatrixSession, String> {
        let user_id = <&UserId>::try_from(
            self.user_id
                .as_deref()
                .ok_or_else(|| "Нет user_id в session.json".to_string())?,
        )
        .map_err(|e| format!("Некорректный user_id в session.json: {}", e))?
        .to_owned();

        let device_id = self
            .device_id
            .clone()
            .unwrap_or_else(|| "PRISMCHAT".to_string())
            .into();

        let access_token = self
            .token
            .clone()
            .ok_or_else(|| "Нет access token в session.json".to_string())?;

        Ok(MatrixSession {
            meta: SessionMeta { user_id, device_id },
            tokens: SessionTokens {
                access_token,
                refresh_token: self.refresh_token.clone(),
            },
        })
    }

    pub fn from_matrix_session(server: &str, session: &MatrixSession) -> Self {
        Self {
            token: Some(session.tokens.access_token.clone()),
            user_id: Some(session.meta.user_id.to_string()),
            server: Some(server.to_string()),
            device_id: Some(session.meta.device_id.to_string()),
            refresh_token: session.tokens.refresh_token.clone(),
        }
    }
}

fn read_session_file(profile_id: &str) -> Result<SessionData, String> {
    let paths = app_paths()?.profile_paths(profile_id)?;
    let stored = fs::read(&paths.session_json).map_err(|e| {
        format!(
            "Не удалось прочитать session.json профиля {}: {}",
            profile_id, e
        )
    })?;
    let was_protected = secure_store::is_protected(&stored);
    let mut content = if was_protected {
        secure_store::read_protected(&paths.session_json)?
    } else {
        stored
    };
    let data = serde_json::from_slice::<SessionData>(&content).map_err(|e| {
        format!(
            "Не удалось распарсить session.json профиля {}: {}",
            profile_id, e
        )
    })?;
    content.zeroize();
    if !was_protected {
        write_session_file(profile_id, &data)?;
    }
    Ok(data)
}
fn write_session_file(profile_id: &str, data: &SessionData) -> Result<(), String> {
    let paths = app_paths()?.profile_paths(profile_id)?;
    paths.ensure_dirs()?;

    let mut json = serde_json::to_vec(data).map_err(|e| {
        format!(
            "Не удалось сериализовать session.json профиля {}: {}",
            profile_id, e
        )
    })?;
    let result = secure_store::write_protected(&paths.session_json, &json).map_err(|e| {
        format!(
            "Не удалось записать защищённый session.json профиля {}: {}",
            profile_id, e
        )
    });
    json.zeroize();
    result
}
fn bump_epoch() {
    SESSION_EPOCH.fetch_add(1, Ordering::SeqCst);
    crate::matrix::media_proxy::clear_media_capabilities();
    crate::matrix::attachments::clear_cache();
}

pub fn current_session_epoch() -> u64 {
    SESSION_EPOCH.load(Ordering::SeqCst)
}

pub async fn get_client() -> Result<Client, String> {
    MATRIX_CLIENT
        .lock()
        .await
        .clone()
        .ok_or_else(|| "Matrix SDK клиент не инициализирован".to_string())
}

fn directory_contains_store_data(path: &std::path::Path) -> bool {
    std::fs::read_dir(path)
        .ok()
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .any(|entry| {
            entry
                .metadata()
                .is_ok_and(|metadata| metadata.is_file() && metadata.len() > 0)
        })
}

/// Shared E2EE policy for persistent Matrix clients.
fn encryption_settings() -> EncryptionSettings {
    EncryptionSettings {
        auto_enable_cross_signing: true,
        backup_download_strategy: BackupDownloadStrategy::AfterDecryptionFailure,
        auto_enable_backups: true,
    }
}

async fn build_client(server: &str, profile_id: &str) -> Result<Client, String> {
    let paths = app_paths()?.profile_paths(profile_id)?;
    paths.ensure_dirs()?;

    if let Ok(cleanup) = crate::storage::maintenance::run_startup_maintenance(profile_id) {
        if cleanup.removed_files > 0 {
            println!(
                "[Storage] Автоочистка: удалено {} файлов, освобождено {} байт",
                cleanup.removed_files, cleanup.freed_bytes
            );
        }
        for warning in cleanup.warnings {
            eprintln!("[Storage] Предупреждение автоочистки: {warning}");
        }
    }

    let has_legacy_store = !paths.store_key_path.exists()
        && (directory_contains_store_data(&paths.sqlite_dir)
            || directory_contains_store_data(&paths.sqlite_cache_dir));
    let store_passphrase = if has_legacy_store {
        // Existing plaintext stores cannot be re-keyed in place safely.
        eprintln!("[Storage] Legacy Matrix store сохранён в совместимом режиме");
        None
    } else {
        Some(secure_store::load_or_create_store_passphrase(
            &paths.store_key_path,
        )?)
    };

    Client::builder()
        .homeserver_url(server)
        .with_encryption_settings(encryption_settings())
        // Matrix SDK owns retries for normal client requests.
        .request_config(RequestConfig::short_retry())
        .sqlite_store_with_cache_path(
            &paths.sqlite_dir,
            &paths.sqlite_cache_dir,
            store_passphrase.as_deref().map(|value| value.as_str()),
        )
        .build()
        .await
        .map_err(|e| format!("Не удалось создать Matrix SDK client: {}", e))
}

async fn apply_session_runtime(profile_id: &str, data: &SessionData, client: &Client) {
    // Subscribe /sync to the persistent event cache.
    if let Err(error) = client.event_cache().subscribe() {
        eprintln!("[Session] Не удалось включить Matrix Event Cache: {error}");
    }

    if let Ok(paths) = app_paths().and_then(|app| app.profile_paths(profile_id)) {
        paths.remove_legacy_presentation_cache();
    }

    {
        let mut session = SESSION.lock().await;
        session.token = data.token.clone();
        session.user_id = data.user_id.clone();
        session.server = data.server.clone();
        session.device_id = data.device_id.clone();
        session.refresh_token = data.refresh_token.clone();
        session.profile_id = Some(profile_id.to_string());
    }

    *MATRIX_CLIENT.lock().await = Some(client.clone());
    crate::matrix::e2ee::clear_pending_identity_reset().await;
    crate::matrix::verification::clear_for_epoch_change().await;
    profile_cache::clear_all().await;
    crate::matrix::auth::clear_avatar_cache().await;
    bump_epoch();
    crate::matrix::timeline_manager::reset().await;
    crate::matrix::rooms::clear_member_snapshots().await;
}

fn state_from_profile_and_data(
    profile_id: &str,
    data: &SessionData,
    saved_profile: Option<&SavedProfile>,
) -> Result<ActiveProfileState, String> {
    Ok(ActiveProfileState {
        profile_id: profile_id.to_string(),
        user_id: data
            .user_id
            .clone()
            .ok_or_else(|| format!("У профиля {} нет user_id", profile_id))?,
        server: data
            .server
            .clone()
            .ok_or_else(|| format!("У профиля {} нет homeserver", profile_id))?,
        avatar_url: saved_profile.and_then(|p| p.avatar_url.clone()),
    })
}

pub async fn activate_persistent_client_from_session(
    server: &str,
    matrix_session: MatrixSession,
    requested_profile_id: Option<&str>,
    avatar_url: Option<String>,
) -> Result<ActiveProfileState, String> {
    let data = SessionData::from_matrix_session(server, &matrix_session);
    let user_id = data
        .user_id
        .clone()
        .ok_or_else(|| "SDK не вернул user_id сессии".to_string())?;
    let profile_id = resolve_profile_id(requested_profile_id, &user_id, server)?;

    let previous_profile = load_profile(&profile_id)?;
    let effective_avatar =
        avatar_url.or_else(|| previous_profile.as_ref().and_then(|p| p.avatar_url.clone()));

    write_session_file(&profile_id, &data)?;
    let saved_profile = touch_profile(
        &profile_id,
        data.user_id.clone(),
        data.server.clone(),
        data.device_id.clone(),
        effective_avatar,
    )?;

    let client = build_client(server, &profile_id).await?;
    client.restore_session(matrix_session).await.map_err(|e| {
        format!(
            "Не удалось восстановить persistent-сессию профиля {}: {}",
            profile_id, e
        )
    })?;

    set_active_profile(Some(&profile_id))?;
    apply_session_runtime(&profile_id, &data, &client).await;

    state_from_profile_and_data(&profile_id, &data, Some(&saved_profile))
}

pub async fn restore_profile_fast(profile_id: &str) -> Result<ActiveProfileState, String> {
    let data = read_session_file(profile_id)?;
    let server = data
        .server
        .clone()
        .ok_or_else(|| format!("У профиля {} нет homeserver", profile_id))?;
    let matrix_session = data.to_matrix_session()?;
    let saved_profile = load_profile(profile_id)?;

    let client = build_client(&server, profile_id).await?;
    client.restore_session(matrix_session).await.map_err(|e| {
        format!(
            "Не удалось восстановить SDK сессию профиля {}: {}",
            profile_id, e
        )
    })?;

    let touched_profile = touch_profile(
        profile_id,
        data.user_id.clone(),
        data.server.clone(),
        data.device_id.clone(),
        saved_profile.as_ref().and_then(|p| p.avatar_url.clone()),
    )?;
    set_active_profile(Some(profile_id))?;
    apply_session_runtime(profile_id, &data, &client).await;

    state_from_profile_and_data(profile_id, &data, Some(&touched_profile))
}

pub async fn restore_active_client() -> Result<Option<ActiveProfileState>, String> {
    let Some(profile_id) = get_active_profile()? else {
        return Ok(None);
    };

    match restore_profile_fast(&profile_id).await {
        Ok(state) => Ok(Some(state)),
        Err(e) => {
            eprintln!("[Session] Не удалось восстановить активный профиль: {e}");
            Err(e)
        }
    }
}

pub async fn list_profiles() -> Result<(Vec<SavedProfile>, Option<String>), String> {
    let active = get_active_profile()?;
    let profiles = list_saved_profiles()?;
    Ok((profiles, active))
}

pub async fn switch_profile(profile_id: &str) -> Result<ActiveProfileState, String> {
    restore_profile_fast(profile_id).await
}

pub async fn delete_profile_by_id(profile_id: &str) -> Result<(), String> {
    let is_current = {
        let session = SESSION.lock().await;
        session.profile_id.as_deref() == Some(profile_id)
    };

    if is_current {
        crate::matrix::verification::clear_for_epoch_change().await;
        {
            let mut session = SESSION.lock().await;
            *session = Session::default();
        }
        *MATRIX_CLIENT.lock().await = None;
        profile_cache::clear_all().await;
        crate::matrix::auth::clear_avatar_cache().await;
        bump_epoch();
        crate::matrix::timeline_manager::reset().await;
        crate::matrix::rooms::clear_member_snapshots().await;
    }

    remove_profile(profile_id)
}

pub async fn clear_session() {
    crate::matrix::verification::clear_for_epoch_change().await;
    let current_profile = {
        let session = SESSION.lock().await;
        session.profile_id.clone()
    };

    if let Ok(client) = get_client().await {
        let _ = client.logout().await;
    }

    if let Some(profile_id) = current_profile {
        let _ = remove_profile(&profile_id);
    } else {
        let _ = set_active_profile(None);
    }

    {
        let mut session = SESSION.lock().await;
        *session = Session::default();
    }

    *MATRIX_CLIENT.lock().await = None;
    profile_cache::clear_all().await;
    crate::matrix::auth::clear_avatar_cache().await;
    bump_epoch();
    crate::matrix::timeline_manager::reset().await;
    crate::matrix::rooms::clear_member_snapshots().await;
}

pub async fn current_profile_id() -> Option<String> {
    let session = SESSION.lock().await;
    session.profile_id.clone()
}

pub async fn current_profile_meta() -> Option<SavedProfile> {
    let profile_id = current_profile_id().await?;
    load_profile(&profile_id).ok().flatten()
}

pub async fn update_current_profile_avatar(avatar_url: Option<String>) -> Result<(), String> {
    let Some(profile_id) = current_profile_id().await else {
        return Ok(());
    };

    update_profile_avatar(&profile_id, avatar_url)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn persistent_clients_use_automatic_key_recovery() {
        let settings = encryption_settings();

        assert!(settings.auto_enable_cross_signing);
        assert!(settings.auto_enable_backups);
        assert_eq!(
            settings.backup_download_strategy,
            BackupDownloadStrategy::AfterDecryptionFailure
        );
    }
}
