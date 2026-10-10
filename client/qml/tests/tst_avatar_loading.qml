import QtQuick
import QtTest
import "../components/common"

Item {
    width: 100
    height: 100
    Component { id: avatarComponent; AvatarItem { size: 36 } }

    TestCase {
        name: "AvatarLoading"
        when: windowShown

        function initTestCase() {
            // Network cases use a local fixture, never the Matrix media proxy.
            var probe = new XMLHttpRequest()
            probe.open("GET", "http://127.0.0.1:18043/health")
            probe.send()
            tryVerify(function() { return probe.readyState === XMLHttpRequest.DONE }, 2000)
            if (probe.status !== 200)
                skip("Start qml/tests/avatar_server.py to run these integration tests")
        }

        function avatar(path) {
            var item = createTemporaryObject(avatarComponent, parent, {
                mxcUrl: "mxc://fixture/" + path + Date.now(),
                mediaProxy: "http://127.0.0.1:18043/media?url="
            })
            verify(item)
            return item
        }

        function test_retryTransientFailure() {
            var item = avatar("transient")
            tryCompare(item, "retryAttempt", 1, 4000)
            tryVerify(function() { return findChild(item, "avatarImage").status === Image.Ready }, 4000)
            wait(1200)
            compare(item.retryAttempt, 1)
        }

        function test_webpDecoderAndAvatarMask() {
            var item = avatar("webp")
            tryVerify(function() { return findChild(item, "avatarImage").status === Image.Ready }, 4000)
            if (item.GraphicsInfo.api !== GraphicsInfo.Software) {
                waitForRendering(item)
                var frame = grabImage(item)
                verify(frame.green(18, 18) > frame.red(18, 18) + 50, "visible green avatar")
            }
        }

        function test_thumbnailFallsBackToOriginal() {
            var item = avatar("original-only")
            tryCompare(item, "retryAttempt", 2, 6000)
            tryVerify(function() { return findChild(item, "avatarImage").status === Image.Ready }, 4000)
        }

        function test_permanentFailureIsBoundedAndNewAvatarResets() {
            var item = avatar("unavailable")
            tryCompare(item, "retryAttempt", 2, 6000)
            wait(3500)
            compare(item.retryAttempt, 2)
            item.mxcUrl = "mxc://fixture/valid-new-avatar"
            compare(item.retryAttempt, 0)
            tryVerify(function() { return findChild(item, "avatarImage").status === Image.Ready }, 4000)
        }
    }
}
