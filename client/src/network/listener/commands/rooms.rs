//! Rooms command handlers.
use crate::network::transport::Tx;
use crate::protocol::commands::{QmlCommand, QmlResponse};
use tokio_tungstenite::tungstenite::Message;

pub(super) async fn handle(command: QmlCommand, tx: Tx) {
    match command {
        QmlCommand::GetRoomList { request_id } => {
            println!("[Listener] Запрос комнат");

            let response = match crate::matrix::rooms::get_room_list().await {
                Ok(rooms) => {
                    println!("[Listener] Комнат: {}", rooms.len());
                    QmlResponse::RoomsResult {
                        request_id,
                        success: true,
                        rooms,
                        error: None,
                    }
                }
                Err(error) => QmlResponse::RoomsResult {
                    request_id,
                    success: false,
                    rooms: vec![],
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

        QmlCommand::GetRoomDetails {
            request_id,
            room_id,
        } => {
            println!("[Listener] Запрос деталей комнаты");

            let response = match crate::matrix::rooms::get_room_details(&room_id).await {
                Ok(details) => QmlResponse::RoomDetailsResult {
                    request_id,
                    success: true,
                    details: Some(details),
                    error: None,
                },
                Err(e) => QmlResponse::RoomDetailsResult {
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

        QmlCommand::GetSpaceHierarchy {
            request_id,
            space_id,
            from,
            limit,
        } => {
            let response = match crate::matrix::relations::space_hierarchy_page(
                &space_id,
                from.filter(|cursor| !cursor.is_empty()),
                limit,
            )
            .await
            {
                Ok((rooms, next_batch)) => QmlResponse::SpaceHierarchyResult {
                    request_id,
                    space_id,
                    success: true,
                    rooms,
                    next_batch,
                    error: None,
                },
                Err(error) => QmlResponse::SpaceHierarchyResult {
                    request_id,
                    space_id,
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

        QmlCommand::JoinSpaceRoom {
            request_id,
            room_id,
            knock,
            via,
        } => {
            let response =
                match crate::matrix::relations::join_space_room(&room_id, knock, &via).await {
                    Ok(()) => QmlResponse::JoinSpaceRoomResult {
                        request_id,
                        success: true,
                        room_id,
                        knocked: knock,
                        error: None,
                    },
                    Err(error) => QmlResponse::JoinSpaceRoomResult {
                        request_id,
                        success: false,
                        room_id,
                        knocked: knock,
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

        QmlCommand::AddRoomToSpace {
            request_id,
            room_id,
            space_id,
        } => {
            let response = match crate::matrix::rooms::add_room_to_space(&room_id, &space_id).await
            {
                Ok(()) => QmlResponse::AddRoomToSpaceResult {
                    request_id,
                    success: true,
                    room_id,
                    space_id,
                    error: None,
                },
                Err(error) => QmlResponse::AddRoomToSpaceResult {
                    request_id,
                    success: false,
                    room_id,
                    space_id,
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

        QmlCommand::RemoveRoomFromSpace {
            request_id,
            room_id,
            space_id,
        } => {
            let response =
                match crate::matrix::rooms::remove_room_from_space(&room_id, &space_id).await {
                    Ok(()) => QmlResponse::RemoveRoomFromSpaceResult {
                        request_id,
                        success: true,
                        room_id,
                        space_id,
                        error: None,
                    },
                    Err(error) => QmlResponse::RemoveRoomFromSpaceResult {
                        request_id,
                        success: false,
                        room_id,
                        space_id,
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

        QmlCommand::UpdateRoom {
            request_id,
            room_id,
            changes,
        } => {
            let response = match crate::matrix::rooms::update_room(&room_id, changes).await {
                Ok(()) => QmlResponse::UpdateRoomResult {
                    request_id,
                    success: true,
                    room_id,
                    error: None,
                },
                Err(error) => QmlResponse::UpdateRoomResult {
                    request_id,
                    success: false,
                    room_id,
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

        QmlCommand::ModerateRoomMember {
            request_id,
            room_id,
            user_id,
            action,
            power_level,
            reason,
        } => {
            let response = match crate::matrix::rooms::moderate_room_member(
                &room_id,
                &user_id,
                &action,
                power_level,
                reason.as_deref(),
            )
            .await
            {
                Ok(()) => QmlResponse::RoomMemberModerationResult {
                    request_id,
                    success: true,
                    room_id,
                    user_id,
                    action,
                    error: None,
                },
                Err(error) => QmlResponse::RoomMemberModerationResult {
                    request_id,
                    success: false,
                    room_id,
                    user_id,
                    action,
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

        QmlCommand::LeaveRoom {
            request_id,
            room_id,
        } => {
            let response = match crate::matrix::rooms::leave_room(&room_id).await {
                Ok(()) => QmlResponse::LeaveRoomResult {
                    request_id,
                    success: true,
                    room_id,
                    error: None,
                },
                Err(error) => QmlResponse::LeaveRoomResult {
                    request_id,
                    success: false,
                    room_id,
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

        QmlCommand::AcceptRoomInvite {
            request_id,
            room_id,
        } => {
            let response = match crate::matrix::rooms::accept_room_invite(&room_id).await {
                Ok(()) => QmlResponse::RoomInviteResult {
                    request_id,
                    success: true,
                    room_id,
                    error: None,
                },
                Err(error) => QmlResponse::RoomInviteResult {
                    request_id,
                    success: false,
                    room_id,
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

        QmlCommand::GetRoomMembers {
            request_id,
            room_id,
            from,
            limit,
        } => {
            let response =
                match crate::matrix::rooms::get_room_members_page(&room_id, from, limit).await {
                    Ok((members, next_batch)) => QmlResponse::RoomMembersResult {
                        request_id,
                        room_id,
                        success: true,
                        members,
                        next_batch,
                        error: None,
                    },
                    Err(error) => QmlResponse::RoomMembersResult {
                        request_id,
                        room_id,
                        success: false,
                        members: vec![],
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

        QmlCommand::OpenDirectMessage {
            request_id,
            user_id,
        } => {
            let response = match crate::matrix::rooms::open_direct_message(&user_id).await {
                Ok((room_id, room_name, avatar_url, created)) => {
                    QmlResponse::OpenDirectMessageResult {
                        request_id,
                        success: true,
                        room_id: Some(room_id),
                        room_name: Some(room_name),
                        avatar_url,
                        target_user_id: Some(user_id),
                        created,
                        error: None,
                    }
                }
                Err(error) => QmlResponse::OpenDirectMessageResult {
                    request_id,
                    success: false,
                    room_id: None,
                    room_name: None,
                    avatar_url: None,
                    target_user_id: Some(user_id),
                    created: false,
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

        QmlCommand::CreateRoom {
            request_id,
            options,
        } => {
            let response = match crate::matrix::rooms::create_room(options).await {
                Ok((room_id, room_name, is_space)) => QmlResponse::CreateRoomResult {
                    request_id,
                    success: true,
                    room_id: Some(room_id),
                    room_name: Some(room_name),
                    is_space,
                    error: None,
                },
                Err(error) => QmlResponse::CreateRoomResult {
                    request_id,
                    success: false,
                    room_id: None,
                    room_name: None,
                    is_space: false,
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
        _ => unreachable!("command routed to the wrong domain"),
    }
}
