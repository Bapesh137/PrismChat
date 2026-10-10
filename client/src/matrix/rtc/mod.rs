//! Room-scoped MatrixRTC widget sessions. Media belongs to embedded Element Call.
mod capabilities;
use crate::{
    matrix::session::{current_session_epoch, get_client},
    network::transport::Tx,
    protocol::commands::{QmlResponse, VoiceParticipant},
};
use capabilities::VoiceCapabilities;
use matrix_sdk::{
    widget::{
        ClientProperties, EncryptionSystem, Intent, VirtualElementCallWidgetConfig,
        VirtualElementCallWidgetProperties, WidgetDriver, WidgetDriverHandle, WidgetSettings,
    },
    Room, RoomState,
};
use serde_json::{json, Value};
use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, LazyLock},
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::{sync::Mutex, task::JoinHandle};
use tokio_tungstenite::tungstenite::Message;

pub const VOICE_ROOM_TYPE: &str = "io.prismchat.voice";
static ACTIVE: LazyLock<Mutex<Option<VoiceSession>>> = LazyLock::new(|| Mutex::new(None));
static CANCELLED: Mutex<std::collections::VecDeque<String>> =
    Mutex::const_new(std::collections::VecDeque::new());
static LIFECYCLE: Mutex<()> = Mutex::const_new(());
static STICKY_HTTP: LazyLock<reqwest::Client> = LazyLock::new(reqwest::Client::new);

#[derive(Clone)]
struct StickyVoiceParticipant {
    epoch: u64,
    user_id: String,
    expires_at_ms: u64,
}

// Expiry-bound cache for MSC4354 memberships missing from matrix-sdk 0.18.
static STICKY_VOICE_PARTICIPANTS: LazyLock<
    Mutex<HashMap<String, HashMap<String, StickyVoiceParticipant>>>,
> = LazyLock::new(|| Mutex::new(HashMap::new()));

struct VoiceSession {
    id: String,
    epoch: u64,
    room: Room,
    owner: Tx,
    handle: WidgetDriverHandle,
    driver: JoinHandle<()>,
    forwarder: JoinHandle<()>,
    // Only membership state keys actually sent by this widget may be cleared.
    membership_keys: Vec<String>,
}

/// Treat two-member joined rooms as DMs when `m.direct` is stale.
pub async fn is_direct_call_room(room: &Room) -> bool {
    room.is_direct().await.unwrap_or(false) || room.joined_members_count() == 2
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .min(u64::MAX as u128) as u64
}

fn sticky_expiry_ms(event: &Value) -> u64 {
    let duration_ms = event
        .pointer("/msc4354_sticky/duration_ms")
        .and_then(Value::as_u64)
        .unwrap_or(60_000)
        .clamp(1, 3_600_000);
    event
        .get("origin_server_ts")
        .and_then(Value::as_u64)
        .unwrap_or_else(now_ms)
        .saturating_add(duration_ms)
}

pub(crate) async fn observe_sticky_participant(
    room: &Room,
    event: &Value,
) -> Option<(String, u64, bool)> {
    if event.get("type").and_then(Value::as_str) != Some("org.matrix.msc4143.rtc.member") {
        return None;
    }
    let sender = event.get("sender").and_then(Value::as_str)?;
    <&matrix_sdk::ruma::UserId>::try_from(sender).ok()?;
    let event_key = event
        .get("event_id")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
        .unwrap_or_else(|| {
            format!(
                "{sender}:{}",
                event
                    .get("origin_server_ts")
                    .and_then(Value::as_u64)
                    .unwrap_or(0)
            )
        });
    let expires_at_ms = sticky_expiry_ms(event);
    if expires_at_ms <= now_ms() {
        return None;
    }
    let record = StickyVoiceParticipant {
        epoch: current_session_epoch(),
        user_id: sender.to_owned(),
        expires_at_ms,
    };
    let mut rooms = STICKY_VOICE_PARTICIPANTS.lock().await;
    let members = rooms.entry(room.room_id().to_string()).or_default();
    let now = now_ms();
    members.retain(|_, member| member.epoch == record.epoch && member.expires_at_ms > now);
    let changed = members
        .get(&event_key)
        .is_none_or(|old| old.expires_at_ms != expires_at_ms || old.user_id != sender);
    members.insert(event_key.clone(), record);
    Some((event_key, expires_at_ms, changed))
}

