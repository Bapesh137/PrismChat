import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.ToolTip {
    id: root

    property color surfaceColor: "#102016"
    property color textColor: "#F2FFF4"
    property color dividerColor: "#29402E"

    delay: 340
    timeout: 3500
    padding: 7
    leftPadding: 9
    rightPadding: 9

    contentItem: Text {
        text: root.text
        color: root.textColor
        font.pointSize: 8
        font.bold: false
    }

    background: Rectangle {
        radius: 8
        color: root.surfaceColor
        border.width: 1
        border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                              root.dividerColor.b, 0.92)
    }
}
