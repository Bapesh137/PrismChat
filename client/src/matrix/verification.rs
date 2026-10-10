//! Matrix SAS verification for the user's own devices.
//!
//! The SDK owns the protocol, cryptography, trust decisions and signatures.
//! PrismChat only retains the live SDK request/SAS object while an interactive
//! flow is visible and forwards display-safe state to QML.

use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        LazyLock,
    },
    time::Duration,
};

use futures_util::StreamExt;
use matrix_sdk::{
    encryption::verification::{
        SasState, SasVerification, VerificationRequest, VerificationRequestState,
    },
    ruma::{
        events::{
            key::verification::{request::ToDeviceKeyVerificationRequestEvent, VerificationMethod},
            AnyToDeviceEvent,
        },
        serde::Raw,
        DeviceId, UserId,
    },
    Client,
};
use tokio::sync::Mutex;

use crate::{
    matrix::{
        e2ee::{emit_overview, send_event},
        session::{current_session_epoch, get_client},
    },
    protocol::commands::QmlResponse,
};

#[derive(Clone)]
enum ActiveVerification {
    Request(VerificationRequest),
    Sas(SasVerification),
}

#[derive(Clone)]
struct ActiveFlow {
    epoch: u64,
    user_id: String,
    device_id: Option<String>,
    direction: String,
    verification: ActiveVerification,
}

static ACTIVE_FLOWS: LazyLock<Mutex<HashMap<String, ActiveFlow>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static SAS_WATCHERS: LazyLock<Mutex<HashMap<String, u64>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static NEXT_SAS_WATCHER_GENERATION: AtomicU64 = AtomicU64::new(0);
static FLOW_DRIVER: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));

fn sas_methods() -> Vec<VerificationMethod> {
    vec![VerificationMethod::SasV1]
}

fn parse_device_id(device_id: &str) -> Result<&DeviceId, String> {
    <&DeviceId>::try_from(device_id).map_err(|_| "Некорректный ID устройства".to_owned())
}

fn active_key(flow_id: &str) -> String {
    flow_id.to_owned()
}

async fn active_flow(flow_id: &str) -> Option<ActiveFlow> {
    ACTIVE_FLOWS.lock().await.get(flow_id).cloned()
}

/// Returns `true` when a new flow was installed and `false` for a duplicate
/// delivery of the same canonical Matrix verification request.
async fn register_request(flow_id: &str, flow: ActiveFlow) -> Result<bool, String> {
    let mut active = ACTIVE_FLOWS.lock().await;
    if active.contains_key(flow_id) {
        return Ok(false);
    }
    if !active.is_empty() {
        return Err("Другая проверка устройства уже выполняется".to_owned());
    }
    active.insert(active_key(flow_id), flow);
    Ok(true)
}

async fn replace_with_sas(flow_id: &str, sas: SasVerification) -> Result<ActiveFlow, String> {
    let mut active = ACTIVE_FLOWS.lock().await;
    let flow = active
        .get_mut(flow_id)
        .ok_or_else(|| "Проверка уже недоступна".to_owned())?;
    if flow.epoch != current_session_epoch() {
        return Err("Matrix-аккаунт был изменён".to_owned());
    }
    flow.device_id = Some(sas.other_device().device_id().to_string());
    flow.verification = ActiveVerification::Sas(sas);
    Ok(flow.clone())
}

async fn remove_flow(flow_id: &str) {
    ACTIVE_FLOWS.lock().await.remove(flow_id);
    SAS_WATCHERS.lock().await.remove(flow_id);
}

async fn device_name(client: &Client, user_id: &UserId, device_id: Option<&str>) -> Option<String> {
    let device_id = device_id.and_then(|value| <&DeviceId>::try_from(value).ok())?;
    client
        .encryption()
        .get_device(user_id, device_id)
        .await
        .ok()
        .flatten()
        .and_then(|device| device.display_name().map(ToOwned::to_owned))
}

