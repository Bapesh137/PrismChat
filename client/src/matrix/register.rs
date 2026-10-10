use matrix_sdk::{
    authentication::matrix::MatrixSession,
    ruma::api::client::{
        account::register::{v3 as register_api, RegistrationKind},
        uiaa::{AuthData, Dummy},
    },
    Client, SessionMeta, SessionTokens,
};

use crate::matrix::{auth::normalize_url, session::activate_persistent_client_from_session};

pub async fn register(
    server: &str,
    username: &str,
    password: &str,
    profile_id: Option<String>,
) -> Result<(String, Option<String>, String), String> {
    let base = normalize_url(server)?;

    let client = Client::builder()
        .homeserver_url(&base)
        .build()
        .await
        .map_err(|e| format!("Не удалось создать Matrix SDK client: {}", e))?;

    println!("[Register] Запрос регистрации через Matrix SDK");

    let mut request = register_api::Request::new();
    request.username = Some(username.to_string());
    request.password = Some(password.to_string());
    request.kind = RegistrationKind::User;
    request.initial_device_display_name = Some("PrismChat".to_string());

    let response = match client.matrix_auth().register(request).await {
        Ok(resp) => resp,
        Err(err) => {
            if let Some(uiaa) = err.as_uiaa_response() {
                let mut request = register_api::Request::new();
                request.username = Some(username.to_string());
                request.password = Some(password.to_string());
                request.kind = RegistrationKind::User;
                request.initial_device_display_name = Some("PrismChat".to_string());

                let mut dummy = Dummy::new();
                dummy.session = uiaa.session.clone();
                request.auth = Some(AuthData::Dummy(dummy));

                client
                    .matrix_auth()
                    .register(request)
                    .await
                    .map_err(|e| format!("Ошибка регистрации: {}", e))?
            } else {
                return Err(format!("Ошибка регистрации: {}", err));
            }
        }
    };

    let access_token = response.access_token.clone().ok_or_else(|| {
        "Сервер зарегистрировал пользователя, но не вернул access_token".to_string()
    })?;

    let device_id = response
        .device_id
        .clone()
        .ok_or_else(|| "Сервер зарегистрировал пользователя, но не вернул device_id".to_string())?;

    let matrix_session = MatrixSession {
        meta: SessionMeta {
            user_id: response.user_id.clone(),
            device_id,
        },
        tokens: SessionTokens {
            access_token: access_token.clone(),
            refresh_token: response.refresh_token.clone(),
        },
    };

    let activated =
        activate_persistent_client_from_session(&base, matrix_session, profile_id.as_deref(), None)
            .await?;

    println!("[Register] Регистрация завершена");
    Ok((
        access_token,
        activated.avatar_url.clone(),
        activated.profile_id,
    ))
}
