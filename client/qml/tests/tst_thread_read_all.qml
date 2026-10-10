import QtQuick
import QtTest
import "../components/chat"
import "../services"

Item {
    id: scene
    width: 950; height: 700
    Component { id: headerFixture; ChatHeader { width: 800; height: 44; roomId: "!a:test" } }
    Component {
        id: chatFixture
        ChatView {
            width: 900; height: 650
            currentRoomId: "!a:test"
            roomMemberCount: 6
            displayedRoomId: currentRoomId
            messageModel: ListModel {}
            autoLoadImages: false
            autoLoadVideos: false
            publicReadReceipts: false
            property var captured: []
            property var errors: []
            onCommandRequested: function(command) { captured.push(command) }
            onFeedbackRequested: function(text, error) { if (error) errors.push(text) }
        }
    }
    Component { id: connectionFixture; MatrixConnection { transportAutoConnect: false } }
    SignalSpy { id: openSpy; signalName: "threadsRequested" }
    SignalSpy { id: readSpy; signalName: "threadsReadRequested" }
    SignalSpy { id: resultSpy; signalName: "allThreadsReadFinished" }

    TestCase {
        name: "ThreadReadAll"
        when: windowShown
        function init() { failOnWarning(/ReferenceError|TypeError|Unable to assign|Binding loop/) }
        function cleanup() {
            openSpy.target = null; readSpy.target = null; resultSpy.target = null
            openSpy.clear(); readSpy.clear(); resultSpy.clear()
        }
        function summary(id, latest) {
            return {root:{event_id:id, sender:"@friend:test", body:id},
                latest_reply:{event_id:latest, sender:"@friend:test", body:latest}, unread:true, reply_count:1}
        }
        function makeChat() {
            var chat = createTemporaryObject(chatFixture, scene)
            verify(chat)
            wait(0)
            chat.roomThreads = [summary("$a", "$a1"), summary("$b", "$b1")]
            chat.threadUnreadCount = 2
            return chat
        }
        function test_rightClickMenuDoesNotOpenThreadsAndLeftClickStillWorks() {
            var header = createTemporaryObject(headerFixture, scene)
            verify(header)
            openSpy.target = header; readSpy.target = header
            var button = findChild(header, "threadsButton")
            var menu = findChild(header, "threadActionsMenu")
            verify(button); verify(menu)
            mouseClick(button, 16, 16, Qt.RightButton)
            tryCompare(menu, "opened", true)
            compare(openSpy.count, 0)
            var action = menu.itemAt(0)
            verify(action.enabled) // Works even before a badge or directory is loaded.
            mouseClick(action, action.width / 2, action.height / 2, Qt.LeftButton)
            compare(readSpy.count, 1)
            tryCompare(menu, "visible", false)
            mouseClick(button, 16, 16, Qt.LeftButton)
            compare(openSpy.count, 1)
            header.markingThreadsRead = true
            mouseClick(button, 16, 16, Qt.RightButton)
            tryCompare(menu, "opened", true)
            verify(!action.enabled)
            header.roomId = "!b:test"
            tryCompare(menu, "visible", false)
        }
        function test_receiptsClearAllBadgesAndRejectOldListsButAllowNewReplies() {
            var chat = makeChat()
            var staleId = chat.roomThreadsRequestId
            chat.markAllThreadsRead()
            var requestId = chat.threadReadAllRequests["!a:test"]
            var command = chat.captured[chat.captured.length - 1]
            compare(command.type, "mark_room_threads_read")
            compare(command.public_receipt, false)
            compare(command.room_id, "!a:test")
            var count = chat.captured.length
            chat.markAllThreadsRead()
            compare(chat.captured.length, count)
            verify(chat.markingThreadsRead)
            chat.receiveRoomThreads("!a:test", [], "", 0, "", staleId)
            compare(chat.threadUnreadCount, 2)
            chat.receiveAllThreadsRead("!a:test", true,
                {"$a":"$a1", "$b":"$b1", "$notLoaded":"$last"}, "", requestId)
            compare(chat.threadUnreadCount, 0)
            verify(!chat.roomThreads[0].unread)
            verify(!chat.markingThreadsRead)
            chat.receiveRoomThreads("!a:test", [summary("$a", "$a1")], "", 1, "", staleId)
            compare(chat.threadUnreadCount, 0)
            chat.receiveRoomThreads("!a:test", [summary("$a", "$new")], "", 1, "", chat.roomThreadsRequestId)
            compare(chat.threadUnreadCount, 1)
        }
        function test_partialFailureKeepsUnreadThreadsAndRoomSwitchIsIsolated() {
            var chat = makeChat()
            chat.markAllThreadsRead()
            var requestId = chat.threadReadAllRequests["!a:test"]
            chat.receiveAllThreadsRead("!a:test", false, {"$a":"$a1"}, "offline", requestId)
            compare(chat.threadUnreadCount, 1)
            verify(!chat.roomThreads[0].unread)
            verify(chat.roomThreads[1].unread)
            compare(chat.errors.length, 1)
            chat.markAllThreadsRead()
            requestId = chat.threadReadAllRequests["!a:test"]
            chat.currentRoomId = "!b:test"
            chat.roomThreads = [summary("$b-other-room", "$b2")]
            chat.threadUnreadCount = 1
            chat.receiveAllThreadsRead("!a:test", true, {"$a":"$a1", "$b":"$b1"}, "", requestId)
            compare(chat.threadUnreadCount, 1)
            verify(chat.roomThreads[0].unread)
            compare(Object.keys(chat.threadReadAllRequests).length, 0)
        }
        function test_sessionChangeRejectsOldCompletion() {
            var chat = makeChat()
            chat.markAllThreadsRead()
            var requestId = chat.threadReadAllRequests["!a:test"]
            chat.sessionEpoch++
            chat.receiveAllThreadsRead("!a:test", true, {"$a":"$a1", "$b":"$b1"}, "", requestId)
            compare(chat.threadUnreadCount, 2)
            verify(!chat.markingThreadsRead)
        }
        function test_ipcResultAndTimeoutCarryTheRequestIdentity() {
            var connection = createTemporaryObject(connectionFixture, scene)
            verify(connection)
            resultSpy.target = connection
            var command = {type:"mark_room_threads_read", request_id:"read-1", room_id:"!a:test", public_receipt:false}
            compare(connection.commandTimeoutMs(command.type), 300000)
            connection.registerPendingCommand(command)
            connection.socketObject.textMessageReceived(JSON.stringify({
                type:"mark_room_threads_read_result", request_id:"read-1", room_id:"!a:test",
                success:true, read_events:{"$a":"$a1"}
            }))
            compare(resultSpy.count, 1)
            compare(resultSpy.signalArguments[0][2]["$a"], "$a1")
            compare(resultSpy.signalArguments[0][4], "read-1")
            command.request_id = "read-timeout"
            connection.handleCommandFailure(command, "timeout")
            compare(resultSpy.count, 2)
            compare(resultSpy.signalArguments[1][1], false)
            compare(resultSpy.signalArguments[1][4], "read-timeout")
        }
    }
}
