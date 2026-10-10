use super::format_room_state;
use crate::matrix::session::get_client;
use crate::protocol::commands::PublicRoomDirectoryEntry;
use futures_util::future::join_all;
use matrix_sdk::ruma::api::client::directory::get_public_rooms_filtered::v3::Request as PublicRoomsRequest;
use matrix_sdk::ruma::directory::Filter;
use matrix_sdk::ruma::directory::RoomTypeFilter;
use matrix_sdk::ruma::OwnedServerName;
use matrix_sdk::ruma::RoomAliasId;
use matrix_sdk::ruma::RoomOrAliasId;
use matrix_sdk::ruma::UInt;
use std::collections::HashSet;
use std::time::Duration;
use tokio::time::timeout;

// Matrix has no global room directory. These are queried in parallel for the
// Spaces picker, matching the multi-directory approach used by other clients.
// Keep the list deliberately small: every entry is another federated request
// made by the user's homeserver.
const SPACE_DIRECTORY_SERVERS: &[&str] = &[
    "matrix.org",
    "kde.org",
    "mozilla.org",
    "gnome.org",
    "tchncs.de",
];
const SPACE_DIRECTORY_TIMEOUT: Duration = Duration::from_secs(8);

pub async fn search_public_rooms(
    query: &str,
    limit: u32,
    spaces_only: bool,
) -> Result<(Vec<PublicRoomDirectoryEntry>, Option<String>), String> {
    let Some(filter) = public_directory_filter(query, spaces_only) else {
        return Ok((Vec::new(), None));
    };

    let client = get_client().await?;
    if spaces_only {
        if let Ok(alias) = <&RoomAliasId>::try_from(query.trim()) {
            return resolve_exact_space_alias(&client, alias).await;
        }
    }
    let directories = public_directory_servers(
        query,
        spaces_only,
        client.user_id().map(|id| id.server_name()),
    );
    let request_limit = UInt::new(u64::from(limit.clamp(1, 50)));
    let requests = directories.into_iter().map(|server| {
        let client = client.clone();
        let filter = filter.clone();
        let directory_name = server
            .as_ref()
            .map(ToString::to_string)
            .unwrap_or_else(|| "local".to_owned());
        async move {
            let mut request = PublicRoomsRequest::new();
            request.limit = request_limit;
            request.filter = filter;
            request.server = server;
            let result = timeout(
                SPACE_DIRECTORY_TIMEOUT,
                client.public_rooms_filtered(request),
            )
            .await
            .map_err(|_| format!("каталог {directory_name} не ответил вовремя"))
            .and_then(|response| {
                response.map_err(|error| format!("каталог {directory_name}: {error}"))
            });
            (directory_name, result)
        }
    });

    let responses = join_all(requests).await;
    let mut rooms = Vec::new();
    let mut seen_room_ids = HashSet::new();
    let mut errors = Vec::new();
    let mut next_batch = None;

    for (directory_name, response) in responses {
        let response = match response {
            Ok(response) => response,
            Err(error) => {
                errors.push(error);
                continue;
            }
        };
        // A single-directory room search can still use the server cursor.
        if !spaces_only && directory_name == "local" {
            next_batch = response.next_batch;
        }

        for room in response.chunk.into_iter().filter(|room| {
            // `room_types` is part of Matrix Client-Server API v1.4+. Keep
            // this check in case a non-conforming homeserver ignores it.
            !spaces_only
                || room
                    .room_type
                    .as_ref()
                    .is_some_and(|room_type| room_type.as_str() == "m.space")
        }) {
            if !seen_room_ids.insert(room.room_id.clone()) {
                continue;
            }
            let known_state = client
                .get_room(&room.room_id)
                .map(|known_room| format!("{:?}", known_room.state()).to_lowercase());
            let joined = known_state.as_deref() == Some("joined");
            let invited = known_state.as_deref() == Some("invited");
            let knocked = known_state.as_deref() == Some("knocked");
            let is_space = room
                .room_type
                .as_ref()
                .is_some_and(|room_type| room_type.as_str() == "m.space");
            rooms.push(PublicRoomDirectoryEntry {
                room_id: room.room_id.to_string(),
                name: room.name,
                canonical_alias: room.canonical_alias.map(|alias| alias.to_string()),
                topic: room.topic,
                avatar_url: room.avatar_url.map(|url| url.to_string()),
                member_count: room.num_joined_members.into(),
                join_rule: format!("{:?}", room.join_rule).to_lowercase(),
                joined,
                invited,
                knocked,
                is_space,
            });
        }
    }

    if rooms.is_empty() && !errors.is_empty() {
        return Err(format!(
            "Не удалось выполнить поиск по каталогам: {}",
            errors.join("; ")
        ));
    }

    sort_public_directory_results(&mut rooms, query);
    rooms.truncate(limit.clamp(1, 50) as usize);

    Ok((rooms, next_batch))
}

