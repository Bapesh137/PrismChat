//! Matrix E2EE account management.
//!
//! This module intentionally contains no cryptographic implementation. All
//! trust decisions, SAS values, secret storage and backup operations are owned
//! by matrix-sdk. QML only receives display-safe snapshots and drives actions.

use std::sync::Arc;

use matrix_sdk::{
    encryption::{
        backups::BackupState,
        recovery::{IdentityResetHandle, RecoveryError, RecoveryState},
        secret_storage::SecretStorageError,
        CrossSigningResetAuthType, VerificationState,
    },
    ruma::api::client::{keys::get_keys, uiaa},
    Client,
};
use tokio::sync::Mutex;
use zeroize::Zeroize;

use crate::{
    matrix::session::{current_session_epoch, get_client, SESSION},
    network::transport::Tx,
    protocol::commands::{EncryptionOverview, QmlResponse},
};

static E2EE_TX: Mutex<Option<Tx>> = Mutex::const_new(None);
static E2EE_OBSERVER_EPOCH: Mutex<u64> = Mutex::const_new(0);

struct PendingIdentityReset {
    epoch: u64,
    /// Present only while the homeserver still expects UIAA/OAuth. Once
    /// `IdentityResetHandle::reset()` succeeds, the handle must never be used
    /// again; the remaining step is a fresh keys query and state validation.
    handle: Option<Arc<IdentityResetHandle>>,
    auth_in_flight: bool,
    previous_master_key: Option<String>,
    expected_master_key: Option<String>,
}

static PENDING_IDENTITY_RESET: Mutex<Option<PendingIdentityReset>> = Mutex::const_new(None);

pub async fn clear_pending_identity_reset() {
    if let Some(pending) = PENDING_IDENTITY_RESET.lock().await.take() {
        if let Some(handle) = pending.handle {
            handle.cancel().await;
        }
    }
}

pub(crate) async fn identity_reset_pending() -> bool {
    PENDING_IDENTITY_RESET
        .lock()
        .await
        .as_ref()
        .is_some_and(|pending| pending.epoch == current_session_epoch())
}

pub async fn cancel_pending_identity_reset() -> Result<(), String> {
    if let Some(pending) = PENDING_IDENTITY_RESET.lock().await.take() {
        if let Some(handle) = pending.handle {
            handle.cancel().await;
        }
    }
    Ok(())
}

fn recovery_state_name(state: RecoveryState) -> &'static str {
    match state {
        RecoveryState::Enabled => "enabled",
        RecoveryState::Incomplete => "incomplete",
        RecoveryState::Disabled => "disabled",
        RecoveryState::Unknown => "unknown",
    }
}

fn backup_state_name(state: BackupState) -> &'static str {
    match state {
        BackupState::Enabled => "enabled",
        BackupState::Creating => "creating",
        BackupState::Enabling => "enabling",
        BackupState::Resuming => "resuming",
        BackupState::Downloading => "downloading",
        BackupState::Disabling => "disabling",
        BackupState::Unknown => "unknown",
    }
}

pub(crate) async fn send_event(response: QmlResponse) {
    let Ok(json) = serde_json::to_string(&response) else {
        eprintln!("[E2EE IPC] failed to serialize frontend event");
        return;
    };
    let Some(tx) = E2EE_TX.lock().await.clone() else {
        eprintln!("[E2EE IPC] event dropped: frontend sink is not installed");
        return;
    };
    let result = {
        let mut writer = tx.lock().await;
        writer
            .send(tokio_tungstenite::tungstenite::Message::Text(json.into()))
            .await
    };
    if let Err(error) = result {
        eprintln!("[E2EE IPC] failed to send frontend event: {error}");
    }
}

pub async fn set_event_sink(tx: Tx) {
    *E2EE_TX.lock().await = Some(tx);
}

