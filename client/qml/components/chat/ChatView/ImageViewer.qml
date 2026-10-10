import ".." as Chat
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../../utils/PrismUtils.js" as Utils

Item {
    required property var chat
    readonly property var root: chat
    id: imageViewer
    anchors.fill: parent
    z: 10000
    property bool opened: false
    property string imageSource: ""
    property string caption: ""
    property int retryToken: 0
    visible: opened || opacity > 0.01
    enabled: opened
    opacity: opened ? 1 : 0

    function open(source, captionText) {
        if (!source || source === "") return
        imageSource = source
        caption = captionText || ""
        retryToken = 0
        opened = true
    }
    function close() {
        opened = false
        // Drop the decoded texture and URL immediately; otherwise the
        // full-size image survives invisibly until another image is opened.
        imageSource = ""
        caption = ""
    }

    Behavior on opacity { NumberAnimation { duration: L10n.UiPreferences.duration(160); easing.type: Easing.OutQuad } }

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.92) }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: imageViewer.close()
        onWheel: function(wheel) { wheel.accepted = true }
    }

    Image {
        id: fullImage
        anchors.fill: parent
        anchors.margins: 48
        anchors.bottomMargin: imageViewer.caption !== "" ? 78 : 48
        source: Utils.withRetryToken(imageViewer.imageSource,
                                     imageViewer.retryToken)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
        smooth: true
        mipmap: true
    }

    Rectangle {
        visible: fullImage.status === Image.Loading
        anchors.centerIn: parent
        width: loadingText.width + 28
        height: 42
        radius: 10
        color: Qt.rgba(0.08, 0.08, 0.08, 0.85)
        Text {
            id: loadingText
            anchors.centerIn: parent
            text: L10n.I18n.tr("Загрузка изображения...")
            color: root.textPrimary
            font.pointSize: 9
        }
    }

    Column {
        visible: fullImage.status === Image.Error
        anchors.centerIn: parent
        spacing: 10
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: L10n.I18n.tr("Не удалось загрузить изображение")
            color: "#ff6b6b"
            font.pointSize: 10
        }
        Basic.Button {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 126
            height: 34
            text: L10n.I18n.tr("Повторить")
            hoverEnabled: true
            onClicked: imageViewer.retryToken++
            contentItem: Text {
                text: parent.text
                color: root.accentColor
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                radius: 9
                color: parent.down
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, 0.24)
                    : Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, 0.14)
                border.width: 1
                border.color: root.accentColor
            }
        }
    }

    Text {
        visible: imageViewer.caption !== ""
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 60
        anchors.bottomMargin: 24
        text: imageViewer.caption
        color: root.textPrimary
        font.pointSize: 9
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        maximumLineCount: 2
    }

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 14
        width: 38
        height: 38
        radius: 19
        color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)

        Item {
            anchors.centerIn: parent
            width: 16
            height: 16
            Rectangle { anchors.centerIn: parent; width: 18; height: 2; radius: 1; color: "white"; rotation: 45; antialiasing: true }
            Rectangle { anchors.centerIn: parent; width: 18; height: 2; radius: 1; color: "white"; rotation: -45; antialiasing: true }
        }

        MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: imageViewer.close()
        }
    }
}
