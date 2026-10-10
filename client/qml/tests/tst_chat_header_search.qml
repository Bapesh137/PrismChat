import QtQuick
import QtTest
import "../components/chat"

Item {
    id: scene
    width: 650; height: 130
    Component {
        id: headerComponent
        ChatHeader {
            width: 430; height: 44
            roomId: "!fixture:test"
            roomName: "A room with a long name"
            searchVisible: true
        }
    }
    TestCase {
        name: "ChatHeaderSearch"
        when: windowShown
        function test_searchCoversEncryptionIcon_data() {
            return [{tag:"dark",surface:"#0b1710",text:"#f2fff4"},
                    {tag:"light",surface:"#f7f9fc",text:"#17202a"}]
        }
        function test_searchCoversEncryptionIcon(data) {
            var header = createTemporaryObject(headerComponent,scene,
                {surfaceColor:data.surface,textPrimary:data.text,roomEncryptionState:0})
            verify(header)
            waitForRendering(header)
            var unlocked = grabImage(header)
            header.roomEncryptionState = 1
            waitForRendering(header)
            var locked = grabImage(header)
            // This narrow header places the lock underneath the search. Its
            // changing colour must not change any pixel inside the search.
            var start = Math.ceil(header.searchFieldLeftX)+3
            var end = Math.floor(header.searchFieldRightX)-3
            for (var y=12;y<32;y++) for (var x=start;x<end;x++) {
                compare(locked.red(x,y),unlocked.red(x,y),"red at "+x+","+y)
                compare(locked.green(x,y),unlocked.green(x,y),"green at "+x+","+y)
                compare(locked.blue(x,y),unlocked.blue(x,y),"blue at "+x+","+y)
            }
        }
    }
}
