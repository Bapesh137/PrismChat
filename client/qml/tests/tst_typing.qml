import QtQuick
import QtTest
import "../components/chat"

TestCase {
    id: testCase

    name: "TypingLifecycle"
    when: windowShown

    Component {
        id: composerComponent

        MessageComposer {
            width: 420
            currentRoomId: "!first:example.org"
        }
    }

    SignalSpy {
        id: typingSpy
        signalName: "typingStateChanged"
    }

    function cleanup() {
        typingSpy.target = null
        typingSpy.clear()
    }

    function test_privacySettingStopsActiveTyping() {
        var composer = createTemporaryObject(composerComponent, testCase)
        verify(composer)
        typingSpy.target = composer

        composer.startEditing("$own", "draft")
        tryCompare(composer, "typingActive", true)
        compare(typingSpy.count, 1)
        compare(typingSpy.signalArguments[0][0], "!first:example.org")
        compare(typingSpy.signalArguments[0][1], true)

        composer.typingNotificationsEnabled = false
        tryCompare(composer, "typingActive", false)
        compare(typingSpy.count, 2)
        compare(typingSpy.signalArguments[1][0], "!first:example.org")
        compare(typingSpy.signalArguments[1][1], false)
    }

    function test_roomChangeStopsTypingInPreviousRoom() {
        var composer = createTemporaryObject(composerComponent, testCase)
        verify(composer)
        typingSpy.target = composer

        composer.startEditing("$own", "draft")
        tryCompare(composer, "typingActive", true)
        typingSpy.clear()
        composer.currentRoomId = "!second:example.org"

        tryCompare(composer, "typingActive", false)
        compare(typingSpy.count, 1)
        compare(typingSpy.signalArguments[0][0], "!first:example.org")
        compare(typingSpy.signalArguments[0][1], false)
    }
}
