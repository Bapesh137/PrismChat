import QtQuick
import QtMultimedia

Item {
    id: root

    property alias source: player.source
    property alias position: player.position
    readonly property alias duration: player.duration
    readonly property alias seekable: player.seekable
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState

    signal mediaLoaded()
    signal mediaFailed(string errorText)
    signal ended()

    function play() { player.play() }
    function pause() { player.pause() }
    function stop() { player.stop() }

    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }

    MediaPlayer {
        id: player
        videoOutput: output
        audioOutput: AudioOutput {}
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia
                    || mediaStatus === MediaPlayer.BufferedMedia)
                root.mediaLoaded()
            if (mediaStatus === MediaPlayer.EndOfMedia)
                root.ended()
        }
        onErrorOccurred: function(error, errorString) {
            if (error !== MediaPlayer.NoError)
                root.mediaFailed(errorString || "")
        }
    }
}
