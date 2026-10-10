import QtQuick
import QtTest
import "../components/voice"
import "../utils" as L10n

Item {
    width: 320
    height: 200

    QtObject {
        id: mockConnection
        property bool connected: true
        property int activeSessionEpoch: 1
        signal voiceEvent(var message)
        function nextRequestId(prefix) { return prefix + "-1" }
        function sendVoiceCommand(command) { return true }
        function sendCommand(command) { return true }
    }

    QtObject {
        id: mockProfile
        property string assetBaseUrl: "http://127.0.0.1:1234/index.html"
    }

    Component {
        id: sessionComponent
        VoiceSession {
            connection: mockConnection
            webProfile: mockProfile
        }
    }

    TestCase {
        name: "VoiceI18n"

        function test_widgetUrlUsesSelectedLanguage() {
            var session = createTemporaryObject(sessionComponent, parent)
            verify(session !== null)
            var previous = L10n.I18n.language

            L10n.I18n.setLanguage("de")
            compare(session.localizedWidgetUrl(
                        "http://127.0.0.1:1234/index.html#?widgetId=call-1"),
                    "http://127.0.0.1:1234/index.html#?widgetId=call-1&lang=de")

            L10n.I18n.setLanguage("zh")
            compare(session.localizedWidgetUrl(
                        "http://127.0.0.1:1234/index.html#?widgetId=call-1&lang=en"),
                    "http://127.0.0.1:1234/index.html#?widgetId=call-1&lang=zh-Hans")

            L10n.I18n.setLanguage(previous)
        }
    }
}
