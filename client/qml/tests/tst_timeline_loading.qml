import QtQuick
import QtTest
import "../components/chat"
import "../services"

Item {
    id: scene
    width: 650; height: 600
    Component {
        id: fixture
        Item {
            id: harness
            width: 600; height: 450
            property string room: ""
            property var saved: ({})
            property alias connection: connection
            property alias view: view
            property alias messages: connection.messageModel
            property alias rooms: rooms
            property var reads: []
            ListModel { id: rooms; dynamicRoles: true }
            MatrixConnection {
                id: connection
                transportAutoConnect: false
                roomModel: rooms
                currentRoomId: harness.room
                activeSessionEpoch: 1
                timelineDiffsSupported: true
                authenticatedUserId: "@me:test"
                readingPositionResolver: function(room) { return harness.saved[room] || null }
                property var commands: []
                function sendCommand(command) {
                    commands.push(command)
                    registerPendingCommand(command)
                    return true
                }
            }
            MessageList {
                id: view
                anchors.fill: parent
                messageModel: connection.messageModel
                readingAccountId: "a"
                currentUserId: connection.authenticatedUserId
                currentRoomId: harness.room
                displayedRoomId: connection.displayedRoomId
                restorePosition: connection.readingRestorePosition
                firstUnreadEventId: connection.unreadBoundaryEventId
                openingUnreadCount: connection.openingUnreadCount
                unreadBoundaryPending: connection.unreadBoundaryPending
                initialTimelineReady: connection.timelineInitialPositionReady
                cachedTimeline: connection.showingCachedTimeline
                isLoadingMessages: connection.isLoadingMessages
                showEmptyState: connection.showEmptyState
                autoLoadImages: false
                autoLoadVideos: false
                onViewportSaved: function(account, room, position) { harness.saved[room] = position }
                onViewportRead: function(room, eventId, remaining) {
                    harness.reads.push({room:room,event:eventId,remaining:remaining})
                    connection.markVisibleMessagesRead(room,eventId,remaining)
                }
            }
        }
    }
    TestCase {
        name: "TimelineLoading"
        when: windowShown
        function create() { return createTemporaryObject(fixture, scene) }
        function open(h, room) { h.room = room; h.connection.requestMessages(room) }
        function items(room, count) {
            var result = []
            for (var i = 1; i <= count; ++i) result.push({kind: "event", timeline_item_id: room + i,
                message: {event_id: room + i, body: "Message " + i + "\nSecond line", timestamp: i * 60000,
                    sender: "@other:test", msg_type: "m.text"}})
            return result
        }
        function snapshot(h, count, more, freshness) {
            h.connection.applyTimelineSnapshot({room_id: h.room,
                request_id: h.connection.timelineRequestByRoom[h.room],
                session_epoch: 1, generation: 1, items: items(h.room, count),
                has_more_backwards: !!more, freshness: freshness || "live"})
        }
        function transport(h) {
            for (var i = 0; i < h.connection.children.length; ++i) {
                var child = h.connection.children[i]
                if (typeof child.activeTransport === "string") return child
            }
            fail("missing transport")
        }
        function test_cachedRoomsKeepTheirOwnDelegateContentDuringBackgroundUpdates() {
            var h = create()
            function listIn(item) {
                if (typeof item.itemAtIndex === "function") return item
                for (var i = 0; i < item.children.length; ++i) {
                    var result = listIn(item.children[i]); if (result) return result
                }
                return null
            }
            var list = listIn(h.view)
            function page(room, count) {
                var rows = items(room, count)
                for (var i = 0; i < rows.length; ++i) {
                    rows[i].message.body = room + ":" + i + " " + "abcdefgh ".repeat(i % 15 + 1)
                    rows[i].message.sender = "@" + room + ":test"
                    rows[i].message.sender_display_name = "Sender " + room
                    rows[i].message.reply_body = i % 3 === 0 ? "Reply " + room : ""
                }
                return rows
            }
            function fresh(room, count) {
                h.connection.applyTimelineSnapshot({room_id: room,
                    request_id: h.connection.timelineRequestByRoom[room],
                    session_epoch: 1, generation: 1, items: page(room,count),
                    has_more_backwards: false, freshness: "live"})
            }
            for (var i = 0; i < 24; ++i) {
                var room = "room" + i
                h.connection.roomMessageCache[room] = page(room, i % 3 === 0 ? 3 : 50)
                    .reverse().map(function(item) { return h.connection.normalizeMessage(item.message) })
                h.connection.preparedModelForRoom(room)
            }
            for (var step = 0; step < 70; ++step) {
                var current = "room" + (step * 7 % 24)
                open(h, current)
                tryCompare(h.view, "positionReady", true)
                fresh(current, step % 3 === 0 ? 3 : 50)
                var other = "room" + ((step * 7 + 1) % 24)
                h.connection.preparePrefetchedRoom(other, page(other, 50).reverse()
                    .map(function(item) { return h.connection.normalizeMessage(item.message) }))
                wait(25)
                for (var rowIndex = 0; rowIndex < h.messages.count; ++rowIndex) {
                    var expected = h.messages.get(rowIndex), row = list.itemAtIndex(rowIndex)
                    verify(String(expected.event_id).indexOf(current) === 0, "wrong room in model")
                    if (!row || row.pooled) continue
                    compare(row.eventId, expected.event_id, "event on switch " + step)
                    compare(row.sender, expected.sender, "sender on switch " + step)
                    compare(row.body, expected.body, "body on switch " + step)
                    compare(row.replyBody, expected.reply_body, "reply on switch " + step)
                }
            }
        }
        function test_switchReusesPreparedModelAndRetainsDeepSavedAnchor() {
            var h = create()
            open(h, "a"); snapshot(h, 500)
            tryCompare(h.view, "initialPositionPending", false)
            h.view.placeEvent("a50", -17)
            tryCompare(h.view, "pendingAnchorEventId", "")
            h.view.captureViewport()
            var prepared = h.messages
            open(h, "b"); snapshot(h, 3)
            tryCompare(h.view, "initialPositionPending", false)
            compare(prepared.count, 200)
            verify(h.connection.roomMessageCache.a.some(function(row) { return row.event_id === "a50" }))
            var inserted = 0, removed = 0
            prepared.rowsInserted.connect(function() { inserted++ })
            prepared.rowsRemoved.connect(function() { removed++ })
            open(h, "a")
            compare(h.messages, prepared)
            tryCompare(h.view, "positionReady", true)
            assertAnchor(h, "a50", -17)
            compare(inserted, 0); compare(removed, 0)
        }
        function test_repeatedClicksDuringOpenDoNotResetRequestOrCache() {
            var h = create()
            open(h, "a"); snapshot(h, 100)
            tryCompare(h.view, "initialPositionPending", false)
            open(h, "b"); snapshot(h, 5)
            tryCompare(h.view, "initialPositionPending", false)
            open(h, "a")
            var request = h.connection.timelineRequestByRoom.a
            var sequence = h.connection.timelineOpenSequence
            for (var i = 0; i < 6; ++i) h.connection.requestMessages("a")
            compare(h.connection.timelineRequestByRoom.a, request)
            compare(h.connection.timelineOpenSequence, sequence)
            compare(h.messages.count, 100)
        }
        function test_switchRoomsCacheThenFreshSnapshotRestoresAnchor() {
            var h = create()
            open(h, "a"); snapshot(h, 100)
            tryCompare(h.view, "initialPositionPending", false)
            h.view.placeEvent("a40", -17); tryCompare(h.view, "pendingAnchorEventId", "")
            h.view.captureViewport()
            for (var pass = 0; pass < 4; ++pass) {
                open(h, "b"); snapshot(h, 3)
                tryCompare(h.view, "initialPositionPending", false)
                open(h, "a")
                tryCompare(h.view,"positionReady",true)
                compare(h.connection.timelineGeneration,0)
                h.view.captureViewport()
                compare(h.view.lastViewportState.event_id,"a40")
                verify(Math.abs(h.view.lastViewportState.offset+17)<1)
                snapshot(h, 100 + pass * 5)
                tryCompare(h.view, "initialPositionPending", false)
                h.view.captureViewport()
                compare(h.view.lastViewportState.event_id, "a40")
                verify(Math.abs(h.view.lastViewportState.offset + 17) < 1)
                compare(h.view.followTail, false)
            }
        }
        function rangeSnapshot(h, first, last, more) {
            h.connection.applyTimelineSnapshot({room_id:h.room,
                request_id:h.connection.timelineRequestByRoom[h.room],session_epoch:1,generation:1,
                items:items(h.room,last).slice(first-1),has_more_backwards:more,freshness:"live"})
        }
        function assertAnchor(h,event,offset) {
            h.view.captureViewport()
            compare(h.view.lastViewportState.event_id,event)
            verify(Math.abs(h.view.lastViewportState.offset-offset)<1)
        }
        function test_partialSnapshotKeepsVisibleCacheAndStableDelegates() {
            var h=create();open(h,"a");snapshot(h,100)
            tryCompare(h.view,"positionReady",true)
            h.view.placeEvent("a40",-17);tryCompare(h.view,"pendingAnchorEventId","")
            open(h,"b");snapshot(h,3);tryCompare(h.view,"positionReady",true)
            open(h,"a");tryCompare(h.view,"positionReady",true)
            rangeSnapshot(h,91,120,true)
            wait(100)
            compare(h.messages.count,120)
            compare(h.connection.showingCachedTimeline,false)
            compare(h.view.positionReady,true)
            assertAnchor(h,"a40",-17)
            var changed=0
            h.messages.dataChanged.connect(function() { changed++ })
            rangeSnapshot(h,91,120,true);wait(80)
            compare(changed,0,"identical snapshot must not reset message roles")
            assertAnchor(h,"a40",-17)
        }
        function test_cacheReadinessDoesNotReadMessagesBeforeRefresh() {
            var h=create();open(h,"a");snapshot(h,100)
            tryCompare(h.view,"positionReady",true)
            h.view.captureViewport()
            var saved=JSON.parse(JSON.stringify(h.view.lastViewportState))
            open(h,"b");snapshot(h,3);tryCompare(h.view,"positionReady",true)
            h.rooms.append({room_id:"a",unread_count:20})
            open(h,"a");tryCompare(h.view,"positionReady",true)
            var before=h.reads.length
            wait(250)
            compare(h.reads.length,before)
            compare(h.view.remainingUnreadCount,20)
            assertAnchor(h,saved.event_id,saved.offset)
            snapshot(h,120);wait(120)
            assertAnchor(h,saved.event_id,saved.offset)
            compare(h.view.remainingUnreadCount,20)
            verify(!h.view.atBottom())
            h.view.jumpDown();tryCompare(h.view,"pendingAnchorEventId","")
            wait(150)
            verify(h.view.remainingUnreadCount>0 && h.view.remainingUnreadCount<20)
            h.view.jumpDown();tryVerify(function() {return h.view.atBottom()},2000)
            tryCompare(h.view,"remainingUnreadCount",0)
        }
        function test_cachedRowsStayVisibleWhileOlderSavedAnchorLoads() {
            var h = create()
            h.saved = {a:{event_id:"a40",offset:-17,read_event_id:"a35"}}
            h.rooms.append({room_id:"a",unread_count:20})
            h.connection.roomMessageCache.a = items("a",100).reverse().slice(0,25)
                .map(function(item) { return h.connection.normalizeMessage(item.message) })
            open(h,"a")
            compare(h.connection.timelineInitialPositionReady,false)
            tryCompare(h.view,"initialCacheVisible",true)
            function listIn(item) {
                if (typeof item.itemAtIndex === "function") return item
                for (var i=0; i<item.children.length; ++i) {
                    var list=listIn(item.children[i]); if(list) return list
                }
                return null
            }
            var list=listIn(h.view)
            compare(list.opacity,1)
            compare(h.messages.count,25)
            compare(h.reads.length,0)
            // A fresh partial snapshot must not turn the cached page blank.
            rangeSnapshot(h,96,100,true)
            wait(150)
            verify(h.view.initialCacheVisible)
            compare(list.opacity,1)
            compare(h.saved.a.event_id,"a40")
            compare(h.saved.a.offset,-17)
            compare(h.reads.length,0)
            rangeSnapshot(h,1,100,false)
            tryCompare(h.view,"positionReady",true)
            compare(h.view.initialCacheVisible,false)
            assertAnchor(h,"a40",-17)
        }
        function test_uncachedFirstMessagesDisplayBeforeUnreadHistoryIsComplete() {
            var h=create();h.rooms.append({room_id:"a",unread_count:80})
            open(h,"a");rangeSnapshot(h,96,100,true)
            compare(h.connection.unreadBoundaryPending,true)
            tryCompare(h.view,"positionReady",true)
            compare(h.messages.count,5)
            compare(h.view.remainingUnreadCount,80)
            compare(h.reads.length,0)
        }
        function test_disconnectedCacheRangeStaysVisibleUntilGapIsFilled() {
            var h=create();open(h,"a");snapshot(h,100)
            tryCompare(h.view,"positionReady",true)
            h.view.placeEvent("a40",-17);tryCompare(h.view,"pendingAnchorEventId","")
            open(h,"b");snapshot(h,3);tryCompare(h.view,"positionReady",true)
            open(h,"a");tryCompare(h.view,"positionReady",true)
            rangeSnapshot(h,150,175,true);wait(100)
            compare(h.connection.timelineCacheGapPending,true)
            compare(h.connection.showingCachedTimeline,true)
            compare(h.connection.timelineInitialFillActive,true)
            compare(h.messages.count,100)
            assertAnchor(h,"a40",-17)
            rangeSnapshot(h,91,175,true);wait(100)
            compare(h.connection.timelineCacheGapPending,false)
            compare(h.connection.showingCachedTimeline,false)
            compare(h.messages.count,175)
            assertAnchor(h,"a40",-17)
        }
        function test_earlyJumpWaitsForActualUnreadBoundaryInsteadOfCachedCount() {
            var h=create();open(h,"a");snapshot(h,100)
            tryCompare(h.view,"positionReady",true)
            h.view.placeEvent("a40",-17);tryCompare(h.view,"pendingAnchorEventId","")
            open(h,"b");snapshot(h,3);tryCompare(h.view,"positionReady",true)
            h.rooms.append({room_id:"a",unread_count:20})
            open(h,"a");tryCompare(h.view,"positionReady",true)
            snapshot(h,0,true);wait(80)
            compare(h.connection.unreadBoundaryPending,true)
            compare(h.connection.unreadBoundaryEventId,"")
            h.view.jumpDown();compare(h.view.pendingJumpDown,true)
            assertAnchor(h,"a40",-17)
            rangeSnapshot(h,91,120,true)
            tryCompare(h.view,"pendingJumpDown",false)
            tryCompare(h.view,"pendingAnchorEventId","")
            compare(h.connection.unreadBoundaryEventId,"a101")
            assertAnchor(h,"a101",0)
            h.view.jumpDown();tryVerify(function(){return h.view.atBottom()},2000)
        }
        function cachedAtOldPosition() {
            var h = create()
            h.saved = {a:{event_id:"a40",offset:-17,read_event_id:"a100"}}
            h.connection.roomMessageCache.a = items("a",100).reverse()
                .map(function(item) { return h.connection.normalizeMessage(item.message) })
            open(h,"a")
            tryCompare(h.view,"positionReady",true)
            assertAnchor(h,"a40",-17)
            return h
        }
        function test_downButtonScrollsCachedMessagesBeforeNetworkRefresh() {
            var h = cachedAtOldPosition()
            compare(h.connection.showingCachedTimeline,true)
            compare(h.connection.unreadBoundaryPending,false)
            // Click the real control, including its hit area and animation.
            wait(180)
            mouseClick(h.view,h.view.width-45,h.view.height-39)
            tryVerify(function(){return h.view.atBottom()},2000)
            compare(h.view.pendingJumpDown,false)
            compare(h.reads.length,0)
            compare(h.connection.showingCachedTimeline,true)
        }
        function test_queuedDownResumesAfterInitialAnchorFinishes() {
            var h = create()
            h.saved = {a:{event_id:"a40",offset:-17,read_event_id:"a100"}}
            h.rooms.append({room_id:"a",unread_count:20})
            h.connection.roomMessageCache.a = items("a",100).reverse()
                .map(function(item) { return h.connection.normalizeMessage(item.message) })
            open(h,"a")
            h.view.positionInitialView()
            verify(h.view.initialPositionPending)
            h.view.jumpDown()
            compare(h.view.pendingJumpDown,true)
            // The reply arrives while the initial anchor timer is still active.
            snapshot(h,120)
            tryCompare(h.view,"pendingJumpDown",false)
            tryCompare(h.view,"pendingAnchorEventId","")
            assertAnchor(h,"a101",0)
            h.view.jumpDown()
            tryVerify(function(){return h.view.atBottom()},2000)
        }
        function test_downAfterOpenTimeoutStillScrollsCacheWithoutReadReceipts() {
            var h = cachedAtOldPosition()
            var request = h.connection.takePendingCommand(h.connection.timelineRequestByRoom.a)
            h.connection.handleCommandFailure(request,"fixture timeout")
            h.view.jumpDown()
            tryVerify(function(){return h.view.atBottom()},2000)
            compare(h.reads.length,0)
            compare(h.connection.showingCachedTimeline,true)
        }
        function test_reopenedSdkIdsReuseExistingEventRows() {
            var h=create();open(h,"a");snapshot(h,100)
            tryCompare(h.view,"positionReady",true)
            var added=0,removed=0
            h.messages.rowsInserted.connect(function(){added++})
            h.messages.rowsRemoved.connect(function(){removed++})
            var next=items("a",100)
            for(var i=0;i<next.length;++i) next[i].timeline_item_id="new-sdk-"+i
            h.connection.applyTimelineSnapshot({room_id:"a",request_id:h.connection.timelineRequestByRoom.a,
                session_epoch:1,generation:2,items:next,has_more_backwards:false,freshness:"live"})
            compare(added,0);compare(removed,0)
        }
        function test_staleSdkSnapshotDoesNotUseOldMessagesAsNewUnread() {
            var h=create();open(h,"a");snapshot(h,100)
            tryCompare(h.view,"positionReady",true)
            h.view.captureViewport()
            open(h,"b");snapshot(h,3);tryCompare(h.view,"positionReady",true)
            h.rooms.append({room_id:"a",unread_count:20})
            open(h,"a");tryCompare(h.view,"positionReady",true)
            snapshot(h,100,true,"catching_up");wait(180)
            compare(h.view.positionReady,true)
            compare(h.connection.showingCachedTimeline,true)
            compare(h.connection.unreadBoundaryPending,true)
            compare(h.connection.unreadBoundaryEventId,"")
            compare(h.view.remainingUnreadCount,20)
            snapshot(h,120,true,"live");wait(150)
            compare(h.connection.showingCachedTimeline,false)
            compare(h.connection.unreadBoundaryEventId,"a101")
            compare(h.view.remainingUnreadCount,20)
        }
        function listInView(item) {
            if (typeof item.itemAtIndex === "function") return item
            for (var i=0;i<item.children.length;i++) {
                var found=listInView(item.children[i])
                if(found) return found
            }
            return null
        }
        function finishPage(h,more,freshness) {
            tryVerify(function(){return h.connection.timelinePaginationInFlight})
            transport(h).textMessageReceived(JSON.stringify({type:"timeline_status",room_id:h.room,
                request_id:h.connection.timelinePaginationRequestId,session_epoch:1,generation:1,
                paginating_backwards:false,has_more_backwards:more,freshness:freshness||"live"}))
        }
        function unreadCachedRoom() {
            var h=create()
            h.saved={a:{event_id:"a40",offset:-17,read_event_id:"a100"}}
            h.rooms.append({room_id:"a",unread_count:20})
            h.connection.roomMessageCache.a=items("a",100).reverse()
                .map(function(item){return h.connection.normalizeMessage(item.message)})
            open(h,"a");tryCompare(h.view,"positionReady",true)
            return h
        }
        function test_livePageStatusResolvesCachedUnreadAndQueuedJumpWithoutDiff() {
            var h=unreadCachedRoom()
            snapshot(h,120,true,"catching_up")
            h.view.jumpDown();compare(h.view.pendingJumpDown,true)
            compare(h.reads.length,0)
            finishPage(h,true,"live")
            compare(h.connection.showingCachedTimeline,false)
            compare(h.connection.unreadBoundaryPending,false)
            compare(h.connection.unreadBoundaryEventId,"a101")
            tryCompare(h.view,"pendingJumpDown",false)
            tryCompare(h.view,"pendingAnchorEventId","")
            assertAnchor(h,"a101",0)
            var dividerRow=listInView(h.view).itemAtIndex(h.view.indexOfEventId("a101"))
            verify(dividerRow && dividerRow.unreadDivider,"new-message divider is displayed")
            h.view.jumpDown();tryVerify(function(){return h.view.atBottom()},2000)
            tryCompare(h.view,"remainingUnreadCount",0)
            tryVerify(function(){return h.connection.roomUnreadCount("a")===0})
        }
        function test_historyEndStatusResolvesOversizedUnreadCountWithoutDiff() {
            var h=create();h.rooms.append({room_id:"a",unread_count:80})
            h.view.readingActive=false
            open(h,"a");snapshot(h,25,true)
            tryCompare(h.view,"positionReady",true)
            compare(h.connection.unreadBoundaryPending,true)
            h.view.jumpDown();compare(h.view.pendingJumpDown,true)
            finishPage(h,false,"live")
            compare(h.connection.unreadBoundaryPending,false)
            compare(h.connection.unreadBoundaryEventId,"a1")
            tryCompare(h.view,"pendingJumpDown",false)
            h.view.readingActive=true
            tryVerify(function(){return h.connection.roomUnreadCount("a")===0})
            compare(h.view.remainingUnreadCount,0)
        }
        function test_syncLiveBeforeSnapshotIsRememberedForTheSession() {
            var h=unreadCachedRoom()
            transport(h).textMessageReceived(JSON.stringify({type:"sync_freshness_changed",session_epoch:1,freshness:"live"}))
            // This notification precedes the room snapshot; cached data is
            // still protected until the matching snapshot actually arrives.
            compare(h.connection.showingCachedTimeline,true)
            compare(h.reads.length,0)
            snapshot(h,120,true,"catching_up")
            compare(h.connection.timelineFreshness,"live")
            compare(h.connection.showingCachedTimeline,false)
            compare(h.connection.unreadBoundaryEventId,"a101")
        }
        function test_slowPageCannotRegressLiveSyncAndOldSessionCannotUnlockCache() {
            var h=unreadCachedRoom()
            snapshot(h,120,true,"catching_up")
            tryVerify(function(){return h.connection.timelinePaginationInFlight})
            transport(h).textMessageReceived(JSON.stringify({type:"sync_freshness_changed",session_epoch:9,freshness:"live"}))
            compare(h.connection.showingCachedTimeline,true)
            transport(h).textMessageReceived(JSON.stringify({type:"sync_freshness_changed",session_epoch:1,freshness:"live"}))
            compare(h.connection.showingCachedTimeline,false)
            finishPage(h,true,"catching_up")
            compare(h.connection.timelineFreshness,"live")
            compare(h.connection.unreadBoundaryPending,false)
            compare(h.connection.unreadBoundaryEventId,"a101")
        }
        function test_firstLiveMessageClearsEmptyState() {
            var h = create(); open(h, "a"); snapshot(h, 0)
            compare(h.connection.showEmptyState, true)
            h.connection.applyTimelineDiffs({room_id: "a", session_epoch: 1, generation: 1,
                diffs: [{op: "push_back", item: items("a", 1)[0]}]})
            compare(h.connection.showEmptyState, false)
            compare(h.connection.isLoadingMessages, false)
            tryCompare(h.view, "initialPositionPending", false)
        }
        function test_syncCompletionStopsEmptyLoadingIndicator() {
            var h = create(); open(h, "a"); snapshot(h, 0, false, "catching_up")
            compare(h.connection.isLoadingMessages, true)
            transport(h).textMessageReceived(JSON.stringify({type: "sync_freshness_changed", session_epoch: 1, freshness: "live"}))
            compare(h.connection.isLoadingMessages, false)
            compare(h.connection.showEmptyState, true)
            tryCompare(h.view, "initialPositionPending", false)
        }
        function test_openFailureReleasesInitialPositionWaitAndAllowsRetry() {
            var h = create(); open(h, "a")
            var request = h.connection.timelineRequestByRoom.a
            transport(h).textMessageReceived(JSON.stringify({type: "timeline_status", room_id: "a",
                request_id: request, session_epoch: 1, request_generation: h.connection.timelineOpenSequence,
                error: "test server unavailable"}))
            compare(h.connection.isLoadingMessages, false)
            tryCompare(h.view, "initialPositionPending", false)
            h.connection.requestMessages("a")
            verify(h.connection.timelineRequestByRoom.a !== request)
        }
    }
}
