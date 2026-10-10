import ".." as Chat
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "../../common"
import "../../../assets/icons" as Icons
import "../../../utils" as L10n
import "../../../utils/PrismUtils.js" as Utils

Rectangle {
    required property var attachments
    readonly property var root: attachments
    readonly property alias attachmentsMoveAreaObject: attachmentsMoveArea
    id: panel
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    x: Math.max(20, Math.min(parent.width - width - 20,
                             Math.round((parent.width - width) / 2 + dragOffsetX)))
    y: Math.max(20, Math.min(parent.height - height - 20,
                             Math.round((parent.height - height) / 2 + dragOffsetY)))
    width: Math.min(860, Math.max(320, root.width - 40))
    height: Math.min(650, Math.max(360, root.height - 40))
    radius: 16
    color: root.surfaceColor
    border.width: 1
    border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                          root.dividerColor.b, 0.9)
    transform: Matrix4x4 {
        matrix: PlanarTransform.fromShear(
                    Math.tan(attachmentsMoveArea.visualShearAngle * Math.PI / 180),
                    0, width / 2, 0)
    }
    scale: root.opened ? 1 : 0.96
    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(170); easing.type: Easing.OutCubic } }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: function(mouse) { mouse.accepted = true }
        onWheel: function(wheel) { wheel.accepted = true }
    }

    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 56

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.right: closeButton.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: L10n.I18n.tr("Вложения")
            color: root.textPrimary
            font.bold: true
            font.pointSize: 13
            elide: Text.ElideRight
        }

        PopupMoveArea {
            id: attachmentsMoveArea
            z: 1
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: closeButton.left
            moveTarget: panel
            movementBoundary: root
            leftEdge: 20
            topEdge: 20
            rightEdge: 20
            bottomEdge: 20
        }

        PopupCloseButton {
            id: closeButton
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            z: 2
            accentColor: root.accentColor
            textPrimary: root.textPrimary
            textSecondary: root.textSecondary
            onClicked: root.close()
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        height: 1
        color: root.dividerColor
        opacity: 0.55
    }

    Row {
        id: categoryTabs
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: 1
        height: 52
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 7

        Repeater {
            model: [L10n.I18n.tr("Медиа"), L10n.I18n.tr("Ссылки"),
                    L10n.I18n.tr("Файлы"), L10n.I18n.tr("Голосовые")]

            delegate: Rectangle {
                id: tabItem
                required property string modelData
                required property int index
                width: Math.max(66, (categoryTabs.width - categoryTabs.spacing * 3) / 4)
                height: 34
                anchors.verticalCenter: parent.verticalCenter
                radius: 10
                scale: tabMouse.pressed ? 0.94 : 1
                color: root.currentCategory === index
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.17)
                    : tabMouse.containsMouse
                        ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.06)
                        : "transparent"
                border.width: root.currentCategory === index ? 1 : 0
                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                      root.accentColor.b, 0.55)
                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(95); easing.type: Easing.OutCubic } }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 10
                    text: tabItem.modelData + "  " + root.categoryCount(tabItem.index)
                    color: root.currentCategory === tabItem.index
                        ? root.accentColor : root.textSecondary
                    font.bold: root.currentCategory === tabItem.index
                    font.pointSize: 8
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.currentCategory = tabItem.index
                }
            }
        }
    }

    StackLayout {
        id: pages
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: categoryTabs.bottom
        anchors.bottom: footer.top
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        currentIndex: root.currentCategory

        GridView {
            id: mediaGrid
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.filtered(0)
            cellWidth: Math.max(132, width / Math.max(1, Math.floor(width / 150)))
            cellHeight: 150

            delegate: Rectangle {
                id: mediaTile
                required property var modelData
                property int retryToken: 0
                onModelDataChanged: retryToken = 0
                width: GridView.view.cellWidth - 8
                readonly property bool videoItem: root.isVideoItem(modelData)
                readonly property string videoSource: videoItem && root.autoLoadVideos
                    ? Utils.proxyUrl(modelData.media_url || "", root.mediaProxy,
                                     modelData.media_file, modelData.media_mime_type)
                    : ""
                readonly property bool videoPreviewReady: videoPreviewLoader.item
                    ? videoPreviewLoader.item.ready : false
                height: GridView.view.cellHeight - 8
                radius: 11
                clip: true
                scale: mediaMouse.pressed ? 0.97 : 1
                color: root.elevatedColor
                border.width: 1
                border.color: mediaMouse.containsMouse
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.65)
                    : Qt.rgba(root.dividerColor.r, root.dividerColor.g, root.dividerColor.b, 0.55)
                Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(95); easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }

                Image {
                    id: mediaImage
                    anchors.fill: parent
                    source: ((mediaTile.modelData.msg_type || "") === "m.image"
                             || (mediaTile.modelData.msg_type || "") === "m.sticker")
                            && root.autoLoadImages
                        ? Utils.withRetryToken(
                            Utils.proxyUrl(mediaTile.modelData.media_url || "",
                                           root.mediaProxy,
                                           mediaTile.modelData.media_file,
                                           mediaTile.modelData.media_mime_type),
                            mediaTile.retryToken) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                    visible: source !== "" && status !== Image.Error
                }

                Loader {
                    id: videoPreviewLoader
                    anchors.fill: parent
                    active: root.opened && mediaTile.videoItem && root.autoLoadVideos
                        && mediaTile.videoSource !== ""
                    visible: active && mediaTile.videoPreviewReady
                    sourceComponent: Component {
                        Chat.AttachmentVideoPreview {
                            source: mediaTile.videoSource
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    visible: root.isVideoItem(mediaTile.modelData)
                        || (((mediaTile.modelData.msg_type || "") === "m.image"
                             || (mediaTile.modelData.msg_type || "") === "m.sticker")
                            && !root.autoLoadImages)
                        || mediaImage.status === Image.Error
                    color: mediaTile.videoPreviewReady
                        ? Qt.rgba(0, 0, 0, 0.20)
                        : Qt.rgba(root.accentColor.r, root.accentColor.g,
                                  root.accentColor.b, 0.08)

                    Rectangle {
                        id: playBadge
                        visible: mediaTile.videoItem || !root.autoLoadImages
                        anchors.centerIn: parent
                        width: 46
                        height: 46
                        radius: 23
                        scale: mediaMouse.containsMouse ? 1.08 : 1
                        color: mediaMouse.containsMouse
                            ? root.accentColor : Qt.rgba(0.03, 0.04, 0.05, 0.76)
                        border.width: 1
                        border.color: mediaMouse.containsMouse
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                      root.accentColor.b, 0.95)
                            : Qt.rgba(1, 1, 1, 0.72)
                        Behavior on scale {
                            NumberAnimation { duration: L10n.UiPreferences.duration(120); easing.type: Easing.OutBack }
                        }
                        Behavior on color {
                            ColorAnimation { duration: L10n.UiPreferences.duration(110) }
                        }

                        Canvas {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: 1
                            width: 18
                            height: 22
                            antialiasing: true
                            property color triangleColor: mediaMouse.containsMouse
                                ? root.accentTextColor : "white"
                            onTriangleColorChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                ctx.fillStyle = triangleColor
                                ctx.beginPath()
                                ctx.moveTo(3.5, 2.5)
                                ctx.quadraticCurveTo(3, 2, 3, 4)
                                ctx.lineTo(3, 18)
                                ctx.quadraticCurveTo(3, 20, 4.7, 19)
                                ctx.lineTo(16, 12)
                                ctx.quadraticCurveTo(17.5, 11, 16, 10)
                                ctx.closePath()
                                ctx.fill()
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        visible: mediaImage.status === Image.Error
                        spacing: 7
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: L10n.I18n.tr("Не удалось загрузить")
                            color: "#ff8a8a"
                            font.pointSize: 8
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: attachmentRetryLabel.implicitWidth + 20
                            height: 28
                            radius: 8
                            color: Qt.rgba(root.accentColor.r,
                                           root.accentColor.g,
                                           root.accentColor.b, 0.18)
                            border.width: 1
                            border.color: root.accentColor
                            Text {
                                id: attachmentRetryLabel
                                anchors.centerIn: parent
                                text: L10n.I18n.tr("Повторить")
                                color: root.accentColor
                                font.bold: true
                                font.pointSize: 8
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 34
                    color: Qt.rgba(0, 0, 0, 0.62)
                    Text {
                        anchors.fill: parent
                        anchors.margins: 7
                        text: mediaTile.modelData.body
                            || (root.isVideoItem(mediaTile.modelData)
                                ? L10n.I18n.tr("Видео")
                                : (mediaTile.modelData.msg_type || "") === "m.sticker"
                                    ? L10n.I18n.tr("Стикер")
                                    : L10n.I18n.tr("Изображение"))
                        color: "white"
                        font.pointSize: 7
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                MouseArea {
                    id: mediaMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton)
                            root.openAttachmentContext(mediaTile.modelData, mediaMouse,
                                                       mouse.x, mouse.y)
                        else if (mediaImage.status === Image.Error)
                            mediaTile.retryToken++
                        else
                            root.openMedia(mediaTile.modelData)
                    }
                }
            }

            ScrollBar.vertical: PrismScrollBar {
                policy: ScrollBar.AsNeeded
                autoHide: true
                handleColor: root.textSecondary
                handleHoverColor: root.accentColor
                trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                    root.textSecondary.b, 0.14)
            }
        }

        ListView {
            id: linksList
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: root.filtered(1)
            delegate: Rectangle {
                id: linkItem
                required property var modelData
                x: 4
                width: Math.max(0, ListView.view.width - 12)
                height: 72
                radius: 10
                clip: true
                scale: linkMouse.pressed ? 0.96 : 1
                color: linkMouse.pressed
                    ? root.blendedColor(root.elevatedColor, root.accentColor, 0.18)
                    : linkMouse.containsMouse
                        ? root.blendedColor(root.elevatedColor, root.accentColor, 0.08)
                        : root.elevatedColor
                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic } }

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 5

                    Text {
                        width: parent.width
                        height: 15
                        text: root.firstLink(linkItem.modelData.body || "")
                        textFormat: Text.PlainText
                        color: root.accentColor
                        font.bold: true
                        font.pointSize: 9
                        wrapMode: Text.NoWrap
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        clip: true
                    }

                    Text {
                        width: parent.width
                        height: 14
                        text: linkItem.modelData.body || ""
                        textFormat: Text.PlainText
                        color: root.textPrimary
                        opacity: 0.78
                        font.pointSize: 8
                        wrapMode: Text.NoWrap
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        clip: true
                    }

                    Text {
                        width: parent.width
                        height: 12
                        text: root.authorName(linkItem.modelData.sender || "", linkItem.modelData.sender_display_name || "")
                            + " · " + root.timestampText(linkItem.modelData.timestamp)
                        textFormat: Text.PlainText
                        color: root.textSecondary
                        font.pointSize: 7
                        wrapMode: Text.NoWrap
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        clip: true
                    }
                }
                MouseArea {
                    id: linkMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton)
                            root.openAttachmentContext(linkItem.modelData, linkMouse,
                                                       mouse.x, mouse.y)
                        else
                            root.urlRequested(root.firstLink(linkItem.modelData.body || ""))
                    }
                }
            }
            ScrollBar.vertical: PrismScrollBar { policy: ScrollBar.AsNeeded; autoHide: true; handleColor: root.textSecondary; handleHoverColor: root.accentColor; trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.14) }
        }

        ListView {
            id: filesList
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: root.filtered(2)
            delegate: Rectangle {
                id: fileItem
                required property var modelData
                width: ListView.view.width - 8
                height: 64
                radius: 10
                scale: fileMouse.pressed ? 0.98 : 1
                color: fileMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.09) : root.elevatedColor
                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(95); easing.type: Easing.OutCubic } }
                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 38
                    height: 38
                    radius: 10
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                   root.accentColor.b, 0.13)
                    Icons.DownloadIcon {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        color: root.iconColor
                    }
                }
                Column { anchors.left: parent.left; anchors.leftMargin: 58; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 4; Text { width: parent.width; text: fileItem.modelData.body || L10n.I18n.tr("Файлы"); color: root.textPrimary; font.bold: true; font.pointSize: 9; elide: Text.ElideRight } Text { width: parent.width; text: root.authorName(fileItem.modelData.sender || "", fileItem.modelData.sender_display_name || "") + " · " + root.timestampText(fileItem.modelData.timestamp); color: root.textSecondary; font.pointSize: 7; elide: Text.ElideRight } }
                MouseArea {
                    id: fileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton)
                            root.openAttachmentContext(fileItem.modelData, fileMouse,
                                                       mouse.x, mouse.y)
                        else
                            root.openFile(fileItem.modelData)
                    }
                }
            }
            ScrollBar.vertical: PrismScrollBar { policy: ScrollBar.AsNeeded; autoHide: true; handleColor: root.textSecondary; handleHoverColor: root.accentColor; trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.14) }
        }

        ListView {
            id: voiceList
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: root.filtered(3)
            delegate: Rectangle {
                id: voiceItem
                required property var modelData
                readonly property bool current: root.activeVoiceEventId === (modelData.event_id || modelData.media_url)
                readonly property bool playing: current && root.activeVoicePlaying
                width: ListView.view.width - 8
                height: 64
                radius: 10
                scale: voiceMouse.pressed ? 0.96 : 1
                color: voiceMouse.pressed
                    ? root.blendedColor(root.elevatedColor, root.accentColor, 0.18)
                    : voiceMouse.containsMouse
                        ? root.blendedColor(root.elevatedColor, root.accentColor, 0.08)
                        : root.elevatedColor
                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 38
                    height: 38
                    radius: 19
                    color: voiceItem.current ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15)
                    Canvas {
                        anchors.centerIn: parent
                        width: 17
                        height: 17
                        antialiasing: true
                        property bool playing: voiceItem.playing
                        property color iconColor: voiceItem.current ? root.accentTextColor : root.accentColor
                        onPlayingChanged: requestPaint()
                        onIconColorChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.fillStyle = iconColor
                            if (playing) {
                                ctx.fillRect(3.5, 3, 3.2, 11)
                                ctx.fillRect(10.3, 3, 3.2, 11)
                            } else {
                                ctx.beginPath()
                                ctx.moveTo(4, 2.5)
                                ctx.lineTo(14, 8.5)
                                ctx.lineTo(4, 14.5)
                                ctx.closePath()
                                ctx.fill()
                            }
                        }
                    }
                }
                Column { anchors.left: parent.left; anchors.leftMargin: 58; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 4; Text { width: parent.width; text: L10n.I18n.tr("Голосовое сообщение"); color: root.textPrimary; font.bold: true; font.pointSize: 9; elide: Text.ElideRight } Text { width: parent.width; text: root.authorName(voiceItem.modelData.sender || "", voiceItem.modelData.sender_display_name || "") + " · " + root.timestampText(voiceItem.modelData.timestamp); color: root.textSecondary; font.pointSize: 7; elide: Text.ElideRight } }
                MouseArea {
                    id: voiceMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton)
                            root.openAttachmentContext(voiceItem.modelData, voiceMouse,
                                                       mouse.x, mouse.y)
                        else
                            root.toggleVoice(voiceItem.modelData)
                    }
                }
            }
            ScrollBar.vertical: PrismScrollBar { policy: ScrollBar.AsNeeded; autoHide: true; handleColor: root.textSecondary; handleHoverColor: root.accentColor; trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.14) }
        }
    }

    Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.loading || root.canLoadMore || root.errorText !== "" ? 54 : 0
        Behavior on height { NumberAnimation { duration: L10n.UiPreferences.duration(120); easing.type: Easing.OutCubic } }

        Row {
            visible: root.loading
            anchors.centerIn: parent
            spacing: 9
            PrismBusyIndicator { width: 20; height: 20; running: parent.visible; accentColor: root.accentColor }
            Text { anchors.verticalCenter: parent.verticalCenter; text: L10n.I18n.tr("Загрузка вложений…"); color: root.textSecondary; font.pointSize: 8 }
        }

        Rectangle {
            objectName: "attachmentsLoadMore"
            visible: !root.loading && (root.canLoadMore || root.errorText !== "")
            anchors.centerIn: parent
            width: 164
            height: 34
            radius: 10
            color: loadMoreMouse.containsMouse
                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
            border.width: 1
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                  root.accentColor.b, 0.55)

            Text {
                anchors.centerIn: parent
                text: root.errorText !== "" ? L10n.I18n.tr("Повторить") : L10n.I18n.tr("Загрузить ещё")
                color: root.accentColor
                font.bold: true
                font.pointSize: 8
            }

            MouseArea {
                id: loadMoreMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.errorText !== "" ? root.requestPage(root.nextFrom) : root.requestNextPage()
            }
        }
    }

    Column {
        visible: !root.loading && root.filtered(root.currentCategory).length === 0
        anchors.centerIn: pages
        width: Math.min(360, pages.width - 30)
        spacing: 9
        Text { width: parent.width; text: root.errorText !== "" ? L10n.I18n.tr("Не удалось загрузить вложения") : L10n.I18n.tr("В этой категории пока ничего нет"); color: root.errorText !== "" ? "#ff6b6b" : root.textSecondary; font.bold: root.errorText !== ""; font.pointSize: 10; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap }
        Text { visible: root.errorText !== ""; width: parent.width; text: root.errorText; color: root.textSecondary; font.pointSize: 8; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap }
    }

}
