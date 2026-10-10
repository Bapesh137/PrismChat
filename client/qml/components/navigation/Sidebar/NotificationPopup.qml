import ".." as Navigation
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../common"
import "../../../assets/icons" as Icons
import "../../../utils/PrismUtils.js" as Utils

Popup {
    required property var sidebar
    readonly property var root: sidebar
    id: notificationPopup
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    parent: Overlay.overlay
    x: Math.max(12, Math.min(Overlay.overlay.width - width - 12,
                            root.mapToItem(Overlay.overlay,
                                           root.width - width, 0).x + dragOffsetX))
    y: Math.max(48, Math.min(Overlay.overlay.height - height - 12,
                            root.mapToItem(Overlay.overlay, 0, 42).y + dragOffsetY))
    width: 360
    height: Math.min(460, Math.max(180, Overlay.overlay.height - 60))
    leftMargin: 12
    rightMargin: 12
    topMargin: 48
    bottomMargin: 12
    padding: 0
    modal: false
    dim: false
    closePolicy: Popup.CloseOnEscape
    onOpened: {
        dragOffsetX = 0
        dragOffsetY = 0
        notificationMoveArea.resetMotion()
    }

    background: Rectangle {
        radius: 14
        color: root.surfaceColor
        border.width: 1
        border.color: root.dividerColor
        transform: Matrix4x4 {
            matrix: PlanarTransform.fromShear(
                        Math.tan(notificationMoveArea.visualShearAngle * Math.PI / 180),
                        0, width / 2, 0)
        }
    }

    contentItem: Item {
        transform: Matrix4x4 {
            matrix: PlanarTransform.fromShear(
                        Math.tan(notificationMoveArea.visualShearAngle * Math.PI / 180),
                        0, width / 2, 0)
        }

        Item {
            id: notificationPopupHeader
            anchors.top: parent.top
            width: parent.width
            height: 52

            PopupMoveArea {
                id: notificationMoveArea
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: clearNotificationsButton.visible
                    ? clearNotificationsButton.left : notificationPopupCloseButton.left
                moveTarget: notificationPopup
                movementBoundary: Overlay.overlay
                leftEdge: 12
                topEdge: 48
                rightEdge: 12
                bottomEdge: 12
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: clearNotificationsButton.visible
                    ? clearNotificationsButton.left : notificationPopupCloseButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.I18n.tr("Уведомления")
                elide: Text.ElideRight
                color: root.textPrimary
                font.pointSize: 11
                font.bold: true
            }

            Basic.Button {
                id: clearNotificationsButton
                visible: root.activeNotificationCount > 0
                anchors.right: notificationPopupCloseButton.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                height: 30
                leftPadding: 10
                rightPadding: 10
                hoverEnabled: true
                scale: down ? 0.96 : 1

                Behavior on scale {
                    NumberAnimation {
                        duration: L10n.UiPreferences.duration(100)
                        easing.type: Easing.OutCubic
                    }
                }

                background: Rectangle {
                    radius: 8
                    color: clearNotificationsButton.hovered
                        ? Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                  root.textPrimary.b, 0.08)
                        : "transparent"
                }
                contentItem: Text {
                    text: L10n.I18n.tr("Очистить")
                    color: root.textSecondary
                    font.pointSize: 8
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: root.notificationsClearRequested(root.notificationTab)
            }

            Basic.ToolButton {
                id: notificationPopupCloseButton
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                padding: 0
                hoverEnabled: true
                scale: down ? 0.90 : 1

                Behavior on scale {
                    NumberAnimation {
                        duration: L10n.UiPreferences.duration(100)
                        easing.type: Easing.OutCubic
                    }
                }

                contentItem: Canvas {
                    property color strokeColor: notificationPopupCloseButton.hovered
                        ? root.textPrimary : root.textSecondary
                    onStrokeColorChanged: requestPaint()
                    onPaint: root.drawCloseIcon(getContext("2d"), strokeColor,
                                                width, height)
                }
                background: Rectangle {
                    radius: 8
                    color: notificationPopupCloseButton.hovered
                        ? Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                  root.textPrimary.b, 0.08)
                        : "transparent"
                }
                PrismToolTip {
                    visible: notificationPopupCloseButton.hovered
                    text: L10n.I18n.tr("Закрыть")
                    surfaceColor: root.elevatedColor
                    textColor: root.textPrimary
                    dividerColor: root.dividerColor
                }
                onClicked: notificationPopup.close()
            }
        }

        Item {
            id: notificationTabs
            anchors.top: notificationPopupHeader.bottom
            width: parent.width
            height: 44

            Row {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.topMargin: 5
                anchors.bottomMargin: 5
                spacing: 6

                Basic.Button {
                    id: invitationsTabButton
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    hoverEnabled: true
                    padding: 0
                    scale: down ? 0.97 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: L10n.UiPreferences.duration(100)
                            easing.type: Easing.OutCubic
                        }
                    }
                    background: Rectangle {
                        radius: 9
                        color: root.notificationTab === "room_invitation"
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                      root.accentColor.b, 0.18)
                            : invitationsTabButton.hovered
                                ? Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                          root.textPrimary.b, 0.07)
                                : "transparent"
                        border.width: root.notificationTab === "room_invitation" ? 1 : 0
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                              root.accentColor.b, 0.38)
                    }
                    contentItem: Text {
                        text: L10n.I18n.tr("Приглашения")
                            + (root.invitationNotificationCount > 0
                               ? "  " + root.invitationNotificationCount : "")
                        color: root.notificationTab === "room_invitation"
                            ? root.textPrimary : root.textSecondary
                        font.pointSize: 8
                        font.bold: root.notificationTab === "room_invitation"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    onClicked: {
                        root.notificationTab = "room_invitation"
                        root.notificationsOpened(root.notificationTab)
                    }
                }

                Basic.Button {
                    id: mentionsTabButton
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    hoverEnabled: true
                    padding: 0
                    scale: down ? 0.97 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: L10n.UiPreferences.duration(100)
                            easing.type: Easing.OutCubic
                        }
                    }
                    background: Rectangle {
                        radius: 9
                        color: root.notificationTab === "mention"
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                      root.accentColor.b, 0.18)
                            : mentionsTabButton.hovered
                                ? Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                          root.textPrimary.b, 0.07)
                                : "transparent"
                        border.width: root.notificationTab === "mention" ? 1 : 0
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                              root.accentColor.b, 0.38)
                    }
                    contentItem: Text {
                        text: L10n.I18n.tr("Упоминания")
                            + (root.mentionNotificationCount > 0
                               ? "  " + root.mentionNotificationCount : "")
                        color: root.notificationTab === "mention"
                            ? root.textPrimary : root.textSecondary
                        font.pointSize: 8
                        font.bold: root.notificationTab === "mention"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    onClicked: {
                        root.notificationTab = "mention"
                        root.notificationsOpened(root.notificationTab)
                    }
                }
            }
        }

        Rectangle {
            id: notificationPopupDivider
            anchors.top: notificationTabs.bottom
            width: parent.width
            height: 1
            color: root.dividerColor
        }

        Item {
            anchors.top: notificationPopupDivider.bottom
            anchors.bottom: parent.bottom
            width: parent.width
            visible: root.activeNotificationCount === 0

            Column {
                anchors.centerIn: parent
                spacing: 8

                Canvas {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 28
                    height: 28
                    property color strokeColor: root.textSecondary
                    onStrokeColorChanged: requestPaint()
                    onPaint: root.drawIcon(getContext("2d"), "bell", strokeColor, width, height)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: L10n.I18n.tr("Новых уведомлений нет")
                    color: root.textSecondary
                    font.pointSize: 9
                }
            }
        }

        ListView {
            id: notificationList
            visible: root.activeNotificationCount > 0
            anchors.top: notificationPopupDivider.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8
            clip: true
            spacing: 6
            model: root.activeNotificationModel
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: PrismScrollBar {
                policy: ScrollBar.AsNeeded
                autoHide: true
                handleColor: root.textSecondary
                handleHoverColor: root.accentColor
                trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                    root.textSecondary.b, 0.14)
            }

            delegate: Rectangle {
                id: notificationDelegate
                width: notificationList.width
                height: notificationContent.implicitHeight + 20
                radius: 11
                required property string notification_id
                required property string notification_type
                required property string title
                required property string body
                required property string room_id
                required property string room_name
                required property double created_at
                required property bool unread
                property string notificationId: notification_id || ""
                property string notificationType: notification_type || "message"
                property string notificationRoomId: room_id || ""
                property string notificationRoomName: room_name || ""
                color: notificationDelegate.unread
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, 0.12)
                    : Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                              root.textPrimary.b, notificationMouse.containsMouse ? 0.07 : 0.035)
                border.width: 1
                border.color: notificationDelegate.unread
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, 0.35)
                    : "transparent"

                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }

                Rectangle {
                    visible: notificationDelegate.unread
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.top: parent.top
                    anchors.topMargin: 14
                    width: 6
                    height: 6
                    radius: 3
                    color: root.accentColor
                }

                Column {
                    id: notificationContent
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    anchors.right: notificationCloseButton.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Text {
                        width: parent.width
                        text: notificationDelegate.title || L10n.I18n.tr("PrismChat")
                        color: root.textPrimary
                        font.pointSize: 9
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: notificationDelegate.body || ""
                        color: root.textSecondary
                        font.pointSize: 8
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.notificationTime(notificationDelegate.created_at)
                        color: root.textSecondary
                        opacity: 0.7
                        font.pointSize: 7
                    }
                    Basic.Button {
                        id: acceptInviteButton
                        visible: notificationDelegate.notificationType === "room_invitation"
                        height: visible ? 30 : 0
                        width: 92
                        leftPadding: 10
                        rightPadding: 10
                        hoverEnabled: true
                        scale: down ? 0.96 : 1
                        Behavior on scale {
                            NumberAnimation {
                                duration: L10n.UiPreferences.duration(100)
                                easing.type: Easing.OutCubic
                            }
                        }
                        background: Rectangle {
                            radius: 8
                            color: acceptInviteButton.down
                                ? Qt.darker(root.accentColor, 1.15)
                                : root.accentColor
                        }
                        contentItem: Text {
                            text: L10n.I18n.tr("Принять")
                            color: root.accentTextColor
                            font.pointSize: 8
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            root.notificationActivated(
                                notificationDelegate.notificationId,
                                notificationDelegate.notificationType,
                                notificationDelegate.notificationRoomId,
                                notificationDelegate.notificationRoomName)
                            notificationPopup.close()
                        }
                    }
                }

                MouseArea {
                    id: notificationMouse
                    anchors.left: parent.left
                    anchors.right: notificationCloseButton.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: notificationDelegate.notificationType !== "room_invitation"
                    onClicked: {
                        root.notificationActivated(
                            notificationDelegate.notificationId,
                            notificationDelegate.notificationType,
                            notificationDelegate.notificationRoomId,
                            notificationDelegate.notificationRoomName)
                        notificationPopup.close()
                    }
                }

                Basic.ToolButton {
                    id: notificationCloseButton
                    anchors.right: parent.right
                    anchors.rightMargin: 7
                    anchors.top: parent.top
                    anchors.topMargin: 7
                    width: 26
                    height: 26
                    padding: 0
                    hoverEnabled: true
                    scale: down ? 0.90 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: L10n.UiPreferences.duration(100)
                            easing.type: Easing.OutCubic
                        }
                    }
                    contentItem: Canvas {
                        property color strokeColor: notificationCloseButton.hovered
                            ? root.textPrimary : root.textSecondary
                        onStrokeColorChanged: requestPaint()
                        onPaint: root.drawCloseIcon(getContext("2d"), strokeColor,
                                                    width, height)
                    }
                    background: Rectangle {
                        radius: 8
                        color: notificationCloseButton.hovered
                            ? Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                      root.textPrimary.b, 0.08)
                            : "transparent"
                    }
                    onClicked: root.notificationDismissed(
                        notificationDelegate.notificationId)
                }
            }
        }
    }
}