async fn emit_flow(client: &Client, flow_id: &str) {
    let Some(flow) = active_flow(flow_id).await else {
        return;
    };
    if flow.epoch != current_session_epoch() {
        return;
    }
    let Ok(user_id) = <&UserId>::try_from(flow.user_id.as_str()) else {
        return;
    };

    let mut state = "requested".to_owned();
    let mut device_id = flow.device_id.clone();
    let mut emoji = Vec::new();
    let mut emoji_descriptions = Vec::new();
    let mut decimals = Vec::new();
    let mut error = None;

    match &flow.verification {
        ActiveVerification::Request(request) => match request.state() {
            VerificationRequestState::Created { .. } => {}
            VerificationRequestState::Requested {
                other_device_data, ..
            } => {
                device_id = Some(other_device_data.device_id().to_string());
            }
            VerificationRequestState::Ready {
                other_device_data, ..
            } => {
                device_id = Some(other_device_data.device_id().to_string());
                state = "ready".to_owned();
            }
            VerificationRequestState::Transitioned { verification } => {
                if let Some(sas) = verification.sas() {
                    device_id = Some(sas.other_device().device_id().to_string());
                    state = sas_state_name(&sas).to_owned();
                }
            }
            VerificationRequestState::Done => state = "done".to_owned(),
            VerificationRequestState::Cancelled(info) => {
                state = "cancelled".to_owned();
                error = Some(info.reason().to_owned());
            }
        },
        ActiveVerification::Sas(sas) => {
            device_id = Some(sas.other_device().device_id().to_string());
            state = sas_state_name(sas).to_owned();
            if sas.can_be_presented() {
                if let Some(values) = sas.emoji() {
                    emoji = values.iter().map(|value| value.symbol.to_owned()).collect();
                    emoji_descriptions = values
                        .iter()
                        .map(|value| value.description.to_owned())
                        .collect();
                }
                if let Some(values) = sas.decimals() {
                    decimals = vec![values.0, values.1, values.2];
                }
            }
            if sas.is_cancelled() {
                error = sas.cancel_info().map(|info| info.reason().to_owned());
            }
        }
    }

    let name = device_name(client, user_id, device_id.as_deref()).await;
    send_event(QmlResponse::VerificationUpdate {
        session_epoch: flow.epoch,
        user_id: flow.user_id,
        flow_id: flow_id.to_owned(),
        device_id,
        device_name: name,
        direction: flow.direction,
        state,
        emoji,
        emoji_descriptions,
        decimals,
        error,
    })
    .await;
}

async fn emit_error(client: &Client, flow_id: &str, message: String) {
    let Some(flow) = active_flow(flow_id).await else {
        return;
    };
    let Ok(user_id) = <&UserId>::try_from(flow.user_id.as_str()) else {
        return;
    };
    let name = device_name(client, user_id, flow.device_id.as_deref()).await;
    send_event(QmlResponse::VerificationUpdate {
        session_epoch: flow.epoch,
        user_id: flow.user_id,
        flow_id: flow_id.to_owned(),
        device_id: flow.device_id,
        device_name: name,
        direction: flow.direction,
        state: "error".to_owned(),
        emoji: Vec::new(),
        emoji_descriptions: Vec::new(),
        decimals: Vec::new(),
        error: Some(message),
    })
    .await;
}

fn sas_state_name(sas: &SasVerification) -> &'static str {
    match sas.state() {
        SasState::KeysExchanged { .. } => "sas",
        SasState::Done { .. } => "done",
        SasState::Cancelled(_) => "cancelled",
        SasState::Created { .. }
        | SasState::Started { .. }
        | SasState::Accepted { .. }
        | SasState::Confirmed => "sas_waiting",
    }
}

fn request_state_log_name(state: &VerificationRequestState) -> &'static str {
    match state {
        VerificationRequestState::Created { .. } => "created",
        VerificationRequestState::Requested { .. } => "requested",
        VerificationRequestState::Ready { .. } => "ready",
        VerificationRequestState::Transitioned { .. } => "transitioned",
        VerificationRequestState::Done => "done",
        VerificationRequestState::Cancelled(_) => "cancelled",
    }
}

fn sas_state_log_name(state: &SasState) -> &'static str {
    match state {
        SasState::Created { .. } => "created",
        SasState::Started { .. } => "started",
        SasState::Accepted { .. } => "accepted",
        SasState::KeysExchanged { .. } => "keys_exchanged",
        SasState::Confirmed => "confirmed",
        SasState::Done { .. } => "done",
        SasState::Cancelled(_) => "cancelled",
    }
}

