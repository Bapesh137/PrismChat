import QtQuick
import QtTest
import "../components/chat"
Item {
    id: scene
    width: 1000; height: 800
    Component { id: panelComponent; RoomAttachmentsPanel { width: 900; height: 700; autoLoadImages:false; autoLoadVideos:false } }
    TestCase {
        name: "AttachmentCache"
        when: windowShown
        function init() { failOnWarning(/Binding loop|ReferenceError|TypeError/) }
        function entry(id,kind) { return {event_id:id,msg_type:kind||"m.image",body:kind==="m.text"?"https://example.org/"+id:id,media_url:"",timestamp:100} }
        function entries(start,count,kind) { var out=[]; for(var i=0;i<count;i++)out.push(entry("$"+(start+i),kind));return out }
        function create() { return createTemporaryObject(panelComponent,scene) }
        function answer(p,items,cursor,error,room) {
            var target=room||p.roomId;verify(p.pageRequests[target]);
            p.receivePage(target,items,cursor,error||"",p.pageRequests[target].id)
        }
        function pending(p,room) { tryVerify(function(){return !!p.pageRequests[room||p.roomId]}) }
        function test_scansEmptyAndSparsePagesUntilThirty() {
            var p=create(),counts=[]
            p.loadMoreRequested.connect(function(room,from,id,category,count){counts.push(count)})
            p.openForRoom("!a:test")
            answer(p,[],"p2");compare(p.canLoadMore,false);compare(p.loading,true);pending(p)
            answer(p,entries(0,7),"p3");compare(p.canLoadMore,false);pending(p)
            answer(p,entries(7,23),"p4")
            compare(p.categoryCount(0),30);compare(p.loading,false);compare(p.canLoadMore,true)
            compare(counts.join(","),"30,30,23")
            p.requestNextPage();answer(p,entries(30,5),"p5");pending(p)
            answer(p,entries(35,25),"p6")
            compare(p.categoryCount(0),60);compare(p.canLoadMore,true)
        }
        function test_emptyAndDuplicatePagesKeepTheVisibleModel() {
            var p=create();p.openForRoom("!a:test");answer(p,entries(0,5),"p2");pending(p)
            var model=p.attachments
            answer(p,[],"p3");verify(p.attachments===model);pending(p)
            answer(p,entries(0,5),"p4");verify(p.attachments===model);pending(p)
            answer(p,entries(5,25),"");compare(p.attachments.length,30)
        }
        function test_endOfHistoryHidesButtonForPartialAndFullBatch() {
            var p=create();p.openForRoom("!a:test");answer(p,entries(0,17),"")
            compare(p.categoryCount(0),17);compare(p.loading,false);compare(p.canLoadMore,false)
            compare(findChild(p,"attachmentsLoadMore").visible,false)
            p.openForRoom("!b:test");answer(p,entries(0,30),"")
            compare(p.categoryCount(0),30);compare(p.canLoadMore,false)
            p.openForRoom("!empty:test");answer(p,[],"")
            compare(p.loading,false);compare(p.canLoadMore,false);compare(p.attachments.length,0)
        }
        function test_closeReopenAndRoomSwitchReusePages() {
            var p=create();p.openForRoom("!a:test");answer(p,entries(0,30),"p2")
            p.close();p.openForRoom("!a:test")
            compare(p.attachments.length,30);compare(p.nextFrom,"p2");compare(p.loading,false)
            p.openForRoom("!b:test");p.close();answer(p,[],"","","!b:test")
            p.openForRoom("!a:test");compare(p.attachments[0].msg_type,"m.image");compare(p.loading,false)
            p.openForRoom("!b:test");compare(p.hasLoadedPage,true);compare(p.loading,false)
            compare(p.requestSequence,2)
        }
        function test_eachCategoryHasItsOwnThirtyAndCursor() {
            var p=create();p.openForRoom("!a:test");answer(p,entries(0,30),"media-next")
            p.currentCategory=1;pending(p);compare(p.pageRequests[p.roomId].category,1)
            answer(p,entries(100,12,"m.text"),"links-next");pending(p)
            answer(p,entries(112,18,"m.text"),"links-more")
            compare(p.categoryCount(1),30);compare(p.nextFrom,"links-more")
            p.currentCategory=0;compare(p.nextFrom,"media-next");compare(p.loading,false)
            p.requestNextPage();compare(p.pageRequests[p.roomId].category,0)
            compare(p.pageRequests[p.roomId].from,"media-next")
            answer(p,entries(30,30),"")
            compare(p.categoryCount(0),60);compare(p.canLoadMore,false)
            p.currentCategory=1;compare(p.categoryCount(1),30);compare(p.canLoadMore,true)
        }
        function test_categorySwitchDuringRequestRoutesLateResponse() {
            var p=create();p.openForRoom("!a:test");p.currentCategory=2
            answer(p,entries(0,3),"media-next")
            pending(p);compare(p.pageRequests[p.roomId].category,2)
            answer(p,entries(50,30,"m.file"),"")
            compare(p.categoryCount(2),30);compare(p.loading,false)
            p.currentCategory=0;pending(p);compare(p.pageRequests[p.roomId].from,"media-next")
            answer(p,entries(3,27),"");compare(p.categoryCount(0),30)
        }
        function test_closePausesAutomaticScanAndReopenResumes() {
            var p=create();p.openForRoom("!a:test");p.close()
            answer(p,entries(0,5),"p2");wait(30);compare(p.requestSequence,1)
            p.openForRoom("!a:test");compare(p.pageRequests[p.roomId].from,"p2")
            answer(p,entries(5,25),"");compare(p.categoryCount(0),30)
        }
        function test_pendingResponsesKeepTheirOwnRoomAndSession() {
            var p=create();p.openForRoom("!a:test");var a=p.pageRequests[p.roomId].id
            p.openForRoom("!b:test");var b=p.pageRequests[p.roomId].id
            p.receivePage("!a:test",entries(0,30),"","",a)
            compare(p.roomId,"!b:test");compare(p.attachments.length,0);compare(p.loading,true)
            p.receivePage("!b:test",entries(50,30),"","",b)
            p.openForRoom("!a:test");compare(p.attachments.length,30);compare(p.loading,false)
            p.reset();p.receivePage("!b:test",[entry("$late")],"","",b)
            compare(Object.keys(p.roomCache).length,0)
        }
        function test_liveAttachmentsEditsAndRedactionsUpdateCache() {
            var p=create();p.openForRoom("!a:test");answer(p,[entry("$old"),entry("$removed")],"")
            var rows=[Object.assign(entry("$old"),{body:"renamed"}),entry("$new"),{event_id:"$removed",is_redacted:true}]
            p.close();p.reconcileTimeline("!a:test",{count:rows.length,get:function(i){return rows[i]}});p.openForRoom("!a:test")
            compare(p.attachments.length,2);compare(p.attachments.filter(function(x){return x.event_id==="$old"})[0].body,"renamed")
            compare(p.requestSequence,1)
        }
        function test_oldRestoredTimelineDoesNotPrematurelyFillBatch() {
            var p=create();p.openForRoom("!a:test");answer(p,entries(0,1),"p2")
            var rows=entries(100,30).map(function(x){return Object.assign({},x,{timestamp:1})})
            p.reconcileTimeline("!a:test",{count:rows.length,get:function(i){return rows[i]}})
            compare(p.categoryCount(0),1);compare(p.canLoadMore,false);pending(p)
            answer(p,entries(1,29),"");compare(p.categoryCount(0),30)
        }
        function test_duplicatesIgnoredAndOtherCategoriesDoNotFillMediaBatch() {
            var p=create();p.openForRoom("!a:test")
            p.setSenderIgnored("@blocked:test",true)
            var items=entries(0,5).concat(entries(0,5)).concat(entries(50,10,"m.file"))
            items.push(Object.assign(entry("$blocked"),{sender:"@blocked:test"}))
            answer(p,items,"p2");compare(p.categoryCount(0),5);pending(p)
            answer(p,entries(5,25),"");compare(p.categoryCount(0),30)
        }
        function test_failedPageKeepsPartialBatchAndRetriesSameCursor() {
            var p=create();p.openForRoom("!a:test");answer(p,entries(0,8),"p2");pending(p)
            answer(p,[],"","timeout")
            compare(p.nextFrom,"p2");compare(p.attachments.length,8);compare(p.loading,false);compare(p.canLoadMore,false)
            p.close();p.openForRoom("!a:test");compare(p.errorText,"timeout")
            p.requestPage(p.nextFrom);compare(p.pageRequests[p.roomId].from,"p2")
            answer(p,entries(8,22),"");compare(p.attachments.length,30);compare(p.errorText,"")
        }
        function test_failedFirstPageCanRetry() {
            var p=create();p.openForRoom("!a:test");var id=p.pageRequests[p.roomId].id
            answer(p,[],"","offline");p.close();p.openForRoom("!a:test")
            verify(p.pageRequests[p.roomId].id!==id)
        }
        function test_nonadvancingCursorStopsLoop() {
            var p=create();p.openForRoom("!a:test");answer(p,[],"same");pending(p)
            answer(p,[],"same");wait(30);compare(p.requestSequence,2);compare(p.canLoadMore,false);compare(p.loading,false)
        }
    }
}
