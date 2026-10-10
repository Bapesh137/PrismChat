import QtQuick
import QtQuick.Controls
import QtTest
import "../components/chat"
import "../utils" as L10n

Item {
    id: scene
    width: 1200; height: 900
    Rectangle { anchors.fill: parent; color: "#07100A" }
    Component { id: previewComponent; ChatPreviewPopup {} }

    TestCase {
        id: tc
        name: "ChatPreviewMotion"
        when: windowShown
        function findItem(item, predicate) {
            if (predicate(item)) return item
            var children = item.children || []
            for (var i = 0; i < children.length; ++i) {
                var found = findItem(children[i], predicate)
                if (found) return found
            }
            return null
        }
        function test_previewMotion_data() {
            return [{tag:"off",mode:"off",enabled:true},
                {tag:"spring",mode:"spring",enabled:true},
                {tag:"linux",mode:"linux",enabled:true},
                {tag:"disabled",mode:"linux",enabled:false}]
        }
        function test_previewMotion(data) {
            L10n.UiPreferences.animationsEnabled = data.enabled
            L10n.UiPreferences.windowWobbleMode = data.mode
            var popup = createTemporaryObject(previewComponent, scene, {parent: scene})
            verify(popup)
            popup.openForRoom("!test:example.org", "Preview", [])
            tryCompare(popup,"opened",true)
            var mover = findItem(popup.contentItem, function(item) { return item.moveTarget !== undefined })
            verify(mover)
            var maximumShear=0
            mover.visualShearAngleChanged.connect(function() {
                maximumShear=Math.max(maximumShear,Math.abs(mover.visualShearAngle))
            })
            var start = mover.mapToItem(scene, 120, 24)
            mousePress(scene,start.x,start.y,Qt.LeftButton)
            mouseMove(scene,start.x+90,start.y+50,30)
            tryVerify(function() { return popup.dragOffsetX > 0 },2000,"Header did not move popup")
            if (data.mode === "linux" && data.enabled)
                tryVerify(function() { return maximumShear > 0.01 },2000,"Linux effect did not respond")
            else compare(mover.visualShearAngle,0)
            mouseRelease(scene,start.x+90,start.y+50,Qt.LeftButton)
            tryVerify(function() { return Math.abs(popup.dragOffsetX-90)<0.1
                && Math.abs(popup.dragOffsetY-50)<0.1 }, 2000)
            popup.close(); tryCompare(popup,"visible",false)
            popup.openForRoom("!next:example.org", "Next", [])
            tryCompare(popup,"opened",true)
            compare(popup.dragOffsetX,0);compare(popup.dragOffsetY,0)
            var close = findItem(popup.contentItem, function(item) { return item.text === "×" && item.clicked !== undefined })
            verify(close)
            mouseClick(close,close.width/2,close.height/2)
            tryCompare(popup,"visible",false)
        }
    }
}
