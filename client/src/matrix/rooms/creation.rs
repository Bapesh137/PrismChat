use crate::matrix::session::get_client;
use matrix_sdk::ruma::api::client::room::create_room::v3::Request as CreateRoomRequest;

fn validate_power_levels_max_100(value: &serde_json::Value, path: &str) -> Result<(), String> {
    match value {
        serde_json::Value::Number(number) => {
            let exceeds_maximum = number
                .as_i64()
                .map(|level| level > 100)
                .or_else(|| number.as_u64().map(|level| level > 100))
                .or_else(|| number.as_f64().map(|level| level > 100.0))
                .unwrap_or(false);
            if exceeds_maximum {
                return Err(format!("{path}: уровень доступа не может быть больше 100"));
            }
        }
        serde_json::Value::Object(object) => {
            for (key, nested) in object {
                validate_power_levels_max_100(nested, &format!("{path}.{key}"))?;
            }
        }
        serde_json::Value::Array(items) => {
            for (index, nested) in items.iter().enumerate() {
                validate_power_levels_max_100(nested, &format!("{path}[{index}]"))?;
            }
        }
        _ => {}
    }
    Ok(())
}

fn validate_create_room_options(options: &serde_json::Value) -> Result<(), String> {
    let object = options
        .as_object()
        .ok_or_else(|| "Параметры создания комнаты должны быть JSON-объектом".to_string())?;

    for key in object.keys() {
        match key.as_str() {
            "visibility"
            | "room_alias_name"
            | "name"
            | "topic"
            | "invite"
            | "invite_3pid"
            | "room_version"
            | "creation_content"
            | "initial_state"
            | "preset"
            | "is_direct"
            | "power_level_content_override" => {}
            _ => return Err(format!("Неизвестный параметр создания комнаты: {key}")),
        }
    }

    if let Some(visibility) = object.get("visibility") {
        match visibility.as_str() {
            Some("private" | "public") => {}
            _ => return Err("visibility должен быть private или public".to_string()),
        }
    }

    if let Some(preset) = object.get("preset") {
        match preset.as_str() {
            Some("private_chat" | "public_chat" | "trusted_private_chat") => {}
            _ => {
                return Err(
                    "preset должен быть private_chat, public_chat или trusted_private_chat"
                        .to_string(),
                )
            }
        }
    }

    for string_key in ["room_alias_name", "name", "topic", "room_version"] {
        if object
            .get(string_key)
            .is_some_and(|value| !value.is_string())
        {
            return Err(format!("{string_key} должен быть строкой"));
        }
    }

    if let Some(alias) = object
        .get("room_alias_name")
        .and_then(|value| value.as_str())
    {
        if alias.is_empty()
            || alias.starts_with('#')
            || alias.contains(':')
            || alias.chars().any(char::is_whitespace)
        {
            return Err(
                "room_alias_name должен содержать локальную часть без #, сервера и пробелов"
                    .to_string(),
            );
        }
    }

    if object
        .get("is_direct")
        .is_some_and(|value| !value.is_boolean())
    {
        return Err("is_direct должен быть логическим значением".to_string());
    }

    if let Some(invites) = object.get("invite") {
        let invites = invites
            .as_array()
            .ok_or_else(|| "invite должен быть массивом Matrix ID".to_string())?;
        for value in invites {
            let user_id = value
                .as_str()
                .ok_or_else(|| "Каждый элемент invite должен быть строкой".to_string())?;
            <&matrix_sdk::ruma::UserId>::try_from(user_id)
                .map_err(|error| format!("Некорректный Matrix ID {user_id}: {error}"))?;
        }
    }

    if let Some(invites) = object.get("invite_3pid") {
        let invites = invites
            .as_array()
            .ok_or_else(|| "invite_3pid должен быть JSON-массивом".to_string())?;
        if invites.iter().any(|value| !value.is_object()) {
            return Err("Каждый элемент invite_3pid должен быть JSON-объектом".to_string());
        }
    }

    for object_key in ["creation_content", "power_level_content_override"] {
        if object
            .get(object_key)
            .is_some_and(|value| !value.is_object())
        {
            return Err(format!("{object_key} должен быть JSON-объектом"));
        }
    }

    if let Some(power_levels) = object.get("power_level_content_override") {
        validate_power_levels_max_100(power_levels, "power_level_content_override")?;
    }

    if let Some(initial_state) = object.get("initial_state") {
        let events = initial_state
            .as_array()
            .ok_or_else(|| "initial_state должен быть JSON-массивом".to_string())?;
        for (index, event) in events.iter().enumerate() {
            let event = event
                .as_object()
                .ok_or_else(|| format!("initial_state[{index}] должен быть JSON-объектом"))?;
            if !event.get("type").is_some_and(|value| value.is_string()) {
                return Err(format!("initial_state[{index}].type должен быть строкой"));
            }
            if !event.get("content").is_some_and(|value| value.is_object()) {
                return Err(format!(
                    "initial_state[{index}].content должен быть JSON-объектом"
                ));
            }
            if event.get("type").and_then(|value| value.as_str()) == Some("m.room.power_levels") {
                validate_power_levels_max_100(
                    event.get("content").expect("content was validated above"),
                    &format!("initial_state[{index}].content"),
                )?;
            }
            if event
                .get("state_key")
                .is_some_and(|value| !value.is_string())
            {
                return Err(format!(
                    "initial_state[{index}].state_key должен быть строкой"
                ));
            }
        }
    }

    Ok(())
}

