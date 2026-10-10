import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../utils" as L10n
import QtQuick.Layouts
import "../common"
import "../../assets/icons" as Icons
import "../../utils/PrismUtils.js" as Utils

Item {
    id: root

    anchors.fill: parent
    z: 9000

    property color accentColor: "#20D500"
    property color accentTextColor: "#071007"
    property color backgroundColor: "#07100A"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"
    property string mediaProxy: ""
    property bool roundAvatars: true
    property string currentUserId: ""
    property string currentDisplayName: ""
    property string currentUserAvatar: ""

    property bool opened: false
    property var details: null
    property real clickX: 0
    property real clickY: 0
    property bool ignoreBusy: false
    readonly property bool ignored: !!(details && (details.is_ignored
        || (details.room_member && details.room_member.is_ignored)))
    property bool moderationBusy: false
    readonly property bool canModerate: !!(details && !details.is_self
        && details.room_member
        && (details.viewer_can_kick || details.viewer_can_ban
            || details.viewer_can_manage_roles))

    visible: opened || panel.opacity > 0.01
    enabled: opened

    signal sendDmRequested(string userId)
    signal mentionRequested(string userId)
    signal copyUserIdRequested(string userId)
    signal ignoreRequested(string userId, bool ignored)
    signal moderationRequested(string roomId, string userId, string action,
                               var powerLevel)
    signal closed()

    function memberMembership() {
        return details && details.room_member
            ? String(details.room_member.membership || "") : ""
    }

    function requestModeration(action, powerLevel) {
        if (!details || !details.room_member || moderationBusy) return
        moderationBusy = true
        moderationRequested(details.room_member.room_id || "",
                            details.user_id || "", action, powerLevel)
    }

    function openModerationMenu() {
        var point = adminButton.mapToItem(Overlay.overlay, 0, adminButton.height + 5)
        moderationMenu.x = Math.max(8, Math.min(
            Overlay.overlay.width - moderationMenu.width - 8,
            point.x + adminButton.width - moderationMenu.width))
        moderationMenu.y = Math.max(8, Math.min(
            Overlay.overlay.height - moderationMenu.implicitHeight - 8, point.y))
        moderationMenu.open()
    }

    function positionPanel() {
        var targetX = clickX - panel.width / 2
        var targetY = clickY - panel.height - 12
        if (targetY < 10)
            targetY = clickY + 20

        var maxX = Math.max(10, root.width - panel.width - 10)
        var maxY = Math.max(10, root.height - panel.height - 10)
        panel.x = Math.max(10, Math.min(maxX, targetX))
        panel.y = Math.max(10, Math.min(maxY, targetY))
    }

    function open(userDetails, sourceX, sourceY) {
        details = userDetails
        clickX = sourceX
        clickY = sourceY
        opened = true
        Qt.callLater(function() { root.positionPanel() })
    }

    function close() {
        opened = false
        root.closed()
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: root.close()
            onWheel: function(wheel) { wheel.accepted = true }
        }
    }

    Rectangle {
        id: panel
        width: 280
        color: root.surfaceColor
        radius: 14
        border.color: root.dividerColor
        border.width: 1

        opacity: root.opened ? 1.0 : 0.0
        scale: root.opened ? 1.0 : 0.95
        Behavior on opacity { NumberAnimation { duration: L10n.UiPreferences.duration(150); easing.type: Easing.OutQuad } }
        Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(150); easing.type: Easing.OutQuad } }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onWheel: function(wheel) { wheel.accepted = true }
        }

        Column {
            id: panelColumn
            width: parent.width

            Rectangle {
                id: panelHeader
                width: parent.width
                height: 76
                color: root.details ? Utils.avatarColor(root.details.user_id) : root.elevatedColor
                radius: 14

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 14
                    color: parent.color
                }

                Rectangle {
                    id: closeButton
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 10
                    width: 26
                    height: 26
                    radius: 13
                    color: closeBtnMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(0, 0, 0, 0.20)

                    Icons.CloseIcon {
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        color: "white"
                    }

                    MouseArea {
                        id: closeBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }

                Rectangle {
                    id: adminButton
                    visible: root.canModerate
                    anchors.top: parent.top
                    anchors.right: ignoreButton.left
                    anchors.topMargin: 10
                    anchors.rightMargin: 6
                    width: 26
                    height: 26
                    radius: 13
                    opacity: root.moderationBusy ? 0.55 : 1
                    scale: adminMouse.pressed ? 0.88 : 1
                    color: adminMouse.containsMouse
                        ? Qt.rgba(0, 0, 0, 0.38)
                        : Qt.rgba(0, 0, 0, 0.20)

                    Behavior on color {
                        ColorAnimation { duration: L10n.UiPreferences.duration(110) }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic }
                    }

                    Canvas {
                        anchors.centerIn: parent
                        width: 17
                        height: 17
                        antialiasing: true
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.strokeStyle = "white"
                            ctx.lineWidth = 1.35
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            var centerX = width / 2
                            var centerY = height / 2
                            var toothCount = 8
                            ctx.beginPath()
                            for (var i = 0; i < toothCount * 4; i++) {
                                var phase = i % 4
                                var radius = phase === 1 || phase === 2 ? 7.25 : 5.35
                                var angle = -Math.PI / 2
                                    + i * Math.PI * 2 / (toothCount * 4)
                                var x = centerX + Math.cos(angle) * radius
                                var y = centerY + Math.sin(angle) * radius
                                if (i === 0)
                                    ctx.moveTo(x, y)
                                else
                                    ctx.lineTo(x, y)
                            }
                            ctx.closePath()
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.arc(centerX, centerY, 2.25, 0, Math.PI * 2)
                            ctx.stroke()
                        }
                    }

                    MouseArea {
                        id: adminMouse
                        anchors.fill: parent
                        enabled: !root.moderationBusy
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openModerationMenu()
                    }

                    ToolTip.visible: adminMouse.containsMouse
                    ToolTip.delay: 300
                    ToolTip.text: L10n.I18n.tr("Действия администратора")
                }

                Rectangle {
                    id: ignoreButton
                    visible: root.details && root.details.user_id !== root.currentUserId
                        && !root.details.is_self
                    anchors.top: parent.top
                    anchors.right: closeButton.left
                    anchors.topMargin: 10
                    anchors.rightMargin: 6
                    width: 26
                    height: 26
                    radius: 13
                    opacity: root.ignoreBusy ? 0.55 : 1
                    color: root.ignored
                        ? "#d83c3e"
                        : ignoreMouse.containsMouse
                            ? Qt.rgba(0, 0, 0, 0.35)
                            : Qt.rgba(0, 0, 0, 0.20)

                    Behavior on color {
                        ColorAnimation { duration: L10n.UiPreferences.duration(110) }
                    }

                    Canvas {
                        id: ignoreIcon
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        antialiasing: true
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.strokeStyle = root.ignored ? "white" : "#ffb0b0"
                            ctx.lineWidth = 1.7
                            ctx.lineCap = "round"
                            ctx.beginPath()
                            ctx.arc(8, 8, 5.5, 0, Math.PI * 2)
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.moveTo(4.2, 11.8)
                            ctx.lineTo(11.8, 4.2)
                            ctx.stroke()
                        }
                        Connections {
                            target: root
                            function onIgnoredChanged() { ignoreIcon.requestPaint() }
                        }
                    }

                    MouseArea {
                        id: ignoreMouse
                        anchors.fill: parent
                        enabled: !root.ignoreBusy
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.ignoreRequested(root.details.user_id, !root.ignored)
                    }

                    ToolTip.visible: ignoreMouse.containsMouse
                    ToolTip.delay: 300
                    ToolTip.text: root.ignored
                        ? L10n.I18n.tr("Разблокировать пользователя")
                        : L10n.I18n.tr("Заблокировать пользователя")
                }

                Item {
                    x: 16
                    y: 34
                    width: 70
                    height: 70
                    z: 2

                    Rectangle {
                        anchors.fill: parent
                        radius: root.roundAvatars ? (parent.width / 2) : Math.round(parent.width * 0.22)
                        color: root.surfaceColor
                    }

                    AvatarItem {
                        anchors.centerIn: parent
                        width: parent.width - 6
                        height: parent.height - 6

                        mxcUrl: root.details && root.details.user_id === root.currentUserId
                            ? root.currentUserAvatar
                            : (root.details ? root.details.avatar_url : "")
                        fallbackId: root.details ? root.details.user_id : ""
                        mediaProxy: root.mediaProxy
                        roundAvatars: root.roundAvatars // <-- НАСТРОЙКА ТЕПЕРЬ РАБОТАЕТ ИДЕАЛЬНО
                        size: 64
                    }

                }
            }

            Column {
                width: parent.width - 32
                x: 16
                spacing: 0

                Item { width: 1; height: 40 } // Отступ под выступающий аватар

                Text {
                    width: parent.width
                    text: root.details && root.details.user_id === root.currentUserId
                        && root.currentDisplayName !== ""
                        ? root.currentDisplayName
                        : (root.details ? root.details.display_name : "")
                    color: root.textPrimary
                    font.bold: true
                    font.pointSize: 14
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Item { width: 1; height: 2 }

                Text {
                    id: matrixUserIdText
                    width: parent.width
                    text: root.details ? root.details.user_id : ""
                    color: matrixIdMouse.containsMouse
                        ? root.accentColor : root.textSecondary
                    font.pointSize: 9
                    elide: Text.ElideRight

                    MouseArea {
                        id: matrixIdMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.details && root.details.user_id)
                                root.copyUserIdRequested(root.details.user_id)
                        }
                    }
                    ToolTip.visible: matrixIdMouse.containsMouse
                    ToolTip.delay: 350
                    ToolTip.text: L10n.I18n.tr("Копировать Matrix ID")
                }

                Item {
                    visible: root.details && (root.details.is_admin
                        || root.details.is_moderator
                        || (root.details.room_member
                            && root.details.room_member.membership === "join"
                            && !root.details.is_admin
                            && !root.details.is_moderator))
                    width: parent.width
                    height: visible ? badgeRow.height + 10 : 0

                    Row {
                        id: badgeRow
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        spacing: 6

                        Rectangle {
                            visible: root.details && root.details.is_admin
                            height: 20
                            width: adminLabel.width + 14
                            radius: 4
                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                            Text {
                                id: adminLabel
                                anchors.centerIn: parent
                                text: L10n.I18n.tr("Админ")
                                color: root.accentColor
                                font.pointSize: 8
                                font.bold: true
                            }
                        }

                        Rectangle {
                            visible: root.details && !root.details.is_admin && root.details.is_moderator
                            height: 20
                            width: modLabel.width + 14
                            radius: 4
                            color: Qt.rgba(0.40, 0.52, 0.98, 0.18)
                            Text {
                                id: modLabel
                                anchors.centerIn: parent
                                text: L10n.I18n.tr("модератор")
                                color: "#667cfa"
                                font.pointSize: 8
                                font.bold: true
                            }
                        }

                        Rectangle {
                            visible: root.details && root.details.room_member
                                && root.details.room_member.membership === "join"
                                && !root.details.is_admin
                                && !root.details.is_moderator
                            height: 20
                            width: memberLabel.width + 14
                            radius: 4
                            color: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.12)

                            Text {
                                id: memberLabel
                                anchors.centerIn: parent
                                text: L10n.I18n.tr("Участник")
                                color: root.textSecondary
                                font.pointSize: 8
                                font.bold: true
                            }
                        }
                    }
                }

                Item {
                    width: 1
                    height: root.details && (root.details.is_admin
                        || root.details.is_moderator
                        || (root.details.room_member
                            && root.details.room_member.membership === "join")) ? 14 : 12
                }

                Item {
                    visible: root.details && root.details.can_send_dm
                    width: parent.width
                    height: visible ? 36 : 0

                    Rectangle {
                        id: dmButton
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 36
                        radius: 8
                        scale: dmMouse.pressed ? 0.97 : 1
                        color: dmMouse.pressed
                            ? Qt.darker(root.accentColor, 1.12)
                            : dmMouse.containsMouse ? Qt.lighter(root.accentColor, 1.1) : root.accentColor

                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                        Behavior on scale {
                            NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: L10n.I18n.tr("Написать сообщение")
                            color: root.accentTextColor
                            font.bold: true
                            font.pointSize: 10
                        }

                        MouseArea {
                            id: dmMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.sendDmRequested(root.details.user_id)
                                root.close()
                            }
                        }
                    }
                }

                Item {
                    visible: root.details && root.details.user_id
                        && root.details.user_id !== root.currentUserId
                        && root.details.room_member
                    width: parent.width
                    height: visible ? 42 : 0

                    Rectangle {
                        id: mentionButton
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 36
                        radius: 8
                        scale: mentionMouse.pressed ? 0.97 : 1
                        color: mentionMouse.pressed
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                      root.accentColor.b, 0.20)
                            : mentionMouse.containsMouse
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                          root.accentColor.b, 0.13)
                                : Qt.rgba(root.accentColor.r, root.accentColor.g,
                                          root.accentColor.b, 0.07)
                        border.width: 1
                        border.color: Qt.rgba(root.accentColor.r,
                                              root.accentColor.g,
                                              root.accentColor.b, 0.42)

                        Text {
                            anchors.centerIn: parent
                            text: L10n.I18n.tr("Упомянуть в чате")
                            color: root.accentColor
                            font.bold: true
                            font.pointSize: 9
                        }

                        MouseArea {
                            id: mentionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.mentionRequested(root.details.user_id)
                                root.close()
                            }
                        }
                    }
                }

                Item { width: 1; height: 10 }
            }
        }

        height: panelColumn.height
        onHeightChanged: if (root.opened) root.positionPanel()
    }

    onWidthChanged: if (opened) positionPanel()
    onHeightChanged: if (opened) positionPanel()

    Basic.Menu {
        id: moderationMenu
        parent: Overlay.overlay
        width: 224
        padding: 6
        modal: true
        dim: false
        closePolicy: Basic.Popup.CloseOnEscape | Basic.Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 10
            color: root.elevatedColor
            border.width: 1
            border.color: root.dividerColor
        }

        Basic.MenuItem {
            id: promoteItem
            visible: root.details && root.details.viewer_can_manage_roles
                && root.memberMembership() === "join"
                && Number(root.details.power_level || 0) < 50
            height: visible ? 38 : 0
            text: L10n.I18n.tr("Назначить модератором")
            onTriggered: root.requestModeration("set_power_level", 50)
            contentItem: Text {
                text: promoteItem.text; color: root.textPrimary; font.pointSize: 8
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                radius: 7
                color: promoteItem.highlighted
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                    : "transparent"
            }
        }

        Basic.MenuItem {
            id: demoteItem
            visible: root.details && root.details.viewer_can_manage_roles
                && root.memberMembership() === "join"
                && Number(root.details.power_level || 0) >= 50
            height: visible ? 38 : 0
            text: L10n.I18n.tr("Снять роль")
            onTriggered: root.requestModeration("set_power_level", 0)
            contentItem: Text {
                text: demoteItem.text; color: root.textPrimary; font.pointSize: 8
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                radius: 7
                color: demoteItem.highlighted
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                    : "transparent"
            }
        }

        Basic.MenuItem {
            id: kickItem
            visible: root.details && root.details.viewer_can_kick
                && root.memberMembership() === "join"
            height: visible ? 38 : 0
            text: L10n.I18n.tr("Исключить из комнаты")
            onTriggered: root.requestModeration("kick", undefined)
            contentItem: Text {
                text: kickItem.text; color: "#ffb36b"; font.pointSize: 8
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                radius: 7
                color: kickItem.highlighted ? Qt.rgba(1, 0.55, 0.2, 0.13) : "transparent"
            }
        }

        Basic.MenuItem {
            id: banItem
            visible: root.details && root.details.viewer_can_ban
                && root.memberMembership() !== "ban"
            height: visible ? 38 : 0
            text: L10n.I18n.tr("Заблокировать в комнате")
            onTriggered: root.requestModeration("ban", undefined)
            contentItem: Text {
                text: banItem.text; color: "#ff7777"; font.pointSize: 8
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                radius: 7
                color: banItem.highlighted ? Qt.rgba(1, 0.3, 0.3, 0.13) : "transparent"
            }
        }

        Basic.MenuItem {
            id: unbanItem
            visible: root.details && root.details.viewer_can_ban
                && root.memberMembership() === "ban"
            height: visible ? 38 : 0
            text: L10n.I18n.tr("Снять блокировку в комнате")
            onTriggered: root.requestModeration("unban", undefined)
            contentItem: Text {
                text: unbanItem.text; color: root.textPrimary; font.pointSize: 8
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