pub async fn overview() -> Result<EncryptionOverview, String> {
    let client = get_client().await?;
    let encryption = client.encryption();
    let current_device_id = SESSION.lock().await.device_id.clone();
    let session_epoch = current_session_epoch();
    let identity_reset_pending = PENDING_IDENTITY_RESET
        .lock()
        .await
        .as_ref()
        .is_some_and(|pending| pending.epoch == session_epoch);
    let user_id = client
        .user_id()
        .ok_or_else(|| "Нет активного Matrix user_id".to_owned())?
        .to_owned();
    // During an OAuth/UIAA reset, the SDK has already generated and persisted
    // the new private identity but the homeserver still returns the old public
    // master key until `IdentityResetHandle::reset()` succeeds. Processing a
    // normal /keys/query in that window makes matrix-sdk clear the new private
    // keys as mismatching. Use the local SDK snapshot until the reset's guarded
    // reconciliation has confirmed that the server exposes the expected key.
    let identity = if identity_reset_pending {
        encryption
            .get_user_identity(&user_id)
            .await
            .map_err(|error| format!("Не удалось прочитать локальную Matrix identity: {error}"))?
    } else {
        encryption
            .request_user_identity(&user_id)
            .await
            .map_err(|error| format!("Не удалось получить Matrix identity: {error}"))?
    };
    let cross_signing_exists = identity.is_some();
    let own_device = encryption
        .get_own_device()
        .await
        .map_err(|error| format!("Не удалось прочитать текущее устройство: {error}"))?;
    let cross_signing = encryption.cross_signing_status().await;
    let current_device_verified = own_device
        .as_ref()
        .is_some_and(|device| device.is_cross_signed_by_owner());
    let identity_state = match (
        cross_signing_exists,
        cross_signing.as_ref(),
        current_device_verified,
    ) {
        (false, _, _) => "not_configured",
        (true, None, _) => "incomplete",
        (true, Some(status), _) if !status.is_complete() => "incomplete",
        (_, _, true) => "verified",
        (_, _, false) => "unverified",
    };
    let has_other_verified_device = encryption
        .has_devices_to_verify_against()
        .await
        .unwrap_or(false);
    let secret_storage_enabled = encryption
        .secret_storage()
        .is_enabled()
        .await
        .unwrap_or(false);
    let backup_exists_on_server = encryption
        .backups()
        .fetch_exists_on_server()
        .await
        .unwrap_or(false);
    Ok(EncryptionOverview {
        identity_state: identity_state.to_owned(),
        cross_signing_exists,
        current_device_verified,
        has_other_verified_device,
        recovery_state: recovery_state_name(encryption.recovery().state()).to_owned(),
        secret_storage_enabled,
        backup_state: backup_state_name(encryption.backups().state()).to_owned(),
        backup_exists_on_server,
        current_device_id,
        identity_reset_pending,
    })
}

pub async fn emit_overview() {
    let session_epoch = current_session_epoch();
    if let Ok(overview) = overview().await {
        if current_session_epoch() != session_epoch {
            return;
        }
        send_event(QmlResponse::EncryptionStateChanged {
            session_epoch,
            overview,
        })
        .await;
    }
}

fn password_auth(
    client: &Client,
    password: String,
    session: Option<String>,
) -> Result<uiaa::AuthData, String> {
    let user_id = client
        .user_id()
        .ok_or_else(|| "Нет активного Matrix user_id".to_owned())?;
    let mut auth = uiaa::Password::new(
        uiaa::UserIdentifier::Matrix(uiaa::MatrixUserIdentifier::new(
            user_id.localpart().to_owned(),
        )),
        password,
    );
    auth.session = session;
    Ok(uiaa::AuthData::Password(auth))
}

fn uiaa_session(error: &matrix_sdk::Error) -> Option<String> {
    error
        .as_uiaa_response()
        .and_then(|response| response.session.clone())
}

pub async fn bootstrap_cross_signing(
    password: Option<String>,
    session: Option<String>,
) -> Result<Option<String>, String> {
    let client = get_client().await?;
    let mut password = password.unwrap_or_default();
    let auth = if password.is_empty() {
        None
    } else {
        Some(password_auth(&client, password.clone(), session)?)
    };
    let has_auth = auth.is_some();
    // The SDK explicitly recommends bypassing the `if_needed` check on the
    // authenticated retry. The first attempt may already have created local
    // private keys even though the UIA-protected upload was rejected.
    let result = if has_auth {
        client.encryption().bootstrap_cross_signing(auth).await
    } else {
        client
            .encryption()
            .bootstrap_cross_signing_if_needed(None)
            .await
    };
    password.zeroize();
    match result {
        Ok(()) => Ok(None),
        Err(error) => {
            if let Some(session) = uiaa_session(&error) {
                Ok(Some(session))
            } else {
                Err(format!("Не удалось настроить личность: {error}"))
            }
        }
    }
}

