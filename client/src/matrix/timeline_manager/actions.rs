use super::TIMELINE_MANAGER;

use matrix_sdk::{
    room::{edit::EditedContent, Receipts},
    ruma::{
        events::{
            marked_unread::MarkedUnreadEventContent,
            room::message::{
                MessageType, RoomMessageEventContent, RoomMessageEventContentWithoutRelation,
            },
            AnyMessageLikeEventContent, Mentions,
        },
        EventId, OwnedUserId,
    },
};
use matrix_sdk_ui::timeline::{EventSendState, TimelineEventItemId};

use crate::matrix::session::get_client;

use super::{get_or_create_thread_timeline, get_or_create_timeline};
fn message_content(
    body: &str,
    msg_type: Option<&str>,
    mentioned_user_ids: &[String],
) -> RoomMessageEventContentWithoutRelation {
    let mut content = match msg_type.unwrap_or("m.text") {
        "m.notice" => RoomMessageEventContentWithoutRelation::notice_plain(body),
        "m.emote" => RoomMessageEventContentWithoutRelation::emote_plain(body),
        crate::matrix::messages::CALL_HISTORY_MSG_TYPE => {
            let msgtype = MessageType::new(
                crate::matrix::messages::CALL_HISTORY_MSG_TYPE,
                body.to_owned(),
                Default::default(),
            )
            .expect("PrismChat call history is a valid custom message type");
            RoomMessageEventContentWithoutRelation::new(msgtype)
        }
        _ => RoomMessageEventContentWithoutRelation::text_plain(body),
    };
    let user_ids = mentioned_user_ids
        .iter()
        .filter_map(|user_id| user_id.parse::<OwnedUserId>().ok())
        .collect::<Vec<_>>();
    if !user_ids.is_empty() {
        content = content.add_mentions(Mentions::with_user_ids(user_ids));
    }
    content
}

/// Send through matrix-sdk-ui so the same Timeline owns the local echo,
/// retries, encryption and the eventual remote echo.
pub async fn send_message(
    room_id: &str,
    body: &str,
    msg_type: Option<&str>,
    reply_to: Option<&str>,
    thread_root: Option<&str>,
    mentioned_user_ids: &[String],
) -> Result<(), String> {
    let timeline = if let Some(root_event_id) = thread_root {
        get_or_create_thread_timeline(room_id, root_event_id).await?
    } else {
        get_or_create_timeline(room_id).await?
    };
    let content = message_content(body, msg_type, mentioned_user_ids);
    if let Some(reply_to) = reply_to {
        let event_id = <&EventId>::try_from(reply_to)
            .map_err(|error| format!("Некорректный reply event_id: {error}"))?
            .to_owned();
        timeline
            .send_reply(content, event_id)
            .await
            .map_err(|error| format!("Не удалось отправить ответ через SDK Timeline: {error}"))?;
    } else {
        let content = RoomMessageEventContent::from(content);
        timeline
            .send(AnyMessageLikeEventContent::RoomMessage(content))
            .await
            .map_err(|error| {
                format!("Не удалось отправить сообщение через SDK Timeline: {error}")
            })?;
    }
    Ok(())
}

pub async fn retry_message(room_id: &str, timeline_item_id: &str) -> Result<(), String> {
    let mut timelines = vec![get_or_create_timeline(room_id).await?];
    let thread_prefix = format!("{room_id}\u{1f}");
    {
        let state = TIMELINE_MANAGER.lock().await;
        timelines.extend(
            state
                .thread_timelines
                .iter()
                .filter(|(key, _)| key.starts_with(&thread_prefix))
                .map(|(_, timeline)| timeline.clone()),
        );
    }

    for timeline in timelines {
        let Some(item) = timeline
            .items()
            .await
            .into_iter()
            .find(|item| item.unique_id().0 == timeline_item_id)
        else {
            continue;
        };
        let event = item
            .as_event()
            .ok_or_else(|| "Выбранный элемент не является сообщением".to_owned())?;
        if matches!(
            event.send_state(),
            Some(EventSendState::SendingFailed {
                is_recoverable: true,
                ..
            })
        ) {
            timeline.room().send_queue().set_enabled(true);
            return Ok(());
        }
        let handle = event
            .local_echo_send_handle()
            .ok_or_else(|| "Это сообщение уже отправлено или не может быть повторено".to_owned())?;
        return handle
            .unwedge()
            .await
            .map_err(|error| format!("Не удалось повторить отправку: {error}"));
    }

    Err("Не удалось найти локальное сообщение для повтора".to_owned())
}

