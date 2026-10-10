import QtQuick
import "../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../common"
import "../../utils/PrismUtils.js" as Utils

Rectangle {
    id: root

    property var members: []
    property bool loading: false
    property string errorText: ""
    property int totalMemberCount: 0
    property var authorNameResolver: null
    property int authorNameRevision: 0
    property string currentRoomId: ""
    property string currentUserId: ""
    property string currentDisplayName: ""
    property string currentUserAvatar: ""
    property string mediaProxy: ""
    property bool roundAvatars: true
    property bool collapsed: false
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"
    property color accentColor: "#20D500"
    property color iconColor: accentColor

    signal userRequested(string userId, real clickX, real clickY)
    signal attachmentsRequested()
    signal membersMoreRequested(string roomId)
    signal retryRequested()

    property bool reconcilingMembers: false

    function memberIndex(userId) {
        for (var index = 0; index < membersModel.count; index++) {
            var entry = membersModel.get(index).memberData || ({})
            if ((entry.user_id || "") === userId) return index
        }
        return -1
    }

    function reconcileMembers() {
        if (reconcilingMembers) return
        reconcilingMembers = true

        var anchorIndex = membersList.indexAt(
            Math.max(6, membersList.width / 2), membersList.contentY + 1)
        var anchorId = ""
        var anchorOffset = 0
        if (anchorIndex >= 0 && anchorIndex < membersModel.count) {
            var anchorEntry = membersModel.get(anchorIndex).memberData || ({})
            anchorId = anchorEntry.user_id || ""
            var anchorItem = membersList.itemAtIndex(anchorIndex)
            if (anchorItem) anchorOffset = membersList.contentY - anchorItem.y
        }

        var desired = root.members || []
        for (var targetIndex = 0; targetIndex < desired.length; targetIndex++) {
            var target = desired[targetIndex]
            var targetId = target.user_id || ""
            var existingIndex = memberIndex(targetId)
            if (existingIndex < 0) {
                membersModel.insert(targetIndex, { memberData: target })
            } else {
                if (existingIndex !== targetIndex)
                    membersModel.move(existingIndex, targetIndex, 1)
                membersModel.set(targetIndex, { memberData: target })
            }
        }
        while (membersModel.count > desired.length)
            membersModel.remove(membersModel.count - 1)

        reconcilingMembers = false
        if (anchorId === "") return
        var restoredIndex = memberIndex(anchorId)
        if (restoredIndex < 0) return
        Qt.callLater(function() {
            membersList.positionViewAtIndex(restoredIndex, ListView.Beginning)
            Qt.callLater(function() {
                var restoredItem = membersList.itemAtIndex(restoredIndex)
                if (!restoredItem) return
                membersList.contentY = restoredItem.y + anchorOffset
                membersList.returnToBounds()
            })
        })
    }

    onMembersChanged: reconcileMembers()

    ListModel {
        id: membersModel
        dynamicRoles: true
    }

    Component.onCompleted: reconcileMembers()

    function membershipText(member) {
        var revision = root.authorNameRevision
        var timestamp = Number(member.membership_event_timestamp || 0)
        var when = timestamp > 0 ? " · " + Qt.formatDateTime(new Date(timestamp), "dd.MM.yyyy HH:mm") : ""
        if (member.membership === "invite")
            return L10n.I18n.tr("Пригласил ")
                + (root.authorNameResolver
                    ? root.authorNameResolver(member.membership_event_sender || "", "")
                    : Utils.displayName(member.membership_event_sender || "")) + when
        if (member.membership === "join")
            return L10n.I18n.tr("Состоит в комнате") + when
        return (member.membership || L10n.I18n.tr("Участник")) + when
    }

    color: surfaceColor
    border.color: Qt.rgba(dividerColor.r, dividerColor.g, dividerColor.b, 0.55)
    border.width: 1
    visible: currentRoomId !== "" && width > 0.5
    clip: true

    Column {
        objectName: "membersLoadingStatus"
        z: 1
        anchors.centerIn: parent
        width: Math.max(0, parent.width - 28)
        spacing: 12
        visible: !root.collapsed && membersModel.count === 0
            && (root.loading || root.errorText !== "")
        PrismBusyIndicator {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 28
            height: 28
            running: parent.visible && root.loading
            accentColor: root.accentColor
        }
        Text {
            width: parent.width
            text: root.loading ? L10n.I18n.tr("Загрузка…") : root.errorText
            color: root.textSecondary
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: 9
        }
        Basic.Button {
            objectName: "membersRetryButton"
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !root.loading && root.errorText !== ""
            text: L10n.I18n.tr("Повторить")
            padding: 10
            scale: down ? 0.96 : 1
            onClicked: root.retryRequested()
            contentItem: Text {
                text: parent.text
                color: root.textPrimary
                font.pointSize: 9
                horizontalAlignment: Text.AlignHCenter
            }
            background: Rectangle {
                radius: 8
                color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, parent.down ? 0.30
                              : parent.hovered ? 0.22 : 0.14)
            }
            Behavior on scale {
                NumberAnimation { duration: L10n.UiPreferences.duration(100) }
            }
        }
    }

    Column {
        anchors.fill: parent

        Item {
            id: membersHeader
            width: parent.width
            height: 45

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: attachmentsButton.left
                anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.I18n.tr("Участники — ")
                    + Math.max(root.totalMemberCount, membersModel.count)
                color: root.textPrimary
                font.bold: true
                font.pointSize: 10
                elide: Text.ElideRight
                opacity: root.collapsed ? 0 : 1
                Behavior on opacity {
                    NumberAnimation { duration: L10n.UiPreferences.duration(110); easing.type: Easing.OutCubic }
                }
            }

            Rectangle {
                id: attachmentsButton
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                radius: 9
                color: attachmentsMouse.pressed
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                    : attachmentsMouse.containsMouse
                        ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                        : "transparent"
                scale: attachmentsMouse.pressed ? 0.88 : 1
                opacity: root.collapsed ? 0 : 1
                enabled: !root.collapsed

                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(105); easing.type: Easing.OutBack } }
                Behavior on opacity { NumberAnimation { duration: L10n.UiPreferences.duration(110); easing.type: Easing.OutCubic } }

                Canvas {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    antialiasing: true
                    property color iconColor: attachmentsMouse.containsMouse ? root.textPrimary : root.iconColor
                    onIconColorChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var scale = Math.min(width, height) / 18
                        ctx.scale(scale, scale)
                        ctx.strokeStyle = iconColor
                        ctx.fillStyle = iconColor
                        ctx.lineWidth = 1 / scale
                        ctx.lineJoin = "round"
                        ctx.lineCap = "round"
                        ctx.strokeRect(0.5, 2.5, 17, 13)
                        ctx.beginPath()
                        ctx.arc(5.25, 6.25, 1.25, 0, Math.PI * 2)
                        ctx.fill()
                        ctx.beginPath()
                        ctx.moveTo(2.5, 13)
                        ctx.lineTo(7.2, 8.7)
                        ctx.lineTo(10.2, 11.2)
                        ctx.lineTo(12.4, 9.2)
                        ctx.lineTo(15.5, 13)
                        ctx.stroke()
                    }
                }

                MouseArea {
                    id: attachmentsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.attachmentsRequested()
                }

                ToolTip {
                    id: attachmentsToolTip
                    visible: attachmentsMouse.containsMouse
                    text: L10n.I18n.tr("Открыть вложения")
                    delay: 300
                    timeout: 3000
                    x: attachmentsButton.width - width
                    y: attachmentsButton.height + 4
                    leftPadding: 10
                    rightPadding: 10
                    topPadding: 7
                    bottomPadding: 7

                    contentItem: Text {
                        text: attachmentsToolTip.text
                        color: root.textPrimary
                        font.pointSize: 8
                    }

                    background: Rectangle {
                        radius: 8
                        color: root.elevatedColor
                        border.width: 1
                        border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                              root.textSecondary.b, 0.38)
                    }

                    enter: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: L10n.UiPreferences.duration(110) }
                    }
                    exit: Transition {
                        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: L10n.UiPreferences.duration(90) }
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: root.dividerColor; opacity: 0.55 }

        ListView {
            id: membersList
            width: parent.width
            opacity: root.collapsed ? 0 : 1
            enabled: !root.collapsed
            Behavior on opacity {
                NumberAnimation { duration: L10n.UiPreferences.duration(110); easing.type: Easing.OutCubic }
            }
            height: parent.height - 46
            clip: true
            model: membersModel
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            onContentYChanged: {
                if (root.currentRoomId !== ""
                        && contentHeight > height
                        && contentY + height >= contentHeight - Math.max(120, height * 0.35)) {
                    root.membersMoreRequested(root.currentRoomId)
                }
            }

            delegate: Rectangle {
                id: memberDelegate
                required property var memberData
                width: ListView.view.width - 10
                height: 54
                x: 5
                radius: 8
                scale: memberMouse.pressed ? 0.97 : 1
                color: memberMouse.pressed
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                    : memberMouse.containsMouse
                        ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.055)
                        : "transparent"

                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                Behavior on scale {
                    NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                }

                AvatarItem {
                    id: memberAvatar
                    anchors.left: parent.left
                    anchors.leftMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    size: 34
                    mxcUrl: memberData.user_id === root.currentUserId
                        ? root.currentUserAvatar
                        : (memberData.avatar_url || "")
                    fallbackId: memberData.user_id || ""
                    mediaProxy: root.mediaProxy
                    roundAvatars: root.roundAvatars
                }

                Column {
                    anchors.left: memberAvatar.right
                    anchors.leftMargin: 9
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Row {
                        spacing: 6
                        Text {
                            text: memberData.user_id === root.currentUserId
                                && root.currentDisplayName !== ""
                                ? root.currentDisplayName
                                : (memberData.display_name || Utils.displayName(memberData.user_id || ""))
                            color: root.textPrimary
                            font.pointSize: 9
                            font.bold: Number(memberData.power_level || 0) >= 50
                            width: Math.min(112, implicitWidth)
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            visible: (memberData.role || "user") !== "user"
                            height: 17
                            width: roleText.implicitWidth + 10
                            radius: 5
                            color: Qt.rgba(0.125, 0.835, 0, 0.13)
                            Text {
                                id: roleText
                                anchors.centerIn: parent
                                text: memberData.role === "creator" ? L10n.I18n.tr("создатель")
                                    : memberData.role === "administrator" ? L10n.I18n.tr("Админ").toLowerCase()
                                    : L10n.I18n.tr("модератор")
                                color: "#63e66d"
                                font.pointSize: 7
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: root.membershipText(memberData)
                        color: root.textSecondary
                        font.pointSize: 7
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: memberMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        var point = memberMouse.mapToItem(root, mouse.x, mouse.y)
                        root.userRequested(memberData.user_id || "", point.x, point.y)
                    }
                }
            }
        }
    }
    PrismScrollBar {
        id: membersScrollBar
        anchors.top: parent.top
        anchors.topMargin: 46
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 9
        z: 1000
        autoHide: true
        autoHideDelay: 2500
        orientation: Qt.Vertical
        policy: ScrollBar.AlwaysOn
        interactive: true
        active: visible
        visible: !root.collapsed && membersList.contentHeight > membersList.height + 2
        size: membersList.contentHeight > 0
            ? Math.min(1, membersList.visibleArea.heightRatio) : 1
        minimumSize: 0.08
        handleColor: root.textSecondary
        handleHoverColor: root.accentColor
        trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                            root.textSecondary.b, 0.16)

        Binding {
            target: membersScrollBar
            property: "position"
            value: Math.max(0, Math.min(1 - membersScrollBar.size,
                                        membersList.visibleArea.yPosition))
            when: !membersScrollBar.pressed
        }

        onPositionChanged: {
            if (!pressed) return
            var safePosition = Math.max(0, Math.min(1 - size, position))
            membersList.contentY = membersList.originY
                + safePosition * membersList.contentHeight
            membersList.returnToBounds()
        }
    }
}
