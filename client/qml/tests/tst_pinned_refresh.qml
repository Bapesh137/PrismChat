import QtQuick
import QtTest
import "../components/chat"

Item {
    id: scene
    width: 900; height: 650
    ListModel { id: emptyMessages }
    Component {
        id: viewComponent
        ChatView {
            width: 850; height: 600
            messageModel: emptyMessages
            currentRoomId: "!fixture:test"
            displayedRoomId: currentRoomId
            timelineInitialPositionReady: true
            showEmptyState: true
            autoLoadImages: false
            autoLoadVideos: false
        }
    }
    TestCase {
        name: "PinnedRefresh"
        when: windowShown
        function test_backgroundErrorsKeepPinsAndExplicitViewReportsErrors() {
            var view = createTemporaryObject(viewComponent,scene)
            verify(view)
            var feedback = []
            view.feedbackRequested.connect(function(text,error){feedback.push(text)})
            view.receivePinnedMessages("!fixture:test",[{event_id:"$pin",body:"Pinned message"}],"")
            view.receivePinnedMessages("!fixture:test",[],"fixture timeout")
            compare(feedback.length,0)
            compare(view.pinnedMessages.length,1)
            var header = null
            for (var i=0;i<view.children.length;i++) {
                var child = view.children[i]
                if (typeof child.pinnedRequested === "function") { header=child; break }
            }
            verify(header)
            header.pinnedRequested()
            view.receivePinnedMessages("!fixture:test",[],"fixture timeout")
            compare(feedback.length,1)
            compare(view.pinnedMessages[0].event_id,"$pin")
            view.receivePinnedMessages("!another:test",[],"old room timeout")
            compare(feedback.length,1)
            view.receivePinnedMessages("!fixture:test",[],"")
            compare(view.pinnedMessages.length,0)
        }
    }
}