#[cfg(test)]
fn request_state_name_impl(cancelled: bool, done: bool, ready: bool) -> &'static str {
    if cancelled {
        "cancelled"
    } else if done {
        "done"
    } else if ready {
        "ready"
    } else {
        "requested"
    }
}

async fn spawn_sas_watcher(client: Client, flow_id: String, sas: SasVerification) {
    // Generations keep replaced SAS watchers from mutating the winning flow.
    let generation = NEXT_SAS_WATCHER_GENERATION.fetch_add(1, Ordering::AcqRel) + 1;
    SAS_WATCHERS
        .lock()
        .await
        .insert(flow_id.clone(), generation);
    tokio::spawn(watch_sas(client, flow_id, sas, generation));
}

async fn sas_watcher_is_current(flow_id: &str, generation: u64) -> bool {
    SAS_WATCHERS
        .lock()
        .await
        .get(flow_id)
        .is_some_and(|current| *current == generation)
}

async fn finish_request_flow(client: &Client, flow_id: &str, epoch: u64) {
    emit_flow(client, flow_id).await;
    if current_session_epoch() == epoch {
        crate::matrix::devices::emit_snapshot(epoch).await;
        emit_overview().await;
    }
    remove_flow(flow_id).await;
}

async fn activate_sas(client: &Client, flow_id: &str, sas: SasVerification) -> Result<(), String> {
    replace_with_sas(flow_id, sas.clone()).await?;
    emit_flow(client, flow_id).await;
    spawn_sas_watcher(client.clone(), flow_id.to_owned(), sas).await;
    Ok(())
}

/// Reconcile UI state with the SDK verification cache.
async fn drive_request_flow(client: &Client, flow_id: &str, refresh_sas: bool) -> bool {
    // Serialize duplicate stream and to-device wakeups.
    let _driver = FLOW_DRIVER.lock().await;
    let Some(flow) = active_flow(flow_id).await else {
        return false;
    };
    if flow.epoch != current_session_epoch() {
        return false;
    }
    let Ok(user_id) = <&UserId>::try_from(flow.user_id.as_str()) else {
        return false;
    };
    let (was_request, stored_request) = match &flow.verification {
        ActiveVerification::Request(request) => (true, Some(request.clone())),
        ActiveVerification::Sas(_) => (false, None),
    };

    // Prefer a transitioned verification over a stale request snapshot.
    if let Some(verification) = client.encryption().get_verification(user_id, flow_id).await {
        if let Some(sas) = verification.sas() {
            eprintln!(
                "[Verification] canonical SAS flow={flow_id} state={}",
                sas_state_name(&sas)
            );
            if was_request || refresh_sas {
                if let Err(error) = activate_sas(client, flow_id, sas.clone()).await {
                    emit_error(client, flow_id, error).await;
                    let _ = sas.cancel().await;
                    remove_flow(flow_id).await;
                }
            } else {
                emit_flow(client, flow_id).await;
            }
            return false;
        }
    }

    // Fall back to the stored request if the SDK cache has not caught up.
    let request = client
        .encryption()
        .get_verification_request(user_id, flow_id)
        .await
        .or(stored_request);
    let Some(request) = request else {
        emit_flow(client, flow_id).await;
        return false;
    };

    let request_state = request.state();
    match request_state {
        VerificationRequestState::Ready { .. } => {
            // Matrix SDK resolves simultaneous SAS starts.
            match request.start_sas().await {
                Ok(Some(sas)) => {
                    if let Err(error) = activate_sas(client, flow_id, sas.clone()).await {
                        emit_error(client, flow_id, error).await;
                        let _ = sas.cancel().await;
                        remove_flow(flow_id).await;
                    }
                    false
                }
                Ok(None) => {
                    // A concurrent remote start will wake the watcher again.
                    emit_flow(client, flow_id).await;
                    true
                }
                Err(error) => {
                    emit_error(
                        client,
                        flow_id,
                        format!("Не удалось начать SAS-проверку: {error}"),
                    )
                    .await;
                    let _ = request.cancel().await;
                    remove_flow(flow_id).await;
                    false
                }
            }
        }
        VerificationRequestState::Transitioned { verification } => {
            let Some(sas) = verification.sas() else {
                emit_error(
                    client,
                    flow_id,
                    "Другой клиент выбрал неподдерживаемый способ проверки".to_owned(),
                )
                .await;
                let _ = request.cancel().await;
                remove_flow(flow_id).await;
                return false;
            };
            if let Err(error) = activate_sas(client, flow_id, sas.clone()).await {
                emit_error(client, flow_id, error).await;
                let _ = sas.cancel().await;
                remove_flow(flow_id).await;
            }
            false
        }
        VerificationRequestState::Done | VerificationRequestState::Cancelled(_) => {
            finish_request_flow(client, flow_id, flow.epoch).await;
            false
        }
        VerificationRequestState::Created { .. } | VerificationRequestState::Requested { .. } => {
            emit_flow(client, flow_id).await;
            true
        }
    }
}

