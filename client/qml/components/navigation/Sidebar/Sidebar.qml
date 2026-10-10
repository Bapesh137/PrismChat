import ".." as Navigation
import QtQuick
import "../../voice"
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../common"
import "../../../assets/icons" as Icons
import "../../../utils/PrismUtils.js" as Utils

Rectangle {
    id: root

    property var voiceSession: null
    property var roomModel
    property bool collapsed: false
    property string currentRoomId: ""
    property var roomReadReceiptOverrides: ({})
    property var roomTypingNotificationOverrides: ({})
    property string selectedSpaceId: ""
    property bool showSpaceRoomsInHome: false
    property string selectedSpaceName: L10n.I18n.tr("Чаты")
    property bool spaceLobbyActive: false
    property string currentUserId: ""
    property string currentDisplayName: ""
    property string currentUserAvatar: ""
    property string mediaProxy: ""
    property bool roundAvatars: true
    property string messageDateFormat: "dd.MM.yyyy"
    property string messageTimeFormat: "HH:mm"

    property var profiles: []
    property var pinnedRoomIds: []
    property var archivedRoomIds: []
    property var mutedRoomIds: []
    property var invitationNotificationModel
    property var mentionNotificationModel
    property string notificationTab: "room_invitation"
    readonly property var activeNotificationModel: notificationTab === "room_invitation"
        ? invitationNotificationModel : mentionNotificationModel
    readonly property int activeNotificationCount: activeNotificationModel
        ? activeNotificationModel.count : 0
    readonly property int invitationNotificationCount: invitationNotificationModel
        ? invitationNotificationModel.count : 0
    readonly property int mentionNotificationCount: mentionNotificationModel
        ? mentionNotificationModel.count : 0
    property int notificationUnreadCount: 0
    property var draftRoomIds: []
    property bool archiveMode: false
    property bool archiveInSpaceRail: false
    property string activeProfileId: ""
    property bool profilesLoading: false
    property bool accountSwitchInFlight: false
    property var requestIdFactory: null
    property int localSearchSequence: 0
    property var messageSearchResults: []
    property var pendingMessageSearchRequests: ({})
    property var messageSearchQueue: []
    property int pendingMessageSearchCount: 0
    property int messageSearchErrorCount: 0
    property string activeMessageSearchQuery: ""
    // Positive values move the entered text down by the specified pixel amount.
    property int searchTextVerticalOffset: 0
    property int clearSearchIconSize: 11
    readonly property string searchQuery: searchField.text.trim()
    readonly property bool searchActive: searchQuery !== ""

    function authorDisplayName(sender, cachedName) {
        if (sender === root.currentUserId && root.currentDisplayName !== "")
            return root.currentDisplayName
        return cachedName || Utils.displayName(sender || "")
    }

    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color accentTextColor: "#071007"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"

    signal roomSelected(string roomId, string roomName)
    signal roomInviteAccepted(string roomId, string roomName)
    signal roomPreviewRequested(string roomId, string roomName)
    signal spaceLobbyRequested()
    signal roomInfoRequested(string roomId)
    signal roomLinkCopyRequested(string roomId, bool isSpace)
    signal roomEditRequested(string roomId)
    signal roomUpdateRequested(string roomId, var changes)
    signal roomMemberModerationRequested(string roomId, string userId,
                                         string action)
    signal roomReadReceiptPreferenceChanged(string roomId, string preference)
    signal roomTypingPreferenceChanged(string roomId, string preference)
    signal roomReadStateRequested(string roomId, bool unread)

    function roomIsUnread(roomId) {
        if (!root.roomModel) return false
        for (var i = 0; i < root.roomModel.count; i++)
            if (root.roomModel.get(i).room_id === roomId)
                return Number(root.roomModel.get(i).unread_count || 0) > 0
        return false
    }
    signal roomDragStarted(string roomId, string roomName)
    signal roomDragFinished()
    signal roomDroppedOnArchive(string roomId, string roomName, string sourceSpaceId)
    signal roomPinRequested(string roomId, bool pinned)
    signal roomArchiveRequested(string roomId, bool archived)
    signal roomMuteRequested(string roomId, bool muted)
    signal archiveLocationRequested(bool inSpaceRail)
    signal userIgnoreRequested(string userId, bool ignored)
    signal leaveRoomRequested(string roomId)
    signal settingsRequested()
    signal addAccountRequested()
    signal directorySearchOpenRequested()
    signal switchProfileRequested(string profileId)
    signal profileSettingsRequested(string profileId)
    signal deleteProfileRequested(string profileId)
    signal messageSearchRequested(string roomId, string query, string requestId)
    signal messageResultSelected(string roomId, string roomName, string eventId)
    signal notificationsOpened(string notificationType)
    signal notificationActivated(string notificationId, string notificationType,
                                 string roomId, string roomName)
    signal notificationDismissed(string notificationId)
    signal notificationsClearRequested(string notificationType)

    property bool accountPopupVisible: false
    property string contextRoomId: ""
    property string contextRoomName: ""
    property bool contextRoomPinned: false
    property bool contextRoomArchived: false
    property bool contextRoomMuted: false
    property string contextRoomDirectUserId: ""
    property bool contextRoomIgnored: false
    property bool contextIsSpace: false
    property bool contextRoomCanEdit: false

    property real contextMenuX: -1
    property real contextMenuY: -1

    function roomCanEdit(roomId) {
        if (!root.roomModel) return false
        for (var i = 0; i < root.roomModel.count; i++) {
            var room = root.roomModel.get(i)
            if (String(room.room_id || "") === String(roomId || ""))
                return !!room.can_edit
        }
        return false
    }

    function openRoomContextMenu(roomId, roomName, directUserId, ignored, isSpace,
                                 clickX, clickY) {
        root.contextRoomId = roomId || ""
        root.contextRoomName = roomName || roomId || ""
        root.contextRoomPinned = root.roomIsPinned(root.contextRoomId)
        root.contextRoomArchived = root.roomIsArchived(root.contextRoomId)
        root.contextRoomMuted = root.roomIsMuted(root.contextRoomId)
        root.contextRoomDirectUserId = directUserId || ""
        root.contextRoomIgnored = !!ignored
        root.contextIsSpace = !!isSpace
        root.contextRoomCanEdit = root.roomCanEdit(root.contextRoomId)
        if (typeof clickX === "number" && isFinite(clickX)
                && typeof clickY === "number" && isFinite(clickY)) {
            root.contextMenuX = clickX
            root.contextMenuY = clickY
        } else {
            var fallback = root.mapToItem(Overlay.overlay, root.width - 12, 64)
            root.contextMenuX = fallback.x
            root.contextMenuY = fallback.y
        }
        roomMenu.open()
    }

    function roomIsPinned(roomId) {
        return pinnedRoomIds && pinnedRoomIds.indexOf(roomId) !== -1
    }

    function roomIsArchived(roomId) {
        return archivedRoomIds && archivedRoomIds.indexOf(roomId) !== -1
    }
    function roomIsMuted(roomId) {
        return mutedRoomIds && mutedRoomIds.indexOf(roomId) !== -1
    }


    function nextSearchRequestId() {
        if (requestIdFactory)
            return requestIdFactory("sidebar-search")
        localSearchSequence++
        return Date.now().toString() + "-sidebar-search-" + localSearchSequence
    }

    function resetMessageSearch() {
        messageSearchTimer.stop()
        messageSearchResults = []
        pendingMessageSearchRequests = ({})
        messageSearchQueue = []
        pendingMessageSearchCount = 0
        messageSearchErrorCount = 0
        activeMessageSearchQuery = ""
    }

    function startMessageSearch() {
        var query = searchField.text.trim()
        messageSearchResults = []
        pendingMessageSearchRequests = ({})
        messageSearchQueue = []
        pendingMessageSearchCount = 0
        messageSearchErrorCount = 0
        activeMessageSearchQuery = query
        if (query.length < 2 || !roomModel) return

        var queue = []
        for (var i = 0; i < roomModel.count; i++) {
            var room = roomModel.get(i)
            var archived = root.roomIsArchived(room.room_id)
            if (room.is_space || !room.room_id
                    || (root.archiveMode ? !archived : archived)
                    || (!root.archiveMode
                        && !roomList.belongsToSelectedSpace(room.parent_space_key)))
                continue
            queue.push({
                room_id: room.room_id,
                room_name: room.name || room.room_id,
                avatar_url: room.avatar_url || "",
                query: query
            })
        }
        messageSearchQueue = queue
        pendingMessageSearchCount = queue.length
        pumpMessageSearchQueue()
    }

    function pumpMessageSearchQueue() {
        if (messageSearchQueue.length === 0 || activeMessageSearchQuery === "") return

        var queue = messageSearchQueue.slice(0)
        var room = queue.shift()
        messageSearchQueue = queue
        var requestId = nextSearchRequestId()
        var pending = ({})
        pending[requestId] = room
        pendingMessageSearchRequests = pending
        messageSearchRequested(room.room_id, room.query, requestId)
    }

    function receiveMessageSearchResults(roomId, messages, errorText, requestId) {
        var pending = pendingMessageSearchRequests
        if (!requestId || !pending.hasOwnProperty(requestId)) return

        var room = pending[requestId]
        delete pending[requestId]
        pendingMessageSearchRequests = pending
        pendingMessageSearchCount = Math.max(0, pendingMessageSearchCount - 1)
        if (room.query !== activeMessageSearchQuery) return
        if (errorText && errorText !== "") messageSearchErrorCount++

        var known = ({})
        var combined = messageSearchResults.slice(0)
        for (var knownIndex = 0; knownIndex < combined.length; knownIndex++)
            known[combined[knownIndex].key] = true

        var found = messages || []
        for (var i = 0; i < found.length; i++) {
            var message = found[i]
            var eventId = message.event_id || ""
            var body = message.body || ""
            var key = (room.room_id || roomId || "") + "|" + eventId
            if (eventId === "" || body === "" || known[key]) continue
            known[key] = true
            combined.push({
                key: key,
                room_id: room.room_id || roomId || "",
                room_name: room.room_name || roomId || "",
                room_avatar_url: room.avatar_url || "",
                message: message
            })
        }
        combined.sort(function(left, right) {
            return Number(right.message.timestamp || 0) - Number(left.message.timestamp || 0)
        })
        messageSearchResults = combined
        Qt.callLater(function() {
            if (room.query === root.activeMessageSearchQuery)
                root.pumpMessageSearchQueue()
        })
    }

    function finishSearch() {
        searchField.text = ""
        resetMessageSearch()
    }

    function focusRoomSearch() {
        root.collapsed = false
        searchField.forceActiveFocus()
        if (searchField.text !== "")
            searchField.selectAll()
    }

    function selectRelativeRoom(step) {
        return roomList.selectRelativeRoom(step)
    }

    function formatSearchTimestamp(timestamp) {
        return Utils.formatMessageTimestamp(timestamp, messageDateFormat, messageTimeFormat, L10n.I18n.tr("вчера"))
    }

    function drawIcon(ctx, icon, color, width, height) {
        var centerX = width / 2
        var centerY = height / 2
        ctx.clearRect(0, 0, width, height)
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = 1.35
        ctx.lineCap = "round"
        ctx.lineJoin = "round"

        if (icon === "info") {
            ctx.beginPath(); ctx.arc(centerX, centerY, 7, 0, Math.PI * 2); ctx.stroke()
            ctx.beginPath(); ctx.arc(centerX, centerY - 3.2, 0.9, 0, Math.PI * 2); ctx.fill()
            ctx.beginPath(); ctx.moveTo(centerX, centerY - 0.2); ctx.lineTo(centerX, centerY + 4.2); ctx.stroke()
        } else if (icon === "read") {
            ctx.beginPath(); ctx.arc(centerX, centerY, 7, 0, Math.PI * 2); ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(centerX - 3.4, centerY)
            ctx.lineTo(centerX - 0.8, centerY + 2.7)
            ctx.lineTo(centerX + 4.2, centerY - 3.2)
            ctx.stroke()
        } else if (icon === "unread") {
            ctx.beginPath(); ctx.arc(centerX, centerY, 7, 0, Math.PI * 2); ctx.stroke()
            ctx.beginPath(); ctx.arc(centerX, centerY, 2.1, 0, Math.PI * 2); ctx.fill()
        } else if (icon === "link") {
            ctx.beginPath()
            ctx.arc(centerX - 3, centerY, 4.2,
                    -Math.PI * 0.72, Math.PI * 0.72)
            ctx.moveTo(centerX + 3, centerY)
            ctx.arc(centerX + 3, centerY, 4.2,
                    Math.PI * 0.28, Math.PI * 1.72)
            ctx.moveTo(centerX - 2.5, centerY)
            ctx.lineTo(centerX + 2.5, centerY)
            ctx.stroke()
        } else if (icon === "edit") {
            ctx.beginPath(); ctx.moveTo(4, 15); ctx.lineTo(5, 11); ctx.lineTo(13.5, 2.5); ctx.lineTo(17.5, 6.5); ctx.lineTo(9, 15); ctx.closePath(); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(12, 4); ctx.lineTo(16, 8); ctx.stroke()
        } else if (icon === "leave") {
            ctx.beginPath(); ctx.moveTo(4, 4); ctx.lineTo(10, 4); ctx.moveTo(4, 4); ctx.lineTo(4, 16); ctx.lineTo(10, 16); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(9, 10); ctx.lineTo(17, 10); ctx.moveTo(14, 7); ctx.moveTo(17, 10); ctx.lineTo(14, 13); ctx.stroke()
        } else if (icon === "members") {
            ctx.beginPath(); ctx.arc(8, 7, 3, 0, Math.PI * 2); ctx.arc(14, 8, 2.5, 0, Math.PI * 2); ctx.stroke()
            ctx.beginPath(); ctx.arc(8, 16, 5, Math.PI, 0); ctx.arc(14, 16, 4, Math.PI, 0); ctx.stroke()
        } else if (icon === "shield") {
            ctx.beginPath(); ctx.moveTo(10, 2); ctx.lineTo(17, 5); ctx.lineTo(16, 12); ctx.quadraticCurveTo(14, 16, 10, 18); ctx.quadraticCurveTo(6, 16, 4, 12); ctx.lineTo(3, 5); ctx.closePath(); ctx.stroke()
        } else if (icon === "bell" || icon === "mute") {
            ctx.beginPath(); ctx.arc(10, 10, 5, Math.PI, 0); ctx.lineTo(15, 14); ctx.lineTo(5, 14); ctx.lineTo(5, 10); ctx.stroke()
            ctx.beginPath(); ctx.arc(10, 17, 1.2, 0, Math.PI * 2); ctx.fill()
            if (icon === "mute") {
                ctx.beginPath(); ctx.moveTo(4, 4); ctx.lineTo(16, 16); ctx.stroke()
            }
        } else if (icon === "hash") {
            ctx.beginPath(); ctx.moveTo(7, 3); ctx.lineTo(5, 17); ctx.moveTo(15, 3); ctx.lineTo(13, 17); ctx.moveTo(3, 8); ctx.lineTo(17, 8); ctx.moveTo(2, 13); ctx.lineTo(16, 13); ctx.stroke()
        } else if (icon === "pin") {
            ctx.beginPath(); ctx.moveTo(5, 4); ctx.lineTo(15, 4); ctx.lineTo(13, 9); ctx.lineTo(16, 12); ctx.lineTo(11, 12); ctx.lineTo(10, 18); ctx.lineTo(9, 12); ctx.lineTo(4, 12); ctx.lineTo(7, 9); ctx.closePath(); ctx.stroke()
        } else if (icon === "archive") {
            ctx.strokeRect(3, 7, 14, 10)
            ctx.beginPath(); ctx.moveTo(2.5, 4); ctx.lineTo(17.5, 4); ctx.lineTo(17.5, 7); ctx.lineTo(2.5, 7); ctx.closePath(); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(8, 11); ctx.lineTo(12, 11); ctx.stroke()
        } else if (icon === "block") {
            ctx.beginPath(); ctx.arc(centerX, centerY, 7, 0, Math.PI * 2); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(5, 15); ctx.lineTo(15, 5); ctx.stroke()
        } else if (icon === "preview") {
            ctx.beginPath()
            ctx.moveTo(2.5, centerY)
            ctx.quadraticCurveTo(centerX, 3.5, 17.5, centerY)
            ctx.quadraticCurveTo(centerX, 16.5, 2.5, centerY)
            ctx.closePath()
            ctx.stroke()
            ctx.beginPath(); ctx.arc(centerX, centerY, 2.6, 0, Math.PI * 2); ctx.stroke()
        }
    }

    function notificationTime(value) {
        var date = new Date(Number(value || Date.now()))
        return Qt.formatDateTime(date, "dd.MM HH:mm")
    }

    function drawCloseIcon(ctx, color, width, height) {
        var centerX = width / 2
        var centerY = height / 2
        var halfSize = 4.5
        ctx.clearRect(0, 0, width, height)
        ctx.strokeStyle = color
        ctx.lineWidth = 1.6
        ctx.lineCap = "round"
        ctx.beginPath()
        ctx.moveTo(centerX - halfSize, centerY - halfSize)
        ctx.lineTo(centerX + halfSize, centerY + halfSize)
        ctx.moveTo(centerX + halfSize, centerY - halfSize)
        ctx.lineTo(centerX - halfSize, centerY + halfSize)
        ctx.stroke()
    }

    implicitWidth: 260
    implicitHeight: 600
    color: surfaceColor
    clip: true

    onCurrentUserIdChanged: {
        archiveMode = false
        finishSearch()
    }
    onCollapsedChanged: {
        if (!collapsed) return
        accountPopupVisible = false
        finishSearch()
    }

    onSelectedSpaceIdChanged: {
        archiveMode = false
        if (searchQuery.length >= 2) {
            resetMessageSearch()
            messageSearchTimer.restart()
        }
    }

    onArchivedRoomIdsChanged: {
        if (archiveMode && (!archivedRoomIds || archivedRoomIds.length === 0))
            archiveMode = false
    }

    Timer {
        id: messageSearchTimer
        interval: 450
        repeat: false
        onTriggered: root.startMessageSearch()
    }

    Rectangle {
        id: header
        anchors.top: parent.top
        width: parent.width
        height: 88
        color: root.surfaceColor

        Text {
            id: spaceTitle
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: notificationBell.left
            anchors.rightMargin: 8
            anchors.top: parent.top
            anchors.topMargin: 13
            text: root.archiveMode ? L10n.I18n.tr("Архив") : root.selectedSpaceName
            color: root.textPrimary
            font.bold: true
            font.pointSize: 12
            elide: Text.ElideRight
            opacity: root.collapsed ? 0 : 1
            Behavior on opacity {
                NumberAnimation { duration: L10n.UiPreferences.duration(110); easing.type: Easing.OutCubic }
            }
        }

        Basic.ToolButton {
            id: notificationBell
            opacity: root.collapsed ? 0 : 1
            enabled: !root.collapsed
            anchors.top: parent.top
            anchors.topMargin: 6
            anchors.horizontalCenter: directorySearchButton.horizontalCenter
            width: 34
            height: 34
            padding: 0
            hoverEnabled: true
            scale: down ? 0.92 : 1

            Behavior on opacity {
                NumberAnimation { duration: L10n.UiPreferences.duration(100) }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: L10n.UiPreferences.duration(100)
                    easing.type: Easing.OutCubic
                }
            }

            contentItem: Item {
                Canvas {
                    id: notificationBellCanvas
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    property color strokeColor: notificationBell.down
                        ? Qt.darker(root.iconColor, 1.12)
                        : notificationBell.hovered ? root.textPrimary : root.iconColor
                    onStrokeColorChanged: requestPaint()
                    onPaint: root.drawIcon(getContext("2d"), "bell", strokeColor, width, height)
                }

                Rectangle {
                    visible: root.notificationUnreadCount > 0
                    anchors.right: parent.right
                    anchors.rightMargin: -2
                    anchors.top: parent.top
                    anchors.topMargin: -1
                    width: Math.max(17, notificationBadgeText.implicitWidth + 7)
                    height: 17
                    radius: height / 2
                    color: "#ff5252"
                    border.width: 1.5
                    border.color: root.surfaceColor

                    Text {
                        id: notificationBadgeText
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -0.5
                        text: root.notificationUnreadCount > 99
                            ? "99+" : String(root.notificationUnreadCount)
                        color: "#ffffff"
                        font.pixelSize: 9
                        font.bold: true
                    }
                }
            }

            background: Rectangle {
                radius: 10
                color: notificationBell.down
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                    : notificationBell.hovered
                        ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                        : "transparent"
                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
            }

            PrismToolTip {
                visible: notificationBell.hovered
                text: L10n.I18n.tr("Уведомления")
                surfaceColor: root.elevatedColor
                textColor: root.textPrimary
                dividerColor: root.dividerColor
            }

            onClicked: {
                root.accountPopupVisible = false
                if (notificationPopup.opened) {
                    notificationPopup.close()
                } else {
                    notificationPopup.open()
                    root.notificationsOpened(root.notificationTab)
                }
            }
        }

        Basic.TextField {
            id: searchField
            opacity: root.collapsed ? 0 : 1
            enabled: !root.collapsed
            anchors.left: parent.left
            anchors.right: directorySearchButton.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            anchors.bottomMargin: 7
            height: 34
            leftPadding: 36
            rightPadding: clearSearchButton.visible ? 36 : 12
            topPadding: Math.max(0, root.searchTextVerticalOffset * 2)
            bottomPadding: Math.max(0, -root.searchTextVerticalOffset * 2)
            verticalAlignment: TextInput.AlignVCenter
            color: root.textPrimary
            placeholderText: L10n.I18n.tr("Чаты, люди и сообщения")
            placeholderTextColor: root.textSecondary
            selectionColor: root.accentColor
            selectedTextColor: root.accentTextColor
            font.pointSize: 9

            Behavior on opacity {
                NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
            }

            background: Rectangle {
                radius: 10
                color: root.elevatedColor
                border.width: searchField.activeFocus ? 1 : 0
                border.color: root.accentColor

                Icons.SearchIcon {
                    id: sidebarSearchIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 15
                    height: 15
                    color: root.iconColor
                    strokeWidth: 1
                }
            }

            onTextChanged: {
                root.resetMessageSearch()
                if (text.trim().length >= 2)
                    messageSearchTimer.restart()
            }
            onAccepted: {
                messageSearchTimer.stop()
                root.startMessageSearch()
            }

            Basic.ToolButton {
                id: clearSearchButton
                visible: searchField.text !== ""
                hoverEnabled: true
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 26
                padding: 0
                scale: down ? 0.88 : 1.0

                Behavior on scale {
                    NumberAnimation { duration: L10n.UiPreferences.duration(110); easing.type: Easing.OutCubic }
                }

                contentItem: Item {
                    Item {
                        id: clearSearchIcon
                        anchors.centerIn: parent
                        width: root.clearSearchIconSize
                        height: root.clearSearchIconSize
                        property color strokeColor: clearSearchButton.down
                            ? root.accentColor
                            : clearSearchButton.hovered ? root.textPrimary : root.textSecondary

                        Rectangle {
                            anchors.centerIn: parent
                            width: clearSearchIcon.width
                            height: 1.5
                            radius: 0.75
                            rotation: 45
                            color: clearSearchIcon.strokeColor
                            antialiasing: true
                            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: clearSearchIcon.width
                            height: 1.5
                            radius: 0.75
                            rotation: -45
                            color: clearSearchIcon.strokeColor
                            antialiasing: true
                            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                        }
                    }
                }

                background: Rectangle {
                    radius: width / 2
                    color: clearSearchButton.down
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                        : clearSearchButton.hovered
                            ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                            : "transparent"

                    Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                }

                onClicked: {
                    searchField.clear()
                    searchField.forceActiveFocus()
                }
            }
        }
        Basic.ToolButton {
            id: directorySearchButton
            opacity: root.collapsed ? 0 : 1
            enabled: !root.collapsed
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 7
            width: 34
            height: 34
            padding: 0
            hoverEnabled: true
            scale: down ? 0.94 : 1

            Behavior on opacity {
                NumberAnimation {
                    duration: L10n.UiPreferences.duration(100)
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: L10n.UiPreferences.duration(105)
                    easing.type: Easing.OutCubic
                }
            }

            contentItem: Item {
                implicitWidth: 18
                implicitHeight: 18

                Icons.PlusIcon {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    strokeWidth: 1.4
                    color: directorySearchButton.down
                        ? Qt.darker(root.iconColor, 1.12)
                        : root.iconColor
                    Behavior on color {
                        ColorAnimation { duration: L10n.UiPreferences.duration(90) }
                    }
                }
            }

            background: Rectangle {
                radius: 10
                color: directorySearchButton.down
                    ? Qt.darker(root.elevatedColor, 1.22)
                    : directorySearchButton.hovered
                        ? Qt.darker(root.elevatedColor, 1.10)
                        : root.elevatedColor
                border.width: 1
                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                      root.accentColor.b, 0)
                Behavior on color {
                    ColorAnimation { duration: L10n.UiPreferences.duration(100) }
                }
                Behavior on border.color {
                    ColorAnimation { duration: L10n.UiPreferences.duration(100) }
                }
            }

            ToolTip {
                id: directorySearchToolTip
                visible: directorySearchButton.hovered
                text: L10n.I18n.tr("Новый чат")
                delay: 300
                timeout: 3000
                x: Math.max(-8, directorySearchButton.width - implicitWidth)
                y: directorySearchButton.height + 5
                leftPadding: 10
                rightPadding: 10
                topPadding: 7
                bottomPadding: 7

                contentItem: Text {
                    text: directorySearchToolTip.text
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
            onClicked: root.directorySearchOpenRequested()
        }

    }

    NotificationPopup {
        id: notificationPopup
        sidebar: root
    }

    Rectangle {
        id: divider
        anchors.top: header.bottom
        width: parent.width
        height: 1
        color: root.dividerColor
        opacity: root.collapsed ? 0.35 : 0.7
        Behavior on opacity { NumberAnimation { duration: L10n.UiPreferences.duration(120) } }
    }

    Item {
        id: navigationBody
        anchors.top: divider.bottom
        anchors.bottom: voiceDock.top
        width: parent.width
        opacity: root.collapsed ? 0 : 1
        enabled: !root.collapsed
        Behavior on opacity {
            NumberAnimation { duration: L10n.UiPreferences.duration(110); easing.type: Easing.OutCubic }
        }

        Text {
            id: roomsSearchLabel
            visible: root.searchActive
            width: parent.width
            height: visible ? 26 : 0
            leftPadding: 14
            verticalAlignment: Text.AlignVCenter
            text: L10n.I18n.tr("Чаты и люди")
            color: root.textSecondary
            font.pointSize: 8
            font.bold: true
        }

        Rectangle {
            id: lobbySection
            visible: root.selectedSpaceId !== "" && !root.searchActive && !root.archiveMode
            anchors.top: roomsSearchLabel.bottom
            width: parent.width
            height: visible ? 51 : 0
            color: "transparent"

            Rectangle {
                id: lobbyButton
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 4
                height: 42
                radius: 10
                scale: lobbyMouse.pressed ? 0.97 : 1
                color: lobbyMouse.pressed
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, 0.24)
                    : root.spaceLobbyActive
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, 0.18)
                    : lobbyMouse.containsMouse
                        ? Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                  root.textPrimary.b, 0.06) : "transparent"
                Behavior on scale {
                    NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                }
                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }

                Icons.HomeIcon {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    color: root.iconColor
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 42
                    anchors.verticalCenter: parent.verticalCenter
                    text: L10n.I18n.tr("Лобби")
                    color: root.textPrimary
                    font.pointSize: 10
                    font.bold: root.spaceLobbyActive
                }
                MouseArea {
                    id: lobbyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.spaceLobbyRequested()
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                height: 1
                color: root.dividerColor
            }
        }

        Navigation.RoomList {
            id: roomList
            anchors.top: lobbySection.bottom
            width: parent.width
            height: root.searchActive
                ? Math.min(contentHeight, Math.max(0, navigationBody.height * 0.36))
                : Math.max(0, navigationBody.height - y)

            voiceSession: root.voiceSession
            roomModel: root.roomModel
            currentRoomId: root.currentRoomId
            selectedSpaceId: root.selectedSpaceId
            showSpaceRoomsInHome: root.showSpaceRoomsInHome
            searchQuery: root.searchQuery
            mediaProxy: root.mediaProxy
            roundAvatars: root.roundAvatars
            pinnedRoomIds: root.pinnedRoomIds
            archivedRoomIds: root.archivedRoomIds
            mutedRoomIds: root.mutedRoomIds
            draftRoomIds: root.draftRoomIds
            archiveMode: root.archiveMode
            archiveInSpaceRail: root.archiveInSpaceRail
            accentColor: root.accentColor
            accentTextColor: root.accentTextColor
            elevatedColor: root.elevatedColor
            textPrimary: root.textPrimary
            textSecondary: root.textSecondary
            dividerColor: root.dividerColor

            onRoomSelected: function(roomId, roomName) {
                root.accountPopupVisible = false
                root.finishSearch()
                root.roomSelected(roomId, roomName)
            }

            onRoomInviteAccepted: function(roomId, roomName) {
                root.accountPopupVisible = false
                root.finishSearch()
                root.roomInviteAccepted(roomId, roomName)
            }

            onArchivedViewRequested: function(archivedView) {
                root.archiveMode = archivedView
                root.finishSearch()
            }
            onArchiveLocationRequested: function(inSpaceRail) {
                root.archiveLocationRequested(inSpaceRail)
            }

            onRoomContextRequested: function(roomId, roomName, directUserId, ignored,
                                             clickX, clickY) {
                var overlayPoint = roomList.mapToItem(Overlay.overlay, clickX, clickY)
                root.openRoomContextMenu(roomId, roomName, directUserId, ignored, false,
                                         overlayPoint.x, overlayPoint.y)
            }
            onRoomDragStarted: function(roomId, roomName) {
                root.roomDragStarted(roomId, roomName)
            }
            onRoomDragFinished: root.roomDragFinished()
            onRoomDroppedOnArchive: function(roomId, roomName, sourceSpaceId) {
                root.roomDroppedOnArchive(roomId, roomName, sourceSpaceId)
            }
        }

        Text {
            id: messagesSearchLabel
            visible: root.searchActive
            anchors.top: roomList.bottom
            width: parent.width
            height: visible ? 30 : 0
            leftPadding: 14
            verticalAlignment: Text.AlignVCenter
            text: root.pendingMessageSearchCount > 0
                ? L10n.I18n.tr("Сообщения · поиск…")
                : L10n.I18n.tr("Сообщения")
            color: root.textSecondary
            font.pointSize: 8
            font.bold: true
        }

        ListView {
            id: messageResultsList
            visible: root.searchActive
            anchors.top: messagesSearchLabel.bottom
            anchors.bottom: parent.bottom
            width: parent.width
            clip: true
            spacing: 0
            model: root.messageSearchResults
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: messageResultDelegate
                required property var modelData
                width: messageResultsList.width - 8
                height: 66
                x: 4
                radius: 10
                color: messageResultMouse.containsMouse
                    ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.06)
                    : "transparent"

                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    AvatarItem {
                        mxcUrl: messageResultDelegate.modelData.room_avatar_url || ""
                        fallbackId: messageResultDelegate.modelData.room_id || ""
                        mediaProxy: root.mediaProxy
                        roundAvatars: root.roundAvatars
                        size: 34
                    }

                    Column {
                        width: parent.width - 44
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Item {
                            width: parent.width
                            height: 16

                            Text {
                                anchors.left: parent.left
                                anchors.right: resultDate.left
                                anchors.rightMargin: 7
                                anchors.verticalCenter: parent.verticalCenter
                                text: messageResultDelegate.modelData.room_name || messageResultDelegate.modelData.room_id
                                color: root.textPrimary
                                font.pointSize: 9
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                id: resultDate
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.formatSearchTimestamp(messageResultDelegate.modelData.message.timestamp)
                                color: root.textSecondary
                                font.pointSize: 7
                            }
                        }

                        Text {
                            width: parent.width
                            text: root.authorDisplayName(
                                messageResultDelegate.modelData.message.sender || "",
                                messageResultDelegate.modelData.message.sender_display_name || "")
                                + ": " + (messageResultDelegate.modelData.message.body || "")
                            color: root.textSecondary
                            font.pointSize: 8
                            elide: Text.ElideRight
                        }
                    }
                }

                MouseArea {
                    id: messageResultMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var result = messageResultDelegate.modelData
                        var roomId = result.room_id || ""
                        var roomName = result.room_name || ""
                        var eventId = result.message.event_id || ""
                        if (roomId === "" || eventId === "") return

                        // Emit before clearing the model: finishSearch() destroys this delegate.
                        root.messageResultSelected(roomId, roomName, eventId)
                        root.finishSearch()
                    }
                }
            }

            Text {
                visible: messageResultsList.count === 0
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                text: root.searchQuery.length < 2
                    ? L10n.I18n.tr("Введите минимум 2 символа для поиска по сообщениям")
                    : root.pendingMessageSearchCount > 0
                        ? L10n.I18n.tr("Ищем сообщения…")
                        : root.messageSearchErrorCount > 0
                            ? L10n.I18n.tr("Часть истории не удалось проверить")
                            : L10n.I18n.tr("Совпадений в сообщениях нет")
                color: root.textSecondary
                font.pointSize: 8
            }
        }

        PrismScrollBar {
            id: searchResultsScrollBar
            anchors.top: messagesSearchLabel.bottom
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
            visible: root.searchActive
                && messageResultsList.contentHeight > messageResultsList.height + 2
            size: messageResultsList.contentHeight > 0
                ? Math.min(1, messageResultsList.visibleArea.heightRatio) : 1
            minimumSize: 0.08
            handleColor: root.textSecondary
            handleHoverColor: root.accentColor
            trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                root.textSecondary.b, 0.16)

            Binding {
                target: searchResultsScrollBar
                property: "position"
                value: Math.max(0, Math.min(1 - searchResultsScrollBar.size,
                                            messageResultsList.visibleArea.yPosition))
                when: !searchResultsScrollBar.pressed
            }

            onPositionChanged: {
                if (!pressed) return
                var safePosition = Math.max(0, Math.min(1 - size, position))
                messageResultsList.contentY = messageResultsList.originY
                    + safePosition * messageResultsList.contentHeight
                messageResultsList.returnToBounds()
            }
        }
    }

    VoiceDock {
        id: voiceDock
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: userPanel.top
        session: root.voiceSession
        surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; accentColor: root.accentColor
    }

    RoomContextMenu {
        id: roomMenu
        sidebar: root
        leaveConfirmDialogObject: leaveConfirmDialog
    }

    function showRoomInfo(details) {
        roomDetailsDialog.openFor(details, "info")
    }

    function showRoomEditor(details) {
        roomDetailsDialog.openFor(details, "edit")
    }

    function finishRoomUpdate(success, errorText) {
        roomDetailsDialog.saving = false
        roomDetailsDialog.errorText = success
            ? "" : String(errorText || L10n.I18n.tr("Не удалось сохранить изменения"))
        if (success)
            roomDetailsDialog.close()
    }

    function finishMemberModeration(success, errorText) {
        if (!roomDetailsDialog.memberModerationBusy)
            return false
        roomDetailsDialog.memberModerationBusy = false
        roomDetailsDialog.errorText = success ? ""
            : String(errorText
                || L10n.I18n.tr("Не удалось выполнить действие модерации"))
        return true
    }

    RoomDetailsDialog {
        id: roomDetailsDialog
        sidebar: root
    }

    LeaveRoomDialog {
        id: leaveConfirmDialog
        sidebar: root
    }

    AccountSwitcherPopup {
        id: accountPopup
        sidebar: root
        userPanelObject: userPanel
    }

    Navigation.UserPanel {
        id: userPanel
        anchors.bottom: parent.bottom
        width: parent.width
        opacity: root.collapsed ? 0 : 1
        enabled: !root.collapsed
        Behavior on opacity {
            NumberAnimation { duration: L10n.UiPreferences.duration(110); easing.type: Easing.OutCubic }
        }

        currentUserId: root.currentUserId
        currentDisplayName: root.currentDisplayName
        currentUserAvatar: root.currentUserAvatar
        mediaProxy: root.mediaProxy
        roundAvatars: root.roundAvatars
        accentColor: root.accentColor
        iconColor: root.iconColor
        surfaceColor: root.surfaceColor
        elevatedColor: root.elevatedColor
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        dividerColor: root.dividerColor

        onSettingsRequested: root.settingsRequested()
        onAccountMenuRequested: {
            if (!root.accountSwitchInFlight)
                root.accountPopupVisible = !root.accountPopupVisible
        }
    }
}