pub(crate) async fn expire_sticky_participant(
    room_id: &str,
    event_key: &str,
    expected_expires_at_ms: u64,
    epoch: u64,
) -> bool {
    let mut rooms = STICKY_VOICE_PARTICIPANTS.lock().await;
    let Some(members) = rooms.get_mut(room_id) else {
        return false;
    };
    let should_remove = members.get(event_key).is_some_and(|member| {
        member.epoch == epoch
            && member.expires_at_ms == expected_expires_at_ms
            && member.expires_at_ms <= now_ms()
    });
    if should_remove {
        members.remove(event_key);
    }
    if members.is_empty() {
        rooms.remove(room_id);
    }
    should_remove
}

async fn sticky_participant_user_ids(room_id: &str) -> Vec<String> {
    let epoch = current_session_epoch();
    let now = now_ms();
    let mut rooms = STICKY_VOICE_PARTICIPANTS.lock().await;
    let Some(members) = rooms.get_mut(room_id) else {
        return Vec::new();
    };
    members.retain(|_, member| member.epoch == epoch && member.expires_at_ms > now);
    let users = members
        .values()
        .map(|member| member.user_id.clone())
        .collect::<Vec<_>>();
    if members.is_empty() {
        rooms.remove(room_id);
    }
    users
}

pub async fn participants(room: &Room) -> Vec<VoiceParticipant> {
    let mut user_ids = room
        .active_room_call_participants()
        .into_iter()
        .map(|user_id| user_id.to_string())
        .collect::<Vec<_>>();
    user_ids.extend(sticky_participant_user_ids(room.room_id().as_str()).await);

    let mut result = Vec::new();
    let mut seen = HashSet::new();
    for user_id in user_ids {
        if !seen.insert(user_id.clone()) {
            continue;
        }
        let Ok(user_id_ref) = <&matrix_sdk::ruma::UserId>::try_from(user_id.as_str()) else {
            continue;
        };
        let member = room.get_member_no_sync(user_id_ref).await.ok().flatten();
        result.push(VoiceParticipant {
            user_id: user_id.clone(),
            display_name: member
                .as_ref()
                .and_then(|m| m.display_name())
                .unwrap_or(user_id_ref.as_str())
                .to_owned(),
            avatar_url: member.and_then(|m| m.avatar_url().map(ToString::to_string)),
        });
    }
    result
}

fn widget_intent(
    value: &str,
    voice_has_participants: bool,
) -> Result<(Intent, Option<&'static str>), String> {
    match value {
        "start_call_dm_voice" => Ok((Intent::StartCallDmVoice, None)),
        "join_existing_dm_voice" => Ok((Intent::JoinExistingDmVoice, None)),
        "join_existing" => Ok((Intent::JoinExisting, None)),
        // Map newer Element Call voice intents onto the closest SDK intents.
        "voice_channel" if voice_has_participants => {
            Ok((Intent::JoinExisting, Some("join_existing_voice")))
        }
        "voice_channel" => Ok((Intent::StartCall, Some("start_call_voice"))),
        _ => Err("Неподдерживаемый режим звонка".into()),
    }
}

fn override_element_call_intent(fragment: String, intent: &str) -> String {
    for sdk_intent in ["start_call", "join_existing"] {
        let needle = format!("intent={sdk_intent}");
        if fragment.contains(&needle) {
            return fragment.replacen(&needle, &format!("intent={intent}"), 1);
        }
    }
    fragment
}

fn validate_element_call_url(value: &str) -> Result<&str, String> {
    let address = value
        .strip_prefix("http://127.0.0.1:")
        .ok_or("Element Call должен запускаться только с локального адреса")?;
    let (port, path) = address
        .split_once('/')
        .ok_or("Некорректный локальный URL Element Call")?;
    if port.parse::<u16>().ok().filter(|port| *port != 0).is_none() || path != "index.html" {
        return Err("Некорректный локальный URL Element Call".into());
    }
    Ok(value)
}

