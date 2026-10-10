import ".." as Chat
import QtQuick
import "../../common"
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtCore
import "../../../assets/icons" as Icons
import "../../../utils/PrismUtils.js" as Utils

Rectangle {
    required property var composer
    readonly property var root: composer
    id: uploadProgressBar
    width: parent.width
    height: root.visibleUploads.length > 0 ? 54 : 0
    visible: height > 0
    color: root.backgroundColor
    clip: true

    ListView {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        orientation: ListView.Horizontal
        spacing: 8
        model: root.visibleUploads
        clip: true

        delegate: Rectangle {
            required property var modelData
            width: Math.min(300, Math.max(220, ListView.view.width - 4))
            height: ListView.view.height
            radius: 9
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                  root.accentColor.b, 0.28)

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 5

                Row {
                    width: parent.width
                    spacing: 8
                    Text {
                        width: parent.width * 0.62
                        text: modelData.filename
                        color: root.textPrimary
                        font.pointSize: 8
                        font.bold: true
                        elide: Text.ElideMiddle
                    }
                    Text {
                        width: parent.width * 0.25
                        text: modelData.total > 0
                            ? root.formatBytes(modelData.current) + " / "
                              + root.formatBytes(modelData.total)
                            : L10n.I18n.tr("Подготовка…")
                        color: root.textSecondary
                        font.pointSize: 7
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }
                    Basic.Button {
                        width: 24; height: 20; text: "×"
                        onClicked: {
                            root.uploadCancelRequested(modelData.request_id)
                            root.finishUpload(modelData.request_id)
                        }
                        contentItem: Text { text: parent.text; color: "#ff7777"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: 5; color: parent.hovered ? Qt.rgba(1, 0.3, 0.3, 0.12) : "transparent" }
                    }
                }

                ProgressBar {
                    width: parent.width
                    height: 5
                    from: 0
                    to: Math.max(1, Number(modelData.total || 0))
                    value: Number(modelData.current || 0)
                    indeterminate: Number(modelData.total || 0) <= 0
                }
            }
        }
    }
}
