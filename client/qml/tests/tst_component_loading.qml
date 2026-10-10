import QtQuick
import QtTest
TestCase {
    name: "ComponentLoading"
    function test_changedComponentsCompile() {
        var files = ["../main.qml", "../PrismChatWindow.qml",
            "../services/MatrixConnection.qml", "../components/chat/ChatView.qml",
            "../components/chat/MessageComposer.qml",
            "../components/chat/MessageDelegate/MessageDelegate.qml",
            "../components/chat/ScheduledMessagesPopup.qml",
            "../components/chat/MessageList.qml", "../components/chat/RoomAttachmentsPanel.qml",
            "../components/chat/ThreadPanel.qml",
            "../components/common/StartupIntro.qml",
            "../components/devices/CurrentDeviceCard.qml", "../settings/pages/EncryptionSettingsPage.qml"]
        files.push("../settings/pages/AppearanceSettingsPage.qml")
        for (var i=0; i<files.length; i++) {
            var component = Qt.createComponent(Qt.resolvedUrl(files[i]))
            tryCompare(component,"status",Component.Ready,5000,component.errorString())
        }
    }
}
