import ".." as Navigation
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../common"
import "../../../assets/icons" as Icons
import "../../../utils/PrismUtils.js" as Utils

Basic.Menu {
    required property var sidebar
    readonly property var root: sidebar
    required property var leaveConfirmDialogObject
    id: roomMenu
    parent: Overlay.overlay
    width: Math.ceil(Math.max(roomInfoMenuContent.implicitWidth,
                              copyRoomLinkContent.implicitWidth,
                              root.contextRoomCanEdit ? editRoomContent.implicitWidth : 0,
                              readStateContent.implicitWidth,
                              previewRoomContent.implicitWidth,
                              pinRoomContent.implicitWidth,
                              archiveRoomContent.implicitWidth,
                              blockRoomContent.implicitWidth,
                              muteRoomContent.implicitWidth,
                              leaveRoomContent.implicitWidth) + 32)
    padding: 6
    modal: true
    dim: false
    x: Math.round(Math.max(8, Math.min(parent.width - width - 8, root.contextMenuX)))
    y: Math.round(Math.max(8, Math.min(parent.height - height - 8, root.contextMenuY)))

    background: Rectangle {
        color: root.elevatedColor
        radius: 10
        border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g, root.dividerColor.b, 0.9)
        border.width: 1
    }

    Basic.MenuItem {
        id: roomInfoAction
        width: roomMenu.availableWidth
        height: 40
        padding: 0
        leftPadding: 10
        rightPadding: 10
        hoverEnabled: true
        scale: down ? 0.97 : 1
        text: root.contextIsSpace
            ? L10n.I18n.tr("Информация о пространстве")
            : L10n.I18n.tr("Информация о комнате")
        onTriggered: root.roomInfoRequested(root.contextRoomId)

        Behavior on scale {
            NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
        }


        contentItem: Row {
            id: roomInfoMenuContent
            spacing: 10
            Canvas {
                id: roomInfoIconCanvas
                width: 20; height: 20
                anchors.verticalCenter: parent.verticalCenter
                onPaint: root.drawIcon(getContext("2d"), "info", root.textSecondary, width, height)
                Connections { target: root; function onTextSecondaryChanged() { roomInfoIconCanvas.requestPaint() } }
            }
            Text {
                text: roomInfoAction.text
                color: root.textPrimary
                font.pointSize: 9
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        background: Rectangle {
            radius: 7
            color: roomInfoAction.down
                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.23)
                : roomInfoAction.highlighted || roomInfoAction.hovered
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.13)
                    : "transparent"
            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
        }
    }


    Basic.MenuItem {
        id: copyRoomLinkAction
        width: roomMenu.availableWidth
        height: 40
        padding: 0
        leftPadding: 10
        rightPadding: 10
        hoverEnabled: true
        scale: down ? 0.97 : 1
        text: root.contextIsSpace
            ? L10n.I18n.tr("Копировать ссылку на пространство")
            : L10n.I18n.tr("Копировать ссылку на комнату")
        onTriggered: root.roomLinkCopyRequested(root.contextRoomId,
                                                 root.contextIsSpace)

        Behavior on scale {
            NumberAnimation {
                duration: L10n.UiPreferences.duration(100)
                easing.type: Easing.OutCubic
            }
        }

        contentItem: Row {
            id: copyRoomLinkContent
            spacing: 10
            Canvas {
                id: copyRoomLinkIconCanvas
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                onPaint: root.drawIcon(getContext("2d"), "link",
                                       root.textSecondary, width, height)
                Connections {
                    target: root
                    function onTextSecondaryChanged() {
                        copyRoomLinkIconCanvas.requestPaint()
                    }
                }
            }
            Text {
                text: copyRoomLinkAction.text
                color: root.textPrimary
                font.pointSize: 9
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        background: Rectangle {
            radius: 7
            color: copyRoomLinkAction.down
                ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                          root.accentColor.b, 0.23)
                : copyRoomLinkAction.highlighted || copyRoomLinkAction.hovered
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, 0.13)
                    : "transparent"
            Behavior on color {
                ColorAnimation { duration: L10n.UiPreferences.duration(110) }
            }
        }
    }


    Basic.MenuItem {
        id: readStateAction
        visible: true
        width: roomMenu.availableWidth
        height: 40
        padding: 0
        leftPadding: 10
        rightPadding: 10
        hoverEnabled: true
        scale: down ? 0.97 : 1
        text: L10n.I18n.tr("Отметить прочитанным")
        onTriggered: root.roomReadStateRequested(root.contextRoomId, false)

        Behavior on scale {
            NumberAnimation {
                duration: L10n.UiPreferences.duration(100)
                easing.type: Easing.OutCubic
            }
        }

        contentItem: Row {
            id: readStateContent
            spacing: 10
            Canvas {
                id: readStateIconCanvas
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                onPaint: root.drawIcon(getContext("2d"), "read",
                                       root.textSecondary, width, height)
                Connections {
                    target: root
                    function onTextSecondaryChanged() {
                        readStateIconCanvas.requestPaint()
                    }
                }
            }
            Text {
                text: readStateAction.text
                color: root.textPrimary
                font.pointSize: 9
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        background: Rectangle {
            radius: 7
            color: readStateAction.down
                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.23)
                : readStateAction.highlighted || readStateAction.hovered
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.13)
                    : "transparent"
            Behavior on color {
                ColorAnimation { duration: L10n.UiPreferences.duration(110) }
            }
        }
    }

    Basic.MenuItem {
        id: editRoomAction
        width: roomMenu.availableWidth
        visible: root.contextRoomCanEdit
        height: visible ? 40 : 0
        padding: 0
        leftPadding: 10
        rightPadding: 10
        hoverEnabled: true
        scale: down ? 0.97 : 1
        text: root.contextIsSpace
            ? L10n.I18n.tr("Редактировать пространство")
            : L10n.I18n.tr("Редактировать комнату")
        onTriggered: root.roomEditRequested(root.contextRoomId)

        Behavior on scale {
            NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
        }

        contentItem: Row {
            id: editRoomContent
            spacing: 10
            Canvas {
                id: editRoomIconCanvas
                width: 20; height: 20
                anchors.verticalCenter: parent.verticalCenter
                onPaint: root.drawIcon(getContext("2d"), "edit", root.textSecondary, width, height)
                Connections { target: root; function onTextSecondaryChanged() { editRoomIconCanvas.requestPaint() } }
            }
            Text {
                text: editRoomAction.text
                color: root.textPrimary
                font.pointSize: 9
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        background: Rectangle {
            radius: 7
            color: editRoomAction.down
                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.23)
                : editRoomAction.highlighted || editRoomAction.hovered
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.13)
                    : "transparent"
            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
        }
    }

    Basic.MenuItem {
        id: previewRoomAction
        visible: !root.contextIsSpace
        width: roomMenu.availableWidth
        height: visible ? 40 : 0
        padding: 0
        leftPadding: 10
        rightPadding: 10
        hoverEnabled: true
        scale: down ? 0.97 : 1
        text: L10n.I18n.tr("Предпросмотр чата")
        onTriggered: root.roomPreviewRequested(root.contextRoomId, root.contextRoomName)

        Behavior on scale {
            NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
        }

        contentItem: Row {
            id: previewRoomContent
            spacing: 10
            Canvas {
                id: previewRoomIconCanvas
                width: 20; height: 20
                anchors.verticalCenter: parent.verticalCenter
                onPaint: root.drawIcon(getContext("2d"), "preview", root.textSecondary, width, height)
                Connections { target: root; function onTextSecondaryChanged() { previewRoomIconCanvas.requestPaint() } }
            }
            Text {
                text: previewRoomAction.text
                color: root.textPrimary
                font.pointSize: 9
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        background: Rectangle {
            radius: 7
            color: previewRoomAction.down
                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.23)
                : previewRoomAction.highlighted || previewRoomAction.hovered
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.13)
                    : "transparent"
            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
        }
    }
    Basic.MenuItem {
        id: pinRoomAction
        visible: !root.contextIsSpace && !root.contextRoomArchived
        width: roomMenu.availableWidth
        height: visible ? 40 : 0
        padding: 0
        leftPadding: 10
        rightPadding: 10
        hoverEnabled: true
        scale: down ? 0.97 : 1
        text: root.contextRoomPinned
            ? L10n.I18n.tr("Открепить чат")
            : L10n.I18n.tr("Закрепить чат")
        onTriggered: {
            root.roomPinRequested(root.contextRoomId, !root.contextRoomPinned)
            root.contextRoomPinned = !root.contextRoomPinned
        }

        Behavior on scale {
            NumberAnimation {
                duration: L10n.UiPreferences.duration(100)
                easing.type: Easing.OutCubic
            }
        }

        contentItem: Row {
            id: pinRoomContent
            spacing: 10
            Canvas {
                id: pinRoomIconCanvas
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                onPaint: root.drawIcon(getContext("2d"), "pin",
                                       root.accentColor, width, height)
            }
            Text {
                text: pinRoomAction.text
                color: root.textPrimary
                font.pointSize: 9
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        background: Rectangle {
            radius: 7
            color: pinRoomAction.down
                ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                          root.accentColor.b, 0.23)
                : pinRoomAction.highlighted || pinRoomAction.hovered
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, 0.13)
                    : "transparent"
            Behavior on color {
                ColorAnimation { duration: L10n.UiPreferences.duration(110) }
            }
        }
    }
    Basic.MenuItem {
        id: muteRoomAction
        visible: !root.contextIsSpace
        width: roomMenu.availableWidth
        height: visible ? 40 : 0
        padding: 0
        leftPadding: 10
        rightPadding: 10
        hoverEnabled: true
        scale: down ? 0.97 : 1
        text: root.contextRoomMuted
            ? L10n.I18n.tr("Включить уведомления")
            : L10n.I18n.tr("Отключить уведомления")
        onTriggered: {
            var nextMuted = !root.contextRoomMuted
            root.roomMuteRequested(root.contextRoomId, nextMuted)
            root.contextRoomMuted = nextMuted
        }

        Behavior on scale {
            NumberAnimation {
                duration: L10n.UiPreferences.duration(100)
                easing.type: Easing.OutCubic
            }
        }

        contentItem: Row {
            id: muteRoomContent
            spacing: 10
            Canvas {
                id: muteRoomIconCanvas
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                onPaint: root.drawIcon(getContext("2d"), "mute",
                                       root.accentColor, width, height)
                Connections {
                    target: root
                    function onAccentColorChanged() { muteRoomIconCanvas.requestPaint() }
                }
            }
            Text {
                text: muteRoomAction.text
                color: root.textPrimary
                font.pointSize: 9
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        background: Rectangle {
            radius: 7
            color: muteRoomAction.down
                ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                          root.accentColor.b, 0.23)
                : muteRoomAction.highlighted || muteRoomAction.hovered
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, 0.13)
                    : "transparent"
            Behavior on color {
                ColorAnimation { duration: L10n.UiPreferences.duration(110) }
            }
        }
    }

    Basic.MenuItem {
        id: archiveRoomAction
        visible: !root.contextIsSpace
        width: roomMenu.availableWidth
        height: visible ? 40 : 0
        padding: 0
        leftPadding: 10
        rightPadding: 10
        hoverEnabled: true
        scale: down ? 0.97 : 1
        text: root.contextRoomArchived
            ? L10n.I18n.tr("Вернуть из архива")
            : L10n.I18n.tr("Добавить в архив")
        onTriggered: {
            var nextArchived = !root.contextRoomArchived
            root.roomArchiveRequested(root.contextRoomId, nextArchived)
            root.contextRoomArchived = nextArchived
            if (nextArchived)
                root.contextRoomPinned = false
        }

        Behavior on scale {
            NumberAnimation {
                duration: L10n.UiPreferences.duration(100)
                easing.type: Easing.OutCubic
            }
        }

        contentItem: Row {
            id: archiveRoomContent
            spacing: 10
            Canvas {
                id: archiveRoomIconCanvas
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                onPaint: root.drawIcon(getContext("2d"), "archive",
                                       root.accentColor, width, height)
                Connections {
                    target: root
                    function onAccentColorChanged() { archiveRoomIconCanvas.requestPaint() }
                }
            }
            Text {
                text: archiveRoomAction.text
                color: root.textPrimary
                font.pointSize: 9
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        background: Rectangle {
            radius: 7
            color: archiveRoomAction.down
                ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                          root.accentColor.b, 0.23)
                : archiveRoomAction.highlighted || archiveRoomAction.hovered
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, 0.13)
                    : "transparent"
            Behavior on color {
                ColorAnimation { duration: L10n.UiPreferences.duration(110) }
            }
        }
    }

    Basic.MenuItem {
        id: blockRoomAction
        visible: root.contextRoomDirectUserId !== ""
        width: roomMenu.availableWidth
        height: visible ? 40 : 0
        padding: 0
        leftPadding: 10
        rightPadding: 10
        hoverEnabled: true
        scale: down ? 0.97 : 1
        text: root.contextRoomIgnored
            ? L10n.I18n.tr("Разблокировать чат")
            : L10n.I18n.tr("Заблокировать чат")
        onTriggered: root.userIgnoreRequested(root.contextRoomDirectUserId,
                                               !root.contextRoomIgnored)

        Behavior on scale {
            NumberAnimation {
                duration: L10n.UiPreferences.duration(100)
                easing.type: Easing.OutCubic
            }
        }

        contentItem: Row {
            id: blockRoomContent
            spacing: 10
            Canvas {
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                onPaint: root.drawIcon(getContext("2d"), "block", "#ff6b6b", width, height)
            }
            Text {
                text: blockRoomAction.text
                color: "#ff6b6b"
                font.pointSize: 9
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        background: Rectangle {
            radius: 7
            color: blockRoomAction.down
                ? Qt.rgba(1, 0.32, 0.32, 0.25)
                : blockRoomAction.highlighted || blockRoomAction.hovered
                    ? Qt.rgba(1, 0.32, 0.32, 0.16)
                    : "transparent"
            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
        }
    }
    Basic.MenuSeparator {
        width: roomMenu.availableWidth
        height: 7
        padding: 0
        contentItem: Rectangle {
            implicitHeight: 1
            color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                           root.dividerColor.b, 0.75)
        }
    }

    Basic.MenuItem {
        id: leaveRoomAction
        width: roomMenu.availableWidth
        height: 40
        padding: 0
        leftPadding: 10
        rightPadding: 10
        hoverEnabled: true
        scale: down ? 0.97 : 1
        text: root.contextIsSpace
            ? L10n.I18n.tr("Покинуть пространство")
            : L10n.I18n.tr("Покинуть комнату")
        onTriggered: {
            leaveConfirmDialogObject.roomId = root.contextRoomId
            leaveConfirmDialogObject.roomName = root.contextRoomName
            leaveConfirmDialogObject.isSpace = root.contextIsSpace
            leaveConfirmDialogObject.open()
        }

        Behavior on scale {
            NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
        }


        contentItem: Row {
            id: leaveRoomContent
            spacing: 10
            Canvas {
                width: 20; height: 20
                anchors.verticalCenter: parent.verticalCenter
                onPaint: root.drawIcon(getContext("2d"), "leave", "#ff6b6b", width, height)
            }
            Text {
                text: leaveRoomAction.text
                color: "#ff6b6b"
                font.pointSize: 9
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        background: Rectangle {
            radius: 7
            color: leaveRoomAction.down
                ? Qt.rgba(1, 0.32, 0.32, 0.25)
                : leaveRoomAction.highlighted || leaveRoomAction.hovered
                    ? Qt.rgba(1, 0.32, 0.32, 0.16)
                    : "transparent"
            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
        }
    }
}
