use crate::matrix::session::get_client;
use matrix_sdk::RoomState;

pub async fn add_room_to_space(room_id: &str, space_id: &str) -> Result<(), String> {
    let client = get_client().await?;
    let room_id = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|error| format!("Некорректный room_id: {error}"))?
        .to_owned();
    let space_id = <&matrix_sdk::ruma::RoomId>::try_from(space_id)
        .map_err(|error| format!("Некорректный space_id: {error}"))?
        .to_owned();

    let room = client
        .get_room(&room_id)
        .ok_or_else(|| format!("Комната не найдена: {room_id}"))?;
    let space = client
        .get_room(&space_id)
        .ok_or_else(|| format!("Пространство не найдено: {space_id}"))?;
    if !space.is_space() {
        return Err(format!(
            "Выбранная комната не является пространством: {space_id}"
        ));
    }
    if room.state() != RoomState::Joined || space.state() != RoomState::Joined {
        return Err(
            "Для изменения пространства нужно состоять и в комнате, и в пространстве".to_string(),
        );
    }

    // Since Matrix room IDs may not contain a server name, use the current
    // user's homeserver as a safe fallback for the `via` routing hint.
    let fallback_server = client
        .user_id()
        .map(|user_id| user_id.server_name().to_string());
    let room_via_server = room_id
        .server_name()
        .map(|server_name| server_name.to_string())
        .or_else(|| fallback_server.clone())
        .ok_or_else(|| "Не удалось определить сервер для связи m.space.child".to_string())?;
    let space_via_server = space_id
        .server_name()
        .map(|server_name| server_name.to_string())
        .or(fallback_server)
        .ok_or_else(|| "Не удалось определить сервер для связи m.space.parent".to_string())?;

    space
        .send_state_event_raw(
            "m.space.child",
            room_id.as_str(),
            serde_json::json!({ "via": [room_via_server], "suggested": false }),
        )
        .await
        .map_err(|error| format!("Не удалось добавить комнату в пространство: {error}"))?;

    // m.space.child is the authoritative relation. The matching parent event
    // improves discovery in clients which inspect the child room directly.
    if let Err(error) = room
        .send_state_event_raw(
            "m.space.parent",
            space_id.as_str(),
            serde_json::json!({
                "via": [space_via_server],
                "canonical": false
            }),
        )
        .await
    {
        eprintln!("[Rooms] m.space.parent was not written: {error}");
    }

    Ok(())
}

/// Remove the direct relationship between a room and a Space.
///
/// `m.space.child` in the Space is authoritative. Matrix removes a Space
/// relationship by replacing the state event content with an empty object.
/// We also clear the matching `m.space.parent` event in the child room as a
/// best-effort compatibility step, mirroring `add_room_to_space`.
pub async fn remove_room_from_space(room_id: &str, space_id: &str) -> Result<(), String> {
    let client = get_client().await?;
    let room_id = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|error| format!("Некорректный room_id: {error}"))?
        .to_owned();
    let space_id = <&matrix_sdk::ruma::RoomId>::try_from(space_id)
        .map_err(|error| format!("Некорректный space_id: {error}"))?
        .to_owned();

    let room = client
        .get_room(&room_id)
        .ok_or_else(|| format!("Комната не найдена: {room_id}"))?;
    let space = client
        .get_room(&space_id)
        .ok_or_else(|| format!("Пространство не найдено: {space_id}"))?;
    if !space.is_space() {
        return Err(format!(
            "Выбранная комната не является пространством: {space_id}"
        ));
    }
    if room.state() != RoomState::Joined || space.state() != RoomState::Joined {
        return Err(
            "Для изменения пространства нужно состоять и в комнате, и в пространстве".to_string(),
        );
    }

    space
        .send_state_event_raw("m.space.child", room_id.as_str(), serde_json::json!({}))
        .await
        .map_err(|error| format!("Не удалось убрать комнату из пространства: {error}"))?;

    // The child event above is authoritative. Failing to clear the mirrored
    // parent event must not turn an otherwise successful move into an error.
    if let Err(error) = room
        .send_state_event_raw("m.space.parent", space_id.as_str(), serde_json::json!({}))
        .await
    {
        eprintln!("[Rooms] m.space.parent was not cleared: {error}");
    }

    Ok(())
}
