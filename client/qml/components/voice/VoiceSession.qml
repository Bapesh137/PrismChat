import QtQuick
import "../../utils" as L10n

Item {
    id: root
    required property var connection
    required property var webProfile
    property string phase: "idle"
    readonly property bool active: phase !== "idle"
    property string callId: ""
    property double callEpoch: 0
    property string roomId: ""
    property string roomName: ""
    property string ownUserId: ""
    property string callIntent: ""
    property bool outgoing: false
    property string widgetUrl: ""
    property string errorText: ""
    property bool panelOpen: false
    property bool panelFullscreen: false
    property bool muted: true
    property bool videoMuted: true
    property bool deafened: false
    property bool muteBeforeDeafen: true
    property bool reconnecting: false
    property double callStartedAt: 0
    property double connectedAt: 0
    property bool callHistoryRecorded: false
    property bool suppressCallHistory: false
    property var participants: []
    property var pendingRoom: null
    property int actionSequence: 0
    // Native-control requests use a separate ID space from WidgetDriver.
    property var pendingHostRequests: ({})
    // Buffer WidgetDriver traffic until QWebChannel is ready.
    property bool widgetBridgeReady: false
    property var pendingWidgetMessages: []
    property string incomingRoomId: ""
    property string incomingRoomName: ""
    property string incomingCallerId: ""
    property string incomingCallerName: ""
    property string incomingCallerAvatar: ""
    property string incomingEventId: ""
    property double incomingExpiresAt: 0
    property double incomingStartedAt: 0
    property var recordedIncomingHistoryIds: ({})
    readonly property bool hasIncoming: incomingEventId !== "" && incomingExpiresAt > Date.now()
    signal toWidget(string message)

    function send(command) { return connection && connection.sendVoiceCommand(command) }
    function deliverToWidget(message) {
        var raw = String(message || "")
        if (!raw) return
        if (!widgetBridgeReady) {
            if (pendingWidgetMessages.length >= 256) pendingWidgetMessages.shift()
            pendingWidgetMessages.push(raw)
            return
        }
        toWidget(raw)
    }
    function setWidgetBridgeReady(value) {
        value = value === true
        if (widgetBridgeReady === value) return
        widgetBridgeReady = value
        if (!value) return
        var queued = pendingWidgetMessages
        pendingWidgetMessages = []
        for (var i = 0; i < queued.length; ++i) toWidget(queued[i])
    }
    function markConnected() {
        if (phase === "preparing" || phase === "loading") {
            timeout.stop()
            if (!connectedAt) connectedAt = Date.now()
            phase = "connected"
        }
    }
    function formatCallDuration(milliseconds) {
        var totalSeconds = Math.max(1, Math.floor(Number(milliseconds || 0) / 1000))
        var hours = Math.floor(totalSeconds / 3600)
        var minutes = Math.floor((totalSeconds % 3600) / 60)
        var seconds = totalSeconds % 60
        function pad(value) { return value < 10 ? "0" + value : String(value) }
        return hours > 0 ? hours + ":" + pad(minutes) + ":" + pad(seconds)
            : minutes + ":" + pad(seconds)
    }
    function sendCallHistory(historyRoomId, startedAt, connectedSince, endedAt) {
        if (!historyRoomId || !connection || !connection.connected
                || !connection.activeSessionEpoch)
            return
        var started = startedAt || Date.now()
        var time = Qt.formatDateTime(new Date(started), "dd.MM.yyyy HH:mm")
        var body = connectedSince > 0
            ? L10n.I18n.tr("📞 Аудиозвонок · %1 · длился %2")
                .replace("%1", time)
                .replace("%2", formatCallDuration((endedAt || Date.now()) - connectedSince))
            : L10n.I18n.tr("📞 Вызов без ответа · %1").replace("%1", time)
        connection.sendCommand({
            type: "send_message",
            request_id: connection.nextRequestId("call-history"),
            room_id: historyRoomId,
            body: body,
            msg_type: "io.prismchat.call.history",
            mentioned_user_ids: []
        })
    }
    function recordCallHistory() {
        if (callHistoryRecorded || suppressCallHistory || !roomId
                || callEpoch !== connection.activeSessionEpoch)
            return
        callHistoryRecorded = true
        sendCallHistory(roomId, callStartedAt, connectedAt, Date.now())
    }
    function recordMissedIncoming() {
        var eventId = incomingEventId
        if (!eventId || recordedIncomingHistoryIds[eventId]) return
        var updated = Object.assign({}, recordedIncomingHistoryIds)
        updated[eventId] = true
        var keys = Object.keys(updated)
        if (keys.length > 128) delete updated[keys[0]]
        recordedIncomingHistoryIds = updated
        sendCallHistory(incomingRoomId, incomingStartedAt, 0, Date.now())
    }
    function ownParticipantPresent(list) {
        if (!ownUserId) return false
        var values = list || []
        for (var i = 0; i < values.length; ++i) {
            if (String((values[i] || {}).user_id || "") === ownUserId) return true
        }
        return false
    }
    function localizedWidgetUrl(value) {
        var address = String(value || "")
        if (!address) return address
        var language = L10n.I18n.language === "zh"
            ? "zh-Hans" : L10n.I18n.language
        var encoded = encodeURIComponent(language)
        if (/[?&]lang=[^&#]*/.test(address))
            return address.replace(/([?&]lang=)[^&#]*/, "$1" + encoded)

        var hashIndex = address.indexOf("#")
        if (hashIndex < 0)
            return address + "#?lang=" + encoded
        var fragment = address.substring(hashIndex + 1)
        return address + (fragment.indexOf("?") >= 0 ? "&" : "?")
            + "lang=" + encoded
    }
    function start(id, name, intent, isOutgoing, startedAt) {
        if (active) {
            panelOpen = true
            if (roomId !== id) { pendingRoom = {id: id, name: name, intent: intent, outgoing: isOutgoing}; leave() }
            return
        }
        if (!connection || !connection.connected || !connection.activeSessionEpoch) {
            errorText = L10n.I18n.tr("Нет соединения с Matrix"); panelOpen = true; return
        }
        if (!webProfile || !webProfile.assetBaseUrl) {
            errorText = L10n.I18n.tr("Не удалось запустить локальный сервер Element Call")
            panelOpen = true; return
        }
        errorText = ""; callEpoch = connection.activeSessionEpoch
        callStartedAt = startedAt || Date.now(); connectedAt = 0
        callHistoryRecorded = false; suppressCallHistory = false
        callId = connection.nextRequestId("voice")
        roomId = id; roomName = name; ownUserId = ""; callIntent = intent; outgoing = isOutgoing
        muted = true; videoMuted = true; deafened = false; panelOpen = true; phase = "preparing"
        widgetBridgeReady = false; pendingWidgetMessages = []
        timeout.interval = 30000; timeout.restart()
        if (!send({type: "voice_begin", request_id: callId, call_id: callId,
                    room_id: roomId, session_epoch: callEpoch, intent: callIntent,
                    element_call_url: webProfile.assetBaseUrl}))
            fail(L10n.I18n.tr("Нет связи с бэкендом"))
    }
    function call(id, name) { start(id, name, "start_call_dm_voice", true) }
    function join(id, name) { start(id, name, "voice_channel", false) }
    function acceptIncoming() {
        if (!hasIncoming) return
        var id = incomingRoomId, name = incomingRoomName, started = incomingStartedAt
        // Resolve simultaneous calls by joining the incoming session.
        if (active && roomId === id && outgoing && phase !== "connected") {
            pendingRoom = {id: id, name: name, intent: "join_existing_dm_voice",
                           outgoing: false, startedAt: started}
            suppressCallHistory = true
            clearIncoming()
            leave()
            return
        }
        clearIncoming(); start(id, name, "join_existing_dm_voice", false, started)
    }
    function declineIncoming() {
        if (!incomingEventId) return
        send({type: "voice_decline", request_id: connection.nextRequestId("voice-decline"),
              room_id: incomingRoomId, notification_event_id: incomingEventId})
        recordMissedIncoming()
        clearIncoming()
    }
    function clearIncoming() {
        incomingRoomId = ""; incomingRoomName = ""; incomingCallerId = ""
        incomingCallerName = ""; incomingCallerAvatar = ""; incomingEventId = ""
        incomingExpiresAt = 0; incomingStartedAt = 0
    }
    function action(name, data) {
        if (!callId || !widgetUrl) return ""
        var id = callId + "-action-" + (++actionSequence)
        pendingHostRequests[id] = name
        deliverToWidget(JSON.stringify({api: "toWidget", widgetId: callId,
            requestId: id, action: name, data: data || {}}))
        return id
    }
    function setMuted(value) {
        if (deafened || !active || phase !== "connected") return
        // Wait for Element Call's effective device-state report.
        action("io.element.device_mute", {audio_enabled: !value, video_enabled: !videoMuted})
    }
    function setDeafened(value) {
        if (value === deafened || !active || phase !== "connected") return
        if (value) muteBeforeDeafen = muted
        deafened = value
        if (value && !muted)
            action("io.element.device_mute", {audio_enabled: false, video_enabled: !videoMuted})
        else if (!value)
            action("io.element.device_mute", {audio_enabled: !muteBeforeDeafen, video_enabled: !videoMuted})
    }
    function leave() {
        if (!active || phase === "leaving" || phase === "ending") return
        if (!widgetUrl) { finishLeave(); return }
        phase = "leaving"; action("im.vector.hangup", {})
        timeout.interval = 4000; timeout.restart()
    }
    function finishLeave() {
        if (!active || phase === "ending") return
        recordCallHistory()
        phase = "ending"; widgetUrl = ""; participants = []
        timeout.interval = 15000; timeout.restart()
        if (!send({type: "voice_end", request_id: callId + "-end", call_id: callId})) reset()
    }
    function reset() {
        timeout.stop(); phase = "idle"; widgetUrl = ""; callId = ""
        roomId = ""; roomName = ""; ownUserId = ""; callIntent = ""; outgoing = false
        callStartedAt = 0; connectedAt = 0
        callHistoryRecorded = false; suppressCallHistory = false
        panelFullscreen = false
        participants = []; muted = true; videoMuted = true; deafened = false; reconnecting = false
        pendingHostRequests = ({})
        widgetBridgeReady = false; pendingWidgetMessages = []
        var next = pendingRoom; pendingRoom = null
        if (next) Qt.callLater(function() {
            root.start(next.id, next.name, next.intent, next.outgoing, next.startedAt || 0)
        })
    }
    function fail(error) {
        errorText = String(error || L10n.I18n.tr("Не удалось подключиться к звонку"))
        panelOpen = true; pendingRoom = null
        if (active) finishLeave()
    }
    function respondToWidget(message, response) {
        deliverToWidget(JSON.stringify(Object.assign({}, message, {response: response || {}})))
    }
    function widgetMessage(raw) {
        var message
        try { message = JSON.parse(raw) } catch (_) { return }
        if (!active || message.widgetId !== callId) return
        if (message.api === "toWidget" && message.response !== undefined) {
            var hostAction = pendingHostRequests[message.requestId]
            if (hostAction !== undefined) {
                delete pendingHostRequests[message.requestId]
                if (hostAction === "im.vector.hangup" && phase === "leaving") finishLeave()
                return
            }
            // WidgetDriver responses continue to Rust.
        }
        if (message.api === "fromWidget" && message.response === undefined) {
            var data = message.data || {}
            if (message.action === "io.element.join") {
                // Element Call owns this host action; acknowledge it locally.
                respondToWidget(message, {})
                markConnected()
                return
            } else if (message.action === "io.element.close" || message.action === "im.vector.hangup") {
                respondToWidget(message, {}); finishLeave(); return
            } else if (message.action === "io.element.device_mute") {
                // Device state also confirms that media joined.
                if (data.audio_enabled !== undefined) muted = data.audio_enabled !== true
                if (data.video_enabled !== undefined) videoMuted = data.video_enabled !== true
                respondToWidget(message, {})
                markConnected()
                return
            } else if (message.action === "set_always_on_screen") {
                respondToWidget(message, {}); return
            }
        }
        send({type: "voice_widget", call_id: callId, session_epoch: callEpoch, message: raw})
    }
    function receive(message) {
        if (message.type === "voice_incoming") {
            if (message.session_epoch !== connection.activeSessionEpoch) return
            // Preserve an incoming ring while an outgoing call is loading.
            if (active && roomId === message.room_id
                    && (!outgoing || phase === "connected")) return
            incomingRoomId = message.room_id; incomingRoomName = message.room_name
            incomingCallerId = message.caller_user_id; incomingCallerName = message.caller_name
            incomingCallerAvatar = message.caller_avatar_url || ""
            incomingEventId = message.notification_event_id; incomingExpiresAt = message.expires_at
            incomingStartedAt = Date.now()
            return
        }
        if (message.type === "voice_incoming_ended") {
            if (message.session_epoch !== connection.activeSessionEpoch) return
            if (incomingEventId === message.notification_event_id) {
                recordMissedIncoming()
                clearIncoming()
            }
            if (message.reason === "declined" && active && outgoing
                    && roomId === message.room_id)
                fail(L10n.I18n.tr("Собеседник отклонил звонок"))
            return
        }
        if (message.type === "voice_participants_changed") {
            if (message.session_epoch !== connection.activeSessionEpoch) return
            if (active && roomId === message.room_id) {
                participants = message.participants || []
                // Participant state alone does not prove local media joined.
            }
            return
        }
        if (!active || message.call_id !== callId || message.session_epoch !== callEpoch) return
        if (message.type === "voice_widget_message") { deliverToWidget(message.message); return }
        if (message.operation === "end") { reset(); return }
        if (!message.success) { fail(message.error); return }
        if (message.operation === "begin" && phase === "preparing") {
            participants = message.data.participants || []
            ownUserId = String(message.data.user_id || "")
            // Pass PrismChat's selected locale in the widget URL.
            phase = "loading"; widgetUrl = localizedWidgetUrl(message.data.widget_url)
            timeout.interval = 60000; timeout.restart()
        }
    }
    Connections {
        target: root.connection
        function onVoiceEvent(message) { root.receive(message) }
        function onActiveSessionEpochChanged() {
            if (root.active && root.callEpoch !== root.connection.activeSessionEpoch) {
                root.pendingRoom = null; root.reset()
            }
            if (root.incomingEventId && root.connection.activeSessionEpoch === 0) root.clearIncoming()
        }
        function onConnectedChanged() {
            if (!root.connection.connected && root.active) {
                root.pendingRoom = null; root.errorText = L10n.I18n.tr("Связь с бэкендом потеряна"); root.reset()
            }
            if (!root.connection.connected) root.clearIncoming()
        }
    }
    Timer {
        interval: 1000; repeat: true; running: root.incomingEventId !== ""
        onTriggered: if (Date.now() >= root.incomingExpiresAt) {
            root.recordMissedIncoming()
            root.clearIncoming()
        }
    }
    Timer {
        id: timeout
        onTriggered: {
            if (root.phase === "leaving") root.finishLeave()
            else if (root.phase === "ending") {
                root.errorText = L10n.I18n.tr("Не удалось подтвердить завершение звонка")
                root.pendingRoom = null; root.reset()
            } else root.fail(L10n.I18n.tr("Звонок не подключился вовремя. Проверьте микрофон и MatrixRTC / LiveKit на сервере."))
        }
    }
}
