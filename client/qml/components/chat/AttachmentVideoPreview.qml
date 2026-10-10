import QtQuick
import QtMultimedia

Item {
    id: root

    property url source: ""
    readonly property bool ready: previewReady
    property bool previewReady: false
    property bool previewStarted: false

    onSourceChanged: {
        loadTimer.stop()
        previewReady = false
        previewStarted = false
        player.stop()
        player.source = ""
        if (source.toString() !== "")
            loadTimer.restart()
    }

    function finishPreview() {
        if (previewReady)
            player.pause()
    }

    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }

    // Grid delegates can disappear while scrolling or closing the panel. Don't
    // open a network/decoder pipeline for a tile that only lives for one frame.
    Timer {
        id: loadTimer
        interval: 120
        onTriggered: player.source = root.source
    }

    MediaPlayer {
        id: player
        videoOutput: output
        // A muted AudioOutput still opens an audio device and decodes AAC.
        // Thumbnails only need a video track, including on machines without audio.
        activeAudioTrack: -1
        onTracksChanged: activeAudioTrack = -1

        onMediaStatusChanged: {
            if ((mediaStatus === MediaPlayer.LoadedMedia
                    || mediaStatus === MediaPlayer.BufferedMedia)
                    && !root.previewStarted) {
                root.previewStarted = true
                if (duration > 1000)
                    position = Math.min(1000, Math.round(duration * 0.1))
                play()
            }
        }
    }

    Connections {
        target: output.videoSink
        function onVideoFrameChanged() {
            // A fixed delay can expire before a slow VM has decoded any frame.
            if (root.previewStarted && !root.previewReady
                    && output.videoSink.videoSize.width > 0) {
                root.previewReady = true
                Qt.callLater(root.finishPreview)
            }
        }
    }

    Component.onDestruction: {
        loadTimer.stop()
        player.stop()
    }
}
