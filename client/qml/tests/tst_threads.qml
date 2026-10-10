import QtQuick
import QtTest
import "../services"

Item {
    id: scene
    width: 640
    height: 480

    Component {
        id: connectionComponent
        MatrixConnection {
            transportAutoConnect: false
            roomModel: ListModel { dynamicRoles: true }
            messageModel: ListModel { dynamicRoles: true }
        }
    }

    TestCase {
        name: "Threads"

        function message(eventId, timestamp, threadRoot, replyCount) {
            return {
                event_id: eventId,
                sender: "@alice:test",
                body: eventId,
                msg_type: "m.text",
                timestamp: timestamp,
                thread_root_id: threadRoot || "",
                thread_reply_count: replyCount || 0,
                reactions: [],
                read_receipts: []
            }
        }

        function test_mainTimelineHidesThreadRepliesButPublishesMetadata() {
            var connection = createTemporaryObject(connectionComponent, scene)
            verify(connection)
            connection.timelineItems = [
                { kind: "event", timeline_item_id: "root", message: message("$root", 1, "", 1) },
                { kind: "event", timeline_item_id: "reply", message: message("$reply", 2, "$root", 0) }
            ]
            var main = connection.rebuildVisibleTimeline(false)
            compare(main.length, 1)
            compare(main[0].event_id, "$root")
            compare(main[0].thread_reply_count, 1)
            var all = connection.rebuildVisibleTimeline(true)
            compare(all.length, 2)
            compare(all[0].thread_root_id, "$root")
        }

        function test_sendFailureMetadataSurvivesNormalization() {
            var connection = createTemporaryObject(connectionComponent, scene)
            verify(connection)
            var normalized = connection.timelineItemMessage({
                kind: "event",
                timeline_item_id: "txn-1",
                send_state: "failed",
                send_error: "offline",
                send_recoverable: true,
                is_local_echo: true,
                message: message("local:txn-1", 3, "", 0)
            })
            compare(normalized.timeline_item_id, "txn-1")
            compare(normalized.send_state, "failed")
            compare(normalized.send_error, "offline")
            verify(normalized.send_recoverable)
        }

        function test_threadReceiptsPropagateToOlderOutgoingMessages() {
            var connection = createTemporaryObject(connectionComponent, scene)
            verify(connection)
            var newest = message("$new", 3, "$root", 0)
            newest.read_receipts = [{ user_id: "@bob:test", timestamp: 3 }]
            var older = message("$old", 2, "$root", 0)
            older.sender = "@me:test"
            var propagated = connection.propagateReadReceipts([newest, older])
            compare(propagated[1].read_receipts.length, 1)
            compare(propagated[1].read_receipts[0].user_id, "@bob:test")
        }
    }
}