async fn ensure_cross_signing_secrets_ready(client: &Client) -> Result<(), String> {
    if PENDING_IDENTITY_RESET
        .lock()
        .await
        .as_ref()
        .is_some_and(|pending| pending.epoch == current_session_epoch())
    {
        return Err("Identity reset ещё не завершён. Нельзя обновлять или экспортировать Recovery secrets до окончания OAuth/UIAA flow.".to_owned());
    }
    let encryption = client.encryption();
    encryption.wait_for_e2ee_initialization_tasks().await;

    let user_id = client
        .user_id()
        .ok_or_else(|| "Нет активного Matrix user_id".to_owned())?;
    let identity = encryption
        .request_user_identity(user_id)
        .await
        .map_err(|error| format!("Не удалось обновить новую Matrix identity: {error}"))?;
    if identity.is_none() {
        return Err("Homeserver ещё не возвращает новую cross-signing identity. Повторите действие после следующей синхронизации.".to_owned());
    }

    let status = encryption
        .cross_signing_status()
        .await
        .ok_or_else(|| "Локальное E2EE-хранилище ещё не готово".to_owned())?;
    if !status.is_complete() {
        return Err("Локальные private cross-signing keys неполны. Recovery нельзя создавать, пока новая cryptographic identity не завершена.".to_owned());
    }

    let own_device = encryption
        .get_own_device()
        .await
        .map_err(|error| format!("Не удалось проверить текущее устройство: {error}"))?
        .ok_or_else(|| "Текущее устройство отсутствует в E2EE device store".to_owned())?;
    if !own_device.is_cross_signed_by_owner() {
        return Err("Текущее устройство ещё не подписано собственной cross-signing identity. Дождитесь обновления ключей и повторите действие.".to_owned());
    }

    if encryption.verification_state().get() != VerificationState::Verified {
        return Err("Matrix SDK ещё не подтвердил новую подпись текущего устройства после /keys/query. Повторите проверку состояния через несколько секунд.".to_owned());
    }

    Ok(())
}

async fn server_master_key(client: &Client) -> Result<Option<String>, String> {
    let user_id = client
        .user_id()
        .ok_or_else(|| "Нет активного Matrix user_id".to_owned())?;
    let identity = client
        .encryption()
        .request_user_identity(user_id)
        .await
        .map_err(|error| format!("Не удалось получить identity с homeserver: {error}"))?;
    Ok(identity.and_then(|identity| {
        identity
            .master_key()
            .get_first_key()
            .map(|key| key.to_base64())
    }))
}

/// Read the public half currently associated with the private identity in the
/// SDK store. This performs no network request.
async fn local_master_key(client: &Client) -> Result<Option<String>, String> {
    let user_id = client
        .user_id()
        .ok_or_else(|| "Нет активного Matrix user_id".to_owned())?;
    let identity = client
        .encryption()
        .get_user_identity(user_id)
        .await
        .map_err(|error| format!("Не удалось прочитать локальную identity: {error}"))?;
    Ok(identity.and_then(|identity| {
        identity
            .master_key()
            .get_first_key()
            .map(|key| key.to_base64())
    }))
}

/// Probe `/keys/query` without feeding the response into the crypto state
/// machine. matrix-sdk clears private cross-signing keys when a processed
/// response contains a different master key. Immediately after OAuth, a
/// temporarily stale homeserver response must therefore not be applied.
async fn probe_server_master_key(client: &Client) -> Result<Option<String>, String> {
    let user_id = client
        .user_id()
        .ok_or_else(|| "Нет активного Matrix user_id".to_owned())?
        .to_owned();
    let mut request = get_keys::v3::Request::new();
    request.device_keys.insert(user_id.clone(), Vec::new());
    let response = client
        .send(request)
        .await
        .map_err(|error| format!("Не удалось проверить master key на homeserver: {error}"))?;
    let Some(raw) = response.master_keys.get(&user_id) else {
        return Ok(None);
    };
    let key = raw
        .deserialize()
        .map_err(|error| format!("Homeserver вернул некорректную master key: {error}"))?;
    Ok(key.keys.values().next().cloned())
}

