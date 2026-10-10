use std::collections::{HashMap, HashSet};

use futures_util::stream::{self, StreamExt};

use matrix_sdk::{
    event_cache::RoomEventCache,
    room::MessagesOptions,
    ruma::{events::relation::RelationType, EventId, RoomId, UInt},
    Room,
};

use crate::matrix::{
    attachments::contains_web_link, auth::fetch_user_avatar, session::get_client,
    users::ignored_user_ids,
};
use crate::protocol::commands::{MessageInfo, ReactionInfo};

/// A persistent room event rendered as a centered timeline entry rather than
/// as a user-authored chat bubble. Other Matrix clients can preserve it as an
/// unknown, harmless `m.room.message` subtype.
pub const CALL_HISTORY_MSG_TYPE: &str = "io.prismchat.call.history";

pub fn system_kind_for_message(msg_type: &str, body: &str) -> Option<&'static str> {
    if msg_type == CALL_HISTORY_MSG_TYPE
        || (msg_type == "m.notice"
            && (body.starts_with("📞 Аудиозвонок · ")
                || body.starts_with("📞 Вызов без ответа · ")))
    {
        Some("call_history")
    } else {
        None
    }
}

pub(crate) fn media_metadata(
    content: &serde_json::Value,
) -> (Option<String>, Option<serde_json::Value>, Option<String>) {
    let media_mime_type = content
        .pointer("/info/mimetype")
        .and_then(|value| value.as_str())
        .map(str::to_owned);
    let encrypted_file = content
        .get("file")
        .filter(|file| file.is_object() && file.get("url").and_then(|url| url.as_str()).is_some())
        .cloned()
        .map(|file| {
            crate::matrix::media_proxy::decorate_encrypted_file(file, media_mime_type.as_deref())
        });
    let media_url = encrypted_file
        .as_ref()
        .and_then(|file| file.get("url"))
        .and_then(|url| url.as_str())
        .or_else(|| content.get("url").and_then(|url| url.as_str()))
        .map(str::to_owned);

    (media_url, encrypted_file, media_mime_type)
}

fn reply_preview_from_raw(raw: &serde_json::Value) -> Option<(String, String)> {
    if raw["type"].as_str() != Some("m.room.message") {
        return None;
    }

    let sender = raw["sender"].as_str().unwrap_or("unknown").to_owned();
    let body = raw["content"]["body"].as_str().unwrap_or("").to_owned();
    Some((sender, body))
}

fn bundled_reactions(raw: &serde_json::Value) -> Vec<ReactionInfo> {
    let aggregation = raw.pointer("/unsigned/m.relations/m.annotation");
    let items = aggregation
        .and_then(|value| value.as_array())
        .or_else(|| aggregation.and_then(|value| value.get("chunk")?.as_array()));
    items
        .into_iter()
        .flatten()
        .filter_map(|item| {
            let key = item.get("key")?.as_str()?.to_owned();
            let count = item.get("count")?.as_u64()?;
            Some(ReactionInfo {
                key,
                count,
                reacted: false,
                own_event_id: None,
            })
        })
        .collect()
}

pub(crate) async fn fetch_reply_preview(room: &Room, event_id: &str) -> Option<(String, String)> {
    let event_id = <&EventId>::try_from(event_id).ok()?;
    let event = room.load_or_fetch_event(event_id, None).await.ok()?;
    let raw: serde_json::Value = event.raw().deserialize_as_unchecked().ok()?;
    reply_preview_from_raw(&raw)
}

async fn cached_reply_preview(
    event_cache: &RoomEventCache,
    event_id: &str,
) -> Option<(String, String)> {
    let event_id = <&EventId>::try_from(event_id).ok()?;
    let event = event_cache.find_event(event_id).await.ok().flatten()?;
    let raw: serde_json::Value = event.raw().deserialize_as_unchecked().ok()?;
    reply_preview_from_raw(&raw)
}

