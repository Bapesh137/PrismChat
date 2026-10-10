import QtQuick
import QtTest
import "../services"
import "../components/navigation"

Item {
    id: scene
    width: 800
    height: 640

    Component {
        id: fixture
        Item {
            width: scene.width
            height: scene.height
            property alias connection: connection
            property alias list: roomList
            property alias sidebar: sidebar
            MatrixConnection {
                id: connection
                transportAutoConnect: false
                roomModel: ListModel { dynamicRoles: true }
            }
            RoomList {
                id: roomList
                width: 320
                height: parent.height
                roomModel: connection.roomModel
            }
            Sidebar {
                id: sidebar
                x: 340
                width: 320
                height: parent.height
                roomModel: connection.roomModel
                selectedSpaceId: roomList.selectedSpaceId
                showSpaceRoomsInHome: roomList.showSpaceRoomsInHome
                archivedRoomIds: roomList.archivedRoomIds
                archiveMode: roomList.archiveMode
            }
        }
    }

    TestCase {
        name: "RoomVisibility"
        when: windowShown

        function create() {
            var h = createTemporaryObject(fixture, scene)
            verify(h)
            var rooms = [
                { room_id: "!plain:test", name: "Plain room" },
                { room_id: "!language:test", name: "Language Exchange",
                  parent_space_ids: ["!unjoined:test"] },
                { room_id: "!matrix:test", name: "Matrix HQ",
                  parent_space_ids: ["!space:test", "!unjoined:test"] },
                { room_id: "!home:test", name: "Homelabbing",
                  parent_space_ids: ["!other:test"] },
                { room_id: "!space:test", name: "Joined space", is_space: true },
                { room_id: "!invite:test", name: "Invitation", room_state: "invited",
                  parent_space_ids: ["!unjoined:test"] }
            ]
            for (var i = 0; i < rooms.length; ++i)
                h.connection.roomModel.append(h.connection.normalizeRoom(rooms[i]))
            h.list.forceLayout()
            return h
        }

        function shown(h, index) {
            h.list.positionViewAtIndex(index, ListView.Contain)
            h.list.forceLayout()
            var row = h.list.itemAtIndex(index)
            verify(row !== null, "Missing room delegate at " + index)
            return row.visible && row.height > 0
        }

        function searchField(item) {
            if (typeof item.placeholderText === "string"
                    && typeof item.text === "string") return item
            var children = item.children || []
            for (var i = 0; i < children.length; ++i) {
                var result = searchField(children[i])
                if (result) return result
            }
            return null
        }

        function searchedRooms(h) {
            var field = searchField(h.sidebar)
            verify(field !== null)
            field.text = "hello"
            // Run the query now instead of racing the input debounce timer.
            h.sidebar.resetMessageSearch()
            h.sidebar.startMessageSearch()
            var ids = []
            while (h.sidebar.pendingMessageSearchCount > 0) {
                tryVerify(function() {
                    return Object.keys(h.sidebar.pendingMessageSearchRequests).length === 1
                })
                var requests = Object.keys(h.sidebar.pendingMessageSearchRequests)
                compare(requests.length, 1)
                var requestId = requests[0]
                var roomId = h.sidebar.pendingMessageSearchRequests[requestId].room_id
                ids.push(roomId)
                h.sidebar.receiveMessageSearchResults(roomId, [], "", requestId)
            }
            wait(0)
            return ids
        }

        function test_homeHidesRoomsFromJoinedSpacesByDefault() {
            var h = create()
            for (var i = 0; i < 6; ++i)
                compare(shown(h, i), i === 0 || i === 1 || i === 3 || i === 5)
            h.list.searchQuery = "language exchange"
            verify(shown(h, 1))
            verify(!shown(h, 0))
            h.list.searchQuery = "MATRIX HQ"
            verify(!shown(h, 2))
            h.list.searchQuery = "Homelabbing"
            verify(shown(h, 3))
        }

        function test_homeCanDuplicateRoomsFromSpaces() {
            var h = create()
            h.list.showSpaceRoomsInHome = true
            for (var i = 0; i < 6; ++i) compare(shown(h, i), i !== 4)
        }

        function test_spaceSelectionStillRestrictsRooms() {
            var h = create()
            h.list.selectedSpaceId = "!space:test"
            for (var i = 0; i < 6; ++i) compare(shown(h, i), i === 2)
            h.list.selectedSpaceId = "!other:test"
            verify(shown(h, 3))
            verify(!shown(h, 2))
            h.list.selectedSpaceId = ""
            verify(!shown(h, 2))
            verify(shown(h, 3))
            h.list.showSpaceRoomsInHome = true
            verify(shown(h, 2))
            verify(shown(h, 3))
        }

        function test_parentStateArrivingLaterUsesCurrentHomeMode() {
            var h = create()
            verify(shown(h, 0))
            h.connection.roomModel.setProperty(0, "parent_space_key", "!missing:test")
            verify(shown(h, 0))
            h.list.showSpaceRoomsInHome = true
            verify(shown(h, 0))
            h.connection.roomModel.append(h.connection.normalizeRoom({
                room_id: "!missing:test", name: "Later space", is_space: true }))
            verify(shown(h, 0))
            h.list.showSpaceRoomsInHome = false
            verify(!shown(h, 0))
            h.list.selectedSpaceId = "!missing:test"
            verify(shown(h, 0))
            h.connection.roomModel.setProperty(0, "parent_space_key", "")
            verify(!shown(h, 0))
            h.list.selectedSpaceId = ""
            verify(shown(h, 0))
        }

        function test_archiveRemainsSeparateAndIncludesSpaceRooms() {
            var h = create()
            h.list.archivedRoomIds = ["!language:test", "!matrix:test"]
            compare(h.list.archivedRoomCount, 2)
            verify(!shown(h, 1))
            verify(!shown(h, 2))
            h.list.archiveMode = true
            verify(shown(h, 1))
            verify(shown(h, 2))
            verify(!shown(h, 0))
            h.list.selectedSpaceId = "!space:test"
            compare(h.list.archivedRoomCount, 1)
            verify(!shown(h, 1))
            verify(shown(h, 2))
            h.list.archiveInSpaceRail = true
            verify(shown(h, 1))
            verify(shown(h, 2))
        }

        function test_messageSearchCoversAllHomeRoomsAndScopesSpaces() {
            var h = create()
            compare(searchedRooms(h).join(","),
                    "!plain:test,!language:test,!home:test,!invite:test")
            h.list.showSpaceRoomsInHome = true
            compare(searchedRooms(h).join(","),
                    "!plain:test,!language:test,!matrix:test,!home:test,!invite:test")
            h.list.selectedSpaceId = "!space:test"
            compare(searchedRooms(h).join(","), "!matrix:test")
            h.list.selectedSpaceId = ""
            h.list.archivedRoomIds = ["!language:test"]
            compare(searchedRooms(h).join(","),
                    "!plain:test,!matrix:test,!home:test,!invite:test")
            h.list.archiveMode = true
            h.sidebar.archiveMode = true
            compare(searchedRooms(h).join(","), "!language:test")
        }
    }
}