async fn ensure_identity_reset_committed(
    client: &Client,
    previous_master_key: Option<&str>,
    expected_master_key: Option<&str>,
) -> Result<(), String> {
    let encryption = client.encryption();
    let status = encryption
        .cross_signing_status()
        .await
        .ok_or_else(|| "Локальное E2EE-хранилище ещё не готово".to_owned())?;
    if !status.is_complete() {
        return Err("SDK не сохранил полный комплект новых private cross-signing keys. Нужен повторный полный сброс identity; обычная проверка состояния это не исправит.".to_owned());
    }

    let expected_master_key = expected_master_key
        .ok_or_else(|| "SDK не предоставил новую локальную master cross-signing key".to_owned())?;
    if previous_master_key == Some(expected_master_key) {
        return Err("SDK не заменил локальную master cross-signing key".to_owned());
    }

    // The upload request already succeeded. Give the homeserver a short time
    // to expose the same key through /keys/query, but do not apply mismatching
    // responses to the crypto store.
    let mut probed_master_key = None;
    for attempt in 0..5 {
        probed_master_key = probe_server_master_key(client).await?;
        if probed_master_key.as_deref() == Some(expected_master_key) {
            break;
        }
        if attempt < 4 {
            tokio::time::sleep(std::time::Duration::from_millis(400)).await;
        }
    }
    if probed_master_key.as_deref() != Some(expected_master_key) {
        return Err("Homeserver принял OAuth, но /keys/query пока не возвращает новую master key. Локальные private keys сохранены; повторите синхронизацию состояния позже.".to_owned());
    }

    // Now it is safe to let matrix-sdk process the fresh query and update its
    // verification observable.
    let current_master_key = server_master_key(client)
        .await?
        .ok_or_else(|| "Homeserver не вернул новую master cross-signing key".to_owned())?;
    if current_master_key != expected_master_key {
        return Err("Master key изменилась между безопасной проверкой и применением ответа. Операция остановлена без повторного reset.".to_owned());
    }
    if previous_master_key == Some(current_master_key.as_str()) {
        return Err("Homeserver по-прежнему возвращает прежнюю master cross-signing key. Сброс нельзя считать завершённым.".to_owned());
    }

    let own_device = encryption
        .get_own_device()
        .await
        .map_err(|error| format!("Не удалось проверить подпись текущего устройства: {error}"))?
        .ok_or_else(|| "Текущее устройство отсутствует в E2EE device store".to_owned())?;
    if !own_device.is_cross_signed_by_owner() {
        return Err("Новая self-signing key не подписала текущее устройство на homeserver. Устройство осталось неподтверждённым.".to_owned());
    }

    if encryption.verification_state().get() != VerificationState::Verified {
        return Err(
            "Matrix SDK ещё не видит текущее устройство подтверждённым после свежего /keys/query."
                .to_owned(),
        );
    }

    if encryption.recovery().state() != RecoveryState::Disabled {
        return Err("Новая identity опубликована, но Recovery ещё не перешло в ожидаемое состояние Disabled. Не создавайте новый recovery key, пока состояние не обновится.".to_owned());
    }

    Ok(())
}

pub async fn enable_recovery(passphrase: Option<String>) -> Result<String, String> {
    let client = get_client().await?;
    ensure_cross_signing_secrets_ready(&client).await?;
    match client.encryption().recovery().state() {
        RecoveryState::Disabled => {}
        RecoveryState::Incomplete => {
            return Err("Recovery уже существует, но этому устройству не хватает secrets. Используйте «Восстановить устройство» со старым recovery key; создание нового Recovery сейчас может перезаписать доступные secrets.".to_owned());
        }
        RecoveryState::Enabled => {
            return Err(
                "Recovery уже настроено. Для ротации используйте «Сменить recovery key»."
                    .to_owned(),
            );
        }
        RecoveryState::Unknown => {
            return Err("Состояние Recovery ещё не получено от Matrix SDK. Дождитесь синхронизации и повторите действие.".to_owned());
        }
    }
    let mut passphrase = passphrase.unwrap_or_default();
    let result = if passphrase.is_empty() {
        client
            .encryption()
            .recovery()
            .enable()
            .wait_for_backups_to_upload()
            .await
    } else {
        client
            .encryption()
            .recovery()
            .enable()
            .wait_for_backups_to_upload()
            .with_passphrase(&passphrase)
            .await
    };
    passphrase.zeroize();
    let mut recovery_key =
        result.map_err(|error| format!("Не удалось настроить восстановление: {error}"))?;
    if client.encryption().recovery().state() != RecoveryState::Enabled {
        recovery_key.zeroize();
        return Err("Matrix SDK создал recovery key, но Recovery не перешло в состояние Enabled. Ключ не показан как рабочий; сначала обновите состояние шифрования.".to_owned());
    }
    Ok(recovery_key)
}