pub(crate) async fn parse_messages(
    room: &Room,
    events: Vec<matrix_sdk::deserialized_responses::TimelineEvent>,
    event_cache: Option<&RoomEventCache>,
) -> Result<Vec<MessageInfo>, String> {
    let mut avatar_cache: HashMap<String, Option<String>> = HashMap::new();
    let mut display_name_cache: HashMap<String, String> = HashMap::new();
    let mut member_cache: HashMap<String, Option<(Option<String>, Option<String>)>> =
        HashMap::new();
    let mut reaction_map: HashMap<String, HashMap<String, HashMap<String, String>>> =
        HashMap::new();
    let mut replacement_map: HashMap<String, (String, String)> = HashMap::new();
    let mut messages: Vec<MessageInfo> = Vec::new();
    let current_user = room.client().user_id().map(|id| id.as_str().to_owned());
    let ignored_users = ignored_user_ids(&room.client()).await;

    for event in events {
        let raw: serde_json::Value = event
            .raw()
            .deserialize_as_unchecked()
            .map_err(|e| format!("Ошибка десериализации timeline event: {}", e))?;

        let event_type = raw["type"].as_str().unwrap_or("");
        if event_type == "m.reaction" {
            let relates = &raw["content"]["m.relates_to"];
            if relates["rel_type"].as_str() == Some("m.annotation") {
                if let (Some(target), Some(key), Some(sender), Some(reaction_event_id)) = (
                    relates["event_id"].as_str(),
                    relates["key"].as_str(),
                    raw["sender"].as_str(),
                    raw["event_id"].as_str(),
                ) {
                    reaction_map
                        .entry(target.to_owned())
                        .or_default()
                        .entry(key.to_owned())
                        .or_default()
                        .insert(sender.to_owned(), reaction_event_id.to_owned());
                }
            }
            continue;
        }
        if event_type != "m.room.message"
            && event_type != "m.room.encrypted"
            && event_type != "m.sticker"
        {
            continue;
        }

        if raw["content"]["m.relates_to"]["rel_type"].as_str() == Some("m.replace") {
            if let Some(target) = raw["content"]["m.relates_to"]["event_id"].as_str() {
                let content = raw["content"]
                    .get("m.new_content")
                    .filter(|value| value.is_object())
                    .unwrap_or(&raw["content"]);
                replacement_map.entry(target.to_owned()).or_insert_with(|| {
                    (
                        content["body"].as_str().unwrap_or("").to_owned(),
                        content["msgtype"].as_str().unwrap_or("m.text").to_owned(),
                    )
                });
            }
            continue;
        }

        let event_id = match raw["event_id"].as_str() {
            Some(id) => id.to_string(),
            None => continue,
        };

        let sender = raw["sender"].as_str().unwrap_or("unknown").to_string();
        let sender_is_ignored = ignored_users.contains(&sender);
        let event_reactions = bundled_reactions(&raw);

        let member_data = if let Some(cached) = member_cache.get(&sender) {
            cached.clone()
        } else {
            let data = if let Ok(user_id) = <&matrix_sdk::ruma::UserId>::try_from(sender.as_str()) {
                // Missing sender profiles are enriched after first paint.
                room.get_member_no_sync(user_id)
                    .await
                    .ok()
                    .flatten()
                    .map(|member| {
                        (
                            member.display_name().map(str::to_owned),
                            member.avatar_url().map(|url| url.to_string()),
                        )
                    })
            } else {
                None
            };
            member_cache.insert(sender.clone(), data.clone());
            data
        };
        let sender_display_name = member_data
            .as_ref()
            .and_then(|(name, _)| name.clone())
            .or_else(|| display_name_cache.get(&sender).cloned());
        if let Some(name) = sender_display_name.clone() {
            display_name_cache.insert(sender.clone(), name);
        }
        let mut sender_avatar_url = member_data.as_ref().and_then(|(_, avatar)| avatar.clone());
        if sender_avatar_url.is_none() {
            sender_avatar_url = avatar_cache.get(&sender).cloned().flatten();
        }
        avatar_cache.insert(sender.clone(), sender_avatar_url.clone());

        let timestamp = raw["origin_server_ts"].as_u64().unwrap_or(0);

        // An event still marked encrypted could not be decrypted by the SDK.
        if event_type == "m.room.encrypted" {
            messages.push(MessageInfo {
                event_id,
                sender,
                sender_avatar_url,
                sender_display_name: sender_display_name.clone(),
                sender_is_ignored,
                body: String::new(),
                msg_type: "m.encrypted".to_string(),
                timestamp,
                reply_to: None,
                reply_sender: None,
                reply_body: None,
                thread_root_id: None,
                thread_reply_count: 0,
                media_url: None,
                media_file: None,
                media_mime_type: None,
                sticker_pack: None,
                is_system: false,
                system_kind: None,
                is_edited: false,
                is_redacted: false,
                is_encrypted: true,
                reactions: event_reactions,
                read_receipts: Vec::new(),
            });
            continue;
        }

        let Some(content) = raw.get("content") else {
            continue;
        };

        let is_sticker = event_type == "m.sticker";
        let is_redacted = content.is_object()
            && if is_sticker {
                content.get("url").is_none() && content.get("file").is_none()
            } else {
                content["msgtype"].as_str().is_none()
            };
        let body = if is_redacted {
            String::new()
        } else {
            content["body"].as_str().unwrap_or("").to_string()
        };

        let msg_type = if is_sticker {
            "m.sticker".to_owned()
        } else {
            content["msgtype"].as_str().unwrap_or("m.text").to_string()
        };
        let system_kind = system_kind_for_message(&msg_type, &body).map(str::to_owned);

        let reply_to = content["m.relates_to"]["m.in_reply_to"]["event_id"]
            .as_str()
            .map(|s| s.to_string());
        let thread_root_id = (content["m.relates_to"]["rel_type"].as_str() == Some("m.thread"))
            .then(|| {
                content["m.relates_to"]["event_id"]
                    .as_str()
                    .map(str::to_owned)
            })
            .flatten();
        let thread_reply_count = raw["unsigned"]["m.relations"]["m.thread"]["count"]
            .as_u64()
            .unwrap_or(0)
            .min(u32::MAX as u64) as u32;

        let (media_url, media_file, media_mime_type) = media_metadata(content);
        let sticker_pack = content
            .get("org.prismchat.sticker_pack")
            .cloned()
            .filter(serde_json::Value::is_object);
        let is_edited = raw["unsigned"]["m.relations"]["m.replace"].is_object();

        messages.push(MessageInfo {
            event_id,
            sender,
            sender_avatar_url,
            sender_display_name,
            sender_is_ignored,
            body,
            msg_type,
            timestamp,
            reply_to,
            reply_sender: None,
            reply_body: None,
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
            is_encrypted: false,
            reactions: event_reactions,
            read_receipts: Vec::new(),
        });
    }

    // Resolve cached relations locally; background enrichment fills gaps.
    if let Some(event_cache) = event_cache {
        let relation_targets = messages
            .iter()
            .map(|message| message.event_id.clone())
            .collect::<Vec<_>>();
        let relation_pages = stream::iter(relation_targets)
            .map(|event_id| async move {
                let event_id = <&EventId>::try_from(event_id.as_str()).ok();
                let Some(event_id) = event_id else {
                    return Vec::new();
                };
                event_cache
                    .find_event_relations(
                        event_id,
                        Some(vec![RelationType::Annotation, RelationType::Replacement]),
                    )
                    .await
                    .unwrap_or_default()
            })
            .buffer_unordered(16)
            .collect::<Vec<_>>()
            .await;
        for relation_page in relation_pages {
            for event in relation_page {
                let Ok(raw) = event.raw().deserialize_as_unchecked::<serde_json::Value>() else {
                    continue;
                };
                let relates = &raw["content"]["m.relates_to"];
                if raw["type"].as_str() == Some("m.reaction")
                    && relates["rel_type"].as_str() == Some("m.annotation")
                {
                    if let (Some(target), Some(key), Some(sender), Some(reaction_event_id)) = (
                        relates["event_id"].as_str(),
                        relates["key"].as_str(),
                        raw["sender"].as_str(),
                        raw["event_id"].as_str(),
                    ) {
                        reaction_map
                            .entry(target.to_owned())
                            .or_default()
                            .entry(key.to_owned())
                            .or_default()
                            .insert(sender.to_owned(), reaction_event_id.to_owned());
                    }
                } else if raw["type"].as_str() == Some("m.room.message")
                    && relates["rel_type"].as_str() == Some("m.replace")
                {
                    if let Some(target) = relates["event_id"].as_str() {
                        let content = raw["content"]
                            .get("m.new_content")
                            .filter(|value| value.is_object())
                            .unwrap_or(&raw["content"]);
                        replacement_map.insert(
                            target.to_owned(),
                            (
                                content["body"].as_str().unwrap_or("").to_owned(),
                                content["msgtype"].as_str().unwrap_or("m.text").to_owned(),
                            ),
                        );
                    }
                }
            }
        }
    }

    let mut preview_by_event = messages
        .iter()
        .filter(|message| !message.is_encrypted && !message.sender_is_ignored)
        .map(|message| {
            (
                message.event_id.clone(),
                (message.sender.clone(), message.body.clone()),
            )
        })
        .collect::<HashMap<_, _>>();
    let missing_reply_ids = messages
        .iter()
        .filter_map(|message| message.reply_to.as_ref())
        .filter(|event_id| !preview_by_event.contains_key(*event_id))
        .cloned()
        .collect::<HashSet<_>>();
    if let Some(event_cache) = event_cache {
        let fetched = stream::iter(missing_reply_ids)
            .map(|event_id| async move {
                let preview = cached_reply_preview(event_cache, &event_id).await;
                (event_id, preview)
            })
            .buffer_unordered(16)
            .collect::<Vec<_>>()
            .await;
        for (event_id, preview) in fetched {
            if let Some(preview) = preview {
                if !ignored_users.contains(&preview.0) {
                    preview_by_event.insert(event_id, preview);
                }
            }
        }
    }

    for message in &mut messages {
        if let Some((body, msg_type)) = replacement_map.get(&message.event_id) {
            message.body = body.clone();
            message.msg_type = msg_type.clone();
            message.is_edited = true;
        }
        if let Some(by_key) = reaction_map.get(&message.event_id) {
            for (key, senders) in by_key {
                let reacted = current_user
                    .as_deref()
                    .is_some_and(|user| senders.contains_key(user));
                let own_event_id = current_user
                    .as_deref()
                    .and_then(|user| senders.get(user))
                    .cloned();
                if let Some(reaction) = message.reactions.iter_mut().find(|item| item.key == *key) {
                    reaction.count = senders.len() as u64;
                    reaction.reacted = reacted;
                    reaction.own_event_id = own_event_id;
                } else {
                    message.reactions.push(ReactionInfo {
                        key: key.clone(),
                        count: senders.len() as u64,
                        reacted,
                        own_event_id,
                    });
                }
            }
        }
        let Some(reply_to) = message.reply_to.as_ref() else {
            continue;
        };
        let Some((sender, body)) = preview_by_event.get(reply_to) else {
            continue;
        };
        message.reply_sender = Some(sender.clone());
        message.reply_body = Some(body.clone());
    }

    let messages_with_reactions = messages
        .iter()
        .filter(|message| !message.reactions.is_empty())
        .count();
    let reaction_groups = messages
        .iter()
        .map(|message| message.reactions.len())
        .sum::<usize>();
    println!(
        "[Messages] Получено: {}, с реакциями: {}, групп реакций: {}",
        messages.len(),
        messages_with_reactions,
        reaction_groups
    );
    Ok(messages)
}