async fn watch_request(client: Client, flow_id: String, request: VerificationRequest) {
    let epoch = current_session_epoch();
    // Subscribe before async work, then process the current state snapshot.
    let mut changes = Box::pin(request.changes());
    let mut current_state = Some(request.state());
    let mut heartbeat = tokio::time::interval_at(
        tokio::time::Instant::now() + Duration::from_secs(30),
        Duration::from_secs(30),
    );

    let result = tokio::time::timeout(Duration::from_secs(600), async {
        loop {
            let state = match current_state.take() {
                Some(state) => state,
                None => {
                    tokio::select! {
                        state = changes.next() => {
                            let Some(state) = state else {
                                eprintln!("[Verification] request stream ended flow={flow_id}");
                                return;
                            };
                            state
                        }
                        _ = heartbeat.tick() => {
                            eprintln!(
                                "[Verification] waiting flow={flow_id} request_state={} sync={}",
                                request_state_log_name(&request.state()),
                                crate::matrix::sync_loop::diagnostic_state().await
                            );
                            continue;
                        }
                    }
                }
            };
            if current_session_epoch() != epoch {
                eprintln!("[Verification] request watcher stale flow={flow_id} epoch={epoch}");
                return;
            }
            eprintln!(
                "[Verification] request stream flow={flow_id} state={}",
                request_state_log_name(&state)
            );
            // Stream entries are wakeups; the driver reads canonical SDK state.
            drop(state);
            if !drive_request_flow(&client, &flow_id, false).await {
                return;
            }
        }
    })
    .await;

    if result.is_err() && current_session_epoch() == epoch {
        let _ = request.cancel().await;
        emit_flow(&client, &flow_id).await;
        remove_flow(&flow_id).await;
    }
}

async fn handle_sas_state(
    client: &Client,
    flow_id: &str,
    sas: &SasVerification,
    state: SasState,
) -> bool {
    match state {
        SasState::Started { .. } => {
            // Accept the protocol winner selected by matrix-sdk.
            if let Err(error) = sas.accept().await {
                emit_error(
                    client,
                    flow_id,
                    format!("Не удалось принять SAS-проверку: {error}"),
                )
                .await;
                let _ = sas.cancel().await;
                return true;
            }
            emit_flow(client, flow_id).await;
            false
        }
        SasState::KeysExchanged { .. } => {
            // `emit_flow()` renders only SDK-provided emoji/decimals.
            emit_flow(client, flow_id).await;
            false
        }
        SasState::Done { .. } | SasState::Cancelled(_) => {
            emit_flow(client, flow_id).await;
            true
        }
        SasState::Created { .. } | SasState::Accepted { .. } | SasState::Confirmed => {
            emit_flow(client, flow_id).await;
            false
        }
    }
}

