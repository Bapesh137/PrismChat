import QtQuick
import QtMultimedia
import "../../utils" as L10n

Item {
    id: root

    property alias source: player.source
    property alias position: player.position
    property alias playbackRate: player.playbackRate
    readonly property alias duration: player.duration
    readonly property alias seekable: player.seekable
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState

    signal ended()
    signal playbackError(string errorText)

    function play() {
        if (!L10n.AudioDevices.outputAvailable) {
            playbackError(L10n.I18n.tr("Нет доступного устройства вывода звука"))
            return
        }
        player.play()
    }
    function pause() { player.pause() }
    function stop() { player.stop() }

    AudioOutput { id: output }

    Connections {
        target: L10n.AudioDevices
        function onOutputAvailableChanged() {
            if (!L10n.AudioDevices.outputAvailable && root.playing) {
                player.pause()
                root.playbackError(L10n.I18n.tr("Нет доступного устройства вывода звука"))
            }
        }
    }

    MediaPlayer {
        id: player
        audioOutput: L10n.AudioDevices.outputAvailable ? output : null
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia) {
                position = 0
                root.ended()
            }
        }
        onErrorOccurred: function(error, errorString) {
            root.playbackError(errorString || "")
        }
    }
}
