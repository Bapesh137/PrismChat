import QtQuick
import QtTest
import ".." as App
import "../components/chat"

Item {
    id: scene
    width: 1000
    height: 700

    Component {
        id: windowComponent
        App.PrismChatWindow { visible: false; transportAutoConnect: false }
    }
    Component {
        id: composerComponent
        MessageComposer { width: 600; currentUserId: "@module:test" }
    }
    Component {
        id: chatComponent
        ChatView {
            width: 950; height: 650
            messageModel: ListModel {}
            currentRoomId: "!module:test"
            roomMemberCount: 6
            displayedRoomId: currentRoomId
            timelineInitialPositionReady: true
            autoLoadImages: false
            autoLoadVideos: false
        }
    }

    TestCase {
        name: "ModuleIntegration"
        when: windowShown

        function init() {
            failOnWarning(/ReferenceError|TypeError|Unable to assign|Binding loop/)
        }

        function test_composerKeepsDraftsAttachmentsAndSchedulingAcrossRooms() {
            var composer = createTemporaryObject(composerComponent, scene)
            verify(composer)
            composer.clearAllDrafts()
            composer.scheduledMessages = []
            composer.currentRoomId = "!first:test"
            composer.startReply("$reply", "@friend:test", "original")
            composer.insertEmoji("Draft text")
            composer.stageAttachment("", "/tmp/module.txt",
                                     "module.txt", false, "text/plain", 0, 12)
            composer.currentRoomId = "!second:test"
            compare(composer.draftSnapshot().text, "")
            composer.insertEmoji("Second draft")
            composer.currentRoomId = "!first:test"
            var draft = composer.draftSnapshot()
            compare(draft.text, "Draft text")
            compare(draft.attachments.length, 1)
            compare(draft.reply_event_id, "$reply")
            composer.saveScheduledMessage("", draft.text, Date.now() - 1000,
                                          draft.attachments, "$reply", [])
            compare(composer.scheduledMessages.length, 1)
            var due = []
            composer.scheduledMessageDue.connect(function(message) { due.push(message) })
            composer.dispatchEnabled = true
            composer.processScheduledMessages()
            compare(due.length, 1)
            compare(due[0].room_id, "!first:test")
            compare(due[0].attachments[0].name, "module.txt")
            compare(composer.scheduledMessages.length, 0)
            composer.clearAllDrafts()
        }

        function test_threadResponsesStayInTheirRoomAfterExtraction() {
            var chat = createTemporaryObject(chatComponent, scene)
            verify(chat)
            var requests = []
            chat.commandRequested.connect(function(command) { requests.push(command) })
            chat.openThread({event_id: "$root", sender: "@friend:test", body: "root", timestamp: 1})
            compare(requests[requests.length - 1].type, "get_thread_messages")
            var requestId = chat.threadRequestId
            chat.receiveThreadMessages("!elsewhere:test", "$root", [], false, "", requestId)
            compare(chat.threadLoading, true)
            chat.receiveThreadMessages("!module:test", "$root", [
                {event_id: "$reply", thread_root_id: "$root", sender: "@friend:test", body: "reply", timestamp: 2}
            ], false, "", requestId)
            compare(chat.threadLoading, false)
            compare(chat.threadMessages.length, 2)
            compare(chat.threadMessages[0].event_id, "$reply")
            chat.closeThread()
            compare(chat.threadsPanelVisible, false)
        }

        function test_smallRoomsRequireExplicitThreadSetting() {
            var chat = createTemporaryObject(chatComponent, scene)
            verify(chat)
            var requests = []
            chat.commandRequested.connect(function(command) { requests.push(command) })
            chat.roomMemberCount = 5
            compare(chat.showThreadsInSmallGroups, false)
            compare(chat.threadsAvailable, false)
            chat.openThread({event_id: "$blocked", sender: "@friend:test",
                             body: "blocked", timestamp: 1})
            compare(chat.threadsPanelVisible, false)
            compare(requests.length, 0)

            chat.showThreadsInSmallGroups = true
            compare(chat.threadsAvailable, true)
            chat.openThread({event_id: "$allowed", sender: "@friend:test",
                             body: "allowed", timestamp: 2})
            compare(chat.threadsPanelVisible, true)
            compare(requests[requests.length - 1].type, "get_thread_messages")

            chat.showThreadsInSmallGroups = false
            compare(chat.threadsPanelVisible, false)
        }

        function test_windowComposesScreensSettingsAndNotificationModels() {
            var window = createTemporaryObject(windowComponent, null)
            verify(window)
            compare(window.transportAutoConnect, false)
            window.showMain("@module:test", "https://example.invalid", "", "test-profile", true)
            compare(window.currentUserId, "@module:test")
            compare(window.pendingLastRoomRestoreProfileId, "test-profile")
            window.currentRoomId = "!module:test"
            tryVerify(function() { return window.sidebar && window.chatView })
            window.addCenterNotification("mention-1", "mention", "Title", "Body",
                                         "!module:test", "Room")
            compare(window.mentionNotificationsModelObject.count, 1)
            window.markCenterNotificationRead("mention-1")
            window.clearCenterNotifications("mention")
            compare(window.mentionNotificationsModelObject.count, 0)
            window.openSettingsDialog(0)
            wait(0)
            window.sidebar.openRoomContextMenu("!module:test", "Room", "", false, false, 20, 40)
            window.sidebar.showRoomInfo({room_id: "!module:test", name: "Room", topic: ""})
            wait(0)
            window.close()
        }
    }
}