/// Fill fields omitted from the first-paint response.
pub async fn enrich_message_details(
    room_id: &str,
    mut messages: Vec<MessageInfo>,
) -> Result<Option<Vec<MessageInfo>>, String> {
    let client = get_client().await?;
    let room_id =
        <&RoomId>::try_from(room_id).map_err(|error| format!("Некорректный room_id: {error}"))?;
    let room = client
        .get_room(room_id)
        .ok_or_else(|| "Комната не найдена в локальном состоянии SDK".to_string())?;
    let ignored_users = ignored_user_ids(&client).await;

    let avatar_users = messages
        .iter()
        .filter(|message| message.sender_avatar_url.is_none())
        .map(|message| message.sender.clone())
        .collect::<HashSet<_>>();
    let avatar_results = stream::iter(avatar_users)
        .map(|user_id| async move {
            let avatar = fetch_user_avatar(&user_id).await;
            (user_id, avatar)
        })
        .buffer_unordered(8)
        .collect::<Vec<_>>()
        .await;
    let avatars = avatar_results.into_iter().collect::<HashMap<_, _>>();

    let reply_ids = messages
        .iter()
        .filter(|message| {
            message.reply_to.is_some() && message.reply_body.is_none() && !message.sender_is_ignored
        })
        .filter_map(|message| message.reply_to.clone())
        .collect::<HashSet<_>>();
    let reply_results = stream::iter(reply_ids)
        .map(|event_id| {
            let room = room.clone();
            async move {
                let preview = tokio::time::timeout(
                    std::time::Duration::from_secs(4),
                    fetch_reply_preview(&room, &event_id),
                )
                .await
                .ok()
                .flatten();
                (event_id, preview)
            }
        })
        .buffer_unordered(8)
        .collect::<Vec<_>>()
        .await;
    let replies = reply_results
        .into_iter()
        .filter_map(|(event_id, preview)| {
            preview
                .filter(|(sender, _)| !ignored_users.contains(sender))
                .map(|preview| (event_id, preview))
        })
        .collect::<HashMap<_, _>>();

    let mut changed = false;
    for message in &mut messages {
        if message.sender_avatar_url.is_none() {
            if let Some(avatar) = avatars.get(&message.sender).cloned().flatten() {
                message.sender_avatar_url = Some(avatar);
                changed = true;
            }
        }
        if let Some(reply_to) = message.reply_to.as_deref() {
            if message.reply_body.is_none() {
                if let Some((sender, body)) = replies.get(reply_to) {
                    message.reply_sender = Some(sender.clone());
                    message.reply_body = Some(body.clone());
                    changed = true;
                }
            }
        }
    }

    Ok(changed.then_some(messages))
}

