import QtQuick
import QtTest
import "../components/chat"
import "../utils" as L10n

Item {
    id: scene
    width: 650; height: 600
    ListModel { id: messages }
    Component {
        id: listComponent
        MessageList {
            width: 600; height: 450
            messageModel: messages
            currentUserId: "@me:test"
            readingAccountId: "a"
            autoLoadImages: false
            autoLoadVideos: false
        }
    }
    TestCase {
        name: "TimelineStability"
        when: windowShown
        function message(i) {
            return { event_id: "$" + i, sender: "@other:test", sender_display_name: "Other",
                body: "Message " + i + "\nSecond line", msg_type: "m.text", timestamp: i * 60000,
                is_system: false, is_redacted: false, is_encrypted: false,
                sender_is_ignored: false, media_url: "" }
        }
        function fill(count) {
            messages.clear()
            for (var i = count; i > 0; --i) messages.append(message(i))
        }
        function init() { L10n.UiPreferences.animationsEnabled = true }
        function cleanup() { messages.clear() }
        function listOf(item) {
            if (typeof item.positionViewAtIndex === "function") return item
            for (var i = 0; i < item.children.length; ++i) {
                var result = listOf(item.children[i])
                if (result) return result
            }
            return null
        }
        function opened(count) {
            fill(count)
            var view = createTemporaryObject(listComponent, scene)
            verify(view)
            view.currentRoomId = "!a:test"
            view.initialTimelineReady = true
            tryCompare(view, "initialPositionPending", false)
            return view
        }
        function offset(view, eventId) {
            var list = listOf(view), row = list.itemAtIndex(view.indexOfEventId(eventId))
            verify(row !== null, "anchor delegate remains available")
            return row.y - list.contentY
        }
        function verifyBottom(view) {
            var list = listOf(view), newest = list.itemAtIndex(0)
            verify(newest !== null)
            verify(Math.abs(newest.y + newest.height - list.contentY - list.height) < 1,
                "newest message bottom=" + (newest.y + newest.height - list.contentY) + ", viewport=" + list.height)
        }
        function test_shortHistoryAtBottom_data() {
            return [{tag: "first message", count: 1}, {tag: "several messages", count: 3}]
        }
        function test_shortHistoryAtBottom(data) {
            var view = opened(data.count)
            verifyBottom(view)
            view.height = 560; wait(60); verifyBottom(view)
            view.width = 350; wait(60); verifyBottom(view)
        }
        function test_emptyRoomThenFirstMessage() {
            fill(0)
            var view = createTemporaryObject(listComponent, scene)
            view.currentRoomId = "!a:test"; view.showEmptyState = true; view.initialTimelineReady = true
            tryCompare(view, "initialPositionPending", false)
            view.showEmptyState = false; messages.insert(0, message(1))
            wait(80); verifyBottom(view)
        }
        function test_loadingDoesNotExposeWrongPosition() {
            fill(120)
            var view = createTemporaryObject(listComponent, scene)
            view.restorePosition = {event_id: "$40", offset: -12}
            view.currentRoomId = "!a:test"
            wait(100)
            var list = listOf(view)
            verify(list.opacity === 0 || !list.visible || list.parent.opacity === 0,
                "do not display arbitrary model position before restoring the saved message")
            compare(list.enabled, false)
            view.initialTimelineReady = true
            tryCompare(view, "initialPositionPending", false)
            compare(list.enabled, true)
            verify(Math.abs(offset(view, "$40") + 12) < 1)
        }
        function test_liveHeightChangesPreserveReadingAnchor() {
            var view = opened(120)
            verify(view.placeEvent("$70", -12))
            tryCompare(view, "pendingAnchorEventId", "")
            view.captureViewport()
            for (var pass = 0; pass < 5; ++pass) {
                for (var i = 46; i < 57; ++i)
                    messages.setProperty(i, "body", "Loaded " + pass + "\n" + "Long line\n".repeat(3 + pass))
                wait(35)
                verify(Math.abs(offset(view, "$70") + 12) < 1,
                    "height change shifted anchor to " + offset(view, "$70"))
            }
        }
        function test_tailSurvivesGrowingHistoryAndResize() {
            var view = opened(2)
            for (var i = 3; i < 30; ++i) {
                messages.insert(0, message(i))
                wait(20); verifyBottom(view)
            }
            view.height = 320; wait(40); verifyBottom(view)
            messages.setProperty(0, "body", "Expanded message\n".repeat(12))
            wait(40); verifyBottom(view)
        }
        function test_paginationAndNewMessagesKeepOldReadingPosition() {
            var view = opened(120)
            verify(view.placeEvent("$70", -12))
            tryCompare(view, "pendingAnchorEventId", "")
            for (var i = 121; i < 145; ++i) messages.insert(0, message(i))
            for (var j = 0; j > -60; --j) messages.append(message(j))
            wait(80)
            verify(Math.abs(offset(view, "$70") + 12) < 1)
            verify(!view.followTail)
        }
        function test_wheelContinuesAcrossRecycledRowsAndCanInterruptJump() {
            var view = opened(120), list = listOf(view)
            wait(80)
            for (var i = 0; i < 12; ++i) {
                var before = list.contentY
                mouseWheel(view, 300, 220, 0, 120)
                wait(20)
                verify(list.contentY < before - 20, "wheel " + i + ": " + before + " -> " + list.contentY
                    + ", origin=" + list.originY + ", height=" + list.contentHeight)
            }
            view.jumpDown(); wait(40)
            verify(!view.atBottom(), "jump must still be animated")
            mouseWheel(view, 300, 220, 0, 120); wait(30)
            var stopped = list.contentY
            wait(320)
            verify(Math.abs(list.contentY - stopped) < 1, "wheel cancels animated jump")
            verify(!view.followTail)
        }
        function test_searchJumpDoesNotRestorePreviousAnchorOnNextLayout() {
            var view = opened(120)
            verify(view.scrollToEvent("$40"))
            wait(50); view.captureViewport()
            var saved = JSON.parse(JSON.stringify(view.lastViewportState))
            messages.setProperty(80, "body", "Expanded search result\n".repeat(7))
            wait(60)
            verify(Math.abs(offset(view, saved.event_id) - saved.offset) < 1)
        }
        function test_animatedJumpFinishesAtTailAfterHeightChanges() {
            var view = opened(120)
            view.placeEvent("$40", -12); tryCompare(view, "pendingAnchorEventId", "")
            view.jumpDown(); wait(35)
            messages.setProperty(0, "body", "Live edit during scroll\n".repeat(8))
            wait(30)
            verify(!view.atBottom(), "height update must not skip the rest of the animation")
            // The last layout correction runs after the animation's final frame.
            // A busy VM may deliver that frame later than a fixed 320 ms wait.
            tryVerify(function() {
                var list=listOf(view), newest=list.itemAtIndex(0)
                return newest && Math.abs(newest.y+newest.height-list.contentY-list.height)<1
            },2000,"animated jump must finish at the actual newest message")
        }
        function test_shortenedHistoryKeepsFollowingNewMessages() {
            var view = opened(120)
            view.placeEvent("$115", -12); tryCompare(view, "pendingAnchorEventId", "")
            messages.remove(3, messages.count - 3)
            wait(60); verifyBottom(view)
            compare(view.followTail, true)
            for (var i = 121; i < 140; ++i) messages.insert(0, message(i))
            wait(60); verifyBottom(view)
        }
    }
}
