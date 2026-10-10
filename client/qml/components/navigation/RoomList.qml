import QtQuick
import "../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../common"
import "../../assets/icons" as Icons

ListView {
    id: root

    property var voiceSession: null
    property var roomModel
    property string currentRoomId: ""
    property string selectedSpaceId: ""
    property bool showSpaceRoomsInHome: false
    property string searchQuery: ""
    property string mediaProxy: ""
    property bool roundAvatars: true
    property var pinnedRoomIds: []
    property var archivedRoomIds: []
    property var mutedRoomIds: []
    property var draftRoomIds: []
    property bool archiveMode: false
    property bool archiveInSpaceRail: false
    property bool roomDragInProgress: false
    readonly property int archivedRoomCount: {
        if (!roomModel || !archivedRoomIds) return 0
        var count = 0
        for (var index = 0; index < roomModel.count; index++) {
            var room = roomModel.get(index)
            if (isRoomArchived(room.room_id)
                    && (selectedSpaceId === ""
                        || belongsToSelectedSpace(room.parent_space_key))) count++
        }
        return count
    }
    property color accentColor: "#20D500"
    property color accentTextColor: "#071007"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"
    readonly property int channelCardLeftInset: 3

    signal roomSelected(string roomId, string roomName)
    signal roomContextRequested(string roomId, string roomName, string directUserId,
                                bool ignored, real clickX, real clickY)
    signal roomInviteAccepted(string roomId, string roomName)
    signal archivedViewRequested(bool archivedView)
    signal archiveLocationRequested(bool inSpaceRail)
    signal roomDragStarted(string roomId, string roomName)
    signal roomDragFinished()
    signal roomDroppedOnArchive(string roomId, string roomName, string sourceSpaceId)

    function isRoomPinned(roomId) {
        return pinnedRoomIds && pinnedRoomIds.indexOf(roomId) !== -1
    }

    function isRoomArchived(roomId) {
        return archivedRoomIds && archivedRoomIds.indexOf(roomId) !== -1
    }

    function isRoomMuted(roomId) {
        return mutedRoomIds && mutedRoomIds.indexOf(roomId) !== -1
    }

    function hasRoomDraft(roomId) {
        return roomId !== currentRoomId
            && draftRoomIds && draftRoomIds.indexOf(roomId) !== -1
    }

    function belongsToSelectedSpace(parentSpaceKey) {
        var key = parentSpaceKey || ""
        if (selectedSpaceId === "")
            return showSpaceRoomsInHome || !hasJoinedParentSpace(key)
        var parents = key.split("\u001f")
        for (var i = 0; i < parents.length; i++) {
            if (parents[i] === selectedSpaceId) return true
        }
        return false
    }

    function hasJoinedParentSpace(parentSpaceKey) {
        var key = parentSpaceKey || ""
        if (key === "" || !roomModel) return false
        var parents = key.split("\u001f")
        for (var roomIndex = 0; roomIndex < roomModel.count; roomIndex++) {
            var room = roomModel.get(roomIndex)
            if (!room.is_space || room.is_invited) continue
            for (var parentIndex = 0; parentIndex < parents.length; parentIndex++) {
                if (parents[parentIndex] === room.room_id) return true
            }
        }
        return false
    }

    function matchesSearch(roomName, roomId, directUserId, lastMessage) {
        var needle = (searchQuery || "").trim().toLocaleLowerCase()
        if (needle === "") return true
        return String(roomName || "").toLocaleLowerCase().indexOf(needle) !== -1
            || String(roomId || "").toLocaleLowerCase().indexOf(needle) !== -1
            || String(directUserId || "").toLocaleLowerCase().indexOf(needle) !== -1
            || String(lastMessage || "").toLocaleLowerCase().indexOf(needle) !== -1
    }

    function selectRelativeRoom(step) {
        if (!roomModel || roomModel.count === 0 || step === 0)
            return false

        var candidates = []
        var currentCandidate = -1
        for (var index = 0; index < roomModel.count; index++) {
            var room = roomModel.get(index)
            var archived = isRoomArchived(room.room_id)
            var shown = !room.is_space && !room.is_invited
                && ((archiveMode && selectedSpaceId === "")
                    || (archiveInSpaceRail && archiveMode)
                    || belongsToSelectedSpace(room.parent_space_key))
                && (archiveMode ? archived : !archived)
                && matchesSearch(room.name, room.room_id, room.direct_user_id,
                                 room.last_message)
            if (!shown)
                continue
            if (room.room_id === currentRoomId)
                currentCandidate = candidates.length
            candidates.push({
                modelIndex: index,
                roomId: room.room_id,
                roomName: room.name || room.room_id
            })
        }
        if (candidates.length === 0)
            return false

        var targetIndex
        if (currentCandidate < 0)
            targetIndex = step > 0 ? 0 : candidates.length - 1
        else
            targetIndex = (currentCandidate + (step > 0 ? 1 : -1)
                           + candidates.length) % candidates.length
        var target = candidates[targetIndex]
        positionViewAtIndex(target.modelIndex, ListView.Contain)
        roomSelected(target.roomId, target.roomName)
        return true
    }

    model: roomModel
    clip: true
    spacing: 0
    boundsBehavior: Flickable.StopAtBounds
    maximumFlickVelocity: 3000
    flickDeceleration: 8000

    header: Item {
        width: root.width
        height: archiveEntry.visible ? 52 : 0

        Rectangle {
            id: archiveEntry
            visible: !root.archiveInSpaceRail && (root.archiveMode || root.archivedRoomCount > 0)
            width: root.width - 8
            height: visible ? 48 : 0
            x: 4
            radius: 10
            scale: archiveEntryDrop.containsDrag ? 1.01 : (archiveMouse.pressed ? 0.97 : 1)
            color: archiveEntryDrop.containsDrag
                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                : archiveMouse.pressed
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                    : archiveMouse.containsMouse
                        ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.06)
                        : "transparent"

            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(120) } }
            Behavior on scale {
                NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
            }

            Canvas {
                id: archiveIcon
                anchors.left: parent.left
                anchors.leftMargin: 15
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = root.accentColor
                    ctx.lineWidth = 1.6
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.strokeRect(3, 7, 14, 10)
                    ctx.beginPath()
                    ctx.moveTo(2.5, 4)
                    ctx.lineTo(17.5, 4)
                    ctx.lineTo(17.5, 7)
                    ctx.lineTo(2.5, 7)
                    ctx.closePath()
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.moveTo(8, 11)
                    ctx.lineTo(12, 11)
                    ctx.stroke()
                }
                Connections {
                    target: root
                    function onAccentColorChanged() { archiveIcon.requestPaint() }
                }
            }

            Column {
                anchors.left: archiveIcon.right
                anchors.leftMargin: 12
                anchors.right: archiveCountBadge.visible ? archiveCountBadge.left : parent.right
                anchors.rightMargin: archiveCountBadge.visible ? 10 : 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    width: parent.width
                    text: root.archiveMode
                        ? L10n.I18n.tr("Назад к чатам")
                        : L10n.I18n.tr("Архив")
                    color: root.textPrimary
                    font.pointSize: 10
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: L10n.I18n.tr("Архивированные чаты")
                    color: root.textSecondary
                    font.pointSize: 8
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                id: archiveCountBadge
                visible: !root.archiveMode && root.archivedRoomCount > 0
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(20, countText.implicitWidth + 10)
                height: 20
                radius: 10
                color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                               root.accentColor.b, 0.16)

                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: String(root.archivedRoomCount)
                    color: root.accentColor
                    font.pointSize: 8
                    font.bold: true
                }
            }

            DropArea {
                id: archiveEntryDrop
                anchors.fill: parent
                z: 2
                enabled: !root.archiveMode
                keys: ["prism-room"]
                onDropped: function(drop) {
                    var roomId = drop.source ? (drop.source.draggedRoomId || "") : ""
                    var roomName = drop.source ? (drop.source.draggedRoomName || roomId) : roomId
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
                    Qt.callLater(function() { root.positionViewAtBeginning() })
                }
            }
        }
    }

    // Keep the empty archive reachable during a drag without resizing the header.
    Rectangle {
        id: transientArchiveDropTarget
        visible: !root.archiveInSpaceRail
            && !root.archiveMode
            && root.roomDragInProgress
            && root.archivedRoomCount === 0
        z: 1000
        x: 4
        y: 4
        width: root.width - 8
        height: 48
        radius: 10
        color: transientArchiveDrop.containsDrag
            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.24)
            : Qt.rgba(root.elevatedColor.r, root.elevatedColor.g, root.elevatedColor.b, 0.96)
        border.width: 1
        border.color: transientArchiveDrop.containsDrag ? root.accentColor : root.dividerColor

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 15
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Canvas {
                id: transientArchiveIcon
                width: 20
                height: 20
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = root.accentColor
                    ctx.lineWidth = 1.6
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.strokeRect(3, 7, 14, 10)
                    ctx.beginPath()
                    ctx.moveTo(2.5, 4); ctx.lineTo(17.5, 4); ctx.lineTo(17.5, 7); ctx.lineTo(2.5, 7)
                    ctx.closePath(); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(8, 11); ctx.lineTo(12, 11); ctx.stroke()
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    text: L10n.I18n.tr("Архив")
                    color: root.textPrimary
                    font.pointSize: 10
                    font.bold: true
                }
                Text {
                    text: L10n.I18n.tr("Архивированные чаты")
                    color: root.textSecondary
                    font.pointSize: 8
                }
            }
        }

        DropArea {
            id: transientArchiveDrop
            anchors.fill: parent
            keys: ["prism-room"]
            onDropped: function(drop) {
                var roomId = drop.source ? (drop.source.draggedRoomId || "") : ""
                var roomName = drop.source ? (drop.source.draggedRoomName || roomId) : roomId
                if (!roomId || roomId === "") {
                    drop.accepted = false
                    return
                }
                root.roomDroppedOnArchive(roomId, roomName, root.selectedSpaceId)
                drop.acceptProposedAction()
            }
        }
    }

    Basic.Menu {
        id: archiveLocationMenu
        width: 230
        background: Rectangle {
            radius: 9
            color: root.elevatedColor
            border.width: 1
            border.color: root.dividerColor
        }
        Basic.MenuItem {
            id: moveArchiveToRailAction
            width: archiveLocationMenu.availableWidth
            height: 38
            text: L10n.I18n.tr("Перенести в панель пространств")
            onTriggered: root.archiveLocationRequested(true)
            contentItem: Text {
                text: moveArchiveToRailAction.text
                color: root.textPrimary
                font.pointSize: 8.5
                verticalAlignment: Text.AlignVCenter
                leftPadding: 10
            }
            background: Rectangle {
                radius: 7
                color: moveArchiveToRailAction.highlighted || moveArchiveToRailAction.hovered
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                    : "transparent"
            }
        }
    }

    ScrollBar.vertical: PrismScrollBar {
        id: roomsScrollBar
        policy: ScrollBar.AsNeeded
        interactive: true
        autoHide: true
        autoHideDelay: 2500
        revealOnActive: true
        handleColor: root.textSecondary
        handleHoverColor: root.accentColor
        trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                            root.textSecondary.b, 0.16)
    }

    delegate: Rectangle {
        id: roomDelegate
        readonly property bool voice: !!model.is_voice
        readonly property var voiceMembers: {
            if (!voice) return []
            if (root.voiceSession && root.voiceSession.roomId === model.room_id
                    && root.voiceSession.phase === "connected") return root.voiceSession.participants
            try { return JSON.parse(model.voice_members_json || "[]") } catch (_) { return [] }
        }
        readonly property bool pinned: root.isRoomPinned(model.room_id)
        readonly property bool archived: root.isRoomArchived(model.room_id)
        readonly property bool muted: root.isRoomMuted(model.room_id)
        readonly property bool hasDraft: root.hasRoomDraft(model.room_id)
        readonly property bool shown: !model.is_space
            && ((root.archiveMode && root.selectedSpaceId === "")
                || (root.archiveInSpaceRail && root.archiveMode)
                || root.belongsToSelectedSpace(model.parent_space_key))
            && (root.archiveMode ? archived : !archived)
            && root.matchesSearch(model.name, model.room_id, model.direct_user_id,
                                  model.last_message)
        visible: shown
        width: root.width - 8
        height: shown ? 48 + voiceMembers.length * 25 : 0
        x: 4
        radius: 10
        property string draggedRoomId: model.room_id
        property string draggedRoomName: model.name || model.room_id
        property string draggedParentSpaceKey: model.parent_space_key || ""
        property bool dragJustFinished: false
        opacity: roomDrag.active ? 0.55 : 1
        scale: roomDrag.active ? 1.02
            : roomMouse.pressed && roomMouse.pressedButtons === Qt.LeftButton ? 0.97 : 1
        color: "transparent"
        Behavior on opacity { NumberAnimation { duration: L10n.UiPreferences.duration(100) } }
        Behavior on scale {
            NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: root.channelCardLeftInset
            radius: 10
            color: roomMouse.pressed && roomMouse.pressedButtons === Qt.LeftButton
                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.24)
                : root.currentRoomId === model.room_id
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                    : roomDelegate.pinned
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.08)
                        : roomMouse.containsMouse
                            ? Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                      root.textPrimary.b, 0.06)
                            : "transparent"
            Behavior on color {
                ColorAnimation { duration: L10n.UiPreferences.duration(120) }
            }
        }

        Rectangle {
            visible: roomDelegate.pinned && root.currentRoomId !== model.room_id
            anchors.left: parent.left
            anchors.leftMargin: root.channelCardLeftInset + 1
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: 24
            radius: 1.5
            color: root.accentColor
            opacity: 0.9
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.top: parent.top
            anchors.topMargin: 7
            spacing: 10

            AvatarItem {
                mxcUrl: model.avatar_url || ""
                fallbackId: model.room_id
                mediaProxy: root.mediaProxy
                roundAvatars: root.roundAvatars
                size: 34
            }

            Column {
                width: Math.max(92, roomDelegate.width - 70
                                - (unreadBadge.visible ? 30 : 0)
                                - (roomDelegate.pinned ? 22 : 0)
                                - (roomDelegate.hasDraft ? 22 : 0))
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    width: parent.width
                    text: (roomDelegate.voice ? "◉  " : "") + (model.name || model.room_id)
                    color: roomDelegate.muted ? root.textSecondary : root.textPrimary
                    font.pointSize: 10
                    font.bold: root.currentRoomId === model.room_id || roomDelegate.pinned
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: roomDelegate.voice || model.is_invited || (model.last_message || "") !== ""
                    text: roomDelegate.voice ? L10n.I18n.tr("Голосовой канал · ") + roomDelegate.voiceMembers.length
                        : model.is_invited
                        ? L10n.I18n.tr("Приглашение · нажмите, чтобы принять")
                        : (model.last_message || "")
                    color: roomDelegate.muted
                        ? root.textSecondary
                        : (model.is_invited ? root.accentColor : root.textSecondary)
                    font.pointSize: 8
                    elide: Text.ElideRight
                }
            }
        }

        Column {
            x: 51; y: 48; width: parent.width - 58; spacing: 1
            Repeater {
                model: roomDelegate.voiceMembers
                delegate: Row {
                    required property var modelData
                    width: parent.width; height: 24; spacing: 6
                    Rectangle {
                        width: 22; height: 22; radius: 11
                        color: "transparent"
                        border.width: 2
                        border.color: modelData.speaking ? root.accentColor : "transparent"
                        AvatarItem {
                            anchors.centerIn: parent; size: 18
                            fallbackId: modelData.user_id || ""
                            mxcUrl: modelData.avatar_url || ""; mediaProxy: root.mediaProxy
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28
                        text: (modelData.muted ? "× " : "") + (modelData.display_name || modelData.user_id)
                        color: modelData.speaking ? root.accentColor : root.textSecondary
                        font.pointSize: 8; elide: Text.ElideRight
                    }
                }
            }
        }

        Icons.PinIcon {
            visible: roomDelegate.pinned
            anchors.right: draftIndicator.visible
                ? draftIndicator.left
                : (unreadBadge.visible ? unreadBadge.left : parent.right)
            anchors.rightMargin: draftIndicator.visible
                ? 7
                : (unreadBadge.visible ? 7 : 10)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            width: 16
            height: 21
            color: root.accentColor
            filled: true
            strokeWidth: 1.35
        }

        Item {
            id: draftIndicator
            visible: roomDelegate.hasDraft
            anchors.right: unreadBadge.visible ? unreadBadge.left : parent.right
            anchors.rightMargin: unreadBadge.visible ? 7 : 10
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 18
            z: 3
            opacity: draftHover.hovered ? 1 : 0.82
            scale: draftHover.hovered ? 1.08 : 1

            Behavior on opacity {
                NumberAnimation { duration: L10n.UiPreferences.duration(110) }
            }
            Behavior on scale {
                NumberAnimation { duration: L10n.UiPreferences.duration(110); easing.type: Easing.OutCubic }
            }

            Canvas {
                id: draftIcon
                anchors.centerIn: parent
                width: 15
                height: 15

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = root.accentColor
                    ctx.lineWidth = 1.55
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    ctx.moveTo(3, 11.8)
                    ctx.lineTo(4, 8.7)
                    ctx.lineTo(10.8, 1.9)
                    ctx.lineTo(13.1, 4.2)
                    ctx.lineTo(6.3, 11)
                    ctx.closePath()
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.moveTo(3, 11.8)
                    ctx.lineTo(6.3, 11)
                    ctx.stroke()
                }

                Connections {
                    target: root
                    function onAccentColorChanged() { draftIcon.requestPaint() }
                }
            }

            HoverHandler {
                id: draftHover
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            }

            ToolTip {
                id: draftToolTip
                visible: draftHover.hovered
                text: L10n.I18n.tr("Черновик")
                delay: 300
                timeout: 2500
                y: draftIndicator.height + 5
                x: Math.round((draftIndicator.width - width) / 2)
                leftPadding: 10
                rightPadding: 10
                topPadding: 7
                bottomPadding: 7
                z: 10000

                contentItem: Text {
                    text: draftToolTip.text
                    color: root.textPrimary
                    font.pointSize: 8
                }

                background: Rectangle {
                    radius: 8
                    color: root.elevatedColor
                    border.width: 1
                    border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                          root.dividerColor.b, 0.72)
                }
            }
        }

        Rectangle {
            id: unreadBadge
            visible: !model.is_invited && Number(model.unread_count) > 0
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            radius: 10
            color: roomDelegate.muted
                ? Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                          root.textSecondary.b, 0.62)
                : root.accentColor

            Text {
                anchors.centerIn: parent
                text: String(model.unread_count)
                color: roomDelegate.muted ? root.elevatedColor : root.accentTextColor
                font.pointSize: 8
                font.bold: true
            }
        }

        Item {
            id: roomDragProxy
            x: roomDrag.activeTranslation.x
            y: roomDrag.activeTranslation.y
            width: roomDelegate.width
            height: roomDelegate.height
            Drag.active: false
            Drag.source: roomDelegate
            Drag.keys: ["prism-room"]
            Drag.supportedActions: Qt.MoveAction
            Drag.proposedAction: Qt.MoveAction
            Drag.hotSpot.x: roomDrag.active
                ? roomDrag.centroid.pressPosition.x : width / 2
            Drag.hotSpot.y: roomDrag.active
                ? roomDrag.centroid.pressPosition.y : height / 2
        }

        Timer {
            id: dragClickGuard
            interval: 140
            repeat: false
            onTriggered: roomDelegate.dragJustFinished = false
        }

        DragHandler {
            id: roomDrag
            target: null
            acceptedButtons: Qt.LeftButton
            enabled: !model.is_invited && !roomDelegate.archived
            dragThreshold: 8
            onActiveChanged: {
                if (active) {
                    root.roomDragInProgress = true
                    roomDelegate.dragJustFinished = true
                    dragClickGuard.stop()
                    roomDragProxy.Drag.active = true
                    root.roomDragStarted(roomDelegate.draggedRoomId,
                                         roomDelegate.draggedRoomName)
                } else if (roomDelegate.dragJustFinished) {
                    // drop() is required to emit DropArea.onDropped.
                    roomDragProxy.Drag.drop()
                    roomDragProxy.Drag.active = false
                    root.roomDragInProgress = false
                    root.roomDragFinished()
                    dragClickGuard.restart()
                }
            }
        }

        MouseArea {
            id: roomMouse
            anchors.fill: parent
            anchors.leftMargin: root.channelCardLeftInset
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse) {
                if (roomDelegate.dragJustFinished)
                    return
                if (mouse.button === Qt.RightButton) {
                    var clickPoint = roomMouse.mapToItem(root, mouse.x, mouse.y)
                    root.roomContextRequested(model.room_id, model.name || model.room_id,
                                              model.direct_user_id || "", !!model.is_ignored,
                                              clickPoint.x, clickPoint.y)
                } else if (model.is_invited)
                    root.roomInviteAccepted(model.room_id, model.name || model.room_id)
                else if (roomDelegate.voice && root.voiceSession)
                    root.voiceSession.join(model.room_id, model.name || model.room_id)
                else
                    root.roomSelected(model.room_id, model.name || model.room_id)
            }
        }
    }
}
