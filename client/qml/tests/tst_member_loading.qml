import QtQuick
import QtTest
import "../services"
import "../components/chat"
import "../utils" as L10n

Item {
    id: scene
    width: 300
    height: 640
    Component {
        id: fixture
        Item {
            id: h
            width: scene.width
            height: scene.height
            property alias connection: c
            property alias panel: panel
            property var cache: ({})
            MatrixConnection {
                id: c
                transportAutoConnect: false
                currentRoomId: "!large:test"
                activeSessionEpoch: 1
                property var commands: []
                function sendCommand(command) {
                    commands.push(command)
                    registerPendingCommand(command)
                    return true
                }
                onRoomMembersReceived: function(roomId, members, nextBatch, append, errorText) {
                    if (errorText !== "") return
                    var cache = Object.assign({}, h.cache)
                    cache[roomId] = append ? (cache[roomId] || []).concat(members) : members
                    h.cache = cache
                }
            }
            RoomMembersPanel {
                id: panel
                anchors.fill: parent
                currentRoomId: c.currentRoomId
                members: h.cache[currentRoomId] || []
                loading: !!c.roomMembersPaginationInFlight[currentRoomId]
                errorText: c.roomMembersErrors[currentRoomId] || ""
                onRetryRequested: c.requestRoomMembers(c.currentRoomId)
            }
        }
    }
    TestCase {
        name: "MemberLoading"
        when: windowShown

        function create() {
            var h = createTemporaryObject(fixture, scene)
            verify(h)
            return h
        }
        function transport(c) {
            for (var i = 0; i < c.children.length; ++i)
                if (typeof c.children[i].activeTransport === "string") return c.children[i]
            fail("Missing transport")
        }
        function page(first, count, room) {
            var result = []
            for (var i = first; i < first + count; ++i)
                result.push({user_id: "@" + (room || "user") + i + ":test",
                    display_name: "Member " + i, membership: "join", role: "user"})
            return result
        }
        function reply(c, command, members, next, error) {
            transport(c).textMessageReceived(JSON.stringify({type: "room_members_result",
                request_id: command.request_id, room_id: command.room_id,
                success: !error, error: error || "", members: members || [], next_batch: next || ""}))
        }
        function list(panel) {
            var children = panel.children
            for (var i = 0; i < children.length; ++i)
                for (var j = 0; j < children[i].children.length; ++j)
                    if (typeof children[i].children[j].positionViewAtIndex === "function")
                        return children[i].children[j]
            fail("Missing members ListView")
        }
        function test_largeRoomResponseSurvivesOrdinaryTimeout() {
            var h = create(), c = h.connection
            c.requestRoomMembers(c.currentRoomId)
            var command = c.commands[0]
            // Age the real pending request by 31 seconds; run the real expiry timer.
            c.pendingCommands[command.request_id].deadline -= 31000
            wait(1200)
            verify(c.roomMembersPaginationInFlight[c.currentRoomId])
            verify(c.pendingCommands[command.request_id] !== undefined)
            verify(h.panel.loading)
            verify(findChild(h.panel, "membersLoadingStatus").visible)
            reply(c, command, page(0, 100), "next-100")
            tryCompare(list(h.panel), "count", 100)
            verify(!h.panel.loading)
            verify(!findChild(h.panel, "membersLoadingStatus").visible)
            list(h.panel).forceLayout()
            compare(list(h.panel).itemAtIndex(0).memberData.user_id, "@user0:test")
        }
        function test_roomSwitchKeepsResultsWithTheirRoom() {
            var h = create(), c = h.connection
            c.requestRoomMembers(c.currentRoomId)
            c.currentRoomId = "!other:test"
            c.requestRoomMembers(c.currentRoomId)
            reply(c, c.commands[0], page(0, 100, "first"), "more-first")
            compare(list(h.panel).count, 0)
            verify(h.panel.loading)
            reply(c, c.commands[1], page(0, 25, "second"))
            compare(list(h.panel).count, 25)
            c.currentRoomId = "!large:test"
            compare(list(h.panel).count, 100)
            compare(h.panel.members[0].user_id, "@first0:test")
        }
        function test_failedRequestShowsRetryAndRejectsOldReply() {
            var h = create(), c = h.connection
            c.requestRoomMembers(c.currentRoomId)
            var old = c.commands[0]
            reply(c, old, [], "", "Network unavailable")
            verify(!h.panel.loading)
            compare(h.panel.errorText, "Network unavailable")
            var button = findChild(h.panel, "membersRetryButton")
            verify(button.visible)
            waitForRendering(h.panel)
            mouseClick(button, button.width / 2, button.height / 2)
            compare(c.commands.length, 2)
            verify(h.panel.loading)
            compare(h.panel.errorText, "")
            reply(c, old, page(0, 20, "stale"))
            compare(list(h.panel).count, 0)
            verify(h.panel.loading)
            reply(c, c.commands[1], page(0, 100), "next-100")
            compare(list(h.panel).count, 100)
        }
        function test_retryLabelFollowsInterfaceLanguage() {
            var h = create(), c = h.connection
            c.requestRoomMembers(c.currentRoomId)
            reply(c, c.commands[0], [], "", "Offline")
            var button = findChild(h.panel, "membersRetryButton")
            var previous = L10n.I18n.language
            try {
                L10n.I18n.setLanguage("en")
                compare(button.text, "Retry")
                L10n.I18n.setLanguage("ru")
                compare(button.text, "Повторить")
            } finally {
                L10n.I18n.setLanguage(previous)
            }
        }
        function test_refreshAndPaginationPreserveVisibleMembers() {
            var h = create(), c = h.connection
            c.requestRoomMembers(c.currentRoomId)
            reply(c, c.commands[0], page(0, 100), "next-100")
            c.requestOlderRoomMembers(c.currentRoomId)
            verify(h.panel.loading)
            compare(list(h.panel).count, 100)
            compare(c.commands[1].from, "next-100")
            reply(c, c.commands[1], page(100, 100), "next-200")
            compare(list(h.panel).count, 200)
            c.requestRoomMembers(c.currentRoomId)
            compare(list(h.panel).count, 200)
            reply(c, c.commands[2], [], "", "Offline")
            compare(list(h.panel).count, 200)
            compare(h.panel.errorText, "Offline")
        }
        function test_membershipBurstCoalescesAndResetDropsErrors() {
            var h = create(), c = h.connection
            c.requestRoomMembers(c.currentRoomId)
            for (var i = 0; i < 50; ++i) c.queueRoomMembersRefresh(c.currentRoomId)
            compare(c.commands.length, 1)
            reply(c, c.commands[0], page(0, 100), "next-100")
            tryCompare(c, "roomMembersRefreshTarget", "")
            tryVerify(function() { return c.commands.length === 2 })
            reply(c, c.commands[1], [], "", "Offline")
            compare(h.panel.errorText, "Offline")
            c.resetMessageState()
            compare(Object.keys(c.roomMembersErrors).length, 0)
            compare(Object.keys(c.roomMembersPaginationInFlight).length, 0)
        }
    }
}