#[cfg(test)]
mod tests {
    use super::{bundled_reactions, media_metadata, reply_preview_from_raw};
    use crate::matrix::attachments::contains_web_link;
    use serde_json::json;

    #[test]
    fn reads_plain_media_source() {
        let content = json!({
            "msgtype": "m.file",
            "url": "mxc://example.org/plain",
            "info": { "mimetype": "application/pdf" }
        });

        let (url, file, mime_type) = media_metadata(&content);
        assert_eq!(url.as_deref(), Some("mxc://example.org/plain"));
        assert!(file.is_none());
        assert_eq!(mime_type.as_deref(), Some("application/pdf"));
    }

    #[test]
    fn prefers_encrypted_media_source() {
        let content = json!({
            "msgtype": "m.image",
            "url": "mxc://example.org/legacy",
            "file": {
                "url": "mxc://example.org/encrypted",
                "key": {
                    "kty": "oct", "key_ops": ["encrypt", "decrypt"],
                    "alg": "A256CTR", "k": "secret", "ext": true
                },
                "iv": "iv",
                "hashes": { "sha256": "hash" },
                "v": "v2"
            },
            "info": { "mimetype": "image/png" }
        });

        let (url, file, mime_type) = media_metadata(&content);
        assert_eq!(url.as_deref(), Some("mxc://example.org/encrypted"));
        assert_eq!(
            file.as_ref().and_then(|value| value["v"].as_str()),
            Some("v2")
        );
        assert_eq!(mime_type.as_deref(), Some("image/png"));
    }