pub async fn recover(recovery_key: String) -> Result<(), String> {
    let client = get_client().await?;
    let mut recovery_key = recovery_key;
    let result = client.encryption().recovery().recover(&recovery_key).await;
    recovery_key.zeroize();
    match result {
        Ok(()) if client.encryption().recovery().state() == RecoveryState::Enabled => Ok(()),
        Ok(()) => Err("Recovery key принят, но после импорта Matrix SDK всё ещё сообщает неполное Recovery. Не считайте устройство восстановленным; проверьте cross-signing secrets и backup.".to_owned()),
        Err(RecoveryError::SecretStorage(SecretStorageError::ImportError { name, .. })) => Err(
            format!(
                "Recovery key принят, но secret {name} на сервере повреждён или не был записан полностью. Это не ошибка ввода ключа. Повторное восстановление тем же ключом не поможет; завершите или повторите сброс cryptographic identity."
            ),
        ),
        Err(error) => Err(format!("Не удалось восстановить ключи: {error}")),
    }
}

pub async fn change_recovery_key(
    old_recovery_key: Option<String>,
    passphrase: Option<String>,
) -> Result<String, String> {
    let client = get_client().await?;
    let recovery = client.encryption().recovery();
    let mut old_recovery_key = old_recovery_key.unwrap_or_default();
    let mut passphrase = passphrase.unwrap_or_default();
    let result = if old_recovery_key.is_empty() {
        if recovery.state() != RecoveryState::Enabled {
            old_recovery_key.zeroize();
            passphrase.zeroize();
            return Err("Смена recovery key доступна только когда Recovery уже включено. Если состояние неполное, сначала восстановите устройство старым recovery key.".to_owned());
        }
        if passphrase.is_empty() {
            recovery.reset_key().await
        } else {
            recovery.reset_key().with_passphrase(&passphrase).await
        }
    } else if passphrase.is_empty() {
        recovery.recover_and_reset(&old_recovery_key).await
    } else {
        recovery
            .recover_and_reset(&old_recovery_key)
            .with_passphrase(&passphrase)
            .await
    };
    old_recovery_key.zeroize();
    passphrase.zeroize();
    let mut recovery_key =
        result.map_err(|error| format!("Не удалось сменить recovery key: {error}"))?;
    if recovery.state() != RecoveryState::Enabled {
        recovery_key.zeroize();
        return Err("Recovery key был ротирован, но Matrix SDK не подтвердил состояние Enabled. Не считайте операцию завершённой.".to_owned());
    }
    Ok(recovery_key)
}

pub async fn repair_key_backup(recovery_key: String) -> Result<(), String> {
    let client = get_client().await?;
    let mut recovery_key = recovery_key;
    let result = client
        .encryption()
        .recovery()
        .recover_and_fix_backup(&recovery_key)
        .await;
    recovery_key.zeroize();
    result.map_err(|error| format!("Не удалось починить backup ключей: {error}"))?;
    if client.encryption().recovery().state() != RecoveryState::Enabled {
        return Err("SDK завершил repair, но Recovery осталось неполным. Серверный backup нельзя считать исправленным.".to_owned());
    }
    Ok(())
}

pub async fn enable_backup() -> Result<(), String> {
    get_client()
        .await?
        .encryption()
        .recovery()
        .enable_backup()
        .await
        .map_err(|error| format!("Не удалось включить резервную копию: {error}"))
}

