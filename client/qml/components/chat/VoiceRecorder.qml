import QtQuick
import QtMultimedia

Item {
    id: root

    readonly property bool recording: recorder.recorderState === MediaRecorder.RecordingState
    readonly property url actualLocation: recorder.actualLocation

    signal durationUpdated(double durationMs)
    signal stopped()
    signal recordingError(string errorText)

    function startAt(outputLocation) {
        recorder.outputLocation = outputLocation
        recorder.record()
    }

    function stop() {
        if (root.recording)
            recorder.stop()
    }

    CaptureSession {
        audioInput: AudioInput {}
        recorder: MediaRecorder {
            id: recorder
            quality: MediaRecorder.HighQuality
            mediaFormat {
                fileFormat: MediaFormat.Wave
                audioCodec: MediaFormat.AudioCodec.Wave
            }
            onDurationChanged: function(duration) {
                root.durationUpdated(Number(duration || 0))
            }
            onRecorderStateChanged: function(state) {
                if (state === MediaRecorder.StoppedState)
                    root.stopped()
            }
            onErrorOccurred: function(error, errorString) {
                root.recordingError(errorString || "")
            }
        }
    }
}
