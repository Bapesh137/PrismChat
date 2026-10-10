pragma Singleton
import QtQuick
import QtMultimedia

QtObject {
    readonly property bool outputAvailable: devices.audioOutputs.length > 0
    property MediaDevices devices: MediaDevices {}
}
