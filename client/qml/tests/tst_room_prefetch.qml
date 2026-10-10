import QtQuick
import QtTest
import "../services"

Item {
    id: scene
    Component {
        id: fixture
        MatrixConnection {
            id: connection
            transportAutoConnect: false
            roomModel: ListModel { dynamicRoles: true }
            authenticatedUserId: "@test:invalid"
            activeSessionEpoch: 1
            timelineDiffsSupported: true
            property var commands: []
            function sendCommand(command) {
                commands.push(command)
                registerPendingCommand(command)
                return true
            }
        }
    }
    TestCase {
        name: "RoomPrefetch"
        when: windowShown
        function transport(c) {
            for (var i = 0; i < c.children.length; ++i)
                if (typeof c.children[i].activeTransport === "string") return c.children[i]
            fail("missing transport")
        }
        function create(count) {
            var c = createTemporaryObject(fixture, scene)
            for (var i = 0; i < count; ++i) c.roomModel.append(c.normalizeRoom({room_id: "r" + i,
                last_event_id: "$" + i, last_timestamp: i}))
            transport(c).activeTransport = "fixture"
            c.scheduleRoomPreviewPrefetch()
            return c
        }
        function page(room, first, count) {
            var result = []
            for (var i = first; i > first-count; --i) result.push({event_id: room + "-" + i,
                body: "Message " + i, sender: "@other:invalid", timestamp: i})
            return result
        }
        function reply(c, command, messages, next, success) {
            transport(c).textMessageReceived(JSON.stringify({type: "timeline_preview_result",
                room_id: command.room_id, request_id: command.request_id,
                messages: messages || [], next_from: next || "", success: success !== false}))
        }
        function pump(c) { c.prefetchQueuedRoomPreviews() }
        function onlyPreviews(c) {
            return c.commands.filter(function(command) { return command.type === "get_timeline_preview" })
        }
        function test_startupPagesContinueThroughAllRoomsInOrder() {
            var c = create(60), done = 0
            pump(c)
            compare(onlyPreviews(c).length, 2)
            for (var step = 0; step < 60; ++step) {
                var commands = onlyPreviews(c), command = commands[done++]
                compare(command.room_id, "r" + step)
                compare(command.limit, c.initialRoomMessageCount)
                reply(c, command, page(command.room_id, 30, 30), "older-history")
                pump(c)
                verify(c.roomPreviewPrefetchInFlight <= 2)
            }
            compare(onlyPreviews(c).length, 60)
            compare(Object.keys(c.preparedRoomModels).length, 20)
            compare(c.preparedRoomModels.r19.count, 25)
            compare(c.roomPreviewCache.r59.length, 25)
            compare(c.messageModel.count, 0)
            verify(!c.preparedRoomModels.r20)
            c.scheduleRoomPreviewPrefetch(); pump(c)
            compare(onlyPreviews(c).length, 60)
            // A fully prepared model is adopted without replacing its rows.
            var model = c.preparedRoomModels.r19, inserts = 0, removes = 0
            model.rowsInserted.connect(function() { inserts++ })
            model.rowsRemoved.connect(function() { removes++ })
            c.currentRoomId = "r19"; c.requestMessages("r19")
            compare(c.messageModel, model)
            verify(c.timelineInitialPositionReady)
            compare(inserts, 0); compare(removes, 0)
            // Later rooms also open their lightweight page before the SDK reply.
            c.currentRoomId = "r59"; c.requestMessages("r59")
            compare(c.messageModel.count, 25)
            verify(c.timelineInitialPositionReady)
            compare(c.commands.filter(function(x) { return x.type.indexOf("mark_") === 0 }).length, 0)
        }
        function test_partialFirstPageIsVisibleAndOnlyRemainderIsRequested() {
            var c = create(1); pump(c)
            reply(c, onlyPreviews(c)[0], page("r0", 30, 1), "cursor-1"); pump(c)
            var commands = onlyPreviews(c)
            compare(commands.length, 2); compare(commands[1].from, "cursor-1")
            compare(commands[1].limit, 24)
            compare(c.preparedRoomModels.r0.count, 1)
            reply(c, commands[1], page("r0", 29, 24), "cursor-25"); pump(c)
            compare(c.preparedRoomModels.r0.count, 25)
            compare(c.preparedRoomModels.r0.get(0).event_id, "r0-30")
            compare(c.preparedRoomModels.r0.get(24).event_id, "r0-6")
            compare(onlyPreviews(c).length, 2)
        }
        function test_openUsesQueuedResultBeforeWaitingForLiveTimeline() {
            var c = create(2); pump(c)
            reply(c, onlyPreviews(c)[0], page("r0", 30, 4), "more")
            compare(c.roomPreviewPrefetchResults.length, 1)
            c.currentRoomId = "r0"; c.requestMessages("r0")
            compare(c.messageModel.count, 4)
            verify(c.showingCachedTimeline)
            verify(c.timelineInitialPositionReady)
            compare(c.timelineGeneration, 0)
            compare(c.roomPreviewPrefetchResults.length, 0)
        }
        function test_partialPageOpensWhileRestOfPageIsInFlight() {
            var c = create(1); pump(c)
            reply(c, onlyPreviews(c)[0], page("r0", 30, 3), "more"); pump(c)
            compare(c.roomPreviewPrefetchInFlight, 1)
            c.currentRoomId = "r0"; c.requestMessages("r0")
            compare(c.messageModel.count, 3)
            verify(c.timelineInitialPositionReady)
            compare(c.timelineGeneration, 0)
        }
        function test_newPinnedTopRoomIsPreparedFromExistingCache() {
            var c = create(25)
            c.roomPreviewCache.r24 = page("r24", 25, 25)
            c.roomPreviewPrefetchState.r24 = {complete:true,stamp:c.roomPrefetchStamp("r24"),updatedAt:Date.now()}
            c.pinnedRoomIds = ["r24"]; c.applyRoomOrder(); c.scheduleRoomPreviewPrefetch(); pump(c)
            compare(c.preparedRoomModels.r24.count,25)
            verify(onlyPreviews(c).every(function(command) { return command.room_id !== "r24" }))
        }
        function test_emptyAndShortRoomsDoNotLoop() {
            var c = create(2); pump(c)
            reply(c, onlyPreviews(c)[0], []); pump(c)
            reply(c, onlyPreviews(c)[1], page("r1", 3, 3)); pump(c)
            compare(c.preparedRoomModels.r0.count, 0)
            compare(c.preparedRoomModels.r1.count, 3)
            for (var i = 0; i < 5; ++i) { c.scheduleRoomPreviewPrefetch(); pump(c) }
            compare(onlyPreviews(c).length, 2)
        }
        function test_openChatPreemptsQueuedWorkAndDefersModelPreparation() {
            var c = create(5); pump(c)
            c.currentRoomId = "r4"; c.requestMessages("r4")
            verify(c.foregroundTimelineBusy)
            reply(c, onlyPreviews(c)[0], page("r0", 30, 30)); pump(c)
            compare(onlyPreviews(c).length, 2)
            verify(!c.preparedRoomModels.r0)
            c.applyTimelineSnapshot({room_id: "r4", session_epoch: 1, generation: 1,
                items: [], has_more_backwards: false, freshness: "live"})
            verify(!c.foregroundTimelineBusy)
            pump(c)
            compare(c.preparedRoomModels.r0.count, 25)
            compare(onlyPreviews(c)[2].room_id, "r2")
        }
        function test_lateBackgroundReplyCannotOverwriteOpenedRoom() {
            var c = create(1); pump(c)
            var command = onlyPreviews(c)[0]
            c.currentRoomId = "r0"; c.requestMessages("r0")
            c.applyTimelineSnapshot({room_id: "r0", session_epoch: 1, generation: 1,
                items: [{kind: "event", timeline_item_id: "fresh", message: page("r0", 40, 1)[0]}],
                has_more_backwards: false, freshness: "live"})
            reply(c, command, page("r0", 30, 30)); pump(c)
            compare(c.messageModel.count, 1)
            compare(c.messageModel.get(0).event_id, "r0-40")
        }
        function test_newMessagesReorderAndInvalidateOnlyChangedRoom() {
            var c = create(2); pump(c)
            reply(c, onlyPreviews(c)[0], page("r0", 30, 30)); pump(c)
            reply(c, onlyPreviews(c)[1], page("r1", 30, 30)); pump(c)
            c.roomModel.move(1, 0, 1)
            c.roomModel.setProperty(0, "last_event_id", "$new")
            c.scheduleRoomPreviewPrefetch(); pump(c)
            compare(onlyPreviews(c).length, 3)
            compare(onlyPreviews(c)[2].room_id, "r1")
            reply(c, onlyPreviews(c)[2], page("r1", 35, 30)); pump(c)
            compare(c.preparedRoomModels.r1.get(0).event_id, "r1-35")
            compare(c.preparedRoomModels.r1.count, 30)
            compare(c.preparedRoomModels.r0.count, 25)
        }
        function test_reorderHonorsPinsAndExcludesSpacesAndInvites() {
            var c = create(25)
            c.roomModel.setProperty(0, "is_space", true)
            c.roomModel.setProperty(1, "is_invited", true)
            c.pinnedRoomIds = ["r24"]
            c.applyRoomOrder(); c.scheduleRoomPreviewPrefetch(); pump(c)
            compare(onlyPreviews(c)[0].room_id, "r24")
            compare(onlyPreviews(c)[1].room_id, "r2")
            verify(c.roomPreviewPrefetchTargets.indexOf("r0") < 0)
            verify(c.roomPreviewPrefetchTargets.indexOf("r1") < 0)
            compare(c.roomPreviewPrefetchTargets.length, 20)
            verify(c.roomPreviewPrefetchQueue.indexOf("r23") >= 0)
        }
        function test_completedEvictedPagesDoNotRestartTheSweep() {
            var c = create(3); pump(c)
            reply(c,onlyPreviews(c)[0],page("r0",25,25)); pump(c)
            reply(c,onlyPreviews(c)[1],page("r1",25,25)); pump(c)
            reply(c,onlyPreviews(c)[2],page("r2",25,25)); pump(c)
            c.discardPreparedRoom("r0")
            delete c.roomMessageCache.r0
            delete c.roomPreviewCache.r0
            c.scheduleRoomPreviewPrefetch(); pump(c)
            compare(onlyPreviews(c).length,3)
        }
        function test_errorsAndNoProgressRetryWithBackoff() {
            var c = create(1); pump(c)
            reply(c, onlyPreviews(c)[0], [], "", false); pump(c)
            compare(onlyPreviews(c).length, 1)
            c.roomPreviewPrefetchState.r0.retryAfter = 0
            c.scheduleRoomPreviewPrefetch(); pump(c)
            compare(onlyPreviews(c).length, 2)
            reply(c, onlyPreviews(c)[1], [], "same"); pump(c)
            reply(c, onlyPreviews(c)[2], [], "same"); pump(c)
            compare(onlyPreviews(c).length, 3)
            verify(!c.roomPreviewPrefetchState.r0.complete)
            c.roomPreviewPrefetchState.r0.retryAfter = 0
            c.scheduleRoomPreviewPrefetch(); pump(c)
            compare(onlyPreviews(c).length, 4)
        }
        function test_accountResetDropsModelsAndRejectsLateResponses() {
            var c = create(3); pump(c)
            reply(c, onlyPreviews(c)[0], page("r0", 30, 30)); pump(c)
            var late = onlyPreviews(c)[1]
            c.resetMessageState()
            reply(c, late, page("r1", 30, 30))
            compare(Object.keys(c.preparedRoomModels).length, 0)
            compare(c.messageModel.count, 0)
            compare(c.roomPreviewPrefetchInFlight, 0)
            compare(c.roomPreviewPrefetchResults.length, 0)
        }
        function test_oldReadingWindowSurvivesNonOverlappingPrefetch() {
            var c = create(1)
            c.roomMessageCache.r0 = page("r0", 200, 200)
            var model = c.preparedModelForRoom("r0")
            c.preparePrefetchedRoom("r0", page("r0", 500, 30))
            compare(c.preparedRoomModels.r0, model)
            compare(model.count, 200)
            compare(model.get(199).event_id, "r0-1")
        }
        function test_retentionProtectsTwentyTargetsAndBoundsOtherRooms() {
            var c = create(25)
            for (var i = 0; i < 30; ++i) {
                c.roomMessageCache["r" + i] = page("r" + i, 30, 30)
                c.preparedModelForRoom("r" + i)
                c.touchMessageCacheRoom("r" + i)
            }
            c.currentRoomId = "r29"; c.requestMessages("r29")
            c.trimMessageCache("r29")
            compare(Object.keys(c.preparedRoomModels).length, 24)
            for (var j = 0; j < 20; ++j) verify(!!c.preparedRoomModels["r" + j])
            verify(!!c.preparedRoomModels.r29)
        }
    }
}