    #[test]
    fn extracts_reply_preview_from_decrypted_room_message() {
        let raw = json!({
            "type": "m.room.message",
            "event_id": "$source:example.org",
            "sender": "@alice:example.org",
            "content": {
                "msgtype": "m.text",
                "body": "Исходное сообщение"
            }
        });

        let preview = reply_preview_from_raw(&raw);
        assert_eq!(
            preview,
            Some((
                "@alice:example.org".to_owned(),
                "Исходное сообщение".to_owned()
            ))
        );
    }

    #[test]
    fn extracts_bundled_reactions() {
        let raw = json!({
            "unsigned": {
                "m.relations": {
                    "m.annotation": {
                        "chunk": [
                            {"type": "m.reaction", "key": "👍", "count": 3},
                            {"type": "m.reaction", "key": "🎉", "count": 1}
                        ]
                    }
                }
            }
        });
        let reactions = bundled_reactions(&raw);
        assert_eq!(reactions.len(), 2);
        assert_eq!(reactions[0].key, "👍");
        assert_eq!(reactions[0].count, 3);
    }

    #[test]
    fn detects_links_for_the_attachments_panel() {
        assert!(contains_web_link("Сайт: HTTPS://example.org/page"));
        assert!(contains_web_link("www.example.org"));
        assert!(!contains_web_link("example.org without a scheme"));
    }
}

