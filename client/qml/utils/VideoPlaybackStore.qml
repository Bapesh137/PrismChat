pragma Singleton
import QtQuick
import QtCore

QtObject {
    id: root

    // Stored locally via QSettings. Values are milliseconds keyed by Matrix
    // event id, with a media URL fallback for local-echo -> remote-echo swaps.
    property var positions: ({})
    readonly property int maxEntries: 300

    property Settings cacheSettings: Settings {
        category: "VideoPlayback"
        property string positionsJson: "{}"
    }

    property Timer persistTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: root.persist()
    }

    Component.onCompleted: {
        try {
            var parsed = JSON.parse(cacheSettings.positionsJson || "{}")
            positions = parsed && typeof parsed === "object" ? parsed : ({})
        } catch (error) {
            positions = ({})
        }
    }

    function eventKey(eventId) {
        var value = String(eventId || "")
        return value !== "" ? "event:" + value : ""
    }

    function mediaKey(mediaUrl) {
        var value = String(mediaUrl || "")
        return value !== "" ? "media:" + value : ""
    }

    function positionFor(eventId, mediaUrl) {
        var keys = [eventKey(eventId), mediaKey(mediaUrl)]
        for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
            var key = keys[keyIndex]
            if (key === "")
                continue
            var entry = positions[key]
            if (!entry)
                continue
            var value = Number(entry.position_ms || 0)
            if (isFinite(value) && value > 0)
                return Math.round(value)
        }
        return 0
    }

    function savePosition(eventId, mediaUrl, positionMs, durationMs) {
        var keys = [eventKey(eventId), mediaKey(mediaUrl)]
        if (keys[0] === "" && keys[1] === "")
            return

        var position = Math.max(0, Math.round(Number(positionMs || 0)))
        var duration = Math.max(0, Math.round(Number(durationMs || 0)))
        var next = Object.assign({}, positions)
        var shouldRemove = position <= 500
            || (duration > 0 && position >= Math.max(0, duration - 1500))

        for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
            var key = keys[keyIndex]
            if (key === "")
                continue
            if (shouldRemove) {
                delete next[key]
            } else {
                next[key] = {
                    position_ms: position,
                    updated_at: Date.now()
                }
            }
        }

        var allKeys = Object.keys(next)
        if (allKeys.length > maxEntries) {
            allKeys.sort(function(a, b) {
                return Number((next[a] && next[a].updated_at) || 0)
                    - Number((next[b] && next[b].updated_at) || 0)
            })
            while (allKeys.length > maxEntries)
                delete next[allKeys.shift()]
        }

        positions = next
        persistTimer.restart()
    }

    function clearPosition(eventId, mediaUrl) {
        var keys = [eventKey(eventId), mediaKey(mediaUrl)]
        var next = Object.assign({}, positions)
        var changed = false
        for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
            var key = keys[keyIndex]
            if (key !== "" && next[key]) {
                delete next[key]
                changed = true
            }
        }
        if (!changed)
            return
        positions = next
        persistTimer.restart()
    }

    function persist() {
        try {
            cacheSettings.positionsJson = JSON.stringify(positions)
        } catch (error) {
            // Ignore serialization failures; playback itself must remain usable.
        }
    }

    function flush() {
        persistTimer.stop()
        persist()
        cacheSettings.sync()
    }
}