fn public_directory_filter(query: &str, spaces_only: bool) -> Option<Filter> {
    let query = query.trim();
    let search_term = query
        .trim_start_matches(|character| matches!(character, '#' | '!'))
        .trim();
    if search_term.is_empty() {
        return None;
    }

    let mut filter = Filter::new();
    filter.generic_search_term = Some(search_term.to_owned());
    if spaces_only {
        filter.room_types.push(RoomTypeFilter::Space);
    }
    Some(filter)
}

fn public_directory_server(query: &str) -> Option<OwnedServerName> {
    <&RoomOrAliasId>::try_from(query.trim())
        .ok()
        .and_then(|room_or_alias| room_or_alias.server_name().map(ToOwned::to_owned))
}

async fn resolve_exact_space_alias(
    client: &matrix_sdk::Client,
    alias: &RoomAliasId,
) -> Result<(Vec<PublicRoomDirectoryEntry>, Option<String>), String> {
    let resolved = client
        .resolve_room_alias(alias)
        .await
        .map_err(|error| format!("Пространство с адресом {alias} не найдено: {error}"))?;
    let room_id = resolved.room_id;
    let room_id_text = room_id.to_string();
    let room_or_alias = <&RoomOrAliasId>::try_from(room_id_text.as_str())
        .map_err(|error| format!("Некорректный room ID для {alias}: {error}"))?;
    let preview = client
        .get_room_preview(room_or_alias, resolved.servers)
        .await
        .ok();

    // If the server could provide the room type, do not present a normal room
    // as a Space. Alias resolution itself is still enough for a direct join
    // when the optional preview endpoints are unavailable.
    if preview.as_ref().is_some_and(|preview| {
        preview
            .room_type
            .as_ref()
            .is_some_and(|room_type| room_type.as_str() != "m.space")
    }) {
        return Ok((Vec::new(), None));
    }

    let known_state = client
        .get_room(&room_id)
        .map(|known_room| format_room_state(known_room.state()))
        .or_else(|| {
            preview
                .as_ref()
                .and_then(|preview| preview.state.map(format_room_state))
        });
    let joined = known_state.as_deref() == Some("joined");
    let invited = known_state.as_deref() == Some("invited");
    let knocked = known_state.as_deref() == Some("knocked");
    let join_rule = preview
        .as_ref()
        .and_then(|preview| preview.join_rule.as_ref())
        .map(|join_rule| format!("{join_rule:?}").to_lowercase())
        // A resolved alias is a valid direct join target even when the
        // homeserver does not implement the optional room-summary endpoint.
        .unwrap_or_else(|| "public".to_owned());

    Ok((
        vec![PublicRoomDirectoryEntry {
            room_id: room_id_text,
            name: preview
                .as_ref()
                .and_then(|preview| preview.name.clone())
                .or_else(|| {
                    Some(
                        alias
                            .as_str()
                            .trim_start_matches('#')
                            .split(':')
                            .next()
                            .unwrap_or(alias.as_str())
                            .to_owned(),
                    )
                }),
            canonical_alias: preview
                .as_ref()
                .and_then(|preview| preview.canonical_alias.as_ref().map(ToString::to_string))
                .or_else(|| Some(alias.to_string())),
            topic: preview.as_ref().and_then(|preview| preview.topic.clone()),
            avatar_url: preview
                .as_ref()
                .and_then(|preview| preview.avatar_url.as_ref().map(ToString::to_string)),
            member_count: preview
                .as_ref()
                .map(|preview| preview.num_joined_members)
                .unwrap_or(0),
            join_rule,
            joined,
            invited,
            knocked,
            is_space: true,
        }],
        None,
    ))
}

