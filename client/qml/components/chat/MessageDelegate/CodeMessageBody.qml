import ".." as Chat
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "../../common"
import "../../../assets/icons" as Icons
import "../../../utils/PrismUtils.js" as Utils

Column {
    required property var message
    readonly property var root: message
    id: segmentedMessageText
    visible: !root.systemMessage && !root.redacted && !root.encrypted
        && !root.contentHidden && root.messageType === "m.text"
        && root.hasCodeBlocks
    width: parent.width
    spacing: 5

    Repeater {
        model: root.textSegments

        delegate: Item {
            id: segmentItem
            required property var modelData
            width: segmentedMessageText.width
            height: modelData.kind === "code"
                ? codeCard.height : plainSegment.implicitHeight

            Text {
                id: plainSegment
                visible: segmentItem.modelData.kind === "text"
                width: parent.width
                text: visible ? Utils.flagStyledText(
                    Utils.linkifiedText(
                        segmentItem.modelData.content || ""),
                    root.emojiFontFamily, false) : ""
                color: root.messageContentColor
                linkColor: root.sendState === "sending"
                    ? root.messageContentColor : "#4da3ff"
                font.pointSize: 10
                wrapMode: Text.Wrap
                textFormat: Text.RichText
                onLinkActivated: function(link) {
                    Qt.openUrlExternally(link)
                }
            }

            Rectangle {
                id: codeCard
                visible: segmentItem.modelData.kind === "code"
                width: parent.width
                height: visible ? Math.max(62,
                    codeText.implicitHeight + 46) : 0
                radius: 9
                color: Qt.rgba(root.textPrimary.r,
                               root.textPrimary.g,
                               root.textPrimary.b, 0.055)
                border.width: 1
                border.color: Qt.rgba(root.dividerColor.r,
                                      root.dividerColor.g,
                                      root.dividerColor.b, 0.78)

                Text {
                    visible: (segmentItem.modelData.language || "") !== ""
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.top: parent.top
                    anchors.topMargin: 7
                    text: segmentItem.modelData.language || ""
                    color: root.textSecondary
                    font.pointSize: 7
                }

                Basic.Button {
                    id: copyCodeButton
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.top: parent.top
                    anchors.topMargin: 5
                    width: 82
                    height: 28
                    text: L10n.I18n.tr("Копировать")
                    hoverEnabled: true
                    onClicked: {
                        if (root.controller)
                            root.controller.copyCode(
                                segmentItem.modelData.content || "")
                    }
                    contentItem: Text {
                        text: parent.text
                        color: copyCodeButton.hovered
                            ? root.accentColor : root.textSecondary
                        font.pointSize: 7
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 7
                        color: copyCodeButton.hovered
                            ? Qt.rgba(root.accentColor.r,
                                      root.accentColor.g,
                                      root.accentColor.b, 0.13)
                            : "transparent"
                    }
                }

                Text {
                    id: codeText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 11
                    anchors.rightMargin: 11
                    anchors.topMargin: 36
                    text: segmentItem.modelData.content || ""
                    textFormat: Text.PlainText
                    color: root.messageContentColor
                    font.family: "monospace"
                    font.pointSize: 9
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
    }
}
