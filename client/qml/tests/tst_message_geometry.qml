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
            width: 600; height: 500
            messageModel: messages
            currentUserId: "@me:test"
            readingAccountId: "a"
            autoLoadImages: false
            autoLoadVideos: false
        }
    }
    TestCase {
        name: "MessageGeometry"
        when: windowShown
        function fill() {
            messages.clear()
            for (var i=199;i>=0;i--) {
                var body = i%4===0 ? "Mornin’" : i%4===1 ? "He shared a screenshot"
                    : i%4===2 ? "https://www.parrotkindergartendoc.com/ apparently they taught parrots to video call and they made friends with other parrots."
                    : "A longer message\nwith several lines\nand one more line"
                messages.append({event_id:"$"+i,sender:"@user"+(i%3)+":test",sender_display_name:"User "+(i%3),
                    body:body,msg_type:"m.text",timestamp:i*60000,is_system:false,is_redacted:false,is_encrypted:false,
                    sender_is_ignored:false,media_url:""})
            }
        }
        function init() { L10n.UiPreferences.animationsEnabled=false; fill() }
        function cleanup() { messages.clear(); L10n.UiPreferences.animationsEnabled=true }
        function findList(item) {
            if (typeof item.positionViewAtIndex === "function") return item
            for (var i=0;i<item.children.length;i++) { var found=findList(item.children[i]); if(found) return found }
            return null
        }
        function checkLayout(view) {
            var list=findList(view)
            verify(list)
            var seen=0
            for (var i=0;i<messages.count;i++) {
                var row=list.itemAtIndex(i)
                if(!row || !row.visible || row.y+row.height<list.contentY || row.y>list.contentY+list.height) continue
                seen++
                var column=null
                for(var j=0;j<row.children.length;j++) if(row.children[j].spacing===3) column=row.children[j]
                verify(column!==null)
                for(var a=0;a<row.children.length;a++) {
                    var avatar=row.children[a]
                    if(avatar.size===36 && avatar.visible)
                        verify(avatar.y+avatar.height <= row.height+0.5,"avatar exceeds row: "+row.eventId+" row="+row.height+" avatar bottom="+(avatar.y+avatar.height))
                }
                verify(row.height+0.5 >= column.y+column.height, "row too short: "+row.eventId+" height="+row.height+" content="+(column.y+column.height))
                for(var c=0;c<column.children.length;c++) {
                    var part=column.children[c]
                    if(!part.visible) continue
                    if(typeof part.contentHeight === "number") verify(part.contentHeight <= part.height+0.5,
                        "text exceeds measured height: "+row.eventId+" height="+part.height+" contentHeight="+part.contentHeight)
                    verify(part.y+part.height <= column.height+0.5,"content outside column "+row.eventId)
                    if(part.spacing===6) {
                        for(var t=0;t<part.children.length;t++) {
                            var text=part.children[t]
                            if(!text.visible) continue
                            verify(text.y>=-0.5 && text.y+text.height<=part.height+0.5,
                                "sender header has wrong height: "+row.eventId+" row="+part.height+" text="+text.height+" y="+text.y)
                        }
                    }
                }
                var older=list.itemAtIndex(i+1)
                if(older && older.visible) verify(older.y+older.height<=row.y+0.5,"adjacent rows overlap: "+row.eventId)
            }
            verify(seen>0)
        }
        function createList() {
            var view=createTemporaryObject(listComponent,scene)
            view.currentRoomId="!room:test"; view.initialTimelineReady=true
            tryCompare(view,"initialPositionPending",false)
            wait(100)
            return view
        }
        function test_shortMessagesAndSenderHeaders() { var view=createList(); checkLayout(view) }
        function test_restoringAndRecyclingDifferentHeightMessages() {
            var view=createList()
            var targets=["$140","$30","$180","$90","$199","$150"]
            for(var i=0;i<targets.length;i++) {
                verify(view.placeEvent(targets[i],-9))
                tryCompare(view,"pendingAnchorEventId", "")
                wait(100);checkLayout(view)
            }
        }
        function test_liveUpdatesAfterRestoring() {
            var view=createList()
            verify(view.placeEvent("$80",-9));tryCompare(view,"pendingAnchorEventId", "")
            for (var pass=0;pass<12;pass++) {
                for(var i=0;i<messages.count;i++) {
                    var data=JSON.parse(JSON.stringify(messages.get(i)))
                    data.body=pass%2===0 ? "Short" : "A longer edited message with more content repeated several times. "+data.body+"\nAnd another line."
                    data.sender="@user"+((i+pass)%5)+":test"
                    messages.set(i,data)
                }
                messages.insert(0,{event_id:"$live"+pass,sender:"@new:test",sender_display_name:"New",body:"A new live message",
                    msg_type:"m.text",timestamp:10000000+pass*60000,is_system:false,is_redacted:false,is_encrypted:false,
                    sender_is_ignored:false,media_url:""})
                wait(40)
            }
            wait(150);checkLayout(view)
            view.scrollToBottom(false);wait(100);checkLayout(view)
        }
        function test_wheelScrollingAndWidthChanges() {
            var view=createList()
            var list=findList(view)
            for(var step=0;step<80;step++) {
                mouseWheel(view,300,220,0,step<40?120:-120)
                if(step%7===0) view.width=step%2===0?380:600
                wait(16)
                checkLayout(view)
            }
        }
        function test_expandingReusedMessagesFromPlaceholders() {
            var view=createList()
            var list=findList(view)
            for(var i=0;i<messages.count;i++) messages.setProperty(i,"is_encrypted",true)
            for(var step=0;step<35;step++) {
                mouseWheel(view,300,220,0,120)
                for(var j=0;j<messages.count;j++) {
                    messages.setProperty(j,"is_encrypted",step%2===0)
                    messages.setProperty(j,"reply_to",step%3===0?"$reply":"")
                    messages.setProperty(j,"reply_body","Reply preview")
                    messages.setProperty(j,"reply_sender","@reply:test")
                }
                view.firstUnreadEventId="$"+(160-step)
                wait(16);checkLayout(view)
            }
        }
        function test_rowsWhileMessageContentIsStillEmpty() {
            for(var i=0;i<messages.count;i++) messages.setProperty(i,"body","")
            var view=createList()
            checkLayout(view)
            for(var j=0;j<messages.count;j++) messages.setProperty(j,"body","Decoded message "+j)
            wait(100);checkLayout(view)
        }
        function test_positioningImmediatelyAfterContentChanges() {
            var view=createList()
            for(var i=0;i<messages.count;i++) {
                messages.setProperty(i,"body","Expanded text\nSecond line\nThird line\nFourth line\nFifth line")
                messages.setProperty(i,"sender","@changed:test")
            }
            verify(view.placeEvent("$192",-9))
            checkLayout(view)
        }
        function test_hiddenRoomThenRestore() {
            var view=createList()
            verify(view.placeEvent("$80",-9));tryCompare(view,"pendingAnchorEventId", "")
            view.captureViewport()
            var saved=JSON.parse(JSON.stringify(view.lastViewportState))
            view.visible=false;view.initialTimelineReady=false;view.currentRoomId="!other:test"
            wait(50);fill()
            view.restorePosition=saved;view.currentRoomId="!room:test";view.initialTimelineReady=true
            wait(100);view.visible=true
            tryCompare(view,"initialPositionPending",false)
            wait(100);checkLayout(view)
        }
    }
}
