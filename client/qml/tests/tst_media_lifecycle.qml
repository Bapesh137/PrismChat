import QtQuick
import QtMultimedia
import QtTest
import "../components/chat"
import "../utils" as Utils

Item {
    id: scene
    width: 320
    height: 200
    Component { id: previewComponent; AttachmentVideoPreview { width: 160; height: 100 } }
    Component { id: voiceComponent; VoiceMessagePlayer {} }

    TestCase {
        name: "MediaLifecycle"
        when: windowShown

        function init() {
            failOnWarning(/No audio device detected|Binding loop|ReferenceError|TypeError/)
        }

        function test_previewDecodesFrameWithoutAudio() {
            var preview = createTemporaryObject(previewComponent, scene, {source: Qt.resolvedUrl("data/preview.mp4")})
            verify(preview)
            tryCompare(preview, "ready", true, 10000)
            // Raster software rendering has no video node. Still check decoding;
            // the OpenGL run also verifies rendered pixels. Qt consumes -platform
            // before exposing application.arguments, so test the actual renderer.
            if (preview.GraphicsInfo.api !== GraphicsInfo.Software) {
                waitForRendering(preview)
                var frame = grabImage(preview)
                verify(frame.red(80, 50) > 180 && frame.green(80, 50) < 80, "decoded red video frame")
            }
            preview.source = ""
            compare(preview.ready, false)
            preview.source = Qt.resolvedUrl("data/preview.mp4")
            tryCompare(preview, "ready", true, 10000)
        }

        function test_shortLivedPreviewDoesNotLoad() {
            var preview = createTemporaryObject(previewComponent, scene, {source: "http://127.0.0.1:1/never-opened.mp4"})
            preview.source = ""
            wait(200)
            compare(preview.previewStarted, false)
            compare(preview.ready, false)
        }

        function test_voiceHandlesMissingOutput() {
            if (Utils.AudioDevices.outputAvailable)
                skip("Requires an environment without an audio output")
            var voice = createTemporaryObject(voiceComponent, scene)
            var error = ""
            voice.playbackError.connect(function(text) { error = text })
            voice.play()
            verify(error.length > 0)
            compare(voice.playing, false)
        }
    }
}
