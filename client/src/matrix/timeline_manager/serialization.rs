use std::sync::Arc;

use eyeball_im::VectorDiff;
use matrix_sdk_ui::timeline::{
    EventSendState, MsgLikeKind, ReactionStatus, TimelineDetails, TimelineItem, VirtualTimelineItem,
};
use serde_json::Value;

use crate::{
    matrix::messages::media_metadata,
    protocol::commands::{
        MessageInfo, ReactionInfo, ReadReceiptInfo, TimelineDiffInfo, TimelineItemInfo,
    },
};

pub(super) fn timeline_diff_info(
    diff: VectorDiff<Arc<TimelineItem>>,
    current_user_id: Option<&str>,
) -> TimelineDiffInfo {
    let empty = || TimelineDiffInfo {
        op: String::new(),
        index: None,
        length: None,
        item: None,
        items: None,
    };
    match diff {
        VectorDiff::Append { values } => TimelineDiffInfo {
            op: "append".to_owned(),
            items: Some(
                values
                    .iter()
                    .map(|item| timeline_item_info(item, current_user_id))
                    .collect(),
            ),
            ..empty()
        },
        VectorDiff::Clear => TimelineDiffInfo {
            op: "clear".to_owned(),
            ..empty()
        },
        VectorDiff::PushFront { value } => TimelineDiffInfo {
            op: "push_front".to_owned(),
            item: Some(timeline_item_info(&value, current_user_id)),
            ..empty()
        },
        VectorDiff::PushBack { value } => TimelineDiffInfo {
            op: "push_back".to_owned(),
            item: Some(timeline_item_info(&value, current_user_id)),
            ..empty()
        },
        VectorDiff::PopFront => TimelineDiffInfo {
            op: "pop_front".to_owned(),
            ..empty()
        },
        VectorDiff::PopBack => TimelineDiffInfo {
            op: "pop_back".to_owned(),
            ..empty()
        },
        VectorDiff::Insert { index, value } => TimelineDiffInfo {
            op: "insert".to_owned(),
            index: Some(index),
            item: Some(timeline_item_info(&value, current_user_id)),
            ..empty()
        },
        VectorDiff::Set { index, value } => TimelineDiffInfo {
            op: "set".to_owned(),
            index: Some(index),
            item: Some(timeline_item_info(&value, current_user_id)),
            ..empty()
        },
        VectorDiff::Remove { index } => TimelineDiffInfo {
            op: "remove".to_owned(),
            index: Some(index),
            ..empty()
        },
        VectorDiff::Truncate { length } => TimelineDiffInfo {
            op: "truncate".to_owned(),
            length: Some(length),
            ..empty()
        },
        VectorDiff::Reset { values } => TimelineDiffInfo {
            op: "reset".to_owned(),
            items: Some(
                values
                    .iter()
                    .map(|item| timeline_item_info(item, current_user_id))
                    .collect(),
            ),
            ..empty()
        },
    }
}

pub(super) fn timeline_item_info(
    item: &TimelineItem,
    current_user_id: Option<&str>,
) -> TimelineItemInfo {
    if let Some(virtual_item) = item.as_virtual() {
        let (kind, timestamp) = match virtual_item {
            VirtualTimelineItem::DateDivider(timestamp) => {
                ("date_divider", Some(timestamp.get().into()))
            }
            VirtualTimelineItem::ReadMarker => ("read_marker", None),
            VirtualTimelineItem::TimelineStart => ("timeline_start", None),
        };
        return TimelineItemInfo {
            timeline_item_id: item.unique_id().0.clone(),
            kind: kind.to_owned(),
            message: None,
            timestamp,
            send_state: None,
            send_error: None,
            send_recoverable: false,
            is_local_echo: false,
            sender_profile_pending: false,
            reply_details_pending: false,
        };
    }

    let event = item.as_event();
    let message = event.and_then(|event| message_from_timeline_event(event, item, current_user_id));
    let (send_state, send_error, send_recoverable) =
        match event.and_then(|event| event.send_state()) {
            Some(EventSendState::NotSentYet { .. }) => (Some("sending".to_owned()), None, false),
            Some(EventSendState::SendingFailed {
                error,
                is_recoverable,
            }) => (
                Some("failed".to_owned()),
                Some(error.to_string()),
                *is_recoverable,
            ),
            Some(EventSendState::Sent { .. }) => (Some("sent".to_owned()), None, false),
            None => (None, None, false),
        };
    let sender_profile_pending = event.is_some_and(|event| {
        matches!(
            event.sender_profile(),
            TimelineDetails::Unavailable | TimelineDetails::Pending
        )
    });
    let reply_details_pending = event.is_some_and(|event| {
        event.content().as_msglike().is_some_and(|content| {
            content.in_reply_to.as_ref().is_some_and(|reply| {
                matches!(
                    reply.event,
                    TimelineDetails::Unavailable | TimelineDetails::Pending
                )
            })
        })
    });
    TimelineItemInfo {
        timeline_item_id: item.unique_id().0.clone(),
        kind: "event".to_owned(),
        timestamp: event.map(|event| event.timestamp().get().into()),
        send_state,
        send_error,
        send_recoverable,
        is_local_echo: event.is_some_and(|event| event.is_local_echo()),
        sender_profile_pending,
        reply_details_pending,
        message,
    }
}

