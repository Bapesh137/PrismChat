import ".." as Chat
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "../../common"
import "../../../assets/icons" as Icons
import "../../../utils/PrismUtils.js" as Utils

Rectangle {
    required property var message
    readonly property var root: message
    id: videoBubble
    anchors.fill: parent
    radius: 14
    clip: true
    color: "black"
    border.width: 1
    border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                          root.dividerColor.b, 0.85)

    property bool inlineStarted: false
    property bool restorePending: false
    property real lastKnownPosition: 0
    property string playbackError: ""
    focus: false

    Keys.onSpacePressed: function(event) {
        if (videoBubble.inlineStarted || root.shouldLoadVideo) {
            videoBubble.toggleInlinePlayback()
            event.accepted = true
        }
    }

    function restoreInlinePosition() {
        if (!restorePending || inlineVideoPlayer.duration <= 0)
            return
        var saved = L10n.VideoPlaybackStore.positionFor(root.eventId, root.mediaUrl)
        if (saved > 0 && saved < inlineVideoPlayer.duration - 1000) {
            inlineVideoPlayer.position = Math.min(saved, inlineVideoPlayer.duration - 500)
            lastKnownPosition = inlineVideoPlayer.position
        }
        restorePending = false
    }

    function persistInlinePosition(flushNow) {
        if (!inlineStarted)
            return
        L10n.VideoPlaybackStore.savePosition(root.eventId, root.mediaUrl,
                                              lastKnownPosition,
                                              inlineVideoPlayer.duration)
        if (flushNow)
            L10n.VideoPlaybackStore.flush()
    }

    function toggleInlinePlayback() {
        if (root.mediaUrl === "")
            return
        videoBubble.forceActiveFocus()
        if (videoBubble.playbackError !== "") {
            videoBubble.playbackError = ""
            root.videoRetryToken++
        }
        if (!root.shouldLoadVideo) {
            root.videoLoadRequested = true
            Qt.callLater(function() { videoBubble.toggleInlinePlayback() })
            return
        }
        if (inlineVideoPlayer.playing) {
            inlineVideoPlayer.pause()
            persistInlinePosition(false)
            return
        }
        if (!inlineStarted) {
            inlineStarted = true
            restorePending = true
            restoreInlinePosition()
        }
        inlineVideoPlayer.play()
        restoreInlinePosition()
    }

    function openExpandedPlayer() {
        if (inlineVideoPlayer.playing)
            inlineVideoPlayer.pause()
        persistInlinePosition(true)
        root.videoOpenRequested({
            event_id: root.eventId,
            title: root.body,
            media_url: root.mediaUrl,
            media_file: root.mediaFile,
            media_mime_type: root.mediaMimeType
        })
    }

    Chat.InlineVideoPlayer {
        id: inlineVideoPlayer
        anchors.fill: parent
        source: root.videoAttachment && videoBubble.inlineStarted
            ? Utils.withRetryToken(
                Utils.proxyUrl(root.mediaUrl, root.mediaProxy,
                               root.mediaFile, root.mediaMimeType),
                root.videoRetryToken) : ""

        onMediaFailed: function(errorText) {
            videoBubble.playbackError = errorText
                || L10n.I18n.tr("Не удалось воспроизвести видео")
        }

        onDurationChanged: function() {
            if (!videoBubble.inlineStarted) {
                // Keep the idle card on the true first frame instead of
                // seeking a little forward just to obtain a thumbnail.
                inlineVideoPlayer.position = Math.min(1, Math.max(0, inlineVideoPlayer.duration - 1))
                inlineVideoPlayer.pause()
            }
            videoBubble.restoreInlinePosition()
        }
        onMediaLoaded: function() {
            if (!videoBubble.inlineStarted) {
                inlineVideoPlayer.position = inlineVideoPlayer.duration > 1 ? 1 : 0
                inlineVideoPlayer.pause()
            }
        }
        onEnded: function() {
            L10n.VideoPlaybackStore.clearPosition(root.eventId, root.mediaUrl)
            L10n.VideoPlaybackStore.flush()
            videoBubble.lastKnownPosition = 0
            videoBubble.inlineStarted = false
            inlineVideoPlayer.position = 0
        }
        onPositionChanged: function() {
            if (videoBubble.inlineStarted)
                videoBubble.lastKnownPosition = inlineVideoPlayer.position
        }
    }

    // A light veil keeps the center control readable while leaving the
    // first video frame visible before playback starts.
    Rectangle {
        anchors.fill: parent
        color: inlineVideoMouse.pressed
            ? Qt.rgba(0, 0, 0, 0.20)
            : inlineVideoMouse.containsMouse
                ? Qt.rgba(0, 0, 0, 0.10)
                : "transparent"
        Behavior on color {
            ColorAnimation { duration: L10n.UiPreferences.duration(110) }
        }
    }

    Rectangle {
        id: inlinePlayBadge
        anchors.centerIn: parent
        width: 50
        height: 50
        radius: 25
        visible: !inlineVideoPlayer.playing
            || inlineVideoMouse.containsMouse
        opacity: inlineVideoPlayer.playing
            && !inlineVideoMouse.containsMouse ? 0 : 1
        scale: inlineVideoMouse.pressed ? 0.90
            : inlineVideoMouse.containsMouse ? 1.04 : 1.0
        color: Qt.rgba(0, 0, 0, 0.62)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.26)

        Behavior on opacity { NumberAnimation { duration: L10n.UiPreferences.duration(100) } }
        Behavior on scale {
            NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
        }

        Item {
            anchors.centerIn: parent
            width: 20
            height: 20

            Item {
                anchors.centerIn: parent
                width: 18
                height: 18
                visible: inlineVideoPlayer.playing
                Rectangle { x: 4; y: 3; width: 3; height: 12; radius: 1.5; color: "white" }
                Rectangle { x: 11; y: 3; width: 3; height: 12; radius: 1.5; color: "white" }
            }

            Canvas {
                anchors.centerIn: parent
                width: 20
                height: 20
                visible: !inlineVideoPlayer.playing
                onVisibleChanged: if (visible) requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = "white"
                    ctx.beginPath()
                    // Slight optical correction: the centroid of a
                    // triangle is left of its bounding-box center.
                    ctx.moveTo(5, 3)
                    ctx.lineTo(16, 10)
                    ctx.lineTo(5, 17)
                    ctx.closePath()
                    ctx.fill()
                }
                Component.onCompleted: requestPaint()
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: inlinePlayBadge.bottom
        anchors.topMargin: 7
        visible: videoBubble.playbackError !== ""
        text: L10n.I18n.tr("Ошибка загрузки · нажмите, чтобы повторить")
        color: "#ff8a8a"
        font.pointSize: 8
    }

    // Minimal inline progress strip. Seeking does not open the popup.
    Rectangle {
        anchors.left: parent.left
        anchors.right: expandVideoButton.left
        anchors.rightMargin: 8
        anchors.bottom: parent.bottom
        anchors.leftMargin: 10
        anchors.bottomMargin: 9
        height: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.22)

        Rectangle {
            width: inlineVideoPlayer.duration > 0
                ? parent.width * Math.max(0, Math.min(1,
                    inlineVideoPlayer.position / inlineVideoPlayer.duration)) : 0
            height: parent.height
            radius: parent.radius
            color: root.accentColor
        }

        MouseArea {
            anchors.fill: parent
            anchors.topMargin: -6
            anchors.bottomMargin: -6
            cursorShape: Qt.PointingHandCursor
            enabled: inlineVideoPlayer.duration > 0 && inlineVideoPlayer.seekable
            onClicked: function(mouse) {
                inlineVideoPlayer.position = Math.round(
                    Math.max(0, Math.min(1, mouse.x / width)) * inlineVideoPlayer.duration)
                if (!videoBubble.inlineStarted)
                    videoBubble.inlineStarted = true
                videoBubble.lastKnownPosition = inlineVideoPlayer.position
            }
        }
    }

    Basic.Button {
        id: expandVideoButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 8
        anchors.bottomMargin: 7
        width: 30
        height: 28
        padding: 0
        hoverEnabled: true
        scale: down ? 0.90 : 1
        onClicked: videoBubble.openExpandedPlayer()

        contentItem: Item {
            Canvas {
                id: inlineExpandIcon
                anchors.centerIn: parent
                width: 16
                height: 16
                property color iconColor: "white"
                onIconColorChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = iconColor
                    ctx.lineWidth = 1.6
                    ctx.lineCap = "round"
                    var inset = 2.4
                    var arm = 4.3
                    var far = width - inset
                    ctx.beginPath()
                    ctx.moveTo(inset, inset + arm); ctx.lineTo(inset, inset); ctx.lineTo(inset + arm, inset)
                    ctx.moveTo(far - arm, inset); ctx.lineTo(far, inset); ctx.lineTo(far, inset + arm)
                    ctx.moveTo(far, far - arm); ctx.lineTo(far, far); ctx.lineTo(far - arm, far)
                    ctx.moveTo(inset + arm, far); ctx.lineTo(inset, far); ctx.lineTo(inset, far - arm)
                    ctx.stroke()
                }
                Component.onCompleted: requestPaint()
            }
        }

        background: Rectangle {
            radius: 8
            color: expandVideoButton.down ? Qt.rgba(0, 0, 0, 0.72)
                : expandVideoButton.hovered ? Qt.rgba(0, 0, 0, 0.60)
                : Qt.rgba(0, 0, 0, 0.46)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.18)
            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
        }
        Behavior on scale {
            NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: inlineVideoMouse
        anchors.fill: parent
        anchors.bottomMargin: 38
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        enabled: root.mediaUrl !== ""
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: videoBubble.toggleInlinePlayback()
    }

    Timer {
        interval: 3000
        repeat: true
        running: inlineVideoPlayer.playing
        onTriggered: videoBubble.persistInlinePosition(false)
    }

    Component.onDestruction: videoBubble.persistInlinePosition(true)
}