pub async fn begin(
    room_id: &str,
    id: &str,
    epoch: u64,
    intent_name: &str,
    element_call_url: &str,
    tx: Tx,
) -> Result<Value, String> {
    let _guard = LIFECYCLE.lock().await;
    if CANCELLED
        .lock()
        .await
        .contains(&format!("{:p}:{id}", Arc::as_ptr(&tx)))
    {
        return Err("Подключение отменено".into());
    }
    if epoch != current_session_epoch() || id.is_empty() || id.len() > 128 {
        return Err("Сессия аккаунта изменилась".into());
    }
    // Frontend completes the old hangup first; this is a second safety boundary.
    if ACTIVE.lock().await.is_some() {
        return Err("Сначала выйдите из текущего голосового канала".into());
    }
    let client = get_client().await?;
    let room_id = <&matrix_sdk::ruma::RoomId>::try_from(room_id).map_err(|e| e.to_string())?;
    let room = client.get_room(room_id).ok_or("Комната недоступна")?;
    let voice_room = room.room_type().as_ref().map(|v| v.as_str()) == Some(VOICE_ROOM_TYPE);
    let voice_has_participants = voice_room && !participants(&room).await.is_empty();
    let (intent, voice_intent_override) = widget_intent(intent_name, voice_has_participants)?;
    let direct_room = is_direct_call_room(&room).await;
    if room.state() != RoomState::Joined || (!voice_room && !direct_room) {
        return Err("Звонки доступны только в личном чате или голосовом канале".into());
    }
    if matches!(
        intent,
        Intent::StartCallDmVoice | Intent::JoinExistingDmVoice
    ) && !direct_room
    {
        return Err("Личный звонок можно начать только в DM-комнате".into());
    }
    if room.encryption_settings().is_none() {
        return Err("Для голосового канала требуется сквозное шифрование комнаты".into());
    }
    let user_id = client.user_id().ok_or("Нет Matrix user_id")?.to_string();
    let device_id = client
        .device_id()
        .ok_or("Нет Matrix device_id")?
        .to_string();
    let element_call_url = validate_element_call_url(element_call_url)?;
    let settings = WidgetSettings::new_virtual_element_call_widget(
        VirtualElementCallWidgetProperties {
            element_call_url: element_call_url.into(),
            widget_id: id.to_owned(),
            parent_url: Some(element_call_url.into()),
            encryption: EncryptionSystem::PerParticipantKeys,
            ..Default::default()
        },
        VirtualElementCallWidgetConfig {
            intent: Some(intent),
            skip_lobby: Some(true),
            app_prompt: Some(false),
            confine_to_room: Some(true),
            hide_screensharing: Some(false),
            controlled_audio_devices: Some(false),
            ..Default::default()
        },
    )
    .map_err(|e| e.to_string())?;
    let mut widget_url = settings
        .generate_webview_url(
            &room,
            ClientProperties::new("io.prismchat", None, Some("dark".into())),
        )
        .await
        .map_err(|e| format!("Не удалось создать URL звонка: {e}"))?;
    let extra = if intent_name == "start_call_dm_voice" {
        "header=none&showControls=true&sendNotificationType=ring&waitForCallPickup=true&autoLeave=true"
    } else if matches!(intent_name, "join_existing_dm_voice" | "join_existing") {
        "header=none&showControls=true&autoLeave=true"
    } else {
        // Persistent voice rooms stay open for their last participant.
        "header=none&showControls=true&autoLeave=false"
    };
    let mut fragment = widget_url
        .fragment()
        .map(|v| format!("{v}&{extra}"))
        .unwrap_or_else(|| extra.into());
    if let Some(voice_intent) = voice_intent_override {
        fragment = override_element_call_intent(fragment, voice_intent);
    }
    widget_url.set_fragment(Some(&fragment));
    let initial_participants = participants(&room).await;
    let (driver, handle) = WidgetDriver::new(settings);
    let capabilities = VoiceCapabilities {
        user_id: user_id.clone(),
        device_id: device_id.clone(),
    };
    let driver_room = room.clone();
    let driver_task = tokio::spawn(async move {
        let _ = driver.run(driver_room, capabilities).await;
    });
    let receiver = handle.clone();
    let forward_tx = tx.clone();
    let call_id = id.to_owned();
    let forwarder = tokio::spawn(async move {
        while let Some(mut message) = receiver.recv().await {
            if current_session_epoch() != epoch {
                break;
            }
            message = advertise_rtc_transport_api(message);
            log_widget_packet("driver->widget", &message);
            if !push(
                &forward_tx,
                QmlResponse::VoiceWidgetMessage {
                    session_epoch: epoch,
                    call_id: call_id.clone(),
                    message,
                },
            )
            .await
            {
                break;
            }
        }
    });
    *ACTIVE.lock().await = Some(VoiceSession {
        id: id.to_owned(),
        epoch,
        room,
        owner: tx,
        handle,
        driver: driver_task,
        forwarder,
        membership_keys: Vec::new(),
    });
    crate::matrix::sync_loop::set_voice_room(Some(room_id.to_string())).await;
    Ok(
        json!({"widget_id": id, "room_id": room_id, "user_id": user_id,
        "device_id": device_id, "base_url": client.homeserver().as_str(),
        "widget_url": widget_url.as_str(), "encrypted": true,
        "participants": initial_participants}),
    )
}

