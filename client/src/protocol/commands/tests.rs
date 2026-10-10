#[cfg(test)]
mod timeline_protocol_tests {
    use super::super::QmlCommand;

    #[test]
    fn parses_personal_call_commands() {
        let begin: QmlCommand = serde_json::from_str(
            r#"{"type":"voice_begin","request_id":"r1","room_id":"!dm:example.org","call_id":"c1","session_epoch":7,"intent":"start_call_dm_voice","element_call_url":"http://127.0.0.1:49152/index.html"}"#,
        ).expect("voice_begin command must deserialize");
        assert!(matches!(begin, QmlCommand::VoiceBegin { intent, .. }
            if intent == "start_call_dm_voice"));

        let decline: QmlCommand = serde_json::from_str(
            r#"{"type":"voice_decline","request_id":"r2","room_id":"!dm:example.org","notification_event_id":"$call:example.org"}"#,
        ).expect("voice_decline command must deserialize");
        assert!(
            matches!(decline, QmlCommand::VoiceDecline { notification_event_id, .. }
            if notification_event_id == "$call:example.org")
        );
    }

    #[test]
    fn read_receipt_can_target_a_visible_event_or_the_entire_room() {
        for (field, expected) in [("", None), (",\"event_id\":\"$visible\"", Some("$visible"))] {
            let json = format!(
                r#"{{"type":"mark_room_read","request_id":"r1","room_id":"!room:example.org"{field}}}"#
            );
            let command: QmlCommand = serde_json::from_str(&json).unwrap();
            assert!(matches!(command, QmlCommand::MarkRoomRead { event_id, .. }
                if event_id.as_deref() == expected));
        }
    }

    #[test]
    fn read_receipt_privacy_is_optional_and_preserved() {
        for (privacy, expected) in [
            ("", None),
            (",\"public_receipt\":false", Some(false)),
            (",\"public_receipt\":true", Some(true)),
        ] {
            let json = format!(
                r#"{{"type":"mark_room_read","request_id":"read-1","room_id":"!room:example.org"{privacy}}}"#
            );
            let command: QmlCommand = serde_json::from_str(&json).unwrap();
            assert!(matches!(
                command,
                QmlCommand::MarkRoomRead { public_receipt, .. } if public_receipt == expected
            ));
        }
    }

    #[test]
    fn typing_generation_is_backwards_compatible_and_preserved() {
        for (field, expected) in [("", 0), (",\"generation\":42", 42)] {
            let json = format!(
                r#"{{"type":"set_typing","request_id":"typing-1","room_id":"!room:example.org","typing":true{field}}}"#
            );
            let command: QmlCommand = serde_json::from_str(&json).unwrap();
            assert!(matches!(
                command,
                QmlCommand::SetTyping {
                    typing: true,
                    generation,
                    ..
                } if generation == expected
            ));
        }
    }

    #[test]
    fn parses_open_timeline_command() {
        let command: QmlCommand = serde_json::from_str(
            r#"{"type":"open_timeline","request_id":"r1","room_id":"!room:example.org"}"#,
        )
        .expect("open_timeline command must deserialize");
        assert!(matches!(command, QmlCommand::OpenTimeline { .. }));
    }

    #[test]
    fn open_timeline_generation_is_backwards_compatible() {
        let command: QmlCommand = serde_json::from_str(
            r#"{"type":"open_timeline","request_id":"r1","room_id":"!room:example.org"}"#,
        )
        .expect("legacy open_timeline command must deserialize");
        assert!(matches!(
            command,
            QmlCommand::OpenTimeline {
                request_generation: 0,
                ..
            }
        ));
    }

    #[test]
    fn parses_timeline_preview_command() {
        let command: QmlCommand = serde_json::from_str(
            r#"{"type":"get_timeline_preview","request_id":"preview-1","room_id":"!room:example.org","limit":30}"#,
        )
        .expect("get_timeline_preview command must deserialize");
        assert!(matches!(
            command,
            QmlCommand::GetTimelinePreview {
                limit: Some(30),
                ..
            }
        ));
    }

    #[test]
    fn parses_room_key_transfer_commands() {
        let export: QmlCommand = serde_json::from_str(
            r#"{"type":"export_room_keys","request_id":"keys-1","path":"C:/keys.txt","passphrase":"correct horse"}"#,
        )
        .expect("export_room_keys command must deserialize");
        assert!(matches!(
            export,
            QmlCommand::ExportRoomKeys { path, passphrase, .. }
                if path == "C:/keys.txt" && passphrase == "correct horse"
        ));

        let import: QmlCommand = serde_json::from_str(
            r#"{"type":"import_room_keys","request_id":"keys-2","path":"C:/keys.txt","passphrase":"correct horse"}"#,
        )
        .expect("import_room_keys command must deserialize");
        assert!(matches!(import, QmlCommand::ImportRoomKeys { .. }));
    }