async fn watch_sas(client: Client, flow_id: String, sas: SasVerification, generation: u64) {
    let epoch = current_session_epoch();
    // Subscribe before awaiting so fast SAS replies remain observable.
    let mut changes = Box::pin(sas.changes());
    let mut current_state = Some(sas.state());

    let result = tokio::time::timeout(Duration::from_secs(600), async {
        loop {
            let state = match current_state.take() {
                Some(state) => state,
                None => {
                    let Some(state) = changes.next().await else {
                        return;
                    };
                    state
                }
            };
            if current_session_epoch() != epoch
                || !sas_watcher_is_current(&flow_id, generation).await
            {
                eprintln!(
                    "[Verification] SAS watcher superseded flow={flow_id} generation={generation}"
                );
                return;
            }
            eprintln!(
                "[Verification] SAS stream flow={flow_id} generation={generation} state={}",
                sas_state_log_name(&state)
            );
            if handle_sas_state(&client, &flow_id, &sas, state).await {
                return;
            }
        }
    })
    .await;

    if result.is_err()
        && current_session_epoch() == epoch
        && sas_watcher_is_current(&flow_id, generation).await
    {
        let _ = sas.cancel().await;
        emit_flow(&client, &flow_id).await;
    }
    if current_session_epoch() == epoch && sas_watcher_is_current(&flow_id, generation).await {
        crate::matrix::devices::emit_snapshot(epoch).await;
        emit_overview().await;
        remove_flow(&flow_id).await;
    }
}

async fn begin_request(
    client: Client,
    user_id: String,
    device_id: Option<String>,
    direction: &str,
    request: VerificationRequest,
) -> Result<String, String> {
    let flow_id = request.flow_id().to_owned();
    eprintln!(
        "[Verification] begin flow={flow_id} direction={direction} current_device={} target_device={} request_state={} epoch={} sync={}",
        client.device_id().map(|id| id.as_str()).unwrap_or("<none>"),
        device_id.as_deref().unwrap_or("<identity>"),
        request_state_log_name(&request.state()),
        current_session_epoch(),
        crate::matrix::sync_loop::diagnostic_state().await
    );
    let flow = ActiveFlow {
        epoch: current_session_epoch(),
        user_id,
        device_id,
        direction: direction.to_owned(),
        verification: ActiveVerification::Request(request.clone()),
    };
    if register_request(&flow_id, flow).await? {
        tokio::spawn(watch_request(client, flow_id.clone(), request));
    }
    Ok(flow_id)
}

pub async fn start_device(device_id: &str) -> Result<String, String> {
    if super::e2ee::identity_reset_pending().await {
        return Err(
            "Нельзя начинать проверку, пока сброс личности ожидает подтверждения".to_owned(),
        );
    }
    let client = get_client().await?;
    crate::matrix::sync_loop::ensure_encryption_sync_running().await?;
    client
        .encryption()
        .wait_for_e2ee_initialization_tasks()
        .await;
    let user_id = client
        .user_id()
        .ok_or_else(|| "Нет активного Matrix user_id".to_owned())?
        .to_owned();
    let device_id = parse_device_id(device_id)?;
    let device = client
        .encryption()
        .get_device(&user_id, device_id)
        .await
        .map_err(|error| format!("Не удалось найти устройство: {error}"))?
        .ok_or_else(|| "Устройство не найдено в E2EE-хранилище".to_owned())?;
    let request = device
        .request_verification_with_methods(sas_methods())
        .await
        .map_err(|error| format!("Не удалось начать проверку: {error}"))?;
    begin_request(
        client,
        user_id.to_string(),
        Some(device_id.to_string()),
        "outgoing",
        request,
    )
    .await
}

pub async fn start_current_device() -> Result<String, String> {
    if super::e2ee::identity_reset_pending().await {
        return Err(
            "Нельзя начинать проверку, пока сброс личности ожидает подтверждения".to_owned(),
        );
    }
    let client = get_client().await?;
    crate::matrix::sync_loop::ensure_encryption_sync_running().await?;
    client
        .encryption()
        .wait_for_e2ee_initialization_tasks()
        .await;
    let user_id = client
        .user_id()
        .ok_or_else(|| "Нет активного Matrix user_id".to_owned())?
        .to_owned();
    let identity = client
        .encryption()
        .request_user_identity(&user_id)
        .await
        .map_err(|error| format!("Не удалось получить identity: {error}"))?
        .ok_or_else(|| "У аккаунта ещё нет cross-signing identity".to_owned())?;
    let request = identity
        .request_verification_with_methods(sas_methods())
        .await
        .map_err(|error| format!("Не удалось начать проверку: {error}"))?;
    begin_request(client, user_id.to_string(), None, "outgoing", request).await
}