fn public_directory_servers(
    query: &str,
    spaces_only: bool,
    current_server: Option<&matrix_sdk::ruma::ServerName>,
) -> Vec<Option<OwnedServerName>> {
    if let Some(server) = public_directory_server(query) {
        return vec![Some(server)];
    }
    if !spaces_only {
        return vec![None];
    }

    let mut directories = vec![None];
    let mut seen = HashSet::new();
    if let Some(server) = current_server {
        seen.insert(server.as_str().to_owned());
    }
    for server in SPACE_DIRECTORY_SERVERS {
        if !seen.insert((*server).to_owned()) {
            continue;
        }
        if let Ok(server) = OwnedServerName::try_from((*server).to_owned()) {
            directories.push(Some(server));
        }
    }
    directories
}

fn sort_public_directory_results(rooms: &mut [PublicRoomDirectoryEntry], query: &str) {
    let query = query
        .trim()
        .trim_start_matches(|character| matches!(character, '#' | '!'))
        .to_lowercase();
    rooms.sort_by(|left, right| {
        let score = |room: &PublicRoomDirectoryEntry| {
            let name = room.name.as_deref().unwrap_or_default().to_lowercase();
            let alias = room
                .canonical_alias
                .as_deref()
                .unwrap_or_default()
                .trim_start_matches('#')
                .to_lowercase();
            if name == query || alias == query {
                3
            } else if name.starts_with(&query) || alias.starts_with(&query) {
                2
            } else if name.contains(&query) || alias.contains(&query) {
                1
            } else {
                0
            }
        };
        score(right)
            .cmp(&score(left))
            .then_with(|| right.member_count.cmp(&left.member_count))
            .then_with(|| left.room_id.cmp(&right.room_id))
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn space_directory_search_uses_the_matrix_room_type_filter() {
        let filter = public_directory_filter("  #matrix:example.org  ", true)
            .expect("a meaningful query should produce a filter");

        assert_eq!(
            filter.generic_search_term.as_deref(),
            Some("matrix:example.org")
        );
        assert_eq!(filter.room_types, vec![RoomTypeFilter::Space]);
        assert_eq!(
            public_directory_server("#matrix:example.org")
                .as_deref()
                .map(|server| server.as_str()),
            Some("example.org")
        );
    }

    #[test]
    fn ordinary_directory_search_keeps_all_room_types() {
        let filter = public_directory_filter("community", false)
            .expect("a meaningful query should produce a filter");

        assert_eq!(filter.generic_search_term.as_deref(), Some("community"));
        assert!(filter.room_types.is_empty());
        assert!(public_directory_filter("#!", true).is_none());
    }

    #[test]
    fn space_search_uses_multiple_directories_but_exact_alias_uses_its_server() {
        let directories = public_directory_servers("kde", true, None);
        assert!(directories.iter().any(Option::is_none));
        assert!(directories.iter().any(|server| {
            server
                .as_deref()
                .is_some_and(|server| server.as_str() == "kde.org")
        }));

        let exact = public_directory_servers("#kde:kde.org", true, None);
        assert_eq!(exact.len(), 1);
        assert_eq!(
            exact[0].as_deref().map(|server| server.as_str()),
            Some("kde.org")
        );
    }

    #[test]
    fn public_directory_results_are_ranked_by_match_then_popularity() {
        let mut rooms = vec![
            PublicRoomDirectoryEntry {
                room_id: "!contains:example.org".to_owned(),
                name: Some("Community for KDE".to_owned()),
                canonical_alias: None,
                topic: None,
                avatar_url: None,
                member_count: 900,
                join_rule: "public".to_owned(),
                joined: false,
                invited: false,
                knocked: false,
                is_space: true,
            },
            PublicRoomDirectoryEntry {
                room_id: "!exact:kde.org".to_owned(),
                name: Some("KDE".to_owned()),
                canonical_alias: Some("#kde:kde.org".to_owned()),
                topic: None,
                avatar_url: None,
                member_count: 10,
                join_rule: "public".to_owned(),
                joined: false,
                invited: false,
                knocked: false,
                is_space: true,
            },
        ];

        sort_public_directory_results(&mut rooms, "kde");
        assert_eq!(rooms[0].room_id, "!exact:kde.org");
    }
}
