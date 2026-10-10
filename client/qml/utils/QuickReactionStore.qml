pragma Singleton
import QtQuick
import QtCore

QtObject {
    id: root

    readonly property var defaults: ["👍", "❤️", "😂", "😮", "😢", "🎉"]
    property var keys: defaults.slice()
    property var recent: []
    readonly property var orderedKeys: sortedKeys()

    property Settings settings: Settings {
        location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation)
            + "/PrismChat/quick-reactions.ini"
        category: "QuickReactions"
        property string stateJson: "{}"
    }

    Component.onCompleted: restore(settings.stateJson)

    function uniqueKeys(values, limit) {
        var result = []
        if (!Array.isArray(values)) return result
        for (var index = 0; index < values.length && result.length < limit; index++) {
            if (typeof values[index] !== "string") continue
            var key = values[index].trim()
            if (key && key.length <= 64 && !/[\r\n]/.test(key)
                    && result.indexOf(key) < 0)
                result.push(key)
        }
        return result
    }

    function restore(serialized) {
        var state = ({})
        try {
            state = JSON.parse(serialized || "{}") || ({})
        } catch (error) {
            state = ({})
        }
        var restored = uniqueKeys(state.keys, 6)
        for (var index = 0; restored.length < 6 && index < defaults.length; index++) {
            if (restored.indexOf(defaults[index]) < 0)
                restored.push(defaults[index])
        }
        keys = restored
        recent = uniqueKeys(state.recent, 64)
    }

    function sortedKeys() {
        var result = []
        for (var recentIndex = 0; recentIndex < recent.length; recentIndex++) {
            if (keys.indexOf(recent[recentIndex]) >= 0)
                result.push(recent[recentIndex])
        }
        for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
            if (result.indexOf(keys[keyIndex]) < 0)
                result.push(keys[keyIndex])
        }
        return result
    }

    function persist() {
        settings.stateJson = JSON.stringify({keys: keys, recent: recent})
    }

    function replaceKey(previous, replacement) {
        var values = uniqueKeys([replacement], 1)
        if (values.length === 0 || keys.indexOf(previous) < 0) return false
        var key = values[0]
        if (keys.indexOf(key) >= 0) return false
        var next = keys.slice()
        next[next.indexOf(previous)] = key
        keys = next
        persist()
        return true
    }

    function recordUse(value) {
        var values = uniqueKeys([value], 1)
        if (values.length === 0) return
        var key = values[0]
        var next = [key]
        for (var index = 0; index < recent.length; index++) {
            if (recent[index] !== key)
                next.push(recent[index])
        }
        for (var tail = next.length - 1; next.length > 64 && tail >= 0; tail--) {
            if (keys.indexOf(next[tail]) < 0)
                next.splice(tail, 1)
        }
        recent = next
        persist()
    }
}