fn log_widget_packet(direction: &str, message: &str) {
    let Ok(value) = serde_json::from_str::<Value>(message) else {
        eprintln!("[VoiceWidget] {direction} invalid-json");
        return;
    };
    let api = value.get("api").and_then(Value::as_str).unwrap_or("?");
    let action = value.get("action").and_then(Value::as_str).unwrap_or("?");
    let kind = if value.get("response").is_some() {
        "response"
    } else {
        "request"
    };

    let has_in_array = |pointer: &str, needle: &str| {
        value
            .pointer(pointer)
            .and_then(Value::as_array)
            .is_some_and(|items| items.iter().any(|v| v.as_str() == Some(needle)))
    };

    if action == "supported_api_versions" && kind == "response" {
        let msc4515 = has_in_array("/response/supported_versions", "org.matrix.msc4515");
        eprintln!(
            "[VoiceWidget] {direction} api={api} action={action} kind={kind} msc4515={msc4515}"
        );
        return;
    }

    if action == "capabilities" && kind == "response" {
        let rtc = has_in_array(
            "/response/capabilities",
            "org.matrix.msc4515.rtc_transports",
        );
        let count = value
            .pointer("/response/capabilities")
            .and_then(Value::as_array)
            .map_or(0, |items| items.len());
        eprintln!(
            "[VoiceWidget] {direction} api={api} action={action} kind={kind} rtc_requested={rtc} caps={count}"
        );
        return;
    }

    if action == "notify_capabilities" && kind == "request" {
        let requested = has_in_array("/data/requested", "org.matrix.msc4515.rtc_transports");
        let approved = has_in_array("/data/approved", "org.matrix.msc4515.rtc_transports");
        eprintln!(
            "[VoiceWidget] {direction} api={api} action={action} kind={kind} rtc_requested={requested} rtc_approved={approved}"
        );
        return;
    }

    eprintln!("[VoiceWidget] {direction} api={api} action={action} kind={kind}");
}

fn advertise_rtc_transport_api(message: String) -> String {
    let Ok(mut value) = serde_json::from_str::<Value>(&message) else {
        return message;
    };
    if value["api"] == "fromWidget" && value["action"] == "supported_api_versions" {
        if let Some(versions) = value
            .pointer_mut("/response/supported_versions")
            .and_then(Value::as_array_mut)
        {
            if !versions
                .iter()
                .any(|version| version == "org.matrix.msc4515")
            {
                versions.push(Value::String("org.matrix.msc4515".into()));
            }
            return value.to_string();
        }
    }

    // Restore MSC4515 capability data dropped by matrix-sdk 0.18.
    if value["api"] == "toWidget"
        && value["action"] == "notify_capabilities"
        && value.get("response").is_none()
    {
        for pointer in ["/data/approved", "/data/requested"] {
            if let Some(capabilities) = value.pointer_mut(pointer).and_then(Value::as_array_mut) {
                for capability in [
                    "org.matrix.msc4515.rtc_transports",
                    "org.matrix.msc4407.send.sticky_event",
                    "org.matrix.msc4407.receive.sticky_event",
                ] {
                    if !capabilities.iter().any(|value| value == capability) {
                        capabilities.push(Value::String(capability.into()));
                    }
                }
            }
        }
        return value.to_string();
    }
    message
}

