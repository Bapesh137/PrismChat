//! Devices command handlers.
use crate::network::transport::Tx;
use crate::protocol::commands::{QmlCommand, QmlResponse};
use tokio_tungstenite::tungstenite::Message;

pub(super) async fn handle(command: QmlCommand, tx: Tx) {
    match command {
        QmlCommand::GetMatrixDevices { request_id } => {
            let response = match crate::matrix::devices::snapshot().await {
                Ok(devices) => QmlResponse::MatrixDevicesResult {
                    request_id,
                    success: true,
                    devices,
                    error: None,
                },
                Err(error) => QmlResponse::MatrixDevicesResult {
                    request_id,
                    success: false,
                    devices: vec![],
                    error: Some(error),
                },
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
        }

        QmlCommand::DeleteMatrixDevices {
            request_id,
            device_ids,
        } => {
            let response = match crate::matrix::devices::begin_delete(device_ids.clone()).await {
                Ok(crate::matrix::devices::DeleteDevicesOutcome::Complete) => {
                    QmlResponse::DeviceOperationResult {
                        request_id,
                        operation: "delete".to_owned(),
                        success: true,
                        device_ids,
                        error: None,
                    }
                }
                Ok(crate::matrix::devices::DeleteDevicesOutcome::WebRequired { url }) => {
                    QmlResponse::DeviceDeleteWebRequired {
                        request_id,
                        device_ids,
                        url,
                    }
                }
                Ok(crate::matrix::devices::DeleteDevicesOutcome::AuthRequired {
                    operation_id,
                    session,
                    flows,
                    password_supported,
                }) => QmlResponse::DeviceDeleteUiaaRequired {
                    request_id,
                    operation_id,
                    session,
                    flows,
                    password_supported,
                },
                Err(error) => QmlResponse::DeviceOperationResult {
                    request_id,
                    operation: "delete".to_owned(),
                    success: false,
                    device_ids,
                    error: Some(error),
                },
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
        }

        QmlCommand::SubmitDeviceDeleteUiaa {
            request_id,
            operation_id,
            auth_type,
            password,
        } => {
            let response = if auth_type != "m.login.password" {
                QmlResponse::DeviceOperationResult {
                    request_id,
                    operation: "delete".to_owned(),
                    success: false,
                    device_ids: vec![],
                    error: Some(
                        "Этот способ подтверждения пока не поддерживается PrismChat".to_owned(),
                    ),
                }
            } else {
                let pending_ids = crate::matrix::devices::pending_delete_ids(&operation_id).await;
                match crate::matrix::devices::submit_delete_password(
                    &operation_id,
                    password.unwrap_or_default(),
                )
                .await
                {
                    Ok(device_ids) => QmlResponse::DeviceOperationResult {
                        request_id,
                        operation: "delete".to_owned(),
                        success: true,
                        device_ids,
                        error: None,
                    },
                    Err(error) => QmlResponse::DeviceOperationResult {
                        request_id,
                        operation: "delete".to_owned(),
                        success: false,
                        device_ids: pending_ids,
                        error: Some(error),
                    },
                }
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
        }

        QmlCommand::RenameMatrixDevice {
            request_id,
            device_id,
            display_name,
        } => {
            let response = match crate::matrix::devices::rename(&device_id, &display_name).await {
                Ok(()) => QmlResponse::DeviceOperationResult {
                    request_id,
                    operation: "rename".to_owned(),
                    success: true,
                    device_ids: vec![device_id.clone()],
                    error: None,
                },
                Err(error) => QmlResponse::DeviceOperationResult {
                    request_id,
                    operation: "rename".to_owned(),
                    success: false,
                    device_ids: vec![device_id],
                    error: Some(error),
                },
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
        }

        QmlCommand::StartVerification {
            request_id,
            device_id,
        } => {
            let result = if let Some(device_id) = device_id.as_deref() {
                crate::matrix::verification::start_device(device_id).await
            } else {
                crate::matrix::verification::start_current_device().await
            };
            let response = match result {
                Ok(flow_id) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: true,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: Some(flow_id),
                    error: None,
                },
                Err(error) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: false,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: None,
                    error: Some(error),
                },
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
        }

        QmlCommand::VerificationAction {
            request_id,
            flow_id,
            action,
        } => {
            let response = match crate::matrix::verification::action(&flow_id, &action).await {
                Ok(()) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: true,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: Some(flow_id),
                    error: None,
                },
                Err(error) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: false,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: Some(flow_id),
                    error: Some(error),
                },
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
        }
        _ => unreachable!("command routed to the wrong domain"),
    }
}
