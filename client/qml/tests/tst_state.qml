import QtQuick
import QtTest
import "../components/chat"

TestCase {
    id: testCase

    name: "RoomScopedState"
    when: windowShown

    ListModel {
        id: testMessages
    }

    Component {
        id: composerComponent

        MessageComposer {
            width: 420
            currentRoomId: "!first:example.org"
        }
    }

    Component {
        id: messageListComponent

        MessageList {
            width: 420
            height: 320
            currentRoomId: "!first:example.org"
            currentUserId: "@me:example.org"
            messageModel: testMessages
        }
    }

    function init() {
        testMessages.clear()
        testMessages.append({
            event_id: "$own",
            sender: "@me:example.org",
            body: "own",
            msg_type: "m.text",
            timestamp: 2,
            is_system: false,
            is_redacted: false
        })
        testMessages.append({
            event_id: "$other",
            sender: "@other:example.org",
            body: "other",
            msg_type: "m.text",
            timestamp: 1,
            is_system: false,
            is_redacted: false
        })
    }

    function cleanup() {
        testMessages.clear()
    }

    function test_roomChangeClearsComposerState() {
        var composer = createTemporaryObject(composerComponent, testCase)
        verify(composer)

        composer.startEditing("$own", "draft")
        compare(composer.editing, true)

        composer.currentRoomId = "!second:example.org"
        tryCompare(composer, "editing", false)
        compare(composer.replying, false)
    }

    function test_roomChangeClearsMessageSelection() {
        var messageList = createTemporaryObject(messageListComponent, testCase)
        verify(messageList)

        messageList.selectAll()
        compare(messageList.selectedCount, 2)

        messageList.currentRoomId = "!second:example.org"
        tryCompare(messageList, "selectedCount", 0)
    }

    function test_adminCapabilityControlsBatchDelete() {
        var messageList = createTemporaryObject(messageListComponent, testCase)
        verify(messageList)

        messageList.selectAll()
        compare(messageList.canDeleteSelection(), false)

        messageList.canRedactOther = true
        compare(messageList.canDeleteSelection(), true)
    }
    function appendSelectionMessages() {
        testMessages.append({
            event_id: "$third",
            sender: "@third:example.org",
            body: "third",
            msg_type: "m.text",
            timestamp: 0,
            is_system: false,
            is_redacted: false
        })
        testMessages.append({
            event_id: "$fourth",
            sender: "@fourth:example.org",
            body: "fourth",
            msg_type: "m.text",
            timestamp: -1,
            is_system: false,
            is_redacted: false
        })
    }

    function test_initialLeftDragSelectsEveryCrossedMessage() {
        appendSelectionMessages()
        var messageList = createTemporaryObject(messageListComponent, testCase)
        verify(messageList)

        verify(messageList.startSelectionGesture(0, false, Qt.LeftButton))
        compare(messageList.selectedCount, 0)

        messageList.continueSelectionGesture(1)
        compare(messageList.selectedCount, 2)
        verify(messageList.isSelected("$own"))
        verify(messageList.isSelected("$other"))

        messageList.continueSelectionGesture(3)
        compare(messageList.selectedCount, 4)
        verify(messageList.isSelected("$third"))
        verify(messageList.isSelected("$fourth"))
        messageList.finishSelectionGesture()
    }

    function test_addGestureIgnoresAlreadySelectedMessages() {
        appendSelectionMessages()
        var messageList = createTemporaryObject(messageListComponent, testCase)
        verify(messageList)

        messageList.applySelection({"$own": 0})
        verify(messageList.startSelectionGesture(1, false, Qt.LeftButton))
        compare(messageList.selectedCount, 2)

        messageList.continueSelectionGesture(0)
        messageList.continueSelectionGesture(2)
        compare(messageList.selectedCount, 3)
        verify(messageList.isSelected("$own"))
        verify(messageList.isSelected("$other"))
        verify(messageList.isSelected("$third"))
        messageList.finishSelectionGesture()
    }

    function test_removeGestureCanLeaveExactlyOneSelectedMessage() {
        appendSelectionMessages()
        var messageList = createTemporaryObject(messageListComponent, testCase)
        verify(messageList)

        messageList.applySelection({"$own": 0, "$other": 1, "$third": 2})
        verify(messageList.startSelectionGesture(0, true, Qt.LeftButton))
        messageList.continueSelectionGesture(1)
        messageList.finishSelectionGesture()

        compare(messageList.selectedCount, 1)
        verify(messageList.isSelected("$third"))
        verify(!messageList.isSelected("$own"))
        verify(!messageList.isSelected("$other"))
    }

    function test_leftDragFromSelectedRemovesOnlySelectedMessages() {
        appendSelectionMessages()
        var messageList = createTemporaryObject(messageListComponent, testCase)
        verify(messageList)

        messageList.applySelection({"$own": 0, "$third": 2})
        verify(messageList.startSelectionGesture(0, true, Qt.LeftButton))
        messageList.continueSelectionGesture(1)
        messageList.finishSelectionGesture()

        compare(messageList.selectedCount, 1)
        verify(messageList.isSelected("$third"))
        verify(!messageList.isSelected("$own"))
        verify(!messageList.isSelected("$other"))

        verify(!messageList.startSelectionGesture(1, false, Qt.RightButton))
        compare(messageList.selectedCount, 1)
    }

    function test_reversingAddDragShrinksSelectionRange() {
        appendSelectionMessages()
        var messageList = createTemporaryObject(messageListComponent, testCase)
        verify(messageList)

        // Bottom -> top selects four, then moving back down shrinks to two.
        verify(messageList.startSelectionGesture(0, false, Qt.LeftButton))
        messageList.continueSelectionGesture(3)
        compare(messageList.selectedCount, 4)

        messageList.continueSelectionGesture(1)
        compare(messageList.selectedCount, 2)
        verify(messageList.isSelected("$own"))
        verify(messageList.isSelected("$other"))
        verify(!messageList.isSelected("$third"))
        verify(!messageList.isSelected("$fourth"))
        messageList.finishSelectionGesture()
    }

    function test_reversingRemoveDragRestoresMessagesOutsideCurrentRange() {
        appendSelectionMessages()
        var messageList = createTemporaryObject(messageListComponent, testCase)
        verify(messageList)

        messageList.applySelection({"$own": 0, "$other": 1, "$third": 2, "$fourth": 3})
        verify(messageList.startSelectionGesture(3, true, Qt.LeftButton))
        messageList.continueSelectionGesture(1)
        compare(messageList.selectedCount, 1)
        verify(messageList.isSelected("$own"))

        // Move back upward: index 1 leaves the remove range and is restored.
        messageList.continueSelectionGesture(2)
        compare(messageList.selectedCount, 2)
        verify(messageList.isSelected("$own"))
        verify(messageList.isSelected("$other"))
        verify(!messageList.isSelected("$third"))
        verify(!messageList.isSelected("$fourth"))
        messageList.finishSelectionGesture()
    }

    function test_lmbModeDependsOnStartSelectionState() {
        var messageList = createTemporaryObject(messageListComponent, testCase)
        verify(messageList)

        messageList.applySelection({"$own": 0})
        verify(messageList.startSelectionGesture(0, true, Qt.LeftButton))
        compare(messageList.selectedCount, 0)
        messageList.finishSelectionGesture()

        messageList.applySelection({"$own": 0})
        verify(messageList.startSelectionGesture(1, false, Qt.LeftButton))
        compare(messageList.selectedCount, 2)
        messageList.finishSelectionGesture()

        verify(!messageList.startSelectionGesture(0, true, Qt.RightButton))
    }

}
