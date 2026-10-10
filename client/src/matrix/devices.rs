//! Matrix login-session and E2EE-device management.
//!
//! Server sessions and crypto devices are deliberately merged by device ID.
//! Trust is derived only from matrix-sdk crypto objects.

use std::{
    collections::HashMap,
    sync::LazyLock,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use futures_util::StreamExt;
use matrix_sdk::{
    ruma::{
        api::client::{
            discovery::get_authorization_server_metadata::v1::{
                AccountManagementActionData, DeviceDeleteData,
            },
            uiaa,
        },
        DeviceId, OwnedDeviceId,
    },
    Client,
};
use tokio::sync::Mutex;
use zeroize::Zeroize;

use crate::{
    matrix::session::{current_session_epoch, get_client},
    protocol::commands::{DeviceDeleteAuthFlow, MatrixDeviceInfo, QmlResponse},
};

use super::e2ee::send_event;

#[derive(Debug, Clone)]
struct ServerDevice {
    device_id: String,
    display_name: Option<String>,
    last_seen_ts: Option<u64>,
    last_seen_ip: Option<String>,
}

#[derive(Debug, Clone)]
struct CryptoDevice {
    device_id: String,
    verified: bool,
    cross_signed: bool,
    dehydrated: bool,
    fingerprint: Option<String>,
}

#[derive(Debug)]
pub enum DeleteDevicesOutcome {
    Complete,
    WebRequired {
        url: String,
    },
    AuthRequired {
        operation_id: String,
        session: Option<String>,
        flows: Vec<DeviceDeleteAuthFlow>,
        password_supported: bool,
    },
}

#[derive(Debug, Clone)]
struct PendingDelete {
    epoch: u64,
    device_ids: Vec<OwnedDeviceId>,
    session: Option<String>,
}

static PENDING_DELETES: LazyLock<Mutex<HashMap<String, PendingDelete>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static LAST_EMITTED: Mutex<Option<(u64, String)>> = Mutex::const_new(None);

fn merge_devices(
    server_devices: Vec<ServerDevice>,
    crypto_devices: Vec<CryptoDevice>,
    current_device_id: Option<&str>,
) -> Vec<MatrixDeviceInfo> {
    let mut crypto_by_id: HashMap<String, CryptoDevice> = crypto_devices
        .into_iter()
        .map(|device| (device.device_id.clone(), device))
        .collect();
    let mut result = Vec::new();

    for server in server_devices {
        let crypto = crypto_by_id.remove(&server.device_id);
        let is_current = current_device_id == Some(server.device_id.as_str());
        let verification_state = match crypto.as_ref() {
            Some(device) if device.verified => "verified",
            Some(_) => "unverified",
            None => "unknown",
        };
        result.push(MatrixDeviceInfo {
            device_id: server.device_id,
            display_name: server.display_name,
            is_current,
            verification_state: verification_state.to_owned(),
            is_cross_signed: crypto.as_ref().is_some_and(|device| device.cross_signed),
            first_seen_ts: None,
            last_seen_ts: server.last_seen_ts,
            last_seen_ip: server.last_seen_ip,
            is_dehydrated: crypto.as_ref().map(|device| device.dehydrated),
            ed25519_fingerprint: crypto
                .as_ref()
                .and_then(|device| device.fingerprint.clone()),
            can_verify: !is_current && crypto.as_ref().is_some_and(|device| !device.verified),
            can_rename: true,
            can_sign_out: !is_current,
        });
    }

    // A key-query may know a crypto device before /devices metadata becomes
    // available. Keep it visible, but do not offer server-session operations.
    for (_, crypto) in crypto_by_id {
        let is_current = current_device_id == Some(crypto.device_id.as_str());
        result.push(MatrixDeviceInfo {
            device_id: crypto.device_id,
            display_name: None,
            is_current,
            verification_state: if crypto.verified {
                "verified"
            } else {
                "unverified"
            }
            .to_owned(),
            is_cross_signed: crypto.cross_signed,
            first_seen_ts: None,
            last_seen_ts: None,
            last_seen_ip: None,
            is_dehydrated: Some(crypto.dehydrated),
            ed25519_fingerprint: crypto.fingerprint,
            can_verify: !is_current && !crypto.verified,
            can_rename: false,
            can_sign_out: false,
        });
    }

    result.sort_by(|left, right| {
        right.is_current.cmp(&left.is_current).then_with(|| {
            right
                .last_seen_ts
                .unwrap_or_default()
                .cmp(&left.last_seen_ts.unwrap_or_default())
        })
    });
    result
}

pub async fn snapshot() -> Result<Vec<MatrixDeviceInfo>, String> {
    let client = get_client().await?;
    let user_id = client
        .user_id()
        .ok_or_else(|| "Нет активного Matrix user_id".to_owned())?;
    let current_device_id = client.device_id().map(ToString::to_string);

    let server = client
        .devices()
        .await
        .map_err(|error| format!("Не удалось получить список устройств: {error}"))?
        .devices
        .into_iter()
        .map(|device| ServerDevice {
            device_id: device.device_id.to_string(),
            display_name: device.display_name,
            last_seen_ts: device.last_seen_ts.map(|timestamp| timestamp.get().into()),
            last_seen_ip: device.last_seen_ip,
        })
        .collect();

    let crypto = client
        .encryption()
        .get_user_devices(user_id)
        .await
        .map_err(|error| format!("Не удалось получить состояние шифрования устройств: {error}"))?
        .devices()
        .map(|device| CryptoDevice {
            device_id: device.device_id().to_string(),
            verified: device.is_verified_with_cross_signing(),
            cross_signed: device.is_cross_signed_by_owner(),
            dehydrated: device.is_dehydrated(),
            fingerprint: device.ed25519_key().map(|key| key.to_base64()),
        })
        .collect();

    // `get_user_devices()` above is the fresh SDK crypto snapshot and its
    // `is_cross_signed_by_owner()` result is authoritative. Do not overwrite
    // the current device with `verification_state()`: that observable is
    // updated asynchronously and can still contain the pre-reset value.
    Ok(merge_devices(server, crypto, current_device_id.as_deref()))
}

pub async fn emit_snapshot(epoch: u64) {
    if current_session_epoch() != epoch {
        return;
    }
    if let Ok(devices) = snapshot().await {
        if current_session_epoch() == epoch {
            let fingerprint = serde_json::to_string(&devices).unwrap_or_default();
            let mut last = LAST_EMITTED.lock().await;
            if last
                .as_ref()
                .is_some_and(|(seen_epoch, seen)| *seen_epoch == epoch && seen == &fingerprint)
            {
                return;
            }
            *last = Some((epoch, fingerprint));
            drop(last);
            send_event(QmlResponse::DevicesChanged {
                session_epoch: epoch,
                devices,
            })
            .await;
        }
    }
}

pub async fn rename(device_id: &str, display_name: &str) -> Result<(), String> {
    let device_id = parse_device_id(device_id)?;
    let display_name = display_name.trim();
    if display_name.is_empty() {
        return Err("Введите название устройства".to_owned());
    }
    get_client()
        .await?
        .rename_device(&device_id, display_name)
        .await
        .map_err(|error| format!("Не удалось переименовать устройство: {error}"))?;
    emit_snapshot(current_session_epoch()).await;
    Ok(())
}

pub async fn begin_delete(device_ids: Vec<String>) -> Result<DeleteDevicesOutcome, String> {
    let client = get_client().await?;
    let current = client.device_id().map(ToString::to_string);
    let mut parsed = Vec::new();
    for id in device_ids {
        if current.as_deref() == Some(id.as_str()) {
            return Err("Текущее устройство нельзя удалить удалённо".to_owned());
        }
        parsed.push(parse_device_id(&id)?);
    }
    if parsed.is_empty() {
        return Err("Не выбраны устройства".to_owned());
    }

    if let Some(url) = oauth_device_management_url(&client, &parsed).await? {
        return Ok(DeleteDevicesOutcome::WebRequired { url });
    }

    match client.delete_devices(&parsed, None).await {
        Ok(_) => {
            emit_snapshot(current_session_epoch()).await;
            Ok(DeleteDevicesOutcome::Complete)
        }
        Err(error) => {
            let info = error
                .as_uiaa_response()
                .ok_or_else(|| format!("Не удалось выйти на устройствах: {error}"))?;
            let operation_id = new_operation_id();
            let flows = auth_flows(info);
            let password_supported = flows.iter().any(|flow| flow.supported);
            PENDING_DELETES.lock().await.insert(
                operation_id.clone(),
                PendingDelete {
                    epoch: current_session_epoch(),
                    device_ids: parsed,
                    session: info.session.clone(),
                },
            );
            Ok(DeleteDevicesOutcome::AuthRequired {
                operation_id,
                session: info.session.clone(),
                flows,
                password_supported,
            })
        }
    }
}

/// MAS/OAuth homeservers own account-session deletion in their web UI. For a
/// single session we deep-link to the exact device. The Matrix action schema
/// has no bulk device IDs, so bulk deletion opens the server's devices list.
async fn oauth_device_management_url(
    client: &Client,
    device_ids: &[OwnedDeviceId],
) -> Result<Option<String>, String> {
    let metadata = match client.oauth().cached_server_metadata().await {
        Ok(metadata) => metadata,
        Err(error) if error.is_not_supported() => return Ok(None),
        Err(error) => {
            return Err(format!(
                "Не удалось проверить web-управление устройствами сервера: {error}"
            ));
        }
    };

    let url = if let [device_id] = device_ids {
        metadata.account_management_url_with_action(AccountManagementActionData::DeviceDelete(
            DeviceDeleteData::new(device_id),
        ))
    } else {
        metadata.account_management_url_with_action(AccountManagementActionData::DevicesList)
    }
    .ok_or_else(|| {
        "Сервер использует OAuth, но не предоставил web-интерфейс управления устройствами"
            .to_owned()
    })?;

    Ok(Some(url.to_string()))
}

pub async fn submit_delete_password(
    operation_id: &str,
    password: String,
) -> Result<Vec<String>, String> {
    let pending = PENDING_DELETES
        .lock()
        .await
        .get(operation_id)
        .cloned()
        .ok_or_else(|| "Запрос подтверждения устарел".to_owned())?;
    if pending.epoch != current_session_epoch() {
        return Err("Аккаунт был изменён".to_owned());
    }
    let client = get_client().await?;
    let mut password = password;
    let auth = password_auth(&client, password.clone(), pending.session)?;
    let ids = pending
        .device_ids
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>();
    let result = client.delete_devices(&pending.device_ids, Some(auth)).await;
    password.zeroize();
    if let Err(error) = result {
        if let Some(info) = error.as_uiaa_response() {
            if let Some(stored) = PENDING_DELETES.lock().await.get_mut(operation_id) {
                stored.session = info.session.clone();
            }
        }
        return Err(format!("Не удалось подтвердить выход: {error}"));
    }
    PENDING_DELETES.lock().await.remove(operation_id);
    emit_snapshot(pending.epoch).await;
    Ok(ids)
}

pub async fn pending_delete_ids(operation_id: &str) -> Vec<String> {
    PENDING_DELETES
        .lock()
        .await
        .get(operation_id)
        .map(|pending| pending.device_ids.iter().map(ToString::to_string).collect())
        .unwrap_or_default()
}

pub async fn clear_for_epoch_change() {
    PENDING_DELETES.lock().await.clear();
    *LAST_EMITTED.lock().await = None;
}

pub async fn observe(epoch: u64) {
    let Ok(client) = get_client().await else {
        return;
    };
    let Ok(mut stream) = client.encryption().devices_stream().await else {
        return;
    };
    tokio::spawn(async move {
        while stream.next().await.is_some() {
            if current_session_epoch() != epoch {
                break;
            }
            emit_snapshot(epoch).await;
        }
    });
}

fn parse_device_id(device_id: &str) -> Result<OwnedDeviceId, String> {
    <&DeviceId>::try_from(device_id)
        .map(ToOwned::to_owned)
        .map_err(|_| "Некорректный ID устройства".to_owned())
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
        uiaa::UserIdentifier::Matrix(uiaa::MatrixUserIdentifier::new(user_id.as_str().to_owned())),
        password,
    );
    auth.session = session;
    Ok(uiaa::AuthData::Password(auth))
}

