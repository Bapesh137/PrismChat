import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../common"
import "../../assets/icons" as Icons
import "../../utils" as L10n

Rectangle {
    id: root

    property var roomModel
    property string selectedSpaceId: ""
    property string mediaProxy: ""
    property bool roundAvatars: true
    property color accentColor: "#20D500"
    property color accentTextColor: "#071007"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color dividerColor: "#29402E"
    property string draggedRoomId: ""
    property string draggedRoomName: ""
    property var archivedRoomIds: []
    property bool archiveMode: false
    property bool archiveInSpaceRail: false
    readonly property int archivedRoomCount: {
        if (!root.roomModel || !root.archivedRoomIds) return 0
        var count = 0
        for (var index = 0; index < root.roomModel.count; ++index) {
            var room = root.roomModel.get(index)
            if (!room.is_space && root.archivedRoomIds.indexOf(room.room_id) !== -1)
                count++
        }
        return count
    }

    signal spaceSelected(string roomId, string roomName)
    signal createSpaceRequested()
    signal joinSpaceRequested()
    signal archivedViewRequested(bool archivedView)
    signal archiveLocationRequested(bool inSpaceRail)
    signal roomDroppedOnSpace(string roomId, string roomName, string spaceId, string spaceName)
    signal roomDroppedOnHome(string roomId, string roomName, string sourceSpaceId)
    signal roomDroppedOnArchive(string roomId, string roomName, string sourceSpaceId)
    signal spaceContextRequested(string spaceId, string spaceName, real clickX, real clickY)

    color: elevatedColor
    implicitWidth: 68

    Item {
        id: homeItem
        anchors.top: parent.top
        anchors.topMargin: 10
        width: parent.width
        height: 46

        Rectangle {
            id: homeButton
            anchors.centerIn: parent
            width: 44
            height: 44
            radius: homeDrop.containsDrag || (root.selectedSpaceId === "" && !root.archiveMode) ? 14 : 22
            scale: homeDrop.containsDrag ? 1.08 : (homeMouse.pressed ? 0.88 : 1)
            color: homeDrop.containsDrag
                ? root.accentColor
                : homeMouse.pressed
                    ? Qt.darker(root.accentColor, 1.12)
                    : homeMouse.containsMouse || (root.selectedSpaceId === "" && !root.archiveMode)
                        ? root.accentColor : root.surfaceColor

            Behavior on scale {
                NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }

            Canvas {
                id: homeCanvas
                anchors.centerIn: parent
                width: 22
                height: 22
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = homeDrop.containsDrag
                        || (root.selectedSpaceId === "" && !root.archiveMode)
                        ? root.accentTextColor : root.textPrimary
                    ctx.fillStyle = ctx.strokeStyle
                    ctx.lineWidth = 2
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    ctx.moveTo(3, 10); ctx.lineTo(11, 3); ctx.lineTo(19, 10)
                    ctx.moveTo(5, 9); ctx.lineTo(5, 19); ctx.lineTo(17, 19); ctx.lineTo(17, 9)
                    ctx.stroke()
                }
            }

            DropArea {
                id: homeDrop
                anchors.fill: parent
                z: 2
                enabled: root.selectedSpaceId !== "" && !root.archiveMode
                keys: ["prism-room"]
                onContainsDragChanged: homeCanvas.requestPaint()
                onDropped: function(drop) {
                    var roomId = root.draggedRoomId
                    var roomName = root.draggedRoomName || roomId
                    if ((!roomId || roomId === "") && drop.source) {
                        roomId = drop.source.draggedRoomId || ""
                        roomName = drop.source.draggedRoomName || roomId
                    }
                    if (!roomId || roomId === "" || root.selectedSpaceId === "") {
                        drop.accepted = false
                        return
                    }
                    root.roomDroppedOnHome(roomId, roomName, root.selectedSpaceId)
                    drop.acceptProposedAction()
                }
            }

            MouseArea {
                id: homeMouse
                anchors.fill: parent
                z: 1
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.spaceSelected("", L10n.I18n.tr("Чаты"))

                ToolTip {
                    id: homeToolTip
                    visible: homeMouse.containsMouse
                    text: L10n.I18n.tr("Чаты")
                    delay: 350
                    timeout: 3000
                    x: homeMouse.width + 8
                    y: Math.round((homeMouse.height - height) / 2)
                    leftPadding: 10
                    rightPadding: 10
                    topPadding: 7
                    bottomPadding: 7
                    z: 10000

                    contentItem: Text {
                        text: homeToolTip.text
                        color: root.textPrimary
                        font.pointSize: 8
                    }

                    background: Rectangle {
                        radius: 8
                        color: root.elevatedColor
                        border.width: 1
                        border.color: Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                              root.textPrimary.b, 0.22)
                    }

                    enter: Transition {
                        NumberAnimation {
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: L10n.UiPreferences.duration(110)
                        }
                    }

                    exit: Transition {
                        NumberAnimation {
                            property: "opacity"
                            from: 1
                            to: 0
                            duration: L10n.UiPreferences.duration(90)
                        }
                    }
                }
            }
        }
    }

    Item {
        id: archiveItem
        visible: root.archiveInSpaceRail
        anchors.top: homeItem.bottom
        anchors.topMargin: 8
        width: parent.width
        height: visible ? 46 : 0

        Rectangle {
            anchors.centerIn: parent
            width: 44
            height: 44
            radius: archiveDrop.containsDrag || root.archiveMode ? 14 : 22
            scale: archiveDrop.containsDrag ? 1.08 : (archiveMouse.pressed ? 0.88 : 1)
            color: archiveDrop.containsDrag
                ? root.accentColor
                : archiveMouse.pressed
                    ? Qt.darker(root.accentColor, 1.12)
                    : archiveMouse.containsMouse || root.archiveMode
                        ? root.accentColor : root.surfaceColor
            border.width: archiveDrop.containsDrag || archiveMouse.containsMouse || root.archiveMode ? 0 : 1
            border.color: root.dividerColor

            Behavior on radius {
                NumberAnimation { duration: L10n.UiPreferences.duration(120); easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }

            Canvas {
                id: railArchiveIcon
                anchors.centerIn: parent
                width: 22
                height: 22
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = archiveDrop.containsDrag || root.archiveMode
                        ? root.accentTextColor : root.textPrimary
                    ctx.lineWidth = 1.7
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.strokeRect(4, 8, 14, 10)
                    ctx.beginPath()
                    ctx.moveTo(3.5, 5)
                    ctx.lineTo(18.5, 5)
                    ctx.lineTo(18.5, 8)
                    ctx.lineTo(3.5, 8)
                    ctx.closePath()
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.moveTo(9, 12)
                    ctx.lineTo(13, 12)
                    ctx.stroke()
                }
                Connections {
                    target: root
                    function onAccentColorChanged() { railArchiveIcon.requestPaint() }
                    function onTextPrimaryChanged() { railArchiveIcon.requestPaint() }
                    function onArchiveModeChanged() { railArchiveIcon.requestPaint() }
                }
            }

            Rectangle {
                visible: root.archivedRoomCount > 0 && !root.archiveMode
                anchors.right: parent.right
                anchors.rightMargin: -2
                anchors.top: parent.top
                anchors.topMargin: -2
                width: Math.max(17, archiveCountText.implicitWidth + 7)
                height: 17
                radius: 9
                color: root.elevatedColor
                border.width: 1
                border.color: root.accentColor

                Text {
                    id: archiveCountText
                    anchors.centerIn: parent
                    text: String(root.archivedRoomCount)
                    color: root.textPrimary
                    font.pointSize: 6.5
                    font.bold: true
                }
            }

            DropArea {
                id: archiveDrop
                anchors.fill: parent
                z: 2
                enabled: !root.archiveMode
                keys: ["prism-room"]
                onContainsDragChanged: railArchiveIcon.requestPaint()
                onDropped: function(drop) {
                    var roomId = root.draggedRoomId
                    var roomName = root.draggedRoomName || roomId
                    if ((!roomId || roomId === "") && drop.source) {
                        roomId = drop.source.draggedRoomId || ""
                        roomName = drop.source.draggedRoomName || roomId
                    }
                    if (!roomId || roomId === "") {
                        drop.accepted = false
                        return
                    }
                    root.roomDroppedOnArchive(roomId, roomName, root.selectedSpaceId)
                    drop.acceptProposedAction()
                }
            }

            MouseArea {
                id: archiveMouse
                anchors.fill: parent
                z: 1
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                        archiveLocationMenu.popup()
                        return
                    }
                    root.archivedViewRequested(!root.archiveMode)
                }

                ToolTip {
                    id: archiveToolTip
                    visible: archiveMouse.containsMouse && !archiveLocationMenu.opened
                    text: root.archiveMode
                        ? L10n.I18n.tr("Назад к чатам")
                        : L10n.I18n.tr("Архив")
                    delay: 300
                    timeout: 3000
                    x: archiveMouse.width + 8
                    y: Math.round((archiveMouse.height - height) / 2)
                    leftPadding: 10
                    rightPadding: 10
                    topPadding: 7
                    bottomPadding: 7
                    z: 10000
                    contentItem: Text {
                        text: archiveToolTip.text
                        color: root.textPrimary
                        font.pointSize: 8
                    }
                    background: Rectangle {
                        radius: 8
                        color: root.elevatedColor
                        border.width: 1
                        border.color: Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                              root.textPrimary.b, 0.22)
                    }
                }
            }
        }
    }

    Rectangle {
        id: divider
        anchors.top: archiveItem.visible ? archiveItem.bottom : homeItem.bottom
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: 34
        height: 1
        color: root.dividerColor
    }

    Flickable {
        id: spacesFlick
        anchors.top: divider.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        contentHeight: spacesColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: spacesColumn
            width: spacesFlick.width
            spacing: 8

            Repeater {
                model: root.roomModel

                delegate: Item {
                    id: spaceDelegate
                    required property string room_id
                    required property string name
                    required property string avatar_url
                    required property bool is_space

                    visible: is_space
                    width: spacesColumn.width
                    height: visible ? 48 : 0

                    Rectangle {
                        visible: !root.archiveMode && root.selectedSpaceId === spaceDelegate.room_id
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 4
                        height: 30
                        radius: 2
                        color: root.accentColor
                    }

                    AvatarItem {
                        id: spaceAvatar
                        anchors.centerIn: parent
                        mxcUrl: spaceDelegate.avatar_url || ""
                        fallbackId: spaceDelegate.name || spaceDelegate.room_id
                        mediaProxy: root.mediaProxy
                        roundAvatars: root.roundAvatars
                        size: 44
                        scale: spaceMouse.pressed ? 0.88
                            : spaceDrop.containsDrag ? 1.10
                            : spaceMouse.containsMouse ? 1.04 : 1
                        opacity: spaceDrop.containsDrag ? 0.82 : 1
                        Behavior on scale {
                            NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                        }
                        Behavior on opacity { NumberAnimation { duration: L10n.UiPreferences.duration(100) } }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 48
                        height: 48
                        radius: 24
                        visible: spaceDrop.containsDrag
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                       root.accentColor.b, 0.16)
                        border.width: 2
                        border.color: root.accentColor
                    }

                    DropArea {
                        id: spaceDrop
                        anchors.fill: parent
                        z: 2
                        keys: ["prism-room"]
                        onDropped: function(drop) {
                            var roomId = root.draggedRoomId
                            var roomName = root.draggedRoomName || roomId
                            if ((!roomId || roomId === "") && drop.source) {
                                roomId = drop.source.draggedRoomId || ""
                                roomName = drop.source.draggedRoomName || roomId
                            }
                            if (!roomId || roomId === "" || roomId === spaceDelegate.room_id) {
                                drop.accepted = false
                                return
                            }
                            root.roomDroppedOnSpace(
                                roomId, roomName,
                                spaceDelegate.room_id,
                                spaceDelegate.name || spaceDelegate.room_id)
                            drop.acceptProposedAction()
                        }
                    }

                    MouseArea {
                        id: spaceMouse
                        anchors.fill: parent
                        z: 1
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.RightButton) {
                                var clickPoint = spaceMouse.mapToItem(
                                    root, mouse.x, mouse.y)
                                root.spaceContextRequested(
                                    spaceDelegate.room_id,
                                    spaceDelegate.name || spaceDelegate.room_id,
                                    clickPoint.x, clickPoint.y)
                            } else {
                                root.spaceSelected(spaceDelegate.room_id,
                                                   spaceDelegate.name || L10n.I18n.tr("Пространство"))
                            }
                        }

                        ToolTip {
                            id: spaceToolTip
                            visible: spaceMouse.containsMouse
                            text: spaceDelegate.name || spaceDelegate.room_id
                            delay: 350
                            timeout: 3000
                            x: spaceMouse.width + 8
                            y: Math.round((spaceMouse.height - height) / 2)
                            leftPadding: 10
                            rightPadding: 10
                            topPadding: 7
                            bottomPadding: 7
                            z: 10000

                            contentItem: Text {
                                text: spaceToolTip.text
                                color: root.textPrimary
                                font.pointSize: 8
                            }

                            background: Rectangle {
                                radius: 8
                                color: root.elevatedColor
                                border.width: 1
                                border.color: Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                                      root.textPrimary.b, 0.22)
                            }

                            enter: Transition {
                                NumberAnimation {
                                    property: "opacity"
                                    from: 0
                                    to: 1
                                    duration: L10n.UiPreferences.duration(110)
                                }
                            }

                            exit: Transition {
                                NumberAnimation {
                                    property: "opacity"
                                    from: 1
                                    to: 0
                                    duration: L10n.UiPreferences.duration(90)
                                }
                            }
                        }
                    }
                }
            }

            Item {
                id: createSpaceItem
                width: spacesColumn.width
                height: 46

                Rectangle {
                    anchors.centerIn: parent
                    width: 44
                    height: 44
                    radius: createSpaceMouse.containsMouse ? 14 : 22
                    scale: createSpaceMouse.pressed ? 0.88 : 1
                    color: createSpaceMouse.pressed
                        ? Qt.darker(root.accentColor, 1.15)
                        : createSpaceMouse.containsMouse ? root.accentColor : root.surfaceColor
                    border.width: createSpaceMouse.containsMouse ? 0 : 1
                    border.color: root.dividerColor

                    Behavior on radius {
                        NumberAnimation { duration: L10n.UiPreferences.duration(120); easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                    }
                    Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }

                    Icons.PlusIcon {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        strokeWidth: 2
                        color: createSpaceMouse.containsMouse ? root.accentTextColor : root.textPrimary
                    }

                    MouseArea {
                        id: createSpaceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: spaceAddMenu.popup()

                        ToolTip {
                            id: createSpaceToolTip
                            visible: createSpaceMouse.containsMouse
                            text: L10n.I18n.tr("Добавить пространство")
                            delay: 300
                            timeout: 3000
                            x: createSpaceMouse.width + 8
                            y: Math.round((createSpaceMouse.height - height) / 2)
                            leftPadding: 10
                            rightPadding: 10
                            topPadding: 7
                            bottomPadding: 7
                            z: 10000

                            contentItem: Text {
                                text: createSpaceToolTip.text
                                color: root.textPrimary
                                font.pointSize: 8
                            }

                            background: Rectangle {
                                radius: 8
                                color: root.elevatedColor
                                border.width: 1
                                border.color: Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                                      root.textPrimary.b, 0.22)
                            }

                            enter: Transition {
                                NumberAnimation {
                                    property: "opacity"
                                    from: 0
                                    to: 1
                                    duration: L10n.UiPreferences.duration(110)
                                }
                            }

                            exit: Transition {
                                NumberAnimation {
                                    property: "opacity"
                                    from: 1
                                    to: 0
                                    duration: L10n.UiPreferences.duration(90)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Basic.Menu {
        id: archiveLocationMenu
        width: 220
        background: Rectangle {
            radius: 9
            color: root.elevatedColor
            border.width: 1
            border.color: root.dividerColor
        }
        Basic.MenuItem {
            id: moveArchiveToChatsAction
            width: archiveLocationMenu.availableWidth
            height: 38
            text: L10n.I18n.tr("Перенести в список чатов")
            onTriggered: root.archiveLocationRequested(false)
            contentItem: Text {
                text: moveArchiveToChatsAction.text
                color: root.textPrimary
                font.pointSize: 8.5
                verticalAlignment: Text.AlignVCenter
                leftPadding: 10
            }
            background: Rectangle {
                radius: 7
                color: moveArchiveToChatsAction.highlighted || moveArchiveToChatsAction.hovered
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                    : "transparent"
            }
        }
    }

    Basic.Menu {
        id: spaceAddMenu
        width: 230
        background: Rectangle {
            radius: 9
            color: root.elevatedColor
            border.width: 1
            border.color: root.dividerColor
        }

        Basic.MenuItem {
            id: joinSpaceAction
            width: spaceAddMenu.availableWidth
            height: 40
            text: L10n.I18n.tr("Присоединиться к пространству")
            onTriggered: root.joinSpaceRequested()
            contentItem: Text {
                text: joinSpaceAction.text
                color: root.textPrimary
                font.pointSize: 8.5
                verticalAlignment: Text.AlignVCenter
                leftPadding: 10
            }
            background: Rectangle {
                radius: 7
                color: joinSpaceAction.highlighted || joinSpaceAction.hovered
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                    : "transparent"
            }
        }

        Basic.MenuItem {
            id: createSpaceAction
            width: spaceAddMenu.availableWidth
            height: 40
            text: L10n.I18n.tr("Создать пространство")
            onTriggered: root.createSpaceRequested()
            contentItem: Text {
                text: createSpaceAction.text
                color: root.textPrimary
                font.pointSize: 8.5
                verticalAlignment: Text.AlignVCenter
                leftPadding: 10
            }
            background: Rectangle {
                radius: 7
                color: createSpaceAction.highlighted || createSpaceAction.hovered
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                    : "transparent"
            }
        }
    }

}
