//! Attachment pagination counts gallery entries, while Matrix pages contain events.
use crate::{
    matrix::{
        messages::parse_messages,
        session::{current_session_epoch, get_client},
    },
    protocol::commands::MessageInfo,
};
use matrix_sdk::{
    deserialized_responses::TimelineEvent,
    room::MessagesOptions,
    ruma::{RoomId, UInt},
};
use serde::{Deserialize, Serialize};
use std::{
    collections::{HashMap, HashSet, VecDeque},
    sync::{Arc, LazyLock, Mutex},
    time::{Duration, Instant},
};

const NETWORK_PAGE: usize = 100;
const CURSOR_PREFIX: &str = "prism-attachments-v1:";
const CACHE_BYTES: usize = 32 * 1024 * 1024;

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Cursor {
    room: String,
    category: Option<u8>,
    epoch: u64,
    token: String,
    skip: usize,
}

impl Cursor {
    fn decode(
        value: Option<String>,
        room: &str,
        category: Option<u8>,
        epoch: u64,
    ) -> Result<Option<Self>, String> {
        let Some(value) = value.filter(|s| !s.is_empty()) else {
            return Ok(None);
        };
        let cursor = if let Some(json) = value.strip_prefix(CURSOR_PREFIX) {
            serde_json::from_str::<Self>(json)
                .map_err(|_| "Некорректная позиция вложений".to_owned())?
        } else {
            // Accept a plain Matrix token from an older frontend.
            Self {
                room: room.to_owned(),
                category,
                epoch,
                token: value,
                skip: 0,
            }
        };
        if cursor.room != room
            || cursor.category != category
            || cursor.epoch != epoch
            || cursor.skip >= NETWORK_PAGE
            || cursor.token.is_empty()
        {
            return Err("Позиция вложений относится к другой вкладке или сессии".to_owned());
        }
        Ok(Some(cursor))
    }

    fn encode(&self) -> String {
        format!(
            "{CURSOR_PREFIX}{}",
            serde_json::to_string(self).expect("serializable attachment cursor")
        )
    }
}

struct HistoryPage {
    room: String,
    epoch: u64,
    start: String,
    end: Option<String>,
    events: Vec<TimelineEvent>,
    bytes: usize,
    created: Instant,
}

static PAGES: LazyLock<Mutex<VecDeque<Arc<HistoryPage>>>> =
    LazyLock::new(|| Mutex::new(VecDeque::new()));

pub fn clear_cache() {
    if let Ok(mut pages) = PAGES.lock() {
        pages.clear();
    }
}

fn cached_page(room: &str, epoch: u64, start: &str) -> Option<Arc<HistoryPage>> {
    let mut pages = PAGES.lock().ok()?;
    pages.retain(|p| p.epoch == epoch && p.created.elapsed() < Duration::from_secs(120));
    let index = pages
        .iter()
        .position(|p| p.room == room && p.start == start)?;
    let page = pages.remove(index)?;
    pages.push_back(page.clone());
    Some(page)
}

fn cache_page(page: Arc<HistoryPage>) {
    if page.bytes > CACHE_BYTES {
        return;
    }
    if let Ok(mut pages) = PAGES.lock() {
        pages.retain(|p| {
            p.epoch == page.epoch
                && p.created.elapsed() < Duration::from_secs(120)
                && !(p.room == page.room && p.start == page.start)
        });
        pages.push_back(page);
        while pages.len() > 32 || pages.iter().map(|p| p.bytes).sum::<usize>() > CACHE_BYTES {
            pages.pop_front();
        }
    }
}

pub(crate) fn contains_web_link(body: &str) -> bool {
    let lower = body.to_ascii_lowercase();
    ["https://", "http://", "www."].iter().any(|prefix| {
        lower.match_indices(prefix).any(|(index, _)| {
            lower[index + prefix.len()..]
                .chars()
                .next()
                .is_some_and(|c| !c.is_whitespace() && !"<>\"'".contains(c))
        })
    })
}

fn category_for(msg_type: &str, body: &str, mime: &str) -> Option<u8> {
    match msg_type {
        "m.image" | "m.video" => Some(0),
        "m.text" if contains_web_link(body) => Some(1),
        "m.audio" => Some(3),
        "m.file" => {
            let extension = body.rsplit('.').next().unwrap_or("").to_ascii_lowercase();
            let video = mime.to_ascii_lowercase().starts_with("video/")
                || [
                    "mp4", "m4v", "mov", "mkv", "webm", "avi", "mpeg", "mpg", "ogv", "ts", "mts",
                    "m2ts", "3gp", "3g2", "flv",
                ]
                .contains(&extension.as_str());
            Some(if video { 0 } else { 2 })
        }
        _ => None,
    }
}