async fn send_sticky_room_event(
    room: &Room,
    event_type: &str,
    content: &Value,
    sticky_duration_ms: u64,
) -> Result<String, String> {
    if sticky_duration_ms == 0 || sticky_duration_ms > 3_600_000 {
        return Err("Некорректная длительность sticky MatrixRTC event".into());
    }
    let session = crate::matrix::session::SESSION.lock().await.clone();
    let token = session.token.ok_or("Нет Matrix access token")?;
    let mut url = room.client().homeserver().clone();
    let transaction_id = uuid::Uuid::new_v4().to_string();
    {
        let mut segments = url
            .path_segments_mut()
            .map_err(|_| "Некорректный homeserver URL")?;
        segments.clear();
        segments.extend([
            "_matrix",
            "client",
            "v3",
            "rooms",
            room.room_id().as_str(),
            "send",
            event_type,
            transaction_id.as_str(),
        ]);
    }
    url.query_pairs_mut().append_pair(
        "org.matrix.msc4354.sticky_duration_ms",
        &sticky_duration_ms.to_string(),
    );
    let response = STICKY_HTTP
        .put(url)
        .bearer_auth(token)
        .json(content)
        .send()
        .await
        .map_err(|e| format!("Не удалось отправить sticky MatrixRTC event: {e}"))?;
    let status = response.status();
    let body: Value = response
        .json()
        .await
        .map_err(|e| format!("Некорректный ответ на sticky MatrixRTC event: {e}"))?;
    if !status.is_success() {
        let detail = body
            .get("error")
            .and_then(Value::as_str)
            .unwrap_or("Matrix homeserver отклонил sticky event");
        return Err(format!("{detail} ({status})"));
    }
    body.get("event_id")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
        .ok_or_else(|| "Homeserver не вернул event_id для sticky event".into())
}

async fn reply_widget_request(
    owner: &Tx,
    epoch: u64,
    call_id: &str,
    request: &Value,
    response: Value,
) -> bool {
    let mut reply = request.clone();
    reply["response"] = response;
    push(
        owner,
        QmlResponse::VoiceWidgetMessage {
            session_epoch: epoch,
            call_id: call_id.to_owned(),
            message: reply.to_string(),
        },
    )
    .await
}

pub(crate) async fn forward_sticky_membership_to_widget(room: &Room, event: &Value, epoch: u64) {
    if current_session_epoch() != epoch
        || event.get("type").and_then(Value::as_str) != Some("org.matrix.msc4143.rtc.member")
    {
        return;
    }
    let active = ACTIVE.lock().await;
    let Some(call) = active
        .as_ref()
        .filter(|call| call.epoch == epoch && call.room.room_id() == room.room_id())
    else {
        return;
    };
    let event_id = event
        .get("event_id")
        .and_then(Value::as_str)
        .unwrap_or("sticky-membership");
    let request = json!({
        "api": "toWidget",
        "widgetId": call.id.clone(),
        "requestId": format!("prism-sticky-{event_id}"),
        "action": "send_event",
        "data": {
            "room_id": room.room_id().as_str(),
            "event_id": event.get("event_id").cloned().unwrap_or(Value::Null),
            "type": "org.matrix.msc4143.rtc.member",
            "sender": event.get("sender").cloned().unwrap_or(Value::Null),
            "origin_server_ts": event.get("origin_server_ts").cloned().unwrap_or(Value::Null),
            "content": event.get("content").cloned().unwrap_or_else(|| json!({})),
            "unsigned": event.get("unsigned").cloned().unwrap_or_else(|| json!({}))
        }
    });
    let _ = push(
        &call.owner,
        QmlResponse::VoiceWidgetMessage {
            session_epoch: epoch,
            call_id: call.id.clone(),
            message: request.to_string(),
        },
    )
    .await;
}