fn auth_flows(info: &uiaa::UiaaInfo) -> Vec<DeviceDeleteAuthFlow> {
    info.flows
        .iter()
        .map(|flow| {
            let stages = flow
                .stages
                .iter()
                .map(|stage| stage.as_str().to_owned())
                .collect::<Vec<_>>();
            let supported = stages.len() == 1 && stages[0] == "m.login.password";
            DeviceDeleteAuthFlow { stages, supported }
        })
        .collect()
}

fn new_operation_id() -> String {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::ZERO)
        .as_millis();
    format!("device-delete-{millis}")
}

#[cfg(test)]
fn is_inactive(last_seen_ts: Option<u64>, now_ms: u64) -> bool {
    const NINETY_DAYS_MS: u64 = 90 * 24 * 60 * 60 * 1000;
    last_seen_ts.is_some_and(|seen| now_ms.saturating_sub(seen) >= NINETY_DAYS_MS)
}

#[cfg(test)]
fn epoch_matches(event_epoch: u64, current_epoch: u64) -> bool {
    event_epoch == current_epoch
}

#[cfg(test)]
mod tests {
    use super::*;

    fn server(id: &str, seen: Option<u64>) -> ServerDevice {
        ServerDevice {
            device_id: id.to_owned(),
            display_name: None,
            last_seen_ts: seen,
            last_seen_ip: None,
        }
    }
    fn crypto(id: &str, signed: bool) -> CryptoDevice {
        CryptoDevice {
            device_id: id.to_owned(),
            verified: signed,
            cross_signed: signed,
            dehydrated: false,
            fingerprint: None,
        }
    }

