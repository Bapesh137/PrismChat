use crate::{
    matrix::{rtc, session::current_session_epoch},
    network::transport::Tx,
    protocol::commands::{QmlCommand, QmlResponse},
};

pub(super) async fn handle(command: QmlCommand, tx: Tx) {
    match command {
        QmlCommand::VoiceBegin {
            request_id,
            room_id,
            call_id,
            session_epoch,
            intent,
            element_call_url,
        } => {
            let result = rtc::begin(
                &room_id,
                &call_id,
                session_epoch,
                &intent,
                &element_call_url,
                tx.clone(),
            )
            .await;
            rtc::push(
                &tx,
                QmlResponse::VoiceResult {
                    request_id,
                    call_id,
                    session_epoch: current_session_epoch(),
                    operation: "begin".into(),
                    success: result.is_ok(),
                    data: result.as_ref().ok().cloned(),
                    error: result.err(),
                },
            )
            .await;
        }
        QmlCommand::VoiceWidget {
            call_id,
            session_epoch,
            message,
        } => {
            if let Err(error) = rtc::widget_message(&call_id, session_epoch, message, &tx).await {
                rtc::push(
                    &tx,
                    QmlResponse::VoiceResult {
                        request_id: String::new(),
                        call_id,
                        session_epoch: current_session_epoch(),
                        operation: "widget".into(),
                        success: false,
                        data: None,
                        error: Some(error),
                    },
                )
                .await;
            }
        }
        QmlCommand::VoiceEnd {
            request_id,
            call_id,
        } => {
            rtc::end(Some(&call_id), Some(&tx)).await;
            rtc::push(
                &tx,
                QmlResponse::VoiceResult {
                    request_id,
                    call_id,
                    session_epoch: current_session_epoch(),
                    operation: "end".into(),
                    success: true,
                    data: None,
                    error: None,
                },
            )
            .await;
        }
        QmlCommand::VoiceDecline {
            request_id,
            room_id,
            notification_event_id,
        } => {
            let result = rtc::decline(&room_id, &notification_event_id).await;
            rtc::push(
                &tx,
                QmlResponse::VoiceResult {
                    request_id,
                    call_id: String::new(),
                    session_epoch: current_session_epoch(),
                    operation: "decline".into(),
                    success: result.is_ok(),
                    data: None,
                    error: result.err(),
                },
            )
            .await;
        }
        _ => unreachable!("RTC dispatcher"),
    }
}