/// Kept for protocol compatibility. Normal repair must go through Recovery,
/// not raw backup deletion, because Recovery owns the SSSS/backup invariants.
pub async fn recreate_backup() -> Result<(), String> {
    Err("Прямой пересоздание backup отключено. Используйте «Починить хранилище ключей» с recovery key.".to_owned())
}

pub enum IdentityResetStep {
    Done,
    Uiaa { session: String },
    OAuth { approval_url: String },
    Refreshing { reason: String },
}

async fn finish_identity_reset(
    client: &Client,
    epoch: u64,
    previous_master_key: Option<&str>,
    expected_master_key: Option<&str>,
) -> IdentityResetStep {
    match ensure_identity_reset_committed(client, previous_master_key, expected_master_key).await {
        Ok(()) => {
            let mut pending = PENDING_IDENTITY_RESET.lock().await;
            if pending
                .as_ref()
                .is_some_and(|pending| pending.epoch == epoch && pending.handle.is_none())
            {
                *pending = None;
            }
            IdentityResetStep::Done
        }
        Err(reason) => IdentityResetStep::Refreshing { reason },
    }
}

pub async fn reset_identity(
    password: Option<String>,
    session: Option<String>,
    oauth_approved: bool,
) -> Result<IdentityResetStep, String> {
    let client = get_client().await?;
    // Finish the one-time SDK startup task before creating a new private
    // identity. An auto-bootstrap racing the reset can otherwise replace the
    // private keys prepared by `reset_identity()`.
    client
        .encryption()
        .wait_for_e2ee_initialization_tasks()
        .await;
    let epoch = current_session_epoch();
    let mut pending = PENDING_IDENTITY_RESET.lock().await;
    if pending
        .as_ref()
        .is_some_and(|pending| pending.epoch != epoch)
    {
        if let Some(pending) = pending.take() {
            if let Some(handle) = pending.handle {
                handle.cancel().await;
            }
        }
    }
    if pending.is_none() {
        let previous_master_key = server_master_key(&client).await?;
        match client.encryption().recovery().reset_identity().await {
            Ok(None) => {
                let expected_master_key = local_master_key(&client).await.unwrap_or(None);
                *pending = Some(PendingIdentityReset {
                    epoch,
                    handle: None,
                    auth_in_flight: false,
                    previous_master_key: previous_master_key.clone(),
                    expected_master_key: expected_master_key.clone(),
                });
                drop(pending);
                return Ok(finish_identity_reset(
                    &client,
                    epoch,
                    previous_master_key.as_deref(),
                    expected_master_key.as_deref(),
                )
                .await);
            }
            Ok(Some(handle)) => {
                let expected_master_key = local_master_key(&client).await.unwrap_or(None);
                let next_step = match handle.auth_type() {
                    CrossSigningResetAuthType::Uiaa(info) => IdentityResetStep::Uiaa {
                        session: info.session.clone().unwrap_or_default(),
                    },
                    CrossSigningResetAuthType::OAuth(info) => IdentityResetStep::OAuth {
                        approval_url: info.approval_url.to_string(),
                    },
                };
                *pending = Some(PendingIdentityReset {
                    epoch,
                    handle: Some(Arc::new(handle)),
                    auth_in_flight: false,
                    previous_master_key,
                    expected_master_key,
                });
                return Ok(next_step);
            }
            Err(error) => return Err(format!("Не удалось начать сброс личности: {error}")),
        }
    }

    let previous_master_key = pending
        .as_ref()
        .and_then(|pending| pending.previous_master_key.clone());
    let expected_master_key = pending
        .as_ref()
        .and_then(|pending| pending.expected_master_key.clone());
    if pending
        .as_ref()
        .is_some_and(|pending| pending.handle.is_none())
    {
        drop(pending);
        return Ok(finish_identity_reset(
            &client,
            epoch,
            previous_master_key.as_deref(),
            expected_master_key.as_deref(),
        )
        .await);
    }
    if pending
        .as_ref()
        .is_some_and(|pending| pending.auth_in_flight)
    {
        return Ok(IdentityResetStep::Refreshing {
            reason: "OAuth/UIAA-подтверждение уже обрабатывается. Можно дождаться результата или отменить операцию.".to_owned(),
        });
    }
    let (handle, auth) = {
        let Some(pending) = pending.as_mut() else {
            return Err("Нет активного сброса личности".to_owned());
        };
        let Some(handle) = pending.handle.as_ref().cloned() else {
            return Err("Сброс личности уже ожидает обновления Matrix state".to_owned());
        };
        let auth = match handle.auth_type() {
            CrossSigningResetAuthType::Uiaa(_) => {
                let mut password = password.unwrap_or_default();
                if password.is_empty() {
                    return Ok(IdentityResetStep::Uiaa {
                        session: session.unwrap_or_default(),
                    });
                }
                let auth = password_auth(&client, password.clone(), session)?;
                password.zeroize();
                Some(auth)
            }
            CrossSigningResetAuthType::OAuth(info) => {
                if !oauth_approved {
                    return Ok(IdentityResetStep::OAuth {
                        approval_url: info.approval_url.to_string(),
                    });
                }
                if info.session.is_some() {
                    let mut auth = uiaa::OAuth::new();
                    auth.session = info.session.clone();
                    Some(uiaa::AuthData::OAuth(auth))
                } else {
                    // The unstable Synapse OAuth reset flow predates the UIAA
                    // session field. matrix-sdk's own 0.18 test continues it
                    // with no AuthData at all.
                    None
                }
            }
        };
        pending.auth_in_flight = true;
        (handle, auth)
    };
    // OAuth can poll for up to two minutes. Do not hold the global operation
    // lock during network I/O, otherwise cancel/logout cannot reach the SDK
    // handle until the polling has already finished.
    drop(pending);
    let result = handle.reset(auth).await;
    let mut pending = PENDING_IDENTITY_RESET.lock().await;
    let Some(current) = pending.as_mut().filter(|pending| pending.epoch == epoch) else {
        return Err("Сброс личности был отменён или Matrix-сессия сменилась".to_owned());
    };
    current.auth_in_flight = false;
    match result {
        Ok(()) => {
            // Authentication and upload have completed. Never submit the same
            // reset handle again merely because the SDK snapshot is catching
            // up.
            current.handle = None;
            drop(pending);
            Ok(finish_identity_reset(
                &client,
                epoch,
                previous_master_key.as_deref(),
                expected_master_key.as_deref(),
            )
            .await)
        }
        Err(error) => Err(format!(
            "Сброс личности не завершён. Recovery/backup уже могли быть отключены SDK; повторите сброс после устранения причины: {error}"
        )),
    }
}
/// Attach account-wide state observers once for each Matrix client/session.
pub async fn start_observers(tx: Tx, session_epoch: u64) {
    set_event_sink(tx).await;
    let mut installed_epoch = E2EE_OBSERVER_EPOCH.lock().await;
    if *installed_epoch == session_epoch {
        eprintln!("[E2EE] observers already installed epoch={session_epoch}; IPC sink refreshed");
        return;
    }
    let Ok(client) = get_client().await else {
        eprintln!("[E2EE] cannot install observers epoch={session_epoch}: client missing");
        return;
    };
    eprintln!(
        "[E2EE] installing observers epoch={session_epoch} device={}",
        client.device_id().map(|id| id.as_str()).unwrap_or("<none>")
    );
    crate::matrix::devices::clear_for_epoch_change().await;
    crate::matrix::verification::clear_for_epoch_change().await;
    // Verification handlers must exist before the first sync response: a
    // to-device request is consumed once and cannot be rediscovered from a
    // later sync merely because the UI observer was installed too late.
    crate::matrix::verification::install_event_handler(&client, session_epoch);
    crate::matrix::devices::observe(session_epoch).await;
    // Publish readiness only after every to-device handler is attached. The
    // sync loop uses this as a barrier before consuming its first response.
    *installed_epoch = session_epoch;
    drop(installed_epoch);
    tokio::spawn(async move {
        let mut states = client.encryption().verification_state();
        while states.next().await.is_some() {
            if current_session_epoch() != session_epoch {
                break;
            }
            emit_overview().await;
            crate::matrix::devices::emit_snapshot(session_epoch).await;
        }
    });
    tokio::spawn(async move {
        if current_session_epoch() == session_epoch {
            emit_overview().await;
        }
    });
}

pub async fn observers_ready(session_epoch: u64) -> bool {
    *E2EE_OBSERVER_EPOCH.lock().await == session_epoch
}