pub async fn widget_message(
    id: &str,
    epoch: u64,
    message: String,
    owner: &Tx,
) -> Result<(), String> {
    if message.len() > 1024 * 1024 {
        return Err("Сообщение виджета слишком велико".into());
    }
    let value: Value =
        serde_json::from_str(&message).map_err(|_| "Некорректное сообщение виджета")?;
    if value["widgetId"].as_str() != Some(id) {
        return Err("Неверный widgetId".into());
    }
    log_widget_packet("widget->driver", &message);
    let mut active = ACTIVE.lock().await;
    let call = active
        .as_mut()
        .filter(|call| {
            call.id == id
                && call.epoch == epoch
                && epoch == current_session_epoch()
                && Arc::ptr_eq(&call.owner, owner)
        })
        .ok_or("Звонок уже завершён")?;
    if value["api"] == "fromWidget"
        && value.get("response").is_none()
        && value["action"] == "send_event"
        && value["data"].get("delay").is_none()
        && value["data"].get("parent_delay_id").is_none()
        && value["data"]["sticky_duration_ms"].as_u64().is_some()
    {
        let event_type = value["data"]["type"]
            .as_str()
            .ok_or("Sticky event не содержит type")?
            .to_owned();
        let content = value["data"]["content"].clone();
        let sticky_duration_ms = value["data"]["sticky_duration_ms"].as_u64().unwrap();
        let room = call.room.clone();
        let room_id = room.room_id().to_string();
        let response_owner = call.owner.clone();
        let response_epoch = call.epoch;
        let response_call_id = call.id.clone();
        drop(active);
        let event_id =
            send_sticky_room_event(&room, &event_type, &content, sticky_duration_ms).await?;
        let _ = reply_widget_request(
            &response_owner,
            response_epoch,
            &response_call_id,
            &value,
            json!({"room_id": room_id, "event_id": event_id}),
        )
        .await;
        return Ok(());
    }
    if value["api"] == "fromWidget"
        && value.get("response").is_none()
        && value["action"] == "org.matrix.msc4515.get_rtc_transports"
    {
        let response_tx = call.owner.clone();
        let call_id = call.id.clone();
        drop(active);
        let client = get_client().await?;
        let transports = match client
            .send(matrix_sdk::ruma::api::client::rtc::transports::v1::Request::new())
            .await
        {
            Ok(response) => response.rtc_transports,
            Err(_) => client
                .rtc_foci()
                .await
                .map_err(|e| format!("MatrixRTC transport недоступен: {e}"))?,
        };
        let mut response = value;
        response["response"] = json!({"rtc_transports": transports});
        push(
            &response_tx,
            QmlResponse::VoiceWidgetMessage {
                session_epoch: epoch,
                call_id,
                message: response.to_string(),
            },
        )
        .await;
        return Ok(());
    }
    if value["api"] == "fromWidget"
        && value.get("response").is_none()
        && value["action"] == "send_event"
        && value["data"]["type"] == "org.matrix.msc3401.call.member"
    {
        if let Some(key) = value["data"]["state_key"].as_str() {
            let provider = VoiceCapabilities {
                user_id: call.room.own_user_id().to_string(),
                device_id: call
                    .room
                    .client()
                    .device_id()
                    .map(ToString::to_string)
                    .unwrap_or_default(),
            };
            if provider.state_keys().contains(&key.to_owned())
                && !call.membership_keys.iter().any(|k| k == key)
            {
                call.membership_keys.push(key.to_owned());
            }
        }
    }
    if call.handle.send(message).await {
        Ok(())
    } else {
        Err("MatrixRTC bridge остановлен".into())
    }
}

pub async fn decline(room_id: &str, notification_event_id: &str) -> Result<(), String> {
    let client = get_client().await?;
    let room_id = <&matrix_sdk::ruma::RoomId>::try_from(room_id).map_err(|e| e.to_string())?;
    let event_id =
        <&matrix_sdk::ruma::EventId>::try_from(notification_event_id).map_err(|e| e.to_string())?;
    let room = client
        .get_room(room_id)
        .ok_or("Комната звонка недоступна")?;
    if room.state() != RoomState::Joined || !is_direct_call_room(&room).await {
        return Err("Отклонить звонок можно только в личном чате".into());
    }
    let content = room
        .make_decline_call_event(event_id)
        .await
        .map_err(|e| e.to_string())?;
    room.send(content).await.map_err(|e| e.to_string())?;
    Ok(())
}

