use crate::matrix::session::{get_client, update_current_profile_avatar};

pub async fn set_avatar(path: &str, mime_type: &str) -> Result<String, String> {
    let client = get_client().await?;

    let bytes = crate::matrix::media::read_avatar_file(path).await?;

    let mime = mime_type
        .parse()
        .map_err(|e| format!("Некорректный MIME type: {}", e))?;

    let mxc = client
        .account()
        .upload_avatar(&mime, bytes)
        .await
        .map_err(|e| format!("Ошибка загрузки аватара: {}", e))?;

    update_current_profile_avatar(Some(mxc.to_string())).await?;

    if let Ok(current_user_id) = {
        let session = crate::matrix::session::SESSION.lock().await;
        Ok::<_, String>(session.user_id.clone())
    } {
        if let Some(current_user_id) = current_user_id {
            crate::storage::profile_cache::invalidate_user_details(&current_user_id).await;
        }
    }
    Ok(mxc.to_string())
}