pub async fn get_messages_around(
    room_id: &str,
    event_id: &str,
    limit: u32,
) -> Result<(Vec<MessageInfo>, Option<String>), String> {
    let client = get_client().await?;
    let room_id =
        <&RoomId>::try_from(room_id).map_err(|e| format!("Некорректный room_id: {}", e))?;
    let event_id =
        <&EventId>::try_from(event_id).map_err(|e| format!("Некорректный event_id: {}", e))?;
    let room = client
        .get_room(room_id)
        .ok_or_else(|| format!("Комната не найдена в локальном состоянии SDK: {}", room_id))?;
    let context_size =
        UInt::new(u64::from(limit)).ok_or_else(|| "Некорректный размер контекста".to_string())?;
    let context = room
        .event_with_context(event_id, true, context_size, None)
        .await
        .map_err(|e| format!("Не удалось загрузить контекст сообщения: {}", e))?;

    // The UI model is newest-first. Matrix returns events_after in
    // chronological order and events_before in reverse chronological order.
    let mut events = context.events_after;
    events.reverse();
    if let Some(target) = context.event {
        events.push(target);
    }
    events.extend(context.events_before);

    let event_cache = room.event_cache().await.ok().map(|(cache, _)| cache);
    let mut messages = parse_messages(&room, events, event_cache.as_ref()).await?;
    messages.truncate(limit as usize);
    Ok((messages, context.prev_batch_token))
}

pub async fn search_room_messages(
    room_id: &str,
    query: &str,
    limit: u32,
    next_batch: Option<String>,
) -> Result<(Vec<MessageInfo>, Option<String>), String> {
    let client = get_client().await?;
    let room_id =
        <&RoomId>::try_from(room_id).map_err(|error| format!("Некорректный room_id: {error}"))?;
    let room = client
        .get_room(room_id)
        .ok_or_else(|| format!("Комната не найдена в SDK: {room_id}"))?;

    // Search complete history pages until the requested match count is reached.
    let target = limit.clamp(1, 100) as usize;
    let max_scanned = target.saturating_mul(10).min(1000).max(target);
    let filters = SearchFilters::parse(query);
    let event_cache = room.event_cache().await.ok().map(|(cache, _)| cache);
    let mut cursor = next_batch.filter(|value| !value.is_empty());
    let mut results = Vec::with_capacity(target);
    let mut scanned = 0usize;
    let mut pages = 0usize;

    while results.len() < target && scanned < max_scanned && pages < 10 {
        let remaining_results = target - results.len();
        let remaining_scan = max_scanned - scanned;
        let request_size = remaining_results.min(remaining_scan).min(100).max(1);
        let mut options = MessagesOptions::backward();
        if let Some(token) = cursor.as_deref() {
            options = options.from(Some(token));
        }
        options.limit = UInt::new(request_size as u64)
            .ok_or_else(|| "Некорректный размер страницы поиска".to_owned())?;

        let response = room
            .messages(options)
            .await
            .map_err(|error| format!("Не удалось продолжить поиск на сервере: {error}"))?;
        let chunk_len = response.chunk.len();
        scanned = scanned.saturating_add(chunk_len);
        let next_cursor = response.end;
        let cursor_unchanged = next_cursor == cursor;
        let messages = parse_messages(&room, response.chunk, event_cache.as_ref()).await?;

        for message in messages {
            if !message.sender_is_ignored && filters.matches(&message) {
                results.push(message);
            }
        }

        cursor = next_cursor;
        pages += 1;
        if chunk_len == 0 || cursor.is_none() || cursor_unchanged {
            break;
        }
    }

    Ok((results, cursor))
}

