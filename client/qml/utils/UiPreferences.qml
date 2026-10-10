pragma Singleton

import QtQuick

QtObject {
    property bool animationsEnabled: true
    property string windowWobbleMode: "off"
    property int windowSpringStrength: 100
    property int windowWobbleStrength: 50
    // Use the platform emoji font and let Qt handle missing glyphs.
    readonly property string emojiFontFamily: Qt.platform.os === "windows"
        ? "Segoe UI Emoji"
        : Qt.platform.os === "osx" ? "Apple Color Emoji" : "Noto Color Emoji"

    function duration(milliseconds) {
        return animationsEnabled ? milliseconds : 0
    }
}