pub async fn end(id: Option<&str>, owner: Option<&Tx>) {
    if let (Some(id), Some(owner)) = (id, owner) {
        let mut cancelled = CANCELLED.lock().await;
        cancelled.push_back(format!("{:p}:{id}", Arc::as_ptr(owner)));
        while cancelled.len() > 128 {
            cancelled.pop_front();
        }
    }
    let _guard = LIFECYCLE.lock().await;
    let mut active = ACTIVE.lock().await;
    if !active.as_ref().is_some_and(|call| {
        id.is_none_or(|id| call.id == id)
            && owner.is_none_or(|owner| Arc::ptr_eq(&call.owner, owner))
    }) {
        return;
    }
    let call = active.take().unwrap();
    drop(active);
    call.driver.abort();
    call.forwarder.abort();
    let _ = call.driver.await;
    let _ = call.forwarder.await;
    // Explicit leave is idempotent. Delayed MatrixRTC leaves cover network loss/crash.
    for state_key in call.membership_keys {
        let _ = tokio::time::timeout(
            Duration::from_secs(5),
            call.room
                .send_state_event_raw("org.matrix.msc3401.call.member", &state_key, json!({})),
        )
        .await;
    }
    crate::matrix::sync_loop::set_voice_room(None).await;
}

pub async fn push(tx: &Tx, response: QmlResponse) -> bool {
    let Ok(json) = serde_json::to_string(&response) else {
        return false;
    };
    tx.lock()
        .await
        .send(Message::Text(json.into()))
        .await
        .is_ok()
}

#[cfg(test)]
mod tests {
    use super::{
        advertise_rtc_transport_api, override_element_call_intent, validate_element_call_url,
        widget_intent,
    };
    use matrix_sdk::widget::Intent;

    #[test]
    fn maps_supported_call_intents() {
        assert!(matches!(
            widget_intent("start_call_dm_voice", false).unwrap(),
            (Intent::StartCallDmVoice, None)
        ));
        assert!(matches!(
            widget_intent("join_existing_dm_voice", false).unwrap(),
            (Intent::JoinExistingDmVoice, None)
        ));
        assert!(matches!(
            widget_intent("voice_channel", false).unwrap(),
            (Intent::StartCall, Some("start_call_voice"))
        ));
        assert!(matches!(
            widget_intent("voice_channel", true).unwrap(),
            (Intent::JoinExisting, Some("join_existing_voice"))
        ));
        assert!(widget_intent("video_party", false).is_err());
    }

    #[test]
    fn patches_only_generated_element_call_intent() {
        assert_eq!(
            override_element_call_intent(
                "?intent=start_call&roomId=!room:example.org".into(),
                "start_call_voice",
            ),
            "?intent=start_call_voice&roomId=!room:example.org"
        );
        assert_eq!(
            override_element_call_intent(
                "?intent=join_existing&roomId=!room:example.org".into(),
                "join_existing_voice",
            ),
            "?intent=join_existing_voice&roomId=!room:example.org"
        );
    }

    #[test]
    fn advertises_msc4515_once() {
        let input = r#"{"api":"fromWidget","action":"supported_api_versions","response":{"supported_versions":["0.0.1"]}}"#;
        let patched = advertise_rtc_transport_api(input.into());
        assert_eq!(patched.matches("org.matrix.msc4515").count(), 1);
        assert_eq!(
            advertise_rtc_transport_api(patched)
                .matches("org.matrix.msc4515")
                .count(),
            1
        );
    }

    #[test]
    fn restores_msc4515_capability_for_old_widget_driver() {
        let input = r#"{"api":"toWidget","action":"notify_capabilities","data":{"requested":[],"approved":[]}}"#;
        let patched = advertise_rtc_transport_api(input.into());
        let value: serde_json::Value = serde_json::from_str(&patched).unwrap();
        for pointer in ["/data/requested", "/data/approved"] {
            assert!(value
                .pointer(pointer)
                .and_then(serde_json::Value::as_array)
                .unwrap()
                .iter()
                .any(|cap| cap == "org.matrix.msc4515.rtc_transports"));
        }
    }

    #[test]
    fn accepts_only_loopback_element_call_assets() {
        assert!(validate_element_call_url("http://127.0.0.1:49152/index.html").is_ok());
        assert!(validate_element_call_url("http://localhost:49152/index.html").is_err());
        assert!(validate_element_call_url("http://127.0.0.1:49152/../index.html").is_err());
        assert!(validate_element_call_url("https://example.org/index.html").is_err());
    }
}
