//! Permissions for the bundled Element Call widget, restricted to one room.
use matrix_sdk::widget::{Capabilities, CapabilitiesProvider};

pub struct VoiceCapabilities {
    pub user_id: String,
    pub device_id: String,
}

impl VoiceCapabilities {
    fn allowed(&self, cap: &str) -> bool {
        if matches!(
            cap,
            "io.element.requires_client"
                | "org.matrix.msc4515.rtc_transports"
                | "org.matrix.msc4407.send.sticky_event"
                | "org.matrix.msc4407.receive.sticky_event"
                | "org.matrix.msc4157.send.delayed_event"
                | "org.matrix.msc4157.update_delayed_event"
                | "org.matrix.msc4039.download_file"
        ) {
            return true;
        }
        let Some((kind, value)) = cap.split_once(':') else {
            return false;
        };
        match kind {
            "org.matrix.msc2762.receive.state_event" => matches!(
                value,
                "m.room.create"
                    | "m.room.name"
                    | "m.room.member"
                    | "m.room.encryption"
                    | "org.matrix.msc3401.call.member"
            ),
            "org.matrix.msc2762.send.state_event" => {
                let prefix = "org.matrix.msc3401.call.member#";
                value
                    .strip_prefix(prefix)
                    .is_some_and(|key| self.state_keys().contains(&key.to_owned()))
            }
            "org.matrix.msc2762.send.event" | "org.matrix.msc2762.receive.event" => matches!(
                value,
                "io.element.call.encryption_keys"
                    | "m.call.encryption_keys"
                    | "m.rtc.notification"
                    | "org.matrix.msc4075.rtc.notification"
                    | "org.matrix.msc4075.call.notify"
                    | "m.call.notify"
                    | "m.rtc.decline"
                    | "org.matrix.msc4310.rtc.decline"
                    | "org.matrix.msc4143.rtc.member"
                    | "org.matrix.rageshake_request"
                    | "m.room.redaction"
                    | "m.reaction"
                    | "io.element.call.reaction"
            ),
            "org.matrix.msc3819.send.to_device" | "org.matrix.msc3819.receive.to_device" => {
                value.starts_with("m.call.") || value == "io.element.call.encryption_keys"
            }
            _ => false,
        }
    }
    pub fn state_keys(&self) -> Vec<String> {
        // MatrixRTC membership state keys exist in several generations in the
        // wild. Element Call can request any of these for the current user /
        // device, so grant the complete SDK-compatible set while still
        // rejecting every other user's/device's state key.
        vec![
            self.user_id.clone(),
            format!("{}_{}", self.user_id, self.device_id),
            format!("{}_{}_m.call", self.user_id, self.device_id),
            format!("_{}_{}", self.user_id, self.device_id),
            format!("_{}_{}_m.call", self.user_id, self.device_id),
        ]
    }
}
impl CapabilitiesProvider for VoiceCapabilities {
    async fn acquire_capabilities(&self, requested: Capabilities) -> Capabilities {
        let requested: Vec<String> =
            serde_json::from_value(serde_json::to_value(requested).unwrap_or_default())
                .unwrap_or_default();
        serde_json::from_value(serde_json::json!(requested
            .into_iter()
            .filter(|cap| self.allowed(cap))
            .collect::<Vec<_>>()))
        .unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn widget_cannot_write_other_devices_or_read_chat_history() {
        let provider = VoiceCapabilities {
            user_id: "@u:s".into(),
            device_id: "A".into(),
        };
        assert!(provider.allowed("org.matrix.msc4515.rtc_transports"));
        assert!(provider.allowed("org.matrix.msc2762.send.event:m.room.redaction"));
        assert!(provider.allowed("org.matrix.msc2762.receive.event:m.room.redaction"));
        for key in provider.state_keys() {
            assert!(provider.allowed(&format!(
                "org.matrix.msc2762.send.state_event:org.matrix.msc3401.call.member#{key}"
            )));
        }
        for cap in [
            "org.matrix.msc2762.send.state_event:m.room.power_levels#",
            "org.matrix.msc2762.receive.event:m.room.message",
            "org.matrix.msc2762.send.state_event:org.matrix.msc3401.call.member#_@u:s_B_m.call",
            "org.matrix.msc2762.send.state_event:org.matrix.msc3401.call.member#@other:s",
        ] {
            assert!(!provider.allowed(cap), "{cap}");
        }
    }
}