pub(super) fn message_from_timeline_event(
    event: &matrix_sdk_ui::timeline::EventTimelineItem,
    item: &TimelineItem,
    current_user_id: Option<&str>,
) -> Option<MessageInfo> {
    let msglike = event.content().as_msglike()?;
    let (body, msg_type, is_edited, is_redacted, is_encrypted) = match &msglike.kind {
        MsgLikeKind::Message(message) => (
            message.body().to_owned(),
            message.msgtype().msgtype().to_owned(),
            message.is_edited(),
            false,
            false,
        ),
        MsgLikeKind::Redacted => (String::new(), "m.text".to_owned(), false, true, false),
        MsgLikeKind::UnableToDecrypt(_) => {
            (String::new(), "m.encrypted".to_owned(), false, false, true)
        }
        MsgLikeKind::Sticker(sticker) => (
            sticker.content().body.clone(),
            "m.sticker".to_owned(),
            false,
            false,
            false,
        ),
        _ => return None,
    };
    let system_kind =
        crate::matrix::messages::system_kind_for_message(&msg_type, &body).map(str::to_owned);

    let profile = match event.sender_profile() {
        TimelineDetails::Ready(profile) => Some(profile),
        _ => None,
    };
    let raw = event
        .latest_json()
        .and_then(|raw| raw.deserialize_as_unchecked::<Value>().ok());
    let raw_content = raw
        .as_ref()
        .and_then(|raw| raw.get("content"))
        .and_then(|content| content.get("m.new_content").or(Some(content)))
        .cloned();
    let typed_content = || match &msglike.kind {
        // For encrypted custom room messages latest_json can still contain the
        // m.room.encrypted envelope. Rebuild the decrypted message content from
        // Ruma's MessageType so custom PrismChat payloads remain available.
        MsgLikeKind::Message(message) => {
            let message_type = message.msgtype();
            let mut object = message_type.data().into_owned();
            object.insert(
                "msgtype".to_owned(),
                Value::String(message_type.msgtype().to_owned()),
            );
            object.insert("body".to_owned(), Value::String(message.body().to_owned()));
            Value::Object(object)
        }
        // Local sticker echoes do not always have latest_json yet.
        MsgLikeKind::Sticker(sticker) => {
            serde_json::to_value(sticker.content()).unwrap_or(Value::Null)
        }
        _ => Value::Null,
    };
    let content = match raw_content {
        Some(value)
            if value.get("msgtype").is_some()
                || matches!(&msglike.kind, MsgLikeKind::Sticker(_)) =>
        {
            value
        }
        _ => typed_content(),
    };
    let (media_url, media_file, media_mime_type) = media_metadata(&content);
    let sticker_pack = content
        .get("org.prismchat.sticker_pack")
        .cloned()
        .filter(Value::is_object);

    let (reply_to, reply_sender, reply_body) = if let Some(reply) = &msglike.in_reply_to {
        let details = match &reply.event {
            TimelineDetails::Ready(embedded) => {
                let body = embedded
                    .content
                    .as_msglike()
                    .and_then(|content| match &content.kind {
                        MsgLikeKind::Message(message) => Some(message.body().to_owned()),
                        _ => None,
                    });
                (Some(embedded.sender.to_string()), body)
            }
            _ => (None, None),
        };
        (Some(reply.event_id.to_string()), details.0, details.1)
    } else {
        (None, None, None)
    };
    let thread_root_id = msglike.thread_root.as_ref().map(ToString::to_string);
    let thread_reply_count = msglike
        .thread_summary
        .as_ref()
        .map(|summary| summary.num_replies)
        .unwrap_or(0);

    let reactions = msglike
        .reactions
        .iter()
        .map(|(key, senders)| {
            let own = current_user_id.and_then(|user_id| senders.get(user_id));
            let own_event_id = own.and_then(|reaction| match &reaction.status {
                ReactionStatus::RemoteToRemote(event_id) => Some(event_id.to_string()),
                _ => None,
            });
            ReactionInfo {
                key: key.clone(),
                count: senders.len() as u64,
                reacted: own.is_some(),
                own_event_id,
            }
        })
        .collect();

    let read_receipts = event
        .read_receipts()
        .iter()
        .filter(|(user_id, _)| current_user_id != Some(user_id.as_str()))
        .map(|(user_id, receipt)| ReadReceiptInfo {
            user_id: user_id.to_string(),
            // Matrix allows receipts without `ts` (notably implicit
            // receipts). The target event time is the best available lower
            // bound and keeps the details popup useful in that case.
            timestamp: Some(receipt.ts.unwrap_or_else(|| event.timestamp()).get().into()),
        })
        .collect();

    Some(MessageInfo {
        event_id: event
            .event_id()
            .map(ToString::to_string)
            .unwrap_or_else(|| format!("local:{}", item.unique_id().0)),
        sender: event.sender().to_string(),
        sender_avatar_url: profile
            .and_then(|profile| profile.avatar_url.as_ref().map(ToString::to_string)),
        sender_display_name: profile.and_then(|profile| profile.display_name.clone()),
        sender_is_ignored: false,
        body,
        msg_type,
        timestamp: event.timestamp().get().into(),
        reply_to,
        reply_sender,
        reply_body,
        thread_root_id,
        thread_reply_count,
        media_url,
        media_file,
        media_mime_type,
        sticker_pack,
        is_system: system_kind.is_some(),
        system_kind,
        is_edited,
        is_redacted,
        is_encrypted,
        reactions,
        read_receipts,
    })
}
