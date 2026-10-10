import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtMultimedia
import "../common" as Common
import "../../utils" as L10n
import "../../utils/PrismUtils.js" as Utils

Popup {
    id: root

    property string eventId: ""
    property string mediaUrl: ""
    property var mediaFile: null
    property string mediaMimeType: ""
    property string mediaProxy: ""
    property string title: ""
    property color accentColor: "#20D500"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color elevatedColor: "#102016"
    property color dividerColor: "#29402E"

    property int retryToken: 0
    readonly property string sourceUrl: Utils.withRetryToken(
        Utils.proxyUrl(mediaUrl, mediaProxy, mediaFile, mediaMimeType), retryToken)
    property bool restorePending: false
    property real lastKnownPosition: 0
    property string activeSource: ""
    property var speedValues: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    parent: Overlay.overlay
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    width: Math.min(920, parent ? parent.width - 40 : 920)
    height: Math.min(680, parent ? parent.height - 40 : 680)
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    padding: 0

    function formatTime(ms) {
        var total = Math.max(0, Math.floor(Number(ms || 0) / 1000))
        var hours = Math.floor(total / 3600)
        var minutes = Math.floor((total % 3600) / 60)
        var seconds = total % 60
        if (hours > 0)
            return hours + ":" + (minutes < 10 ? "0" : "") + minutes
                    + ":" + (seconds < 10 ? "0" : "") + seconds
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }

    function restorePositionIfReady() {
        if (!restorePending || videoPlayer.duration <= 0)
            return
        var saved = L10n.VideoPlaybackStore.positionFor(eventId, mediaUrl)
        if (saved > 0 && saved < videoPlayer.duration - 1000) {
            videoPlayer.position = Math.min(saved, videoPlayer.duration - 500)
            lastKnownPosition = videoPlayer.position
        }
        restorePending = false
    }

    function persistPosition() {
        L10n.VideoPlaybackStore.savePosition(eventId, mediaUrl,
                                              lastKnownPosition,
                                              videoPlayer.duration)
    }

    function togglePlayback() {
        if (videoPlayer.error !== MediaPlayer.NoError) {
            retryToken++
            activeSource = ""
            Qt.callLater(function() {
                activeSource = root.sourceUrl
                Qt.callLater(videoPlayer.play)
            })
        } else if (videoPlayer.playbackState === MediaPlayer.PlayingState)
            videoPlayer.pause()
        else
            videoPlayer.play()
    }

    onOpened: {
        restorePending = true
        retryToken = 0
        lastKnownPosition = 0
        speedBox.currentIndex = 2
        activeSource = root.sourceUrl
        Qt.callLater(function() {
            if (!root.opened)
                return
            videoPlayer.playbackRate = 1.0
            if (root.activeSource !== "")
                videoPlayer.play()
            restorePositionIfReady()
        })
    }

    onClosed: {
        persistPosition()
        L10n.VideoPlaybackStore.flush()
        // Closing the popup must release decoder buffers, network buffers and
        // the video texture instead of retaining an invisible FFmpeg pipeline.
        videoPlayer.stop()
        activeSource = ""
        restorePending = false
    }

    Component.onDestruction: {
        if (opened) {
            persistPosition()
            L10n.VideoPlaybackStore.flush()
        }
    }

    Shortcut {
        sequence: "Space"
        enabled: root.opened
        context: Qt.ApplicationShortcut
        onActivated: root.togglePlayback()
    }

    background: Rectangle {
        radius: 17
        color: root.elevatedColor
        border.width: 1
        border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                              root.dividerColor.b, 0.92)
    }

    // This wrapper clips both the video and the control bar to the popup's
    // rounded outline, including the previously square lower corners.
    contentItem: Rectangle {
        radius: 16
        color: "transparent"
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "black"

                VideoOutput {
                    id: videoOutput
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                }

                Text {
                    anchors.centerIn: parent
                    visible: videoPlayer.mediaStatus === MediaPlayer.LoadingMedia
                        || videoPlayer.mediaStatus === MediaPlayer.BufferingMedia
                    text: L10n.I18n.tr("Загрузка видео…")
                    color: "white"
                    font.pointSize: 10
                }

                Text {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    visible: videoPlayer.hasAudio && !L10n.AudioDevices.outputAvailable
                    text: L10n.I18n.tr("Нет доступного устройства вывода звука")
                    color: "white"
                    font.pointSize: 8
                }

                Column {
                    z: 2
                    anchors.centerIn: parent
                    width: parent.width - 48
                    visible: videoPlayer.error !== MediaPlayer.NoError
                    spacing: 10
                    Text {
                        width: parent.width
                        text: L10n.I18n.tr("Не удалось воспроизвести видео")
                            + (videoPlayer.errorString
                               ? "\n" + videoPlayer.errorString : "")
                        color: "#ff7b7b"
                        font.pointSize: 9
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Basic.Button {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 126
                        height: 34
                        text: L10n.I18n.tr("Повторить")
                        onClicked: root.togglePlayback()
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

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.togglePlayback()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 98
                radius: 16
                color: root.elevatedColor
                clip: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 16
                    color: parent.color
                }

                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: 1
                    color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                   root.dividerColor.b, 0.8)
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    spacing: 8

                    Basic.Slider {
                        id: seekSlider
                        Layout.fillWidth: true
                        from: 0
                        to: Math.max(1, videoPlayer.duration)
                        value: videoPlayer.position
                        enabled: videoPlayer.seekable && videoPlayer.duration > 0
                        onMoved: videoPlayer.position = Math.round(value)

                        background: Rectangle {
                            x: seekSlider.leftPadding
                            y: seekSlider.topPadding + seekSlider.availableHeight / 2 - height / 2
                            width: seekSlider.availableWidth
                            height: 4
                            radius: 2
                            color: Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                           root.textPrimary.b, 0.13)

                            Rectangle {
                                width: seekSlider.visualPosition * parent.width
                                height: parent.height
                                radius: parent.radius
                                color: root.accentColor
                            }
                        }

                        handle: Rectangle {
                            x: seekSlider.leftPadding + seekSlider.visualPosition
                               * (seekSlider.availableWidth - width)
                            y: seekSlider.topPadding + seekSlider.availableHeight / 2 - height / 2
                            implicitWidth: 14
                            implicitHeight: 14
                            radius: 7
                            color: root.accentColor
                            border.width: 2
                            border.color: root.elevatedColor
                            scale: seekSlider.pressed ? 1.18 : 1.0
                            Behavior on scale {
                                NumberAnimation {
                                    duration: L10n.UiPreferences.duration(90)
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Basic.Button {
                            id: playButton
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 34
                            hoverEnabled: true
                            scale: down ? 0.90 : 1.0
                            padding: 0
                            onClicked: root.togglePlayback()

                            contentItem: Item {
                                implicitWidth: 16
                                implicitHeight: 16

                                Item {
                                    anchors.centerIn: parent
                                    width: 16
                                    height: 16
                                    visible: videoPlayer.playbackState === MediaPlayer.PlayingState

                                    Rectangle {
                                        x: 4
                                        y: 2
                                        width: 3
                                        height: 12
                                        radius: 1.5
                                        color: root.textPrimary
                                    }
                                    Rectangle {
                                        x: 9
                                        y: 2
                                        width: 3
                                        height: 12
                                        radius: 1.5
                                        color: root.textPrimary
                                    }
                                }

                                Canvas {
                                    anchors.centerIn: parent
                                    width: 16
                                    height: 16
                                    visible: videoPlayer.playbackState !== MediaPlayer.PlayingState
                                    property color iconColor: root.textPrimary
                                    onIconColorChanged: requestPaint()
                                    onVisibleChanged: if (visible) requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        ctx.fillStyle = iconColor
                                        ctx.beginPath()
                                        ctx.moveTo(3, 2)
                                        ctx.lineTo(13, 8)
                                        ctx.lineTo(3, 14)
                                        ctx.closePath()
                                        ctx.fill()
                                    }
                                    Component.onCompleted: requestPaint()
                                }
                            }

                            background: Rectangle {
                                radius: 10
                                color: playButton.down
                                    ? Qt.rgba(0, 0, 0, 0.30)
                                    : playButton.hovered
                                        ? Qt.rgba(0, 0, 0, 0.18)
                                        : Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                                  root.textPrimary.b, 0.07)
                                border.width: 1
                                border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                                      root.dividerColor.b, 0.8)
                                Behavior on color {
                                    ColorAnimation { duration: L10n.UiPreferences.duration(110) }
                                }
                            }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: L10n.UiPreferences.duration(90)
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        Text {
                            text: root.formatTime(videoPlayer.position) + " / "
                                  + root.formatTime(videoPlayer.duration)
                            color: root.textSecondary
                            font.pointSize: 9
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            id: speedPanel
                            Layout.preferredWidth: 176
                            Layout.preferredHeight: 38
                            radius: 11
                            color: Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                           root.textPrimary.b, 0.065)
                            border.width: 1
                            border.color: Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                                  root.textPrimary.b, 0.12)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 5
                                spacing: 7

                                Text {
                                    text: L10n.I18n.tr("Скорость")
                                    color: root.textSecondary
                                    font.pointSize: 8.5
                                }

                                Common.StyledComboBox {
                                    id: speedBox
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    model: ["0.5×", "0.75×", "1×", "1.25×", "1.5×", "2×"]
                                    currentIndex: 2
                                    accentColor: root.accentColor
                                    textPrimary: root.textPrimary
                                    textSecondary: root.textSecondary
                                    surfaceColor: root.elevatedColor
                                    elevatedColor: root.elevatedColor
                                    leftPadding: 8
                                    rightPadding: 27
                                    font.pointSize: 8.5
                                    onActivated: videoPlayer.playbackRate = root.speedValues[currentIndex]
                                }
                            }
                        }

                        Basic.Button {
                            id: closeButton
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 34
                            hoverEnabled: true
                            scale: down ? 0.90 : 1.0
                            padding: 0
                            onClicked: root.close()

                            contentItem: Text {
                                text: "×"
                                color: root.textPrimary
                                font.pointSize: 15
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                radius: 10
                                color: closeButton.down
                                    ? Qt.rgba(0, 0, 0, 0.30)
                                    : closeButton.hovered
                                        ? Qt.rgba(0, 0, 0, 0.18)
                                        : Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                                  root.textPrimary.b, 0.07)
                                border.width: 1
                                border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                                      root.dividerColor.b, 0.8)
                                Behavior on color {
                                    ColorAnimation { duration: L10n.UiPreferences.duration(110) }
                                }
                            }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: L10n.UiPreferences.duration(90)
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    AudioOutput { id: audioOutput }

    Connections {
        target: L10n.AudioDevices
        function onOutputAvailableChanged() {
            videoPlayer.activeAudioTrack = L10n.AudioDevices.outputAvailable ? 0 : -1
        }
    }

    MediaPlayer {
        id: videoPlayer
        source: root.activeSource
        videoOutput: videoOutput
        audioOutput: L10n.AudioDevices.outputAvailable ? audioOutput : null
        activeAudioTrack: L10n.AudioDevices.outputAvailable ? 0 : -1
        onTracksChanged: activeAudioTrack = L10n.AudioDevices.outputAvailable ? 0 : -1

        onPositionChanged: function() {
            if (root.opened)
                root.lastKnownPosition = videoPlayer.position
        }
        onDurationChanged: function() { root.restorePositionIfReady() }
        onMediaStatusChanged: function() {
            root.restorePositionIfReady()
            if (videoPlayer.mediaStatus === MediaPlayer.EndOfMedia) {
                L10n.VideoPlaybackStore.clearPosition(root.eventId, root.mediaUrl)
                L10n.VideoPlaybackStore.flush()
                root.lastKnownPosition = 0
            }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.opened && videoPlayer.playbackState === MediaPlayer.PlayingState
        onTriggered: root.persistPosition()
    }
}
