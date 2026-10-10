//! Directory command handlers.
use crate::network::transport::Tx;
use crate::protocol::commands::{QmlCommand, QmlResponse};
use tokio_tungstenite::tungstenite::Message;

pub(super) async fn handle(command: QmlCommand, tx: Tx) {
    match command {
        QmlCommand::SearchRoomMessages {
            request_id,
            room_id,
            query,
            limit,
            next_batch,
        } => {
            let response = match crate::matrix::messages::search_room_messages(
                &room_id,
                &query,
                limit.unwrap_or(50),
                next_batch,
            )
            .await
            {
                Ok((messages, next_batch)) => QmlResponse::SearchRoomMessagesResult {
                    request_id,
                    room_id,
                    success: true,
                    messages,
                    next_batch,
                    error: None,
                },
                Err(error) => QmlResponse::SearchRoomMessagesResult {
                    request_id,
                    room_id,
                    success: false,
                    messages: vec![],
                    next_batch: None,
                    error: Some(error),
                },
            };
            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::SearchUsers {
            request_id,
            query,
            limit,
        } => {
            let response = match crate::matrix::users::search_user_directory(
                &query,
                limit.unwrap_or(40),
            )
            .await
            {
                Ok((users, limited)) => QmlResponse::UserSearchResult {
                    request_id,
                    success: true,
                    users,
                    limited,
                    error: None,
                },
                Err(error) => QmlResponse::UserSearchResult {
                    request_id,
                    success: false,
                    users: vec![],
                    limited: false,
                    error: Some(error),
                },
            };
            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::SearchPublicRooms {
            request_id,
            query,
            limit,
            spaces_only,
        } => {
            let response = match crate::matrix::rooms::search_public_rooms(
                &query,
                limit.unwrap_or(40),
                spaces_only,
            )
            .await
            {
                Ok((rooms, next_batch)) => QmlResponse::PublicRoomsSearchResult {
                    request_id,
                    success: true,
                    rooms,
                    next_batch,
                    error: None,
                },
                Err(error) => QmlResponse::PublicRoomsSearchResult {
                    request_id,
                    success: false,
                    rooms: vec![],
                    next_batch: None,
                    error: Some(error),
                },
            };
            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::GetUserDetails {
            request_id,
            user_id,
            room_id,
        } => {
            let response = match crate::matrix::users::get_user_details(&user_id, room_id).await {
                Ok(details) => QmlResponse::UserDetailsResult {
                    request_id,
                    success: true,
                    details: Some(details),
                    error: None,
                },
                Err(e) => QmlResponse::UserDetailsResult {
                    request_id,
                    success: false,
                    details: None,
                    error: Some(e),
                },
            };

            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::SetUserIgnored {
            request_id,
            user_id,
            ignored,
        } => {
            let result = crate::matrix::users::set_user_ignored(&user_id, ignored).await;
            let response = QmlResponse::UserIgnoredResult {
                request_id,
                success: result.is_ok(),
                user_id,
                ignored,
                error: result.err(),
            };

            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::UpdateOwnProfile {
            request_id,
            display_name,
            clear_display_name,
        } => {
            println!("[Listener] Обновление собственного профиля");

            let response =
                match crate::matrix::users::update_own_profile(display_name, clear_display_name)
                    .await
                {
                    Ok(details) => QmlResponse::UpdateOwnProfileResult {
                        request_id,
                        success: true,
                        details: Some(details),
                        error: None,
                    },
                    Err(e) => QmlResponse::UpdateOwnProfileResult {
                        request_id,
                        success: false,
                        details: None,
                        error: Some(e),
                    },
                };

            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }
        _ => unreachable!("command routed to the wrong domain"),
    }
}