fn matches(message: &MessageInfo, category: Option<u8>) -> bool {
    !message.sender_is_ignored
        && !message.is_redacted
        && !message.is_encrypted
        && category_for(
            &message.msg_type,
            &message.body,
            message.media_mime_type.as_deref().unwrap_or(""),
        )
        .is_some_and(|found| category.is_none_or(|wanted| wanted == found))
}

// The raw offset (not a filtered-result offset) remains valid if an attachment is
// redacted/ignored between requests. Replay from the fixed Matrix start token if
// the small in-memory page cache was evicted; no history tail is discarded.
fn take_batch(
    mut found: Vec<(usize, MessageInfo)>,
    limit: usize,
) -> (Vec<MessageInfo>, Option<usize>) {
    found.sort_by_key(|(index, _)| *index);
    let mut seen = HashSet::new();
    found.retain(|(_, message)| seen.insert(message.event_id.clone()));
    let resume = (found.len() > limit).then(|| found[limit - 1].0 + 1);
    found.truncate(limit);
    (
        found.into_iter().map(|(_, message)| message).collect(),
        resume,
    )
}

pub async fn get_room_attachments(
    room_id: &str,
    limit: u32,
    from: Option<String>,
    category: Option<u8>,
) -> Result<(Vec<MessageInfo>, Option<String>), String> {
    if category.is_some_and(|value| value > 3) {
        return Err("Неизвестная категория вложений".to_owned());
    }
    let epoch = current_session_epoch();
    let cursor = Cursor::decode(from, room_id, category, epoch)?;
    let client = get_client().await?;
    let matrix_room_id =
        <&RoomId>::try_from(room_id).map_err(|e| format!("Некорректный room_id: {e}"))?;
    let room = client
        .get_room(matrix_room_id)
        .ok_or_else(|| "Комната не найдена в SDK".to_owned())?;
    let cached = cursor
        .as_ref()
        .and_then(|c| cached_page(room_id, epoch, &c.token));
    let page = if let Some(page) = cached {
        page
    } else {
        let mut options = MessagesOptions::backward();
        if let Some(c) = &cursor {
            options = options.from(Some(c.token.as_str()));
        }
        options.limit = UInt::new(NETWORK_PAGE as u64).expect("bounded network page");
        let response = room
            .messages(options)
            .await
            .map_err(|e| format!("Не удалось загрузить вложения с сервера: {e}"))?;
        if current_session_epoch() != epoch {
            return Err("Matrix-сессия изменилась".to_owned());
        }
        let end = response.end.filter(|token| {
            !token.is_empty()
                && token != &response.start
                && cursor.as_ref().is_none_or(|c| token != &c.token)
        });
        let bytes = response
            .chunk
            .iter()
            .map(|event| event.raw().json().get().len())
            .sum();
        let page = Arc::new(HistoryPage {
            room: room_id.to_owned(),
            epoch,
            start: response.start,
            end,
            events: response.chunk,
            bytes,
            created: Instant::now(),
        });
        cache_page(page.clone());
        page
    };
    let skip = cursor.as_ref().map_or(0, |c| c.skip);
    let mut positions = HashMap::new();
    let mut candidates = Vec::new();
    let edited_targets = page
        .events
        .iter()
        .filter_map(|event| {
            let raw = event
                .raw()
                .deserialize_as_unchecked::<serde_json::Value>()
                .ok()?;
            (raw["content"]["m.relates_to"]["rel_type"] == "m.replace")
                .then(|| {
                    raw["content"]["m.relates_to"]["event_id"]
                        .as_str()
                        .map(str::to_owned)
                })
                .flatten()
        })
        .collect::<HashSet<_>>();
    for (index, event) in page.events.iter().enumerate().skip(skip) {
        let Ok(raw) = event.raw().deserialize_as_unchecked::<serde_json::Value>() else {
            continue;
        };
        if raw["type"] != "m.room.message" {
            continue;
        }
        let content = &raw["content"];
        // Keep replacements so a link removed by an edit is not counted. Avoid
        // member/reply/reaction lookups for the ordinary messages being scanned.
        let replacement = content["m.relates_to"]["rel_type"] == "m.replace";
        let found = category_for(
            content["msgtype"].as_str().unwrap_or(""),
            content["body"].as_str().unwrap_or(""),
            content["info"]["mimetype"].as_str().unwrap_or(""),
        );
        let edited = raw["unsigned"]["m.relations"]["m.replace"].is_object()
            || raw["event_id"]
                .as_str()
                .is_some_and(|id| edited_targets.contains(id));
        if replacement || edited || found.is_some_and(|c| category.is_none_or(|wanted| wanted == c))
        {
            if let Some(id) = raw["event_id"].as_str() {
                positions.insert(id.to_owned(), index);
            }
            candidates.push(event.clone());
        }
    }
    let event_cache = room.event_cache().await.ok().map(|(cache, _)| cache);
    let parsed = parse_messages(&room, candidates, event_cache.as_ref()).await?;
    if current_session_epoch() != epoch {
        return Err("Matrix-сессия изменилась".to_owned());
    }
    let found = parsed
        .into_iter()
        .filter(|m| matches(m, category))
        .filter_map(|m| positions.get(&m.event_id).copied().map(|index| (index, m)))
        .collect();
    let (items, resume) = take_batch(found, limit.clamp(1, 30) as usize);
    let next = if let Some(skip) = resume {
        Some(
            Cursor {
                room: room_id.to_owned(),
                category,
                epoch,
                token: page.start.clone(),
                skip,
            }
            .encode(),
        )
    } else {
        page.end.as_ref().map(|token| {
            Cursor {
                room: room_id.to_owned(),
                category,
                epoch,
                token: token.clone(),
                skip: 0,
            }
            .encode()
        })
    };
    Ok((items, next))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn item(id: usize, kind: &str) -> MessageInfo {
        serde_json::from_value(json!({
            "event_id": format!("${id}"),
            "sender": "@test:local",
            "body": "file",
            "msg_type": kind,
            "timestamp": id,
            "sender_is_ignored": false,
            "is_system": false,
            "is_edited": false,
            "is_redacted": false,
            "is_encrypted": false
        }))
        .unwrap()
    }

    #[test]
    fn dense_page_has_no_dropped_or_repeated_tail() {
        let mut skip = 0;
        let mut ids = Vec::new();
        let mut lengths = Vec::new();
        loop {
            let found = (skip..100).map(|i| (i, item(i, "m.image"))).collect();
            let (items, resume) = take_batch(found, 30);
            lengths.push(items.len());
            ids.extend(items.into_iter().map(|m| m.event_id));
            let Some(next) = resume else { break };
            skip = next;
        }
        assert_eq!(lengths, vec![30, 30, 30, 10]);
        assert_eq!(ids, (0..100).map(|i| format!("${i}")).collect::<Vec<_>>());
    }

    #[test]
    fn sparse_page_uses_raw_offsets_and_consumes_final_nonattachments() {
        let found = (0..100)
            .filter(|i| i % 3 == 0)
            .map(|i| (i, item(i, "m.image")))
            .collect();
        let (items, resume) = take_batch(found, 30);
        assert_eq!(items.len(), 30);
        assert_eq!(resume, Some(88));
        let (tail, resume) = take_batch(
            vec![
                (90, item(90, "m.image")),
                (93, item(93, "m.image")),
                (96, item(96, "m.image")),
                (99, item(99, "m.image")),
            ],
            30,
        );
        assert_eq!(tail.len(), 4);
        assert_eq!(resume, None);
        assert!(take_batch(Vec::new(), 30).1.is_none());
    }

    #[test]
    fn duplicate_events_do_not_consume_visible_slots() {
        let (items, resume) = take_batch(
            vec![
                (0, item(0, "m.image")),
                (1, item(0, "m.image")),
                (2, item(2, "m.image")),
            ],
            2,
        );
        assert_eq!(items.len(), 2);
        assert!(resume.is_none());
    }

    #[test]
    fn categories_match_gallery_including_video_files() {
        assert_eq!(category_for("m.image", "x", ""), Some(0));
        assert_eq!(
            category_for("m.file", "clip.MKV", "application/octet-stream"),
            Some(0)
        );
        assert_eq!(category_for("m.file", "unknown", "VIDEO/MP4"), Some(0));
        assert_eq!(category_for("m.file", "song.mp3", "audio/mpeg"), Some(2));
        assert_eq!(category_for("m.audio", "voice", ""), Some(3));
        assert_eq!(
            category_for("m.text", "Visit HTTPS://example.org", ""),
            Some(1)
        );
        assert_eq!(category_for("m.text", "http:// ", ""), None);
        assert_eq!(category_for("m.sticker", "x", "image/png"), None);
        let mut message = item(1, "m.image");
        assert!(matches(&message, Some(0)));
        message.is_redacted = true;
        assert!(!matches(&message, Some(0)));
        message.is_redacted = false;
        message.sender_is_ignored = true;
        assert!(!matches(&message, None));
    }

    #[test]
    fn cursor_roundtrip_binds_room_category_and_session() {
        let c = Cursor {
            room: "!room:local".into(),
            category: Some(0),
            epoch: 4,
            token: "opaque-token".into(),
            skip: 30,
        };
        let encoded = c.encode();
        assert_eq!(
            Cursor::decode(Some(encoded.clone()), &c.room, c.category, 4)
                .unwrap()
                .unwrap()
                .skip,
            30
        );
        assert!(Cursor::decode(Some(encoded.clone()), "!other:local", c.category, 4).is_err());
        assert!(Cursor::decode(Some(encoded.clone()), &c.room, Some(2), 4).is_err());
        assert!(Cursor::decode(Some(encoded), &c.room, c.category, 5).is_err());
        assert!(
            Cursor::decode(Some(format!("{CURSOR_PREFIX}{{}}")), &c.room, c.category, 4).is_err()
        );
    }
}
