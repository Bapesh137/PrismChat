use matrix_sdk::ruma::{api::client::space::get_hierarchy, EventId, RoomId, RoomOrAliasId};

use crate::{
    matrix::{messages::media_metadata, session::get_client, users::ignored_user_ids},
    protocol::commands::{MessageInfo, SpaceRoomInfo},
};

pub async fn pin_message(room_id: &str, event_id: &str, pinned: bool) -> Result<(), String> {
    let client = get_client().await?;
    let room_id = <&RoomId>::try_from(room_id).map_err(|e| e.to_string())?;
    let event_id = <&EventId>::try_from(event_id).map_err(|e| e.to_string())?;
    let room = client
        .get_room(room_id)
        .ok_or_else(|| "Комната не найдена".to_string())?;
    if pinned {
        room.pin_event(event_id)
            .await
            .map_err(|e| format!("Не удалось закрепить сообщение: {e}"))?;
    } else {
        room.unpin_event(event_id)
            .await
            .map_err(|e| format!("Не удалось открепить сообщение: {e}"))?;
    }
    Ok(())
}

pub async fn pinned_messages(room_id: &str) -> Result<Vec<MessageInfo>, String> {
    let client = get_client().await?;
    let room_id = <&RoomId>::try_from(room_id).map_err(|e| e.to_string())?;
    let room = client
        .get_room(room_id)
        .ok_or_else(|| "Комната не найдена".to_string())?;
    let ids = room
        .load_pinned_events()
        .await
        .map_err(|e| format!("Не удалось загрузить закреплённые сообщения: {e}"))?
        .unwrap_or_default();
    let ignored_users = ignored_user_ids(&client).await;
    let mut result = Vec::new();
    for id in ids {
        let Ok(event) = room.event(&id, None).await else {
            continue;
        };
        let Ok(raw) = event.raw().deserialize_as_unchecked::<serde_json::Value>() else {
            continue;
        };
        let content = &raw["content"];
        let msg_type = content["msgtype"].as_str().unwrap_or("m.text");
        if !matches!(
            msg_type,
            "m.text" | "m.notice" | "m.emote" | "m.image" | "m.file"
        ) {
            continue;
        }
        let (media_url, media_file, media_mime_type) = media_metadata(content);
        result.push(MessageInfo {
            event_id: raw["event_id"].as_str().unwrap_or("").to_owned(),
            sender: raw["sender"].as_str().unwrap_or("").to_owned(),
            sender_avatar_url: None,
            sender_display_name: None,
            sender_is_ignored: raw["sender"]
                .as_str()
                .is_some_and(|sender| ignored_users.contains(sender)),
            body: content["body"].as_str().unwrap_or("").to_owned(),
            msg_type: msg_type.to_owned(),
            timestamp: raw["origin_server_ts"].as_u64().unwrap_or_default(),
            reply_to: None,
            reply_sender: None,
            reply_body: None,
            thread_root_id: None,
            thread_reply_count: 0,
            media_url,
            media_file,
            media_mime_type,
            sticker_pack: content
                .get("org.prismchat.sticker_pack")
                .cloned()
                .filter(serde_json::Value::is_object),
            is_system: false,
            system_kind: None,
            is_edited: false,
            is_redacted: false,
            is_encrypted: false,
            reactions: Vec::new(),
            read_receipts: Vec::new(),
        });
    }
    Ok(result)
}

pub async fn space_hierarchy_page(
    space_id: &str,
    from: Option<String>,
    limit: Option<u32>,
) -> Result<(Vec<SpaceRoomInfo>, Option<String>), String> {
    let client = get_client().await?;
    let space_id = <&RoomId>::try_from(space_id)
        .map_err(|e| e.to_string())?
        .to_owned();
    let mut rooms = Vec::new();
    let mut request = get_hierarchy::v1::Request::new(space_id.clone());
    request.from = from;
    request.limit = Some(limit.unwrap_or(25).clamp(1, 100).into());
    let response = client
        .send(request)
        .await
        .map_err(|e| format!("Не удалось загрузить комнаты пространства: {e}"))?;
    for chunk in response.rooms {
        // Some homeservers include the hierarchy root itself in the response.
        // It is a room technically, but it must not be rendered as a child of itself.
        if chunk.summary.room_id == space_id {
            continue;
        }
        let id = chunk.summary.room_id.to_string();
        if rooms.iter().any(|room: &SpaceRoomInfo| room.room_id == id) {
            continue;
        }
        let known_state = client
            .get_room(&chunk.summary.room_id)
            .map(|room| format!("{:?}", room.state()).to_lowercase());
        let joined = known_state.as_deref() == Some("joined");
        let invited = known_state.as_deref() == Some("invited");
        let knocked = known_state.as_deref() == Some("knocked");
        let via = id
            .split_once(':')
            .map(|(_, server)| vec![server.to_owned()])
            .unwrap_or_default();
        rooms.push(SpaceRoomInfo {
            room_id: id,
            name: chunk.summary.name,
            topic: chunk.summary.topic,
            avatar_url: chunk.summary.avatar_url.map(|url| url.to_string()),
            joined,
            invited,
            knocked,
            join_rule: format!("{:?}", chunk.summary.join_rule).to_lowercase(),
            world_readable: chunk.summary.world_readable,
            member_count: chunk.summary.num_joined_members.into(),
            via,
        });
    }
    Ok((rooms, response.next_batch))
}

pub async fn join_space_room(room_id: &str, knock: bool, via: &[String]) -> Result<(), String> {
    let client = get_client().await?;
    let inferred_server = room_id.split_once(':').map(|(_, server)| server.to_owned());
    let room_or_alias = <&RoomOrAliasId>::try_from(room_id).map_err(|e| e.to_string())?;
    let mut via = via
        .iter()
        .filter_map(|server| server.parse().ok())
        .collect::<Vec<_>>();
    // Directory results currently carry a room ID rather than hierarchy
    // `via` hints. The server from an ID/alias is the correct first
    // federation hint and also makes direct alias joins work.
    if via.is_empty() {
        if let Some(server) = inferred_server.and_then(|server| server.parse().ok()) {
            via.push(server);
        }
    }
    if knock {
        // The Matrix /knock endpoint intentionally accepts either a room ID or
        // an alias. This matters for private spaces which are absent from the
        // public room directory but whose address is known to the user.
        client
            .knock(room_or_alias.to_owned(), None, via)
            .await
            .map_err(|e| format!("Не удалось отправить запрос на вступление: {e}"))?;
    } else {
        client
            .join_room_by_id_or_alias(room_or_alias, &via)
            .await
            .map_err(|e| format!("Не удалось вступить в комнату: {e}"))?;
    }
    Ok(())
}