pub async fn edit_message(room_id: &str, event_id: &str, body: &str) -> Result<(), String> {
    let timeline = get_or_create_timeline(room_id).await?;
    let event_id = <&EventId>::try_from(event_id)
        .map_err(|error| format!("Некорректный event_id: {error}"))?
        .to_owned();
    timeline
        .edit(
            &TimelineEventItemId::EventId(event_id),
            EditedContent::RoomMessage(message_content(body, Some("m.text"), &[])),
        )
        .await
        .map_err(|error| {
            format!("Не удалось отредактировать сообщение через SDK Timeline: {error}")
        })
}

pub async fn redact_message(room_id: &str, event_id: &str) -> Result<(), String> {
    let timeline = get_or_create_timeline(room_id).await?;
    let event_id = <&EventId>::try_from(event_id)
        .map_err(|error| format!("Некорректный event_id: {error}"))?
        .to_owned();
    timeline
        .redact(&TimelineEventItemId::EventId(event_id), None)
        .await
        .map_err(|error| format!("Не удалось удалить сообщение через SDK Timeline: {error}"))
}

pub async fn toggle_reaction(room_id: &str, event_id: &str, key: &str) -> Result<bool, String> {
    let timeline = get_or_create_timeline(room_id).await?;
    let event_id = <&EventId>::try_from(event_id)
        .map_err(|error| format!("Некорректный event_id: {error}"))?
        .to_owned();
    timeline
        .toggle_reaction(&TimelineEventItemId::EventId(event_id), key)
        .await
        .map_err(|error| format!("Не удалось изменить реакцию через SDK Timeline: {error}"))
}

pub(super) fn read_receipts(event_id: matrix_sdk::ruma::OwnedEventId, public: bool) -> Receipts {
    Receipts::new()
        .fully_read_marker(event_id.clone())
        .public_read_receipt(public.then(|| event_id.clone()))
        .private_read_receipt((!public).then_some(event_id))
}

pub async fn mark_as_read(
    room_id: &str,
    public_receipt: bool,
    event_id: Option<&str>,
) -> Result<(), String> {
    if let Some(event_id) = event_id {
        let event_id = <&EventId>::try_from(event_id)
            .map_err(|error| format!("Некорректный event_id: {error}"))?
            .to_owned();
        // A viewport receipt must stop at the event actually seen, even when
        // sync has already delivered newer events to the room.
        return get_or_create_timeline(room_id)
            .await?
            .send_multiple_receipts(read_receipts(event_id, public_receipt))
            .await
            .map_err(|error| format!("Не удалось обновить позицию чтения: {error}"));
    }

    let client = get_client().await?;
    let parsed_room_id = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|error| format!("Некорректный room_id: {error}"))?;
    let room = client
        .get_room(parsed_room_id)
        .ok_or_else(|| "Комната не найдена".to_owned())?;

    // Explicit "mark as read" can use the room summary without creating a
    // Timeline solely for this operation.
    if let Some(event_id) = (*room).latest_event().event_id() {
        return room
            .send_multiple_receipts(read_receipts(event_id, public_receipt))
            .await
            .map_err(|error| format!("Не удалось отметить комнату прочитанной: {error}"));
    }

    let timeline = get_or_create_timeline(room_id).await?;
    if let Some(event_id) = timeline.latest_event_id().await {
        timeline
            .send_multiple_receipts(read_receipts(event_id, public_receipt))
            .await
            .map_err(|error| format!("Не удалось отметить Timeline прочитанным: {error}"))
    } else {
        room.set_unread_flag(false)
            .await
            .map_err(|error| format!("Не удалось снять отметку непрочитанного: {error}"))
    }
}

pub async fn set_marked_unread(room_id: &str, unread: bool) -> Result<(), String> {
    let room_id = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|error| format!("Некорректный room_id: {error}"))?;
    let room = crate::matrix::session::get_client()
        .await?
        .get_room(room_id)
        .ok_or_else(|| "Комната не найдена".to_owned())?;
    room.set_account_data(MarkedUnreadEventContent::new(unread))
        .await
        .map(|_| ())
        .map_err(|error| format!("Не удалось изменить отметку непрочитанного: {error}"))
}