    #[test]
    fn parses_storage_commands() {
        let preferences: QmlCommand = serde_json::from_str(
            r#"{"type":"set_storage_preferences","request_id":"storage-1","auto_cleanup_days":30,"cache_limit_mb":2048,"downloads_dir":"D:/Downloads","auto_load_images":true,"auto_load_videos":false}"#,
        )
        .expect("storage preferences command must deserialize");
        assert!(matches!(
            preferences,
            QmlCommand::SetStoragePreferences {
                auto_cleanup_days: 30,
                cache_limit_mb: 2048,
                auto_load_images: true,
                auto_load_videos: false,
                ..
            }
        ));

        let clear: QmlCommand = serde_json::from_str(
            r#"{"type":"clear_cache","request_id":"storage-clear","clear_media":false,"clear_event_cache":true,"clear_sqlite":true}"#,
        )
        .expect("clear cache command must deserialize");
        assert!(matches!(
            clear,
            QmlCommand::ClearCache {
                clear_media: false,
                clear_event_cache: true,
                clear_sqlite: true,
                ..
            }
        ));

        let legacy_clear: QmlCommand =
            serde_json::from_str(r#"{"type":"clear_cache","request_id":"storage-clear-legacy"}"#)
                .expect("legacy clear cache command must deserialize");
        assert!(matches!(
            legacy_clear,
            QmlCommand::ClearCache {
                clear_media: true,
                clear_event_cache: false,
                clear_sqlite: false,
                ..
            }
        ));

        let download: QmlCommand = serde_json::from_str(
            r#"{"type":"download_media","request_id":"storage-2","media_url":"mxc://example.org/file","filename":"report.pdf"}"#,
        )
        .expect("download media command must deserialize");
        assert!(matches!(download, QmlCommand::DownloadMedia { .. }));
    }

    #[test]
    fn parses_create_room_command_with_full_options() {
        let command: QmlCommand = serde_json::from_str(
            r#"{"type":"create_room","request_id":"create-1","options":{"name":"Project","visibility":"private","preset":"private_chat","is_direct":false,"creation_content":{"m.federate":true},"initial_state":[{"type":"m.room.encryption","state_key":"","content":{"algorithm":"m.megolm.v1.aes-sha2"}}],"power_level_content_override":{"users_default":0}}}"#,
        )
        .expect("create_room command must deserialize");
        assert!(matches!(
            command,
            QmlCommand::CreateRoom { options, .. }
                if options.get("name").and_then(|value| value.as_str()) == Some("Project")
        ));
    }

    #[test]
    fn parses_room_member_moderation_command() {
        let command: QmlCommand = serde_json::from_str(
            r#"{"type":"moderate_room_member","request_id":"mod-1","room_id":"!room:example.org","user_id":"@member:example.org","action":"set_power_level","power_level":50,"reason":"Promoted"}"#,
        )
        .expect("moderate_room_member command must deserialize");
        assert!(matches!(
            command,
            QmlCommand::ModerateRoomMember {
                action,
                power_level: Some(50),
                reason: Some(reason),
                ..
            } if action == "set_power_level" && reason == "Promoted"
        ));
    }

    #[test]
    fn advertises_timeline_capability_command() {
        let command: QmlCommand =
            serde_json::from_str(r#"{"type":"get_capabilities","request_id":"cap-1"}"#)
                .expect("get_capabilities command must deserialize");
        assert!(matches!(command, QmlCommand::GetCapabilities { .. }));
    }

    #[test]
    fn paginate_timeline_uses_bounded_default_page_size() {
        let command: QmlCommand = serde_json::from_str(
            r#"{"type":"paginate_timeline_backwards","request_id":"r2","room_id":"!room:example.org"}"#,
        )
        .expect("pagination command must deserialize");
        assert!(matches!(
            command,
            QmlCommand::PaginateTimelineBackwards {
                count: 25,
                session_epoch: 0,
                generation: 0,
                ..
            }
        ));
    }

    #[test]
    fn parses_thread_and_retry_commands() {
        let send: QmlCommand = serde_json::from_str(
            r#"{"type":"send_message","request_id":"thread-send","room_id":"!room:example.org","body":"reply","thread_root":"$root"}"#,
        )
        .expect("thread reply command must deserialize");
        assert!(
            matches!(send, QmlCommand::SendMessage { thread_root: Some(root), .. } if root == "$root")
        );

        let load: QmlCommand = serde_json::from_str(
            r#"{"type":"get_thread_messages","request_id":"thread-load","room_id":"!room:example.org","root_event_id":"$root"}"#,
        )
        .expect("thread history command must deserialize");
        assert!(matches!(
            load,
            QmlCommand::GetThreadMessages { limit: 50, .. }
        ));

        let list: QmlCommand = serde_json::from_str(
            r#"{"type":"get_room_threads","request_id":"threads","room_id":"!room:example.org"}"#,
        )
        .expect("room thread list command must deserialize");
        assert!(matches!(list, QmlCommand::GetRoomThreads { limit: 20, .. }));

        let mark: QmlCommand = serde_json::from_str(
            r#"{"type":"mark_thread_read","request_id":"thread-read","room_id":"!room:example.org","root_event_id":"$root","event_id":"$latest","public_receipt":false}"#,
        )
        .expect("thread receipt command must deserialize");
        assert!(matches!(
            mark,
            QmlCommand::MarkThreadRead {
                public_receipt: Some(false),
                ..
            }
        ));

        let retry: QmlCommand = serde_json::from_str(
            r#"{"type":"retry_message","request_id":"retry-1","room_id":"!room:example.org","timeline_item_id":"txn-1"}"#,
        )
        .expect("retry command must deserialize");
        assert!(
            matches!(retry, QmlCommand::RetryMessage { timeline_item_id, .. } if timeline_item_id == "txn-1")
        );
    }
    #[test]
    fn read_all_threads_preserves_room_scope_and_receipt_privacy() {
        let command: QmlCommand = serde_json::from_str(
            r#"{"type":"mark_room_threads_read","request_id":"all-read","room_id":"!room:test","public_receipt":false}"#,
        ).unwrap();
        assert!(
            matches!(command, QmlCommand::MarkRoomThreadsRead { room_id, public_receipt: Some(false), .. } if room_id == "!room:test")
        );
        let default: QmlCommand = serde_json::from_str(
            r#"{"type":"mark_room_threads_read","request_id":"all-read","room_id":"!room:test"}"#,
        )
        .unwrap();
        assert!(matches!(
            default,
            QmlCommand::MarkRoomThreadsRead {
                public_receipt: None,
                ..
            }
        ));
    }
}