    #[test]
    fn server_rename_is_reflected_in_merged_model() {
        let mut source = server("A", None);
        source.display_name = Some("Desktop PrismChat".to_owned());
        let merged = merge_devices(vec![source], vec![crypto("A", true)], None);
        assert_eq!(merged[0].display_name.as_deref(), Some("Desktop PrismChat"));
    }

    #[test]
    fn merges_server_and_crypto_by_id() {
        let merged = merge_devices(
            vec![server("A", Some(5))],
            vec![crypto("A", true)],
            Some("A"),
        );
        assert_eq!(merged.len(), 1);
        assert!(merged[0].is_current);
        assert_eq!(merged[0].verification_state, "verified");
    }

    #[test]
    fn distinguishes_unknown_from_unverified() {
        let merged = merge_devices(
            vec![server("A", None), server("B", None)],
            vec![crypto("B", false)],
            None,
        );
        assert_eq!(
            merged
                .iter()
                .find(|d| d.device_id == "A")
                .unwrap()
                .verification_state,
            "unknown"
        );
        assert_eq!(
            merged
                .iter()
                .find(|d| d.device_id == "B")
                .unwrap()
                .verification_state,
            "unverified"
        );
    }

    #[test]
    fn cross_signed_but_untrusted_is_not_reported_as_verified() {
        let crypto = CryptoDevice {
            device_id: "A".to_owned(),
            verified: false,
            cross_signed: true,
            dehydrated: false,
            fingerprint: None,
        };
        let merged = merge_devices(vec![server("A", None)], vec![crypto], None);
        assert_eq!(merged[0].verification_state, "unverified");
        assert!(merged[0].is_cross_signed);
    }

    #[test]
    fn missing_last_seen_is_not_inactive() {
        assert!(!is_inactive(None, u64::MAX));
    }

    #[test]
    fn ninety_days_is_inactive() {
        assert!(is_inactive(Some(0), 90 * 24 * 60 * 60 * 1000));
    }

    #[test]
    fn stale_session_events_are_rejected() {
        assert!(epoch_matches(4, 4));
        assert!(!epoch_matches(3, 4));
    }

    #[test]
    fn password_only_uiaa_is_supported() {
        let info = uiaa::UiaaInfo::new(vec![uiaa::AuthFlow::new(vec![uiaa::AuthType::Password])]);
        let flows = auth_flows(&info);
        assert_eq!(flows.len(), 1);
        assert!(flows[0].supported);
    }

    #[test]
    fn unsupported_uiaa_is_not_silently_accepted() {
        let info = uiaa::UiaaInfo::new(vec![uiaa::AuthFlow::new(vec![uiaa::AuthType::Sso])]);
        assert!(!auth_flows(&info)[0].supported);
    }
}
