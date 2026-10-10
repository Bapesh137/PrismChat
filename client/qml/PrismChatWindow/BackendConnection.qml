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

MatrixConnection {
    required property var window
    readonly property var ownerWindow: window
    required property var appSettingsObject
    required property var chatPreviewLoaderObject
    required property var chatViewObject
    required property var createRoomLoaderObject
    required property var directorySearchLoaderObject
    required property var globalVerificationLoaderObject
    required property var roomsModelObject
    required property var settingsDialogLoaderObject
    required property var sidebarObject
    required property var spaceLobbyObject
    required property var userPickerLoaderObject
    id: matrixConnection
    readingPositionResolver: ownerWindow.readingPositionFor
    roomModel: roomsModelObject
    currentRoomId: ownerWindow.currentRoomId
    accentColor: ownerWindow.accentColor
    pinnedRoomIds: ownerWindow.pinnedRoomIds
    readReceiptsEnabled: ownerWindow.readReceiptsEnabled
    roomReadReceiptOverrides: ownerWindow.roomReadReceiptOverrides

    onConnectionStateChanged: function(text, stateColor) {
        ownerWindow.connectionStatus = text
        ownerWindow.connectionStatusColor = stateColor
    }
    onRoomsUpdated: {
        ownerWindow.updateCurrentRoomMemberCount()
        ownerWindow.restoreLastOpenedRoom()
    }
    onRoomsLoadFinished: function(success) {
        ownerWindow.startupInitialDataReady = true
        ownerWindow.maybeFinishStartupIntro()
    }
    onRoomInvitationReceived: function(roomId, roomName, inviter) {
        if (roomId === "")
            return
        var inviterName = inviter !== "" ? Utils.displayName(inviter) : ""
        var text = inviterName !== ""
            ? inviterName + " " + L10n.I18n.tr("приглашает вас в чат")
            : L10n.I18n.tr("Новое приглашение в чат")
        var title = roomName || roomId || L10n.I18n.tr("Приглашение")
        ownerWindow.addCenterNotification("invite:" + roomId, "room_invitation",
                                        title, text, roomId, title)

        if (!ownerWindow.systemNotificationAllowed(roomId, "room_invitation"))
            return
        ownerWindow.showSystemNotification(title, text, roomId)
    }

    onBackgroundMessageReceived: function(roomId, message) {
        if (!message || message.sender === ownerWindow.currentUserId
                || message.sender_is_ignored || message.is_edited
                || message.is_redacted
                || message.msg_type === "m.key.verification.request"
                || !ownerWindow.messageMentionsCurrentUser(message))
            return
        var senderName = message.sender_display_name
            || Utils.displayName(message.sender || "")
        var roomName = ownerWindow.roomNameForId(roomId)
        var title = senderName !== ""
            ? senderName + " — " + roomName
            : roomName
        var body = ownerWindow.notificationBody(message)
        if (!ownerWindow.roomIsMuted(roomId)) {
            var eventKey = message.event_id || message.timestamp || Date.now()
            ownerWindow.addCenterNotification(
                "mention:" + roomId + ":" + eventKey, "mention",
                title, body, roomId, roomName)
        }
        if (ownerWindow.systemNotificationAllowed(roomId, "mention"))
            ownerWindow.showSystemNotification(title, body, roomId)
    }


    onAuthenticated: function(userId, server, avatarUrl, profileId, resetUi) {
        ownerWindow.startupSessionResolved = true
        if (loginScreen)
            loginScreen.completeLogin()
        if (registerScreen)
            registerScreen.completeRegistration()
        ownerWindow.showMain(userId, server, avatarUrl, profileId, resetUi)
    }

    onSessionStateResolved: function(authenticated) {
        ownerWindow.startupSessionResolved = true
        if (!authenticated)
            ownerWindow.startupInitialDataReady = true
        ownerWindow.maybeFinishStartupIntro()
    }

    onLoginFailed: function(errorText) {
        if (loginScreen)
            loginScreen.setLoginFailed(errorText)
    }

    onRegistrationFailed: function(errorText) {
        if (registerScreen)
            registerScreen.setRegistrationFailed(errorText)
    }

    onLoggedOut: {
        ownerWindow.pendingSettingsProfileId = ""
        ownerWindow.clearMainState()
        ownerWindow.clearCenterNotifications()
        ownerWindow.setAccountIdentity("", "", "", false)
        ownerWindow.sessionServer = ""
        ownerWindow.currentProfileId = ""
        ownerWindow.currentDeviceId = ""
        ownerWindow.profiles = []
        ownerWindow.currentPage = "login"
        ownerWindow.addingAccountMode = false
        if (settingsDialogLoaderObject.item)
            settingsDialogLoaderObject.item.close()
    }

    onAvatarUpdated: function(success, errorText, avatarUrl) {
        ownerWindow.avatarStatusText = success
            ? L10n.I18n.tr("Аватарка обновлена!")
            : L10n.I18n.tr("Ошибка: ") + errorText
        ownerWindow.avatarStatusColor = success ? ownerWindow.accentColor : "#ff5252"
        if (success && avatarUrl !== "") {
            ownerWindow.setAccountIdentity(
                ownerWindow.currentUserId,
                ownerWindow.currentDisplayName,
                avatarUrl,
                ownerWindow.currentDisplayNameKnown)
            ownerWindow.refreshAccountIdentity("avatar-profile")
        }
    }

    onProfilesUpdated: function(profiles, activeProfileId) {
        ownerWindow.profiles = profiles || []
        ownerWindow.currentProfileId = activeProfileId || ""
        if (!ownerWindow.currentDisplayNameKnown) {
            for (var identityIndex = 0; identityIndex < ownerWindow.profiles.length;
                    identityIndex++) {
                var profile = ownerWindow.profiles[identityIndex]
                if (profile.profile_id !== ownerWindow.currentProfileId) continue
                ownerWindow.setAccountIdentity(
                    profile.user_id || ownerWindow.currentUserId,
                    profile.display_name || ownerWindow.currentDisplayName,
                    profile.avatar_url || ownerWindow.currentUserAvatar,
                    false)
                break
            }
        }
        ownerWindow.updateCurrentDeviceIdFromProfiles()
    }

    onCurrentProfileUpdated: function(userId, server, avatarUrl, profileId) {
        if (profileId !== "" && profileId === ownerWindow.currentProfileId) {
            if (server !== "")
                ownerWindow.sessionServer = server
            ownerWindow.setAccountIdentity(
                userId || ownerWindow.currentUserId,
                ownerWindow.currentDisplayName,
                avatarUrl || ownerWindow.currentUserAvatar,
                ownerWindow.currentDisplayNameKnown)
            ownerWindow.updateCurrentDeviceIdFromProfiles()
        }
    }

    onProfileSwitchFailed: function(errorText) {
        ownerWindow.pendingSettingsProfileId = ""
        ownerWindow.showNotification(L10n.I18n.tr("Не удалось переключить аккаунт: ") + errorText, true)
    }

    onProfileDeleted: function(profileId, wasActive, errorText) {
        if (errorText && errorText !== "")
            ownerWindow.showNotification(L10n.I18n.tr("Не удалось удалить аккаунт: ") + errorText, true)
        else
            ownerWindow.forgetLastOpenedRoom(profileId)
    }

    onUserDetailsReceived: function(details, requestId, errorText) {
        if (requestId.indexOf("miniprofile") !== -1 && chatViewObject)
            chatViewObject.receiveUserDetails(details, requestId, errorText)
        if (errorText === "" && details)
            ownerWindow.applyAccountIdentityDetails(details)
        if (requestId === ownerWindow.pendingProfileDetailsRequestId) {
            ownerWindow.pendingProfileDetailsRequestId = ""
        }
    }

    onUserIgnoreFinished: function(userId, ignored, success, errorText, requestId) {
        if (chatViewObject)
            chatViewObject.receiveUserIgnoreResult(userId, ignored, success, errorText, requestId)
        if (!success && requestId.indexOf("miniprofile-ignore") === -1)
            ownerWindow.showNotification(errorText || L10n.I18n.tr("Не удалось выполнить действие"), true)
    }

    onRoomMemberModerationFinished: function(roomId, userId, action,
                                              success, errorText, requestId) {
        if (chatViewObject)
            chatViewObject.receiveModerationResult(roomId, userId, action, success,
                                             errorText, requestId)
        var settingsHandled = sidebarObject
            ? sidebarObject.finishMemberModeration(success, errorText) : false
        if (success && roomId !== "") {
            var members = Object.assign({}, ownerWindow.roomMembersCache)
            var updatedAt = Object.assign({}, ownerWindow.roomMembersCacheUpdatedAt)
            delete members[roomId]
            delete updatedAt[roomId]
            ownerWindow.roomMembersCache = members
            ownerWindow.roomMembersCacheUpdatedAt = updatedAt
            if (roomId === ownerWindow.currentRoomId)
                ownerWindow.currentRoomMembers = []
            matrixConnection.requestRoomMembers(roomId)
            if (settingsHandled) {
                var detailsRequestId = matrixConnection.nextRequestId(
                    "room-details-moderation")
                ownerWindow.pendingRoomDetailsMode = "edit"
                ownerWindow.pendingRoomDetailsRequestId = detailsRequestId
                matrixConnection.requestRoomDetails(roomId, detailsRequestId)
            }
        }
    }

    onEncryptionOverviewReceived: function(overview, errorText) {
        if (settingsDialogLoaderObject.item)
            settingsDialogLoaderObject.item.receiveEncryptionOverview(overview, errorText)
    }

    onMatrixDevicesReceived: function(devices, errorText) {
        if (settingsDialogLoaderObject.item)
            settingsDialogLoaderObject.item.receiveMatrixDevices(devices, errorText)
    }

    onMatrixDevicesChanged: function(devices, sessionEpoch) {
        if (settingsDialogLoaderObject.item)
            settingsDialogLoaderObject.item.receiveMatrixDevices(devices, "")
    }

    onDeviceOperationFinished: function(requestId, operation, success, deviceIds, errorText) {
        if (settingsDialogLoaderObject.item)
            settingsDialogLoaderObject.item.receiveDeviceOperation(operation, success, deviceIds, errorText)
        if (operation === "copy" && success)
            ownerWindow.showNotification(L10n.I18n.tr("Скопировано"), false)
    }

    onDeviceDeleteUiaaRequired: function(requestId, operationId, flows, passwordSupported) {
        if (settingsDialogLoaderObject.item)
            settingsDialogLoaderObject.item.receiveDeviceDeleteUiaa(operationId, flows, passwordSupported)
    }

    onDeviceDeleteWebRequired: function(requestId, deviceIds, url) {
        if (settingsDialogLoaderObject.item)
            settingsDialogLoaderObject.item.receiveDeviceDeleteWeb(deviceIds, url)
    }

    onE2eeActionFinished: function(requestId, success, uiaaSession, authType, approvalUrl, recoveryKey, flowId, errorText) {
        if (settingsDialogLoaderObject.item)
            settingsDialogLoaderObject.item.receiveE2eeAction(requestId, success, uiaaSession,
                                                        authType, approvalUrl,
                                                        recoveryKey, flowId, errorText)
    }

    onVerificationUpdated: function(update) {
        if (!globalVerificationLoaderObject.shouldIgnore(update))
            ownerWindow.openGlobalVerification(update)
    }

    onOwnProfileUpdated: function(success, details, errorText, requestId) {
        if (requestId !== ownerWindow.pendingDisplayNameRequestId) return
        ownerWindow.pendingDisplayNameRequestId = ""
        ownerWindow.displayNameBusy = false
        ownerWindow.displayNameStatusText = success
            ? L10n.I18n.tr("Отображаемое имя обновлено")
            : L10n.I18n.tr("Ошибка: ") + errorText
        ownerWindow.displayNameStatusColor = success ? ownerWindow.accentColor : "#ff5252"
        if (success && details) {
            ownerWindow.applyAccountIdentityDetails(details)
            matrixConnection.applyUserProfileChanged("", details.user_id || ownerWindow.currentUserId,
                                                     details.global_display_name || details.display_name || "",
                                                     details.global_avatar_url || details.avatar_url || "")
        }
    }

    onUserProfileChanged: function(roomId, userId, displayName, avatarUrl) {
        if (roomId === "") return
        var cachedMembers = ownerWindow.roomMembersCache[roomId] || []
        for (var i = 0; i < cachedMembers.length; i++) {
            if ((cachedMembers[i].user_id || "") === userId) {
                cachedMembers[i] = Object.assign({}, cachedMembers[i], {
                    display_name: displayName || "",
                    avatar_url: avatarUrl || ""
                })
            }
        }
        ownerWindow.roomMembersCache[roomId] = cachedMembers
        var cacheTimes = Object.assign({}, ownerWindow.roomMembersCacheUpdatedAt)
        delete cacheTimes[roomId]
        ownerWindow.roomMembersCacheUpdatedAt = cacheTimes
        if (roomId === ownerWindow.currentRoomId)
            ownerWindow.requestRoomMembersIfNeeded(roomId)
    }

    onRoomDetailsReceived: function(details, requestId, errorText) {
        if (requestId !== ownerWindow.pendingRoomDetailsRequestId) return
        ownerWindow.pendingRoomDetailsRequestId = ""
        if (errorText !== "") {
            ownerWindow.showNotification(errorText, true)
            return
        }
        if (!sidebarObject)
            return
        if (ownerWindow.pendingRoomDetailsMode === "edit")
            sidebarObject.showRoomEditor(details)
        else
            sidebarObject.showRoomInfo(details)
    }

    onRoomAddedToSpace: function(roomId, spaceId, success, errorText) {
        if (!success) {
            ownerWindow.showNotification(errorText || L10n.I18n.tr("Не удалось добавить комнату в пространство"), true)
            return
        }
        ownerWindow.showNotification(L10n.I18n.tr("Комната добавлена в пространство"), false)
        for (var roomIndex = 0; roomIndex < roomsModelObject.count; ++roomIndex) {
            var room = roomsModelObject.get(roomIndex)
            if (String(room.room_id || "") !== roomId)
                continue
            var parents = String(room.parent_space_key || "")
                .split("\u001f").filter(function(value) { return value !== "" })
            if (parents.indexOf(spaceId) === -1)
                parents.push(spaceId)
            roomsModelObject.setProperty(roomIndex, "parent_space_key", parents.join("\u001f"))
            break
        }
        matrixConnection.requestRooms()
        if (spaceId === ownerWindow.selectedSpaceId)
            matrixConnection.requestSpaceHierarchy(spaceId)
    }

    onRoomRemovedFromSpace: function(roomId, spaceId, success, errorText, requestId) {
        if (!success) {
            ownerWindow.showNotification(errorText || L10n.I18n.tr("Не удалось убрать комнату из пространства"), true)
            return
        }

        // Update the visible model immediately; requestRooms() below will
        // reconcile it with the homeserver once the sync/state catches up.
        for (var roomIndex = 0; roomIndex < roomsModelObject.count; ++roomIndex) {
            var room = roomsModelObject.get(roomIndex)
            if (String(room.room_id || "") !== roomId)
                continue
            var parents = String(room.parent_space_key || "")
                .split("\u001f").filter(function(value) { return value !== "" && value !== spaceId })
            roomsModelObject.setProperty(roomIndex, "parent_space_key", parents.join("\u001f"))
            break
        }

        ownerWindow.showNotification(L10n.I18n.tr("Комната убрана из пространства"), false)
        matrixConnection.requestRooms()
        if (spaceId !== "")
            matrixConnection.requestSpaceHierarchy(spaceId)
    }

    onRoomUpdateFinished: function(roomId, success, errorText) {
        if (sidebarObject)
            sidebarObject.finishRoomUpdate(success, errorText)
        if (!success) {
            ownerWindow.showNotification(errorText || L10n.I18n.tr("Не удалось изменить комнату"), true)
            return
        }
        ownerWindow.showNotification(L10n.I18n.tr("Изменения комнаты сохранены"), false)
        matrixConnection.requestRooms()
        if (ownerWindow.selectedSpaceId !== "")
            matrixConnection.requestSpaceHierarchy(ownerWindow.selectedSpaceId)
    }

    onRoomLeaveStarted: function(roomId) {
        if (ownerWindow.currentRoomId === roomId) {
            ownerWindow.clearMainState()
            ownerWindow.spaceLobbyOpen = ownerWindow.selectedSpaceId !== ""
        }
    }

    onRoomLeaveFinished: function(roomId, success, errorText) {
        if (!success) {
            ownerWindow.showNotification(L10n.I18n.tr("Не удалось покинуть комнату: ") + errorText, true)
            return
        }

        if (ownerWindow.roomIsPinned(roomId))
            ownerWindow.setRoomPinned(roomId, false)

        if (ownerWindow.currentRoomId === roomId) {
            ownerWindow.clearMainState()
            ownerWindow.spaceLobbyOpen = ownerWindow.selectedSpaceId !== ""
        }
        matrixConnection.requestRooms()
    }

    onRoomInviteFinished: function(roomId, success, errorText) {
        if (roomId !== ownerWindow.pendingInviteRoomId) return
        var roomName = ownerWindow.pendingInviteRoomName
        ownerWindow.pendingInviteRoomId = ""
        ownerWindow.pendingInviteRoomName = ""
        if (!success) {
            ownerWindow.showNotification(errorText || L10n.I18n.tr("Не удалось принять приглашение"), true)
            return
        }
        ownerWindow.dismissCenterNotification("invite:" + roomId)
        ownerWindow.spaceLobbyOpen = false
        ownerWindow.currentRoomId = roomId
        ownerWindow.currentRoomName = roomName || roomId
        ownerWindow.currentRoomMembers = []
        matrixConnection.requestMessages(roomId)
        ownerWindow.requestRoomMembersIfNeeded(roomId)
    }

    onDirectMessageReady: function(roomId, roomName, avatarUrl, created, errorText, requestId) {
        if (requestId === ""
                || requestId !== ownerWindow.pendingDirectMessageRequestId)
            return
        ownerWindow.pendingDirectMessageRequestId = ""
        if (errorText !== "" || roomId === "") {
            ownerWindow.showNotification(L10n.I18n.tr("Не удалось открыть личный чат: ")
                + (errorText || L10n.I18n.tr("неизвестная ошибка")), true)
            return
        }

        ownerWindow.currentRoomId = roomId
        ownerWindow.currentRoomName = roomName || L10n.I18n.tr("Личный чат")
        ownerWindow.currentRoomMembers = ownerWindow.roomMembersCache[roomId] || []
        matrixConnection.requestMessages(roomId)
        ownerWindow.requestRoomMembersIfNeeded(roomId)
    }

    onRoomCreated: function(roomId, roomName, isSpace, errorText, requestId) {
        var attemptedSpace = createRoomLoaderObject.item
            ? createRoomLoaderObject.item.creatingSpace : false
        if (createRoomLoaderObject.item)
            createRoomLoaderObject.item.receiveResult(errorText === "" && roomId !== "", errorText)
        if (errorText !== "" || roomId === "") {
            ownerWindow.showNotification(
                (attemptedSpace
                    ? L10n.I18n.tr("Не удалось создать пространство: ")
                    : L10n.I18n.tr("Не удалось создать комнату: "))
                    + (errorText || L10n.I18n.tr("неизвестная ошибка")), true)
            return
        }

        if (isSpace) {
            ownerWindow.selectedSpaceId = roomId
            ownerWindow.selectedSpaceName = roomName || roomId
            ownerWindow.clearMainState()
            ownerWindow.spaceLobbyOpen = true
            matrixConnection.requestSpaceHierarchy(roomId)
            ownerWindow.showNotification(L10n.I18n.tr("Пространство создано"), false)
            return
        }

        ownerWindow.selectedSpaceId = ""
        ownerWindow.selectedSpaceName = L10n.I18n.tr("Чаты")
        ownerWindow.spaceLobbyOpen = false
        ownerWindow.currentRoomId = roomId
        ownerWindow.currentRoomName = roomName || roomId
        ownerWindow.currentRoomMembers = ownerWindow.roomMembersCache[roomId] || []
        matrixConnection.requestMessages(roomId)
        ownerWindow.requestRoomMembersIfNeeded(roomId)
        ownerWindow.showNotification(L10n.I18n.tr("Комната создана"), false)
    }

    onRoomMembersReceived: function(roomId, members, nextBatch, append, errorText) {
        if (errorText !== "") {
            if (roomId === ownerWindow.currentRoomId)
                ownerWindow.showNotification(errorText, true)
            return
        }
        var incomingMembers = members || []
        var mergedMembers = append ? (ownerWindow.roomMembersCache[roomId] || []).slice(0) : []
        for (var memberIndex = 0; memberIndex < incomingMembers.length; memberIndex++) {
            var incomingMember = incomingMembers[memberIndex]
            var duplicateMember = false
            for (var existingMemberIndex = 0; existingMemberIndex < mergedMembers.length; existingMemberIndex++) {
                if (mergedMembers[existingMemberIndex].user_id === incomingMember.user_id) {
                    duplicateMember = true
                    break
                }
            }
            if (!duplicateMember) mergedMembers.push(incomingMember)
        }
        ownerWindow.roomMembersCache[roomId] = mergedMembers
        var memberCacheTimes = Object.assign({}, ownerWindow.roomMembersCacheUpdatedAt)
        memberCacheTimes[roomId] = Date.now()
        ownerWindow.roomMembersCacheUpdatedAt = memberCacheTimes
        var memberAccess = Object.assign({}, ownerWindow.roomMembersCacheLastAccess)
        memberAccess[roomId] = Date.now()
        ownerWindow.roomMembersCacheLastAccess = memberAccess
        ownerWindow.trimRoomMembersCache(roomId)
        if (roomId === ownerWindow.currentRoomId)
            ownerWindow.currentRoomMembers = mergedMembers
    }

    onRoomSearchReceived: function(roomId, messages, nextBatch, errorText, requestId) {
        if (sidebarObject)
            sidebarObject.receiveMessageSearchResults(roomId, messages, errorText, requestId)
        if (chatViewObject && roomId === ownerWindow.currentRoomId)
            chatViewObject.receiveSearchResults(messages, nextBatch, errorText, requestId)
    }
    onUserDirectorySearchReceived: function(users, limited, errorText, requestId) {
        if (directorySearchLoaderObject.item)
            directorySearchLoaderObject.item.receiveResults(
                "users", users, limited, errorText, requestId)
        if (userPickerLoaderObject.item)
            userPickerLoaderObject.item.receiveResults(users, limited, errorText, requestId)
    }

    onPublicRoomSearchReceived: function(rooms, nextBatch, errorText, requestId) {
        if (directorySearchLoaderObject.item
                && directorySearchLoaderObject.item.searchMode === "spaces") {
            var spaces = []
            for (var index = 0; index < rooms.length; ++index) {
                if (rooms[index].is_space)
                    spaces.push(rooms[index])
            }
            directorySearchLoaderObject.item.receiveResults(
                "spaces", spaces, nextBatch !== "", errorText, requestId)
            return
        }
        if (directorySearchLoaderObject.item)
            directorySearchLoaderObject.item.receiveResults(
                "rooms", rooms, nextBatch !== "", errorText, requestId)
    }


    onRoomAttachmentsReceived: function(roomId, messages, nextFrom, errorText, requestId) {
        if (chatViewObject)
            chatViewObject.receiveAttachments(roomId, messages, nextFrom, errorText, requestId)
    }
    onThreadMessagesReceived: function(roomId, rootEventId, messages, hasMore,
                                       errorText, requestId) {
        if (chatViewObject)
            chatViewObject.receiveThreadMessages(roomId, rootEventId, messages, hasMore,
                                           errorText, requestId)
    }
    onRoomThreadsReceived: function(roomId, threads, nextFrom, unreadCount,
                                    errorText, requestId) {
        if (chatViewObject)
            chatViewObject.receiveRoomThreads(roomId, threads, nextFrom, unreadCount,
                                        errorText, requestId)
    }
    onAllThreadsReadFinished: function(roomId, success, readEvents, errorText, requestId) {
        if (chatViewObject)
            chatViewObject.receiveAllThreadsRead(roomId, success, readEvents, errorText, requestId)
    }
    onThreadReadFinished: function(roomId, rootEventId, success, errorText) {
        if (chatViewObject)
            chatViewObject.receiveThreadRead(roomId, rootEventId, success, errorText)
    }
    onTimelineMessagesUpdated: function(roomId, messages) {
        if (chatViewObject)
            chatViewObject.receiveLiveTimelineMessages(roomId, messages)
    }
    onThreadMutationFinished: function(roomId, rootEventId) {
        if (chatViewObject)
            chatViewObject.receiveThreadMutation(roomId, rootEventId)
    }
    onRoomPreviewReceived: function(roomId, messages, nextFrom, append, errorText, requestId) {
        if (chatPreviewLoaderObject.item)
            chatPreviewLoaderObject.item.receivePage(roomId, messages, nextFrom,
                                               append, errorText, requestId)
    }

    onMessageContextReceived: function(roomId, eventId, found) {
        if (chatViewObject)
            chatViewObject.receiveMessageContext(roomId, eventId, found)
    }

    onPinnedMessagesReceived: function(roomId, messages, errorText) {
        if (chatViewObject)
            chatViewObject.receivePinnedMessages(roomId, messages, errorText)
    }

    onSpaceHierarchyReceived: function(spaceId, rooms, nextBatch, append, errorText) {
        if (spaceLobbyObject && spaceId === ownerWindow.selectedSpaceId) {
            var page = rooms || []
            var mergedRooms = append ? (spaceLobbyObject.hierarchyRooms || []).slice(0) : []
            for (var roomIndex = 0; roomIndex < page.length; roomIndex++) {
                var roomEntry = page[roomIndex]
                if ((roomEntry.room_id || "") === spaceId)
                    continue
                var alreadyPresent = false
                for (var existingRoomIndex = 0; existingRoomIndex < mergedRooms.length; existingRoomIndex++) {
                    if (mergedRooms[existingRoomIndex].room_id === roomEntry.room_id) {
                        alreadyPresent = true
                        break
                    }
                }
                if (!alreadyPresent) mergedRooms.push(roomEntry)
            }
            spaceLobbyObject.hierarchyRooms = mergedRooms
            spaceLobbyObject.hierarchyNextBatch = nextBatch || ""
            spaceLobbyObject.hierarchyLoading = false
            spaceLobbyObject.hierarchyError = errorText || ""
            spaceLobbyObject.hierarchyReady = true
        }
    }

    onJoinSpaceRoomFinished: function(roomId, success, knocked, errorText) {
        var directoryJoin = roomId !== ""
            && roomId === ownerWindow.pendingDirectoryRoomId
        var directoryRoomName = ownerWindow.pendingDirectoryRoomName
        var directoryIsSpace = ownerWindow.pendingDirectoryIsSpace
        if (directoryJoin) {
            ownerWindow.pendingDirectoryRoomId = ""
            ownerWindow.pendingDirectoryRoomName = ""
            ownerWindow.pendingDirectoryIsSpace = false
        }

        if (!success) {
            ownerWindow.showNotification(
                errorText || L10n.I18n.tr("Не удалось войти в комнату"), true)
            return
        }

        if (ownerWindow.selectedSpaceId !== "")
            matrixConnection.requestSpaceHierarchy(ownerWindow.selectedSpaceId)

        // A successful /knock does not mean that we joined the room.
        // We stay outside until a moderator accepts the request with an invite.
        if (knocked) {
            ownerWindow.showNotification(
                L10n.I18n.tr("Заявка на вступление отправлена"), false)
            return
        }

        if (!directoryJoin)
            return

        if (directoryIsSpace) {
            ownerWindow.openSpace(roomId, directoryRoomName || roomId)
            return
        }

        ownerWindow.spaceLobbyOpen = false
        ownerWindow.currentRoomId = roomId
        ownerWindow.currentRoomName = directoryRoomName || roomId
        ownerWindow.currentRoomMembers = ownerWindow.roomMembersCache[roomId] || []
        matrixConnection.requestMessages(roomId)
        ownerWindow.requestRoomMembersIfNeeded(roomId)
    }

    onClipboardPasteFinished: function(requestId, success, text, attachments, errorText) {
        if (chatViewObject)
            chatViewObject.receiveClipboardPasteResult(requestId, success, text, attachments, errorText)
    }

    onEditMessageFinished: function(requestId, success, errorText) {
        if (chatViewObject)
            chatViewObject.receiveEditResult(requestId, success, errorText)
    }

    onUploadProgressChanged: function(requestId, current, total) {
        if (chatViewObject)
            chatViewObject.receiveUploadProgress(requestId, current, total)
    }

    onUploadFinished: function(requestId, success, errorText) {
        if (chatViewObject)
            chatViewObject.receiveUploadResult(requestId, success, errorText)
    }

    onStickerAssetUploaded: function(requestId, success, mediaUrl, mimeType, errorText) {
        if (chatViewObject)
            chatViewObject.receiveStickerAssetUpload(requestId, success, mediaUrl, mimeType, errorText)
    }

    onRoomKeysTransferFinished: function(requestId, operation, success,
                                         importedCount, totalCount, errorText) {
        if (requestId !== ownerWindow.pendingKeyTransferRequestId) return
        ownerWindow.pendingKeyTransferRequestId = ""
        ownerWindow.keyTransferBusy = false
        ownerWindow.keyTransferError = !success

        if (!success) {
            ownerWindow.keyTransferStatus = errorText
                || L10n.I18n.tr("Не удалось обработать файл ключей")
            ownerWindow.showNotification(ownerWindow.keyTransferStatus, true)
            return
        }

        if (operation === "import") {
            ownerWindow.keyTransferStatus = L10n.I18n.tr("Импортировано ключей: ")
                + importedCount + " / " + totalCount
            matrixConnection.invalidateMessageCachesAfterKeyImport()
            if (chatPreviewLoaderObject.item)
                chatPreviewLoaderObject.item.close()
            if (ownerWindow.currentRoomId !== "")
                matrixConnection.requestMessages(ownerWindow.currentRoomId, true)
        } else {
            ownerWindow.keyTransferStatus =
                L10n.I18n.tr("Ключи шифрования успешно экспортированы")
        }
        ownerWindow.showNotification(ownerWindow.keyTransferStatus, false)
    }

    onStorageStatsReceived: function(stats, errorText) {
        ownerWindow.storageBusy = false
        if (errorText !== "" || !stats) {
            ownerWindow.storageStatus = errorText
                || L10n.I18n.tr("Не удалось получить сведения о хранилище")
            ownerWindow.storageStatusError = true
            return
        }
        ownerWindow.storageSqliteBytes = Number(stats.sqlite_bytes || 0)
        ownerWindow.storageEventCacheBytes = Number(stats.event_cache_bytes || 0)
        ownerWindow.storageMediaBytes = Number(stats.media_bytes || 0)
        ownerWindow.storageTotalCacheBytes = Number(stats.total_cache_bytes || 0)
        ownerWindow.storageAutoCleanupDays = Number(stats.auto_cleanup_days || 0)
        ownerWindow.storageCacheLimitMb = Math.max(64, Number(stats.cache_limit_mb || 1024))
        ownerWindow.storageDownloadsDirectory = stats.downloads_dir || ""
        ownerWindow.storageAutoLoadImages = stats.auto_load_images !== false
        ownerWindow.storageAutoLoadVideos = stats.auto_load_videos !== false
        appSettingsObject.storageAutoCleanupDays = ownerWindow.storageAutoCleanupDays
        appSettingsObject.storageCacheLimitMb = ownerWindow.storageCacheLimitMb
        appSettingsObject.storageDownloadsDirectory = ownerWindow.storageDownloadsDirectory
        appSettingsObject.storageAutoLoadImages = ownerWindow.storageAutoLoadImages
        appSettingsObject.storageAutoLoadVideos = ownerWindow.storageAutoLoadVideos
        ownerWindow.storageStatus = L10n.I18n.tr("Размер хранилища обновлён")
        ownerWindow.storageStatusError = false
    }

    onStorageActionFinished: function(action, success, details, errorText) {
        if (action === "set_storage_preferences") {
            if (!success) {
                ownerWindow.storageStatus = errorText
                    || L10n.I18n.tr("Не удалось сохранить настройки хранилища")
                ownerWindow.storageStatusError = true
            }
            return
        }

        if (action === "download_media") {
            if (success) {
                var savedPath = details && details.path ? details.path : ""
                ownerWindow.showNotification(
                    savedPath !== ""
                        ? L10n.I18n.tr("Файл сохранён: ") + savedPath
                        : L10n.I18n.tr("Файл сохранён"), false)
            } else {
                ownerWindow.showNotification(errorText
                    || L10n.I18n.tr("Не удалось сохранить файл"), true)
            }
            return
        }

        ownerWindow.storageBusy = false
        ownerWindow.storageStatusError = !success
        if (action === "clear_cache") {
            if (success) {
                var restartRequired = details && details.restart_required
                ownerWindow.storageStatus = restartRequired
                    ? L10n.I18n.tr("Выбранные данные будут очищены после перезапуска приложения")
                    : L10n.I18n.tr("Кэш очищен")
                if (!restartRequired) {
                    matrixConnection.sendCommand({
                        type: "get_storage_stats",
                        request_id: matrixConnection.nextRequestId("storage-stats-after-clear")
                    })
                    ownerWindow.storageBusy = true
                }
            } else {
                ownerWindow.storageStatus = errorText
                    || L10n.I18n.tr("Не удалось полностью очистить кэш")
            }
        } else if (action === "clear_temporary_data") {
            ownerWindow.storageStatus = success
                ? L10n.I18n.tr("Черновики и временные голосовые очищены")
                : (errorText || L10n.I18n.tr("Не удалось очистить временные данные"))
        } else if (action === "export_diagnostics") {
            ownerWindow.storageStatus = success
                ? L10n.I18n.tr("Диагностический отчёт сохранён")
                : (errorText || L10n.I18n.tr("Не удалось сохранить диагностический отчёт"))
        }
        if (ownerWindow.storageStatus !== "")
            ownerWindow.showNotification(ownerWindow.storageStatus, !success)
    }

    onOperationFeedback: function(text, isError) {
        ownerWindow.showNotification(text, isError)
    }
}
