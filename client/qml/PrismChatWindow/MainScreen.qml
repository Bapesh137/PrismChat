import QtQuick
import "../utils" as L10n
import QtQuick.Controls
import QtCore
import "../components/chat"
import "../components/common"
import "../components/navigation"
import "../components/verification"
import "../dialogs"
import "../screens/auth"
import "../services"
import "../settings"
import "../themes" as Themes
import "../utils/PrismUtils.js" as Utils

Rectangle {
    required property var window
    readonly property var ownerWindow: window
    required property var appSettingsObject
    required property var invitationNotificationsModelObject
    required property var matrixConnectionObject
    required property var mentionNotificationsModelObject
    required property var roomsModelObject
    id: mainScreenContent
    property alias spaceRailObject: spaceRail
    property alias sidebarObject: sidebar
    readonly property var chatViewObject: chatViewLoader.item
    readonly property var spaceLobbyObject: spaceLobbyLoader.item
    width: parent.width / ownerWindow.uiScale
    height: parent.height / ownerWindow.uiScale
    transformOrigin: Item.TopLeft
    scale: ownerWindow.uiScale
    visible: ownerWindow.currentPage === "main"
    color: ownerWindow.backgroundColor

    Row {
        anchors.fill: parent

        SpaceRail {
            id: spaceRail
            width: 68
            height: parent.height
            roomModel: roomsModelObject
            selectedSpaceId: ownerWindow.selectedSpaceId
            mediaProxy: ownerWindow.mediaProxy
            roundAvatars: ownerWindow.roundAvatars
            accentColor: ownerWindow.accentColor
            accentTextColor: ownerWindow.accentTextColor
            surfaceColor: ownerWindow.surfaceColor
            elevatedColor: ownerWindow.elevatedColor
            textPrimary: ownerWindow.textPrimary
            dividerColor: ownerWindow.dividerColor
            draggedRoomId: ownerWindow.draggedRoomId
            draggedRoomName: ownerWindow.draggedRoomName
            archivedRoomIds: ownerWindow.archivedRoomIds
            archiveMode: sidebar.archiveMode
            archiveInSpaceRail: ownerWindow.archiveInSpaceRail

            onCreateSpaceRequested: ownerWindow.openCreateRoom(true)
            onJoinSpaceRequested: ownerWindow.openDirectorySearch("spaces")
            onArchiveLocationRequested: function(inSpaceRail) {
                ownerWindow.setArchiveInSpaceRail(inSpaceRail)
            }
            onArchivedViewRequested: function(archivedView) {
                if (archivedView) {
                    // Archive does not replace the selected Space.
                    ownerWindow.clearMainState()
                    ownerWindow.spaceLobbyOpen = false
                }
                sidebar.archiveMode = archivedView
                sidebar.finishSearch()
            }

            onRoomDroppedOnHome: function(roomId, roomName, sourceSpaceId) {
                if (!roomId || !sourceSpaceId)
                    return
                ownerWindow.draggedRoomId = ""
                ownerWindow.draggedRoomName = ""
                if (matrixConnectionObject.removeRoomFromSpace(roomId, sourceSpaceId) === "")
                    ownerWindow.showNotification(L10n.I18n.tr("Не удалось убрать комнату из пространства"), true)
            }

            onRoomDroppedOnArchive: function(roomId, roomName, sourceSpaceId) {
                if (!roomId)
                    return
                ownerWindow.draggedRoomId = ""
                ownerWindow.draggedRoomName = ""
                // Archiving is local and does not change Space membership.
                ownerWindow.setRoomArchived(roomId, true)
            }

            onRoomDroppedOnSpace: function(roomId, roomName, spaceId, spaceName) {
                if (!roomId || !spaceId || roomId === spaceId)
                    return
                ownerWindow.draggedRoomId = ""
                ownerWindow.draggedRoomName = ""
                matrixConnectionObject.addRoomToSpace(roomId, spaceId)
            }

            onSpaceContextRequested: function(spaceId, spaceName, clickX, clickY) {
                var point = spaceRail.mapToItem(
                    Overlay.overlay, clickX, clickY)
                sidebar.openRoomContextMenu(
                    spaceId, spaceName, "", false, true, point.x, point.y)
            }

            onSpaceSelected: function(roomId, roomName) {
                ownerWindow.openSpace(roomId, roomName)
            }
        }

        Sidebar {
            id: sidebar
            width: collapsed ? 0 : ownerWindow.sidebarPanelWidth
            height: parent.height

            Behavior on width {
                enabled: !sidebarResizeDrag.active
                NumberAnimation { duration: L10n.UiPreferences.duration(220); easing.type: Easing.InOutCubic }
            }

            voiceSession: ownerWindow.voiceSessionObject
            roomModel: roomsModelObject
            currentRoomId: ownerWindow.currentRoomId
            selectedSpaceId: ownerWindow.selectedSpaceId
            showSpaceRoomsInHome: ownerWindow.showSpaceRoomsInHome
            selectedSpaceName: ownerWindow.selectedSpaceName
            spaceLobbyActive: ownerWindow.spaceLobbyOpen
            currentUserId: ownerWindow.currentUserId
            currentDisplayName: ownerWindow.currentDisplayName
            currentUserAvatar: ownerWindow.currentUserAvatar
            mediaProxy: ownerWindow.mediaProxy
            roundAvatars: ownerWindow.roundAvatars
            messageDateFormat: ownerWindow.messageDateFormat
            messageTimeFormat: ownerWindow.messageTimeFormat
            profiles: ownerWindow.profiles
            pinnedRoomIds: ownerWindow.pinnedRoomIds
            archivedRoomIds: ownerWindow.archivedRoomIds
            archiveInSpaceRail: ownerWindow.archiveInSpaceRail
            draftRoomIds: ownerWindow.draftRoomIds
            mutedRoomIds: ownerWindow.mutedRoomIds
            roomReadReceiptOverrides: ownerWindow.roomReadReceiptOverrides
            roomTypingNotificationOverrides: ownerWindow.roomTypingNotificationOverrides
            invitationNotificationModel: invitationNotificationsModelObject
            mentionNotificationModel: mentionNotificationsModelObject
            notificationUnreadCount: ownerWindow.notificationUnreadCount
            activeProfileId: ownerWindow.currentProfileId
            accountSwitchInFlight: matrixConnectionObject.profileSwitchInFlight
            profilesLoading: matrixConnectionObject.profileListInFlight
            requestIdFactory: function(suffix) {
                return matrixConnectionObject.nextRequestId(suffix)
            }

            accentColor: ownerWindow.accentColor
            iconColor: ownerWindow.iconColor
            accentTextColor: ownerWindow.accentTextColor
            surfaceColor: ownerWindow.surfaceColor
            elevatedColor: ownerWindow.elevatedColor
            textPrimary: ownerWindow.textPrimary
            textSecondary: ownerWindow.textSecondary
            dividerColor: ownerWindow.dividerColor

            onRoomSelected: function(roomId, roomName) {
                ownerWindow.spaceLobbyOpen = false
                ownerWindow.currentRoomId = roomId
                ownerWindow.currentRoomName = roomName
                ownerWindow.currentRoomMembers = ownerWindow.roomMembersCache[roomId] || []
                matrixConnectionObject.requestMessages(roomId)
                ownerWindow.requestRoomMembersIfNeeded(roomId)
            }

            onRoomInviteAccepted: function(roomId, roomName) {
                ownerWindow.pendingInviteRoomId = roomId
                ownerWindow.pendingInviteRoomName = roomName
                matrixConnectionObject.acceptRoomInvite(roomId)
            }

            onSpaceLobbyRequested: {
                ownerWindow.clearMainState()
                ownerWindow.spaceLobbyOpen = true
                var lobby = mainScreenContent.spaceLobbyObject
                if (lobby) {
                    lobby.hierarchyRooms = []
                    lobby.hierarchyReady = false
                    lobby.hierarchyNextBatch = ""
                    lobby.hierarchyLoading = true
                    lobby.hierarchyError = ""
                }
                matrixConnectionObject.requestSpaceHierarchy(ownerWindow.selectedSpaceId)
            }

            onMessageSearchRequested: function(roomId, query, requestId) {
                matrixConnectionObject.sendCommand({
                    type: "search_room_messages",
                    request_id: requestId,
                    room_id: roomId,
                    query: query,
                    limit: 6
                })
            }

            onMessageResultSelected: function(roomId, roomName, eventId) {
                if (roomId === "" || eventId === "") return
                ownerWindow.spaceLobbyOpen = false
                ownerWindow.currentRoomId = roomId
                ownerWindow.currentRoomName = roomName || roomId
                ownerWindow.currentRoomMembers = ownerWindow.roomMembersCache[roomId] || []
                matrixConnectionObject.requestMessages(roomId)
                ownerWindow.requestRoomMembersIfNeeded(roomId)
                Qt.callLater(function() {
                    if (mainScreenContent.chatViewObject)
                        mainScreenContent.chatViewObject.openExternalSearchResult(roomId, eventId)
                })
            }

            onRoomPreviewRequested: function(roomId, roomName) {
                ownerWindow.openChatPreview(
                    roomId, roomName,
                    matrixConnectionObject.cachedRoomPreview(roomId, 30))
            }
            onRoomPinRequested: function(roomId, pinned) {
                ownerWindow.setRoomPinned(roomId, pinned)
            }

            onRoomArchiveRequested: function(roomId, archived) {
                ownerWindow.setRoomArchived(roomId, archived)
            }
            onArchiveLocationRequested: function(inSpaceRail) {
                ownerWindow.setArchiveInSpaceRail(inSpaceRail)
            }
            onRoomDroppedOnArchive: function(roomId, roomName, sourceSpaceId) {
                if (!roomId)
                    return
                ownerWindow.draggedRoomId = ""
                ownerWindow.draggedRoomName = ""
                ownerWindow.setRoomArchived(roomId, true)
            }
            onRoomMuteRequested: function(roomId, muted) {
                ownerWindow.setRoomMuted(roomId, muted)
            }
            onNotificationsOpened: function(notificationType) {
                ownerWindow.markCenterNotificationsRead(notificationType)
            }
            onNotificationActivated: function(notificationId, notificationType, roomId, roomName) {
                ownerWindow.activateCenterNotification(notificationId, notificationType,
                                                     roomId, roomName)
            }
            onNotificationDismissed: function(notificationId) {
                ownerWindow.dismissCenterNotification(notificationId)
            }
            onNotificationsClearRequested: function(notificationType) {
                ownerWindow.clearCenterNotifications(notificationType)
            }


            onUserIgnoreRequested: function(userId, ignored) {
                matrixConnectionObject.setUserIgnored(userId, ignored)
            }

            onRoomInfoRequested: function(roomId) {
                var requestId = matrixConnectionObject.nextRequestId("room-details")
                ownerWindow.pendingRoomDetailsMode = "info"
                ownerWindow.pendingRoomDetailsRequestId = requestId
                matrixConnectionObject.requestRoomDetails(roomId, requestId)
            }
            onRoomLinkCopyRequested: function(roomId, isSpace) {
                var link = ownerWindow.matrixToLink(roomId)
                if (link === "") return
                ownerWindow.copyText(link)
                ownerWindow.showNotification(isSpace
                    ? L10n.I18n.tr("Ссылка на пространство скопирована")
                    : L10n.I18n.tr("Ссылка на комнату скопирована"), false)
            }
            onRoomEditRequested: function(roomId) {
                var requestId = matrixConnectionObject.nextRequestId("room-details-edit")
                ownerWindow.pendingRoomDetailsMode = "edit"
                ownerWindow.pendingRoomDetailsRequestId = requestId
                matrixConnectionObject.requestRoomDetails(roomId, requestId)
            }
            onRoomMemberModerationRequested: function(roomId, userId, action) {
                matrixConnectionObject.moderateRoomMember(
                    roomId, userId, action, undefined, "")
            }
            onRoomDragStarted: function(roomId, roomName) {
                ownerWindow.draggedRoomId = roomId
                ownerWindow.draggedRoomName = roomName
            }
            onRoomDragFinished: {
                // DropArea consumes the payload before the deferred reset.
                Qt.callLater(function() {
                    ownerWindow.draggedRoomId = ""
                    ownerWindow.draggedRoomName = ""
                })
            }
            onRoomUpdateRequested: function(roomId, changes) {
                matrixConnectionObject.updateRoom(roomId, changes)
            }
            onRoomReadReceiptPreferenceChanged: function(roomId, preference) {
                var next = Object.assign({}, ownerWindow.roomReadReceiptOverrides)
                if (preference === "inherit") delete next[roomId]
                else next[roomId] = preference
                ownerWindow.roomReadReceiptOverrides = next
                appSettingsObject.roomReadReceiptOverridesJson = JSON.stringify(next)
                appSettingsObject.sync()
            }
            onRoomTypingPreferenceChanged: function(roomId, preference) {
                var next = Object.assign({}, ownerWindow.roomTypingNotificationOverrides)
                if (preference === "inherit") delete next[roomId]
                else next[roomId] = preference
                ownerWindow.roomTypingNotificationOverrides = next
                appSettingsObject.roomTypingNotificationOverridesJson = JSON.stringify(next)
                appSettingsObject.sync()
            }
            onRoomReadStateRequested: function(roomId, unread) {
                matrixConnectionObject.setRoomReadState(roomId, unread)
            }
            onLeaveRoomRequested: function(roomId) {
                matrixConnectionObject.leaveRoom(roomId)
            }

            onSettingsRequested: ownerWindow.openSettingsDialog()
            onProfileSettingsRequested: function(profileId) { ownerWindow.openProfileSettings(profileId) }
            onDirectorySearchOpenRequested: ownerWindow.openDirectorySearch("users")
            onAddAccountRequested: ownerWindow.beginAddAccount()
            onSwitchProfileRequested: function(profileId) {
                matrixConnectionObject.switchProfile(profileId)
            }
            onDeleteProfileRequested: function(profileId) {
                matrixConnectionObject.deleteProfile(profileId)
            }

            Item {
                id: sidebarResizeHandle
                visible: !sidebar.collapsed
                x: sidebar.width - width / 2
                y: 0
                width: 10
                height: sidebar.height
                z: 10000

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: sidebarResizeDrag.active
                        || sidebarResizeHover.containsMouse ? 2 : 1
                    height: parent.height
                    color: sidebarResizeDrag.active
                        || sidebarResizeHover.containsMouse
                        ? ownerWindow.accentColor : ownerWindow.dividerColor
                    opacity: sidebarResizeDrag.active
                        || sidebarResizeHover.containsMouse ? 0.72 : 0.32
                    Behavior on color {
                        ColorAnimation {
                            duration: L10n.UiPreferences.duration(100)
                        }
                    }
                }

                HoverHandler { id: sidebarResizeHover }
                DragHandler {
                    id: sidebarResizeDrag
                    target: null
                    xAxis.enabled: true
                    yAxis.enabled: false
                    property real startWidth: 260
                    cursorShape: Qt.SplitHCursor
                    onActiveChanged: {
                        if (active) {
                            startWidth = ownerWindow.sidebarPanelWidth
                        } else {
                            appSettingsObject.sidebarPanelWidth =
                                ownerWindow.sidebarPanelWidth
                            appSettingsObject.sync()
                        }
                    }
                    onActiveTranslationChanged: {
                        if (!active) return
                        ownerWindow.sidebarPanelWidth = Math.max(220,
                            Math.min(420, startWidth + activeTranslation.x))
                    }
                }
            }
        }

        Loader {
            id: chatViewLoader
            width: active ? parent.width - sidebar.width - spaceRail.width : 0
            height: parent.height
            visible: ownerWindow.currentRoomId !== "" && !ownerWindow.spaceLobbyOpen
            active: ownerWindow.currentPage === "main"
            sourceComponent: Component {
        ChatView {
            id: chatView
            anchors.fill: parent
            chatsPanelCollapsed: sidebar.collapsed
            popupLayer: mainScreenContent

            messageModel: matrixConnectionObject.messageModel
            currentRoomId: ownerWindow.currentRoomId
            readingAccountId: ownerWindow.currentProfileId
            localReadEventIds: ownerWindow.otherProfileReadEventIds(ownerWindow.currentRoomId)
            sessionEpoch: matrixConnectionObject.activeSessionEpoch
            displayedRoomId: matrixConnectionObject.displayedRoomId
            restorePosition: matrixConnectionObject.readingRestorePosition
            openingUnreadCount: matrixConnectionObject.openingUnreadCount
            readingActive: ownerWindow.active && ownerWindow.currentPage === "main"
            onViewportSaved: function(accountId, roomId, position) {
                ownerWindow.saveReadingPosition(accountId, roomId, position)
            }
            onViewportRead: function(roomId, eventId, remaining) {
                matrixConnectionObject.markVisibleMessagesRead(roomId, eventId, remaining)
            }
            unreadBoundaryEventId: matrixConnectionObject.unreadBoundaryEventId
            unreadBoundaryPending: matrixConnectionObject.unreadBoundaryPending
            timelineInitialPositionReady: matrixConnectionObject.timelineInitialPositionReady
            cachedTimeline: matrixConnectionObject.showingCachedTimeline
            currentUserId: ownerWindow.currentUserId
            backendConnected: matrixConnectionObject.connected
            currentUserAvatar: ownerWindow.currentUserAvatar
            currentDisplayName: ownerWindow.currentDisplayName
            currentDisplayNameKnown: ownerWindow.currentDisplayNameKnown
            roomName: ownerWindow.currentRoomName
            voiceSession: ownerWindow.voiceSessionObject
            roomIsDirect: ownerWindow.roomIsDirect(ownerWindow.currentRoomId)
            roomEncryptionState: ownerWindow.currentRoomEncryptionState
            isLoadingMessages: matrixConnectionObject.isLoadingMessages
            timelinePaginationInFlight: matrixConnectionObject.timelinePaginationInFlight
            showEmptyState: matrixConnectionObject.showEmptyState
            mediaProxy: ownerWindow.mediaProxy
            roundAvatars: ownerWindow.roundAvatars
            messageDateFormat: ownerWindow.messageDateFormat
            messageTimeFormat: ownerWindow.messageTimeFormat
            autoLoadImages: ownerWindow.storageAutoLoadImages
            autoLoadVideos: ownerWindow.storageAutoLoadVideos
            draftClearGeneration: ownerWindow.draftClearGeneration
            typingNotificationsEnabled:
                ownerWindow.typingNotificationsEnabledForRoom(ownerWindow.currentRoomId)
            publicReadReceipts: {
                var preference = String(ownerWindow.roomReadReceiptOverrides[
                    ownerWindow.currentRoomId] || "inherit")
                return preference === "on" || (preference !== "off"
                    && ownerWindow.readReceiptsEnabled)
            }
            typingUserIds: matrixConnectionObject.typingUsersForRoom(ownerWindow.currentRoomId)
            accentColor: ownerWindow.accentColor
            iconColor: ownerWindow.iconColor
            accentTextColor: ownerWindow.accentTextColor
            backgroundColor: ownerWindow.backgroundColor
            surfaceColor: ownerWindow.surfaceColor
            elevatedColor: ownerWindow.elevatedColor
            textPrimary: ownerWindow.textPrimary
            textSecondary: ownerWindow.textSecondary
            dividerColor: ownerWindow.dividerColor
            roomMembers: ownerWindow.currentRoomMembers
            roomMembersLoading: !!matrixConnectionObject.roomMembersPaginationInFlight[ownerWindow.currentRoomId]
            roomMembersError: matrixConnectionObject.roomMembersErrors[ownerWindow.currentRoomId] || ""
            roomMemberCount: ownerWindow.currentRoomMemberCount
            showThreadsInSmallGroups: ownerWindow.showThreadsInSmallGroups
            expandedMembersPanelWidth: ownerWindow.membersPanelPreferredWidth
            requestIdFactory: function(suffix) {
                return matrixConnectionObject.nextRequestId(suffix)
            }

            onChatsPanelToggleRequested: sidebar.collapsed = !sidebar.collapsed
            onMembersPanelResizeCommitted: function(panelWidth) {
                ownerWindow.membersPanelPreferredWidth = panelWidth
                appSettingsObject.membersPanelWidth = panelWidth
                appSettingsObject.sync()
            }
            onDraftRoomIdsChanged: ownerWindow.draftRoomIds = draftRoomIds
            onTypingStateChanged: function(roomId, typing) {
                matrixConnectionObject.sendTyping(roomId, typing)
            }

            onCommandRequested: function(command) {
                if (command && command.type === "get_pinned_messages") {
                    matrixConnectionObject.requestPinnedMessages(command.room_id || "")
                    return
                }
                if (command && command.type === "open_direct_message")
                    ownerWindow.pendingDirectMessageRequestId = command.request_id || ""
                matrixConnectionObject.sendCommand(command)
            }

            onFeedbackRequested: function(text, isError) {
                ownerWindow.showNotification(text, isError)
            }

            onSourceRequested: function(jsonText) {
                ownerWindow.openMessageSource(jsonText)
            }

            onOlderMessagesRequested: function(roomId) {
                console.log("[TimelineUI] older requested", roomId)
                if (roomId !== ownerWindow.currentRoomId
                        || roomId !== matrixConnectionObject.displayedRoomId)
                    return
                if (matrixConnectionObject.timelineDiffsSupported) {
                    var paginationStarted =
                        matrixConnectionObject.paginateTimelineBackwards()
                    if (paginationStarted) {
                        console.log("[TimelineUI] sending timeline pagination")
                    } else {
                        Qt.callLater(function() {
                            if (chatView) chatView.rearmOlderMessagesRequest()
                        })
                    }
                } else {
                    matrixConnectionObject.requestOlderMessages(roomId)
                }
            }

            Connections {
                target: matrixConnectionObject
                function onTimelinePaginationFinished() {
                    chatView.rearmOlderMessagesRequest()
                }
            }

            onOlderMembersRequested: function(roomId) {
                matrixConnectionObject.requestOlderRoomMembers(roomId)
            }
            onMembersRefreshRequested: function(roomId) {
                matrixConnectionObject.requestRoomMembers(roomId)
            }

            onSearchRequested: function(roomId, query, nextBatch, requestId) {
                matrixConnectionObject.searchRoomMessages(roomId, query, nextBatch, requestId)
            }

            onMessageContextRequested: function(roomId, eventId) {
                matrixConnectionObject.requestMessageContext(roomId, eventId)
            }

            onRoomMarkedUnreadRequested: function(roomId, eventId, unreadCount) {
                matrixConnectionObject.setRoomReadState(roomId, true, eventId, unreadCount)
            }
        }
            }
        }

        Item {
            width: visible ? parent.width - sidebar.width - spaceRail.width : 0
            height: parent.height
            visible: ownerWindow.currentRoomId === "" && !ownerWindow.spaceLobbyOpen

            Text {
                anchors.centerIn: parent

                text: L10n.I18n.tr("Выберите чат")
                color: ownerWindow.textSecondary
                font.pointSize: 10
            }
        }

        Loader {
            id: spaceLobbyLoader
            width: ownerWindow.spaceLobbyOpen
                ? parent.width - sidebar.width - spaceRail.width : 0
            height: parent.height
            visible: ownerWindow.spaceLobbyOpen
            active: ownerWindow.spaceLobbyOpen
            sourceComponent: Component {
        SpaceLobbyView {
            id: spaceLobby
            anchors.fill: parent
            roomModel: roomsModelObject
            selectedSpaceId: ownerWindow.selectedSpaceId
            selectedSpaceName: ownerWindow.selectedSpaceName
            mediaProxy: ownerWindow.mediaProxy
            roundAvatars: ownerWindow.roundAvatars
            accentColor: ownerWindow.accentColor
            iconColor: ownerWindow.iconColor
            accentTextColor: ownerWindow.accentTextColor
            backgroundColor: ownerWindow.backgroundColor
            surfaceColor: ownerWindow.surfaceColor
            elevatedColor: ownerWindow.elevatedColor
            textPrimary: ownerWindow.textPrimary
            textSecondary: ownerWindow.textSecondary
            dividerColor: ownerWindow.dividerColor

            onRoomSelected: function(roomId, roomName) {
                ownerWindow.spaceLobbyOpen = false
                ownerWindow.currentRoomId = roomId
                ownerWindow.currentRoomName = roomName
                ownerWindow.currentRoomMembers = ownerWindow.roomMembersCache[roomId] || []
                matrixConnectionObject.requestMessages(roomId)
                ownerWindow.requestRoomMembersIfNeeded(roomId)
            }
            onRoomInfoRequested: function(room) {
                if (!room || !room.room_id)
                    return
                if (room.joined === false) {
                    sidebar.showRoomInfo({
                        room_id: room.room_id || "",
                        display_name: room.name || room.room_id || "",
                        name: room.name || room.room_id || "",
                        topic: room.topic || "",
                        avatar_url: room.avatar_url || "",
                        joined_members_count: Number(room.member_count || 0),
                        invited_members_count: 0,
                        active_members_count: Number(room.member_count || 0),
                        direct_targets_count: 0,
                        unread_notification_count: 0,
                        unread_highlight_count: 0,
                        room_state: L10n.I18n.tr("Недоступно"),
                        room_type: L10n.I18n.tr("Комната"),
                        is_encrypted: false,
                        is_space: false
                    })
                    return
                }
                var requestId = matrixConnectionObject.nextRequestId("room-details")
                ownerWindow.pendingRoomDetailsMode = "info"
                ownerWindow.pendingRoomDetailsRequestId = requestId
                matrixConnectionObject.requestRoomDetails(room.room_id, requestId)
            }
            onJoinRequested: function(room) {
                matrixConnectionObject.joinSpaceRoom(room, String(room.join_rule || "").indexOf("knock") !== -1)
            }

            onMoreRoomsRequested: {
                if (spaceLobby.hierarchyNextBatch === "" || spaceLobby.hierarchyLoading)
                    return
                spaceLobby.hierarchyLoading = true
                matrixConnectionObject.requestSpaceHierarchy(
                    ownerWindow.selectedSpaceId, spaceLobby.hierarchyNextBatch)
            }
        }
            }
        }
    }
}
