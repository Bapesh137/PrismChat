import QtQuick
import QtTest
import "../components/chat"
import "../utils" as L10n
Item {
    id: scene
    width: 650; height: 440
    ListModel { id: messages }
    Component {
        id: listComponent
        MessageList {
            width: 600; height: 360
            messageModel: messages
            currentUserId: "@me:test"
            readingAccountId: "account-a"
        }
    }
    TestCase {
        name: "ReadingPosition"
        when: windowShown
        function fill(latest) {
            messages.clear()
            for (var i=latest;i>0;i--)
                messages.append({ event_id: "$"+i, sender:"@other:test", body:"Message "+i+"\nSecond line\nThird line",
                    msg_type:"m.text", timestamp:i*60000, is_system:false,is_redacted:false,is_encrypted:false,
                    sender_is_ignored:false, sender_display_name:"Other", media_url:"" })
        }
        function init() { L10n.UiPreferences.animationsEnabled=false; fill(100) }
        function cleanup() { messages.clear(); L10n.UiPreferences.animationsEnabled=true }
        function createList() {
            var view=createTemporaryObject(listComponent,scene)
            verify(view)
            view.currentRoomId="!a:test"
            view.initialTimelineReady=true
            tryCompare(view,"initialPositionPending",false)
            return view
        }
        function test_restoresPartialMessageWithNewUnreadAndTwoStageJump() {
            var view=createList()
            view.followTail=false
            verify(view.placeEvent("$40",-23))
            tryCompare(view,"pendingAnchorEventId", "")
            view.captureViewport()
            var saved=JSON.parse(JSON.stringify(view.lastViewportState))
            verify(saved)
            compare(saved.event_id,"$40")
            verify(Math.abs(saved.offset+23)<1)
            view.initialTimelineReady=false
            view.currentRoomId="!b:test"
            fill(120)
            view.restorePosition=saved
            view.openingUnreadCount=20
            view.firstUnreadEventId="$101"
            view.currentRoomId="!a:test"
            view.initialTimelineReady=true
            tryCompare(view,"initialPositionPending",false)
            view.captureViewport()
            compare(view.lastViewportState.event_id,saved.event_id)
            verify(Math.abs(view.lastViewportState.offset-saved.offset)<1)
            compare(view.remainingUnreadCount,20)
            view.jumpDown()
            tryCompare(view,"pendingAnchorEventId", "")
            view.captureViewport()
            compare(view.lastViewportState.event_id,"$101")
            verify(view.remainingUnreadCount>0 && view.remainingUnreadCount<20)
            var firstRemaining=view.remainingUnreadCount
            view.placeEvent("$111",0); tryCompare(view,"pendingAnchorEventId", ""); view.captureViewport()
            verify(view.remainingUnreadCount<firstRemaining)
            var advanced=view.remainingUnreadCount
            view.placeEvent("$102",0); tryCompare(view,"pendingAnchorEventId", ""); view.captureViewport()
            compare(view.remainingUnreadCount,advanced)
            view.jumpDown(); wait(10); view.captureViewport()
            verify(view.atBottom())
            compare(view.remainingUnreadCount,0)
        }
        function test_savedBottomStillRestoresBeforeNewMessagesWithStaleServerCount() {
            var view=createList()
            view.captureViewport()
            var saved=JSON.parse(JSON.stringify(view.lastViewportState))
            verify(saved.at_bottom)
            view.initialTimelineReady=false; view.currentRoomId="!b:test"
            fill(120)
            view.restorePosition=saved; view.openingUnreadCount=0
            view.currentRoomId="!a:test"; view.initialTimelineReady=true
            tryCompare(view,"initialPositionPending",false)
            view.captureViewport()
            compare(view.lastViewportState.event_id,saved.event_id)
            verify(Math.abs(view.lastViewportState.offset-saved.offset)<1)
            verify(!view.atBottom())
        }
        function test_waitsForSavedAnchorInsteadOfJumpingToBottom() {
            var view=createTemporaryObject(listComponent,scene)
            view.restorePosition={event_id:"$40",offset:-11,at_bottom:false,read_event_id:"$100"}
            view.currentRoomId="!a:test"
            wait(180)
            compare(view.initialPositionPending,true)
            view.initialTimelineReady=true
            tryCompare(view,"initialPositionPending",false)
            view.captureViewport()
            compare(view.lastViewportState.event_id,"$40")
            verify(Math.abs(view.lastViewportState.offset+11)<1)
        }
        function test_inactiveWindowDoesNotAdvanceReading() {
            var view=createTemporaryObject(listComponent,scene)
            var readReports=0
            view.viewportRead.connect(function() { readReports++ })
            view.openingUnreadCount=20; view.firstUnreadEventId="$81"
            view.readingActive=false; view.currentRoomId="!a:test"; view.initialTimelineReady=true
            tryCompare(view,"initialPositionPending",false)
            wait(180)
            compare(view.remainingUnreadCount,20)
            compare(readReports,0)
            view.readingActive=true
            // Activation reports reading after the viewport/layout timer settles.
            // Exercise that path instead of forcing a read in the same JS turn.
            tryVerify(function() { return view.remainingUnreadCount<20 && readReports>0 },2000)
        }
    }
}