#[derive(Default)]
struct SearchFilters {
    text: String,
    sender: Option<String>,
    media_kind: Option<String>,
    before_ms: Option<u64>,
    after_ms: Option<u64>,
}

impl SearchFilters {
    fn parse(query: &str) -> Self {
        let mut filters = Self::default();
        let mut text = Vec::new();
        for token in query.split_whitespace() {
            if let Some(value) = token
                .strip_prefix("from:")
                .filter(|value| !value.is_empty())
            {
                filters.sender = Some(value.trim_matches('"').to_lowercase());
            } else if let Some(value) = token.strip_prefix("has:") {
                filters.media_kind = Some(value.to_lowercase());
            } else if let Some(value) = token.strip_prefix("before:") {
                filters.before_ms = parse_search_date(value);
            } else if let Some(value) = token.strip_prefix("after:") {
                filters.after_ms = parse_search_date(value);
            } else {
                text.push(token);
            }
        }
        filters.text = text.join(" ").to_lowercase();
        filters
    }

    fn matches(&self, message: &MessageInfo) -> bool {
        if !self.text.is_empty() && !message.body.to_lowercase().contains(&self.text) {
            return false;
        }
        if let Some(sender) = &self.sender {
            let display_name = message.sender_display_name.as_deref().unwrap_or_default();
            if !message.sender.to_lowercase().contains(sender)
                && !display_name.to_lowercase().contains(sender)
            {
                return false;
            }
        }
        if self
            .before_ms
            .is_some_and(|timestamp| message.timestamp >= timestamp)
            || self
                .after_ms
                .is_some_and(|timestamp| message.timestamp < timestamp)
        {
            return false;
        }
        if let Some(kind) = &self.media_kind {
            let matches_kind = match kind.as_str() {
                "file" => matches!(
                    message.msg_type.as_str(),
                    "m.file" | "m.image" | "m.video" | "m.audio"
                ),
                "image" => message.msg_type == "m.image" || message.msg_type == "m.sticker",
                "video" => message.msg_type == "m.video",
                "audio" | "voice" => message.msg_type == "m.audio",
                "link" => contains_web_link(&message.body),
                _ => true,
            };
            if !matches_kind {
                return false;
            }
        }
        true
    }
}

fn parse_search_date(value: &str) -> Option<u64> {
    let mut parts = value.split('-');
    let year = parts.next()?.parse::<i64>().ok()?;
    let month = parts.next()?.parse::<i64>().ok()?;
    let day = parts.next()?.parse::<i64>().ok()?;
    if parts.next().is_some() || !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    let adjusted_year = year - i64::from(month <= 2);
    let era = adjusted_year.div_euclid(400);
    let year_of_era = adjusted_year - era * 400;
    let shifted_month = month + if month > 2 { -3 } else { 9 };
    let day_of_year = (153 * shifted_month + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    let days_since_epoch = era * 146_097 + day_of_era - 719_468;
    u64::try_from(days_since_epoch)
        .ok()?
        .checked_mul(86_400_000)
}
