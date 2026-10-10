import ".." as Chat
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "../../common"
import "../../../assets/icons" as Icons
import "../../../utils/PrismUtils.js" as Utils

Loader {
    required property var message
    readonly property var root: message
    required property var messageColumnObject
    id: voiceMessageLoader
    readonly property bool isVoiceMessage: !root.systemMessage
        && !root.redacted && !root.encrypted && !root.contentHidden
        && root.messageType === "m.audio" && !root.pooled
    visible: isVoiceMessage
    active: isVoiceMessage
    width: Math.min(280, messageColumnObject.width)
    height: visible ? 54 : 0

    sourceComponent: Component {
        Rectangle {
            id: voiceBubble
            anchors.fill: parent
            radius: 12
            color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                           root.accentColor.b, 0.10)
            border.width: 1
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                  root.accentColor.b, 0.20)
            property string playbackError: ""
            readonly property bool active: root.activeVoiceEventId === root.eventId
            readonly property bool playing: active && root.activeVoicePlaying
            readonly property real position: active ? root.activeVoicePosition : 0
            readonly property real duration: active
                ? root.activeVoiceDuration : 0

            function formatDuration(durationMs) {
                var totalSeconds = Math.max(0,
                    Math.floor(Number(durationMs || 0) / 1000))
                var minutes = Math.floor(totalSeconds / 60)
                var seconds = totalSeconds % 60
                return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 9

                Basic.Button {
                    id: voicePlayButton
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    padding: 0
                    hoverEnabled: true
                    scale: down ? 0.86 : 1

                    contentItem: Item {
                        Canvas {
                            id: voicePlayIcon
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                        property bool playing: voiceBubble.playing
                        property color iconColor: voicePlayButton.hovered
                            || voicePlayButton.down
                            ? root.accentColor : root.textPrimary

                        onPlayingChanged: requestPaint()
                        onIconColorChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.fillStyle = iconColor
                            if (playing) {
                                ctx.fillRect(4.5, 3.5, 3.2, 11)
                                ctx.fillRect(10.3, 3.5, 3.2, 11)
                            } else {
                                ctx.beginPath()
                                ctx.moveTo(5.5, 3)
                                ctx.lineTo(14, 9)
                                ctx.lineTo(5.5, 15)
                                ctx.closePath()
                                ctx.fill()
                            }
                        }
                            Component.onCompleted: requestPaint()
                        }
                    }

                    background: Rectangle {
                        radius: 10
                        color: voicePlayButton.down
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                      root.accentColor.b, 0.22)
                            : voicePlayButton.hovered
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                          root.accentColor.b, 0.12)
                                : Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                          root.textPrimary.b, 0.06)
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                    }

                    onClicked: {
                        voiceBubble.playbackError = ""
                        if (root.controller) root.controller.toggleVoice({
                            event_id: root.eventId,
                            room_id: root.currentRoomId,
                            title: root.senderDisplayName || L10n.I18n.tr("Голосовое сообщение"),
                            source: Utils.proxyUrl(root.mediaUrl, root.mediaProxy,
                                                   root.mediaFile, root.mediaMimeType)
                        })
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 5

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            text: voiceBubble.playbackError !== ""
                                ? voiceBubble.playbackError : L10n.I18n.tr("Голосовое сообщение")
                            color: voiceBubble.playbackError !== ""
                                ? "#ff6b6b" : root.textPrimary
                            font.pointSize: 8
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            text: voiceBubble.formatDuration(
                                voiceBubble.playing || voiceBubble.position > 0
                                    ? voiceBubble.position : voiceBubble.duration)
                            color: Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                           root.textPrimary.b, 0.52)
                            font.pointSize: 7
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 10

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 3
                            radius: 2
                            color: Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                           root.textPrimary.b, 0.16)

                            Rectangle {
                                width: voiceBubble.duration > 0
                                    ? parent.width * Math.max(0, Math.min(1,
                                        voiceBubble.position / voiceBubble.duration))
                                    : 0
                                height: parent.height
                                radius: parent.radius
                                color: root.accentColor
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) {
                                if (voiceBubble.duration > 0 && root.controller)
                                    root.controller.seekVoice(Math.round(
                                        mouse.x / width * voiceBubble.duration))
                            }
                        }
                    }
                }
            }
        }
    }
}