pub async fn action(flow_id: &str, action: &str) -> Result<(), String> {
    let client = get_client().await?;
    eprintln!(
        "[Verification] UI action flow={flow_id} action={action} epoch={} sync={}",
        current_session_epoch(),
        crate::matrix::sync_loop::diagnostic_state().await
    );
    let flow = active_flow(flow_id)
        .await
        .ok_or_else(|| "Проверка уже завершена или недоступна".to_owned())?;
    if flow.epoch != current_session_epoch() {
        return Err("Matrix-аккаунт был изменён".to_owned());
    }

    match (action, flow.verification) {
        ("accept", ActiveVerification::Request(request)) => request
            .accept_with_methods(sas_methods())
            .await
            .map_err(|error| format!("Не удалось принять проверку: {error}"))?,
        ("start_sas", ActiveVerification::Request(request)) => {
            let _driver = FLOW_DRIVER.lock().await;
            let sas = request
                .start_sas()
                .await
                .map_err(|error| format!("Не удалось начать SAS: {error}"))?
                .ok_or_else(|| {
                    "SAS пока нельзя начать: второе устройство ещё не готово".to_owned()
                })?;
            activate_sas(&client, flow_id, sas).await?;
        }
        ("confirm", ActiveVerification::Sas(sas)) => sas
            .confirm()
            .await
            .map_err(|error| format!("Не удалось подтвердить SAS: {error}"))?,
        ("mismatch", ActiveVerification::Sas(sas)) => sas
            .mismatch()
            .await
            .map_err(|error| format!("Не удалось отклонить несовпадающий SAS: {error}"))?,
        ("cancel", ActiveVerification::Request(request)) => request
            .cancel()
            .await
            .map_err(|error| format!("Не удалось отменить проверку: {error}"))?,
        ("cancel", ActiveVerification::Sas(sas)) => sas
            .cancel()
            .await
            .map_err(|error| format!("Не удалось отменить SAS: {error}"))?,
        ("confirm" | "mismatch", ActiveVerification::Request(_)) => {
            return Err("Сравнение SAS ещё не началось".to_owned());
        }
        ("accept" | "start_sas", ActiveVerification::Sas(_)) => {
            return Err("Проверка уже перешла к сравнению SAS".to_owned());
        }
        _ => return Err("Неизвестное действие проверки".to_owned()),
    }

    emit_flow(&client, flow_id).await;
    Ok(())
}

async fn handle_incoming_request(
    client: Client,
    event: ToDeviceKeyVerificationRequestEvent,
    session_epoch: u64,
) {
    if current_session_epoch() != session_epoch {
        return;
    }
    let Some(own_user_id) = client.user_id() else {
        return;
    };
    if event.sender != own_user_id {
        return;
    }
    if client.device_id() == Some(event.content.from_device.as_ref()) {
        return;
    }

    let flow_id = event.content.transaction_id.as_str();
    let Some(request) = client
        .encryption()
        .get_verification_request(&event.sender, flow_id)
        .await
    else {
        eprintln!(
            "[Verification] canonical incoming request unavailable flow={flow_id} epoch={session_epoch}"
        );
        return;
    };
    if !request.is_self_verification() || request.other_user_id() != own_user_id {
        return;
    }

    let device_id = match request.state() {
        VerificationRequestState::Requested {
            other_device_data, ..
        }
        | VerificationRequestState::Ready {
            other_device_data, ..
        } => Some(other_device_data.device_id().to_string()),
        VerificationRequestState::Transitioned { ref verification } => verification
            .clone()
            .sas()
            .map(|sas| sas.other_device().device_id().to_string()),
        _ => Some(event.content.from_device.to_string()),
    };
    if device_id.as_deref() == client.device_id().map(|value| value.as_str()) {
        return;
    }

    let flow = ActiveFlow {
        epoch: session_epoch,
        user_id: event.sender.to_string(),
        device_id,
        direction: "incoming".to_owned(),
        verification: ActiveVerification::Request(request.clone()),
    };
    match register_request(flow_id, flow).await {
        Ok(true) => {
            eprintln!(
                "[Verification] incoming request flow={flow_id} from_device={} state={} epoch={session_epoch}",
                event.content.from_device,
                request_state_log_name(&request.state())
            );
            // The watcher subscribes to changes before processing state(), so
            // a fast ready/start transition cannot be lost here.
            tokio::spawn(watch_request(client, flow_id.to_owned(), request));
        }
        Ok(false) => {
            // Duplicate to-device delivery for the already watched flow.
        }
        Err(error) => {
            eprintln!("[Verification] rejecting incoming flow={flow_id}: {error}");
            let _ = request.cancel().await;
        }
    }
}