fn create_room_request(options: &serde_json::Value) -> Result<CreateRoomRequest, String> {
    fn parse_field<T: serde::de::DeserializeOwned>(
        options: &serde_json::Value,
        field: &str,
    ) -> Result<Option<T>, String> {
        options
            .get(field)
            .cloned()
            .map(serde_json::from_value)
            .transpose()
            .map_err(|error| format!("Некорректное поле {field}: {error}"))
    }

    let mut request = CreateRoomRequest::new();
    request.creation_content = parse_field(options, "creation_content")?;
    request.initial_state = parse_field(options, "initial_state")?.unwrap_or_default();
    request.invite = parse_field(options, "invite")?.unwrap_or_default();
    request.invite_3pid = parse_field(options, "invite_3pid")?.unwrap_or_default();
    request.is_direct = options
        .get("is_direct")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or_default();
    request.name = parse_field(options, "name")?;
    request.power_level_content_override = parse_field(options, "power_level_content_override")?;
    request.preset = parse_field(options, "preset")?;
    request.room_alias_name = parse_field(options, "room_alias_name")?;
    request.room_version = parse_field(options, "room_version")?;
    request.topic = parse_field(options, "topic")?;
    if let Some(visibility) = parse_field(options, "visibility")? {
        request.visibility = visibility;
    }
    Ok(request)
}

pub async fn create_room(options: serde_json::Value) -> Result<(String, String, bool), String> {
    validate_create_room_options(&options)?;
    let is_space = options
        .get("creation_content")
        .and_then(|value| value.get("type"))
        .and_then(|value| value.as_str())
        == Some("m.space");
    let requested_name = options
        .get("name")
        .and_then(|value| value.as_str())
        .filter(|value| !value.trim().is_empty())
        .map(str::to_owned);
    let requested_alias = options
        .get("room_alias_name")
        .and_then(|value| value.as_str())
        .map(str::to_owned);

    let request = create_room_request(&options)?;
    let room = get_client()
        .await?
        .create_room(request)
        .await
        .map_err(|error| format!("Не удалось создать комнату через Matrix SDK: {error}"))?;
    let room_id_text = room.room_id().to_string();
    let room_name = requested_name
        .or_else(|| room.name())
        .or_else(|| requested_alias.map(|value| format!("#{value}")))
        .unwrap_or_else(|| room_id_text.clone());

    Ok((room_id_text, room_name, is_space))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn create_room_options_become_a_typed_sdk_request() {
        let options = serde_json::json!({
            "name": "Project",
            "visibility": "private",
            "preset": "private_chat",
            "is_direct": true,
            "invite": ["@friend:example.org"],
            "creation_content": { "m.federate": true },
            "initial_state": [{
                "type": "m.room.encryption",
                "state_key": "",
                "content": { "algorithm": "m.megolm.v1.aes-sha2" }
            }],
            "power_level_content_override": { "users_default": 0 }
        });

        validate_create_room_options(&options).expect("options should be valid");
        let request = create_room_request(&options).expect("SDK request should be typed");

        assert_eq!(request.name.as_deref(), Some("Project"));
        assert!(request.is_direct);
        assert_eq!(request.invite.len(), 1);
        assert_eq!(request.initial_state.len(), 1);
        assert!(request.creation_content.is_some());
        assert!(request.power_level_content_override.is_some());
    }
}