async fn notify_active_verification_event(
    client: Client,
    raw: serde_json::Value,
    session_epoch: u64,
) {
    if current_session_epoch() != session_epoch {
        return;
    }
    let Some(event_type) = raw.get("type").and_then(|value| value.as_str()) else {
        return;
    };
    if !event_type.starts_with("m.key.verification.") || event_type == "m.key.verification.request"
    {
        return;
    }
    let Some(sender) = raw.get("sender").and_then(|value| value.as_str()) else {
        return;
    };
    if client.user_id().map(|user| user.as_str()) != Some(sender) {
        return;
    }
    let Some(flow_id) = raw
        .get("content")
        .and_then(|value| value.get("transaction_id"))
        .and_then(|value| value.as_str())
        .or_else(|| raw.get("event_id").and_then(|value| value.as_str()))
    else {
        return;
    };
    if active_flow(flow_id).await.is_some() {
        // This is only a wake-up hint. State and cryptography are always read
        // from matrix-sdk's canonical request/SAS objects.
        drive_request_flow(&client, flow_id, event_type == "m.key.verification.start").await;
    }
}

pub fn install_event_handler(client: &Client, session_epoch: u64) {
    eprintln!(
        "[Verification] installing to-device handler epoch={session_epoch} device={}",
        client.device_id().map(|id| id.as_str()).unwrap_or("<none>")
    );
    let request_client = client.clone();
    client.add_event_handler(move |event: ToDeviceKeyVerificationRequestEvent| {
        let client = request_client.clone();
        async move {
            handle_incoming_request(client, event, session_epoch).await;
        }
    });

    let handler_client = client.clone();
    client.add_event_handler(move |raw: Raw<AnyToDeviceEvent>| {
        let client = handler_client.clone();
        async move {
            if let Ok(value) = raw.deserialize_as_unchecked::<serde_json::Value>() {
                let event_type = value
                    .get("type")
                    .and_then(|value| value.as_str())
                    .unwrap_or("<unknown>");
                // Only verification traffic is relevant to this handler.
                if event_type.starts_with("m.key.verification.") {
                    notify_active_verification_event(client, value, session_epoch).await;
                }
            } else {
                eprintln!(
                    "[ToDevice] failed to decode event for diagnostics epoch={session_epoch}"
                );
            }
        }
    });
}

pub async fn clear_for_epoch_change() {
    let flows = {
        let mut active = ACTIVE_FLOWS.lock().await;
        std::mem::take(&mut *active)
    };
    SAS_WATCHERS.lock().await.clear();
    for (_, flow) in flows {
        match flow.verification {
            ActiveVerification::Request(request) => {
                let _ = request.cancel().await;
            }
            ActiveVerification::Sas(sas) => {
                let _ = sas.cancel().await;
            }
        }
    }
}

#[cfg(test)]
fn request_state_name(cancelled: bool, done: bool, ready: bool) -> &'static str {
    request_state_name_impl(cancelled, done, ready)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn verification_transitions_are_ordered() {
        assert_eq!(request_state_name(false, false, false), "requested");
        assert_eq!(request_state_name(false, false, true), "ready");
        assert_eq!(request_state_name(false, true, true), "done");
    }

    #[test]
    fn cancellation_wins_over_other_states() {
        assert_eq!(request_state_name(true, true, true), "cancelled");
    }
}
