import QtQuick
import "../components/voice"
import Prism.Ipc 1.0 as Native
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

ApplicationWindow {
    id: appWindow

    readonly property alias appSettingsObject: appSettings
    readonly property alias voiceSessionObject: voiceSession
    readonly property alias matrixConnectionObject: matrixConnection
    readonly property alias roomsModelObject: roomsModel
    readonly property alias startupIntroLoaderObject: startupIntroLoader
    readonly property var i18nService: L10n.I18n

    property alias transportAutoConnect: matrixConnection.transportAutoConnect

    readonly property alias invitationNotificationsModelObject: invitationNotificationsModel
    readonly property alias mentionNotificationsModelObject: mentionNotificationsModel

    FontLoader {
        id: cjkUiFont
        // Avoid loading the large CJK font for unrelated locales.
        source: appWindow.cjkInterfaceLanguage
            ? Qt.resolvedUrl("../assets/NotoSansCJK-Regular.ttc") : ""
    }

    readonly property bool cjkInterfaceLanguage: languageCode === "zh"
        || languageCode === "ja" || languageCode === "ko"
    readonly property string cjkUiFontFamily: languageCode === "zh"
        ? "Noto Sans CJK SC" : languageCode === "ko"
            ? "Noto Sans CJK KR" : "Noto Sans CJK JP"
    font.family: cjkInterfaceLanguage && cjkUiFont.status === FontLoader.Ready
        ? cjkUiFontFamily : ""

    onClosing: {
        appSettings.roomReadingPositionsJson = JSON.stringify(roomReadingPositions)
        voiceSession.pendingRoom = null
        voiceSession.leave()
    }

    visible: true
    readonly property bool remoteCustomTitleBar: typeof prismRemoteWayland !== "undefined"
        && prismRemoteWayland
    property bool windowPinned: false
    flags: Qt.Window
        | (remoteCustomTitleBar ? Qt.FramelessWindowHint : 0)
        | (windowPinned ? Qt.WindowStaysOnTopHint : 0)
    width: 980
    height: 680
    minimumWidth: 900
    minimumHeight: 560
    title: "PrismChat"
    color: backgroundColor

    header: PrismWindowTitleBar {
        visible: appWindow.remoteCustomTitleBar
        height: visible ? implicitHeight : 0
        window: appWindow
        pinned: appWindow.windowPinned
        backgroundColor: appWindow.surfaceColor
        textColor: appWindow.textPrimary
        secondaryTextColor: appWindow.textSecondary
        accentColor: appWindow.accentColor
        dividerColor: appWindow.dividerColor
        onPinToggled: {
            appWindow.windowPinned = !appWindow.windowPinned
            Qt.callLater(function() {
                appWindow.show()
                appWindow.raise()
                appWindow.requestActivate()
            })
        }
    }

    property string currentPage: "login"
    property bool startupIntroMinimumFinished: false
    property bool startupSessionResolved: false
    property bool startupInitialDataReady: false
    property string currentRoomId: ""
    property string currentRoomName: L10n.I18n.tr("Выберите чат")
    property int currentRoomEncryptionState: -1
    property int currentRoomMemberCount: 0
    property var accountIdentity: ({
        user_id: "",
        display_name: "",
        avatar_url: "",
        known: false
    })
    readonly property string currentUserId: accountIdentity.user_id || ""
    property string sessionServer: ""
    readonly property string currentUserAvatar: accountIdentity.avatar_url || ""
    readonly property string currentDisplayName: accountIdentity.display_name || ""
    readonly property bool currentDisplayNameKnown: !!accountIdentity.known
    property string currentProfileId: ""
    property var roomReadingPositions: ({})
    property real sidebarPanelWidth: Math.max(220, Math.min(420,
        Number(appSettings.sidebarPanelWidth || 260)))
    property real membersPanelPreferredWidth: Math.max(190, Math.min(420,
        Number(appSettings.membersPanelWidth || 230)))

    function matrixToLink(identifier) {
        var value = String(identifier || "")
        return value === "" ? ""
            : "https://matrix.to/#/" + encodeURIComponent(value)
    }

    function copyText(text) {
        appClipboard.text = String(text || "")
        appClipboard.selectAll()
        appClipboard.copy()
        appClipboard.text = ""
    }

    TextEdit {
        id: appClipboard
        visible: false
    }

    function readingPositionFor(roomId) {
        return roomReadingPositions[JSON.stringify([currentProfileId, roomId])] || null
    }
    function otherProfileReadEventIds(roomId) {
        var result = []
        if (!roomId) return result
        var keys = Object.keys(roomReadingPositions || {})
        for (var index = 0; index < keys.length; ++index) {
            var identity
            try { identity = JSON.parse(keys[index]) } catch (_) { continue }
            if (!Array.isArray(identity) || identity.length !== 2
                    || identity[0] === currentProfileId || identity[1] !== roomId)
                continue
            var position = roomReadingPositions[keys[index]] || {}
            var eventId = String(position.read_event_id || "")
            if (eventId && result.indexOf(eventId) < 0) result.push(eventId)
        }
        return result
    }
    function saveReadingPosition(accountId, roomId, position) {
        if (!accountId || !roomId || !position || !position.event_id) return
        var next = Object.assign({}, roomReadingPositions)
        next[JSON.stringify([accountId, roomId])] = position
        var keys = Object.keys(next).sort(function(a,b) { return next[b].updated_at-next[a].updated_at })
        while (keys.length > 500) delete next[keys.pop()]
        roomReadingPositions = next
        readingPositionSaveTimer.restart()
    }
    Timer {
        id: readingPositionSaveTimer
        interval: 500
        onTriggered: appSettings.roomReadingPositionsJson = JSON.stringify(appWindow.roomReadingPositions)
    }
    readonly property bool shortcutModalOpen:
        (settingsDialogLoader.item && settingsDialogLoader.item.opened)
        || (logoutConfirmLoader.item && logoutConfirmLoader.item.opened)
        || (globalVerificationLoader.item && globalVerificationLoader.item.opened)
        || (sourceDialogLoader.item && sourceDialogLoader.item.opened)
        || (directorySearchLoader.item && directorySearchLoader.item.opened)
        || (userPickerLoader.item && userPickerLoader.item.opened)
        || (createRoomLoader.item && createRoomLoader.item.opened)
        || (avatarDialogLoader.item && avatarDialogLoader.item.opened)

    Shortcut {
        sequence: "Ctrl+K"
        context: Qt.ApplicationShortcut
        enabled: appWindow.currentPage === "main" && !appWindow.shortcutModalOpen
            && !!appWindow.sidebar
        onActivated: appWindow.sidebar.focusRoomSearch()
    }
    Shortcut {
        sequence: "Ctrl+F"
        context: Qt.ApplicationShortcut
        enabled: appWindow.currentPage === "main" && !appWindow.shortcutModalOpen
            && !!appWindow.chatView
        onActivated: appWindow.chatView.focusMessageSearch()
    }
    Shortcut {
        sequence: "Ctrl+,"
        context: Qt.ApplicationShortcut
        enabled: appWindow.currentPage === "main" && !appWindow.shortcutModalOpen
        onActivated: appWindow.openSettingsDialog()
    }
    Shortcut {
        sequence: "Alt+Up"
        context: Qt.ApplicationShortcut
        enabled: appWindow.currentPage === "main" && !appWindow.shortcutModalOpen
            && !!appWindow.sidebar
        onActivated: appWindow.sidebar.selectRelativeRoom(-1)
    }
    Shortcut {
        sequence: "Alt+Down"
        context: Qt.ApplicationShortcut
        enabled: appWindow.currentPage === "main" && !appWindow.shortcutModalOpen
            && !!appWindow.sidebar
        onActivated: appWindow.sidebar.selectRelativeRoom(1)
    }
    property string pendingSettingsProfileId: ""
    property string currentDeviceId: ""
    property var lastRoomIdsByProfile: ({})
    property string pendingLastRoomRestoreProfileId: ""
    onCurrentRoomIdChanged: {
        currentRoomEncryptionState = -1
        rememberLastOpenedRoom(currentRoomId)
        updateCurrentRoomMemberCount()
        updateCurrentRoomEncryptionState()
    }
    property var profiles: []
    property var pinnedRoomIds: []
    property var archivedRoomIds: []
    property var mutedRoomIds: []
    property bool archiveInSpaceRail: false
    property var draftRoomIds: []
    property bool addingAccountMode: false
    property string selectedSpaceId: ""
    property bool showSpaceRoomsInHome: false
    property string selectedSpaceName: L10n.I18n.tr("Чаты")
    property bool spaceLobbyOpen: false
    property var currentRoomMembers: []
    property var roomMembersCache: ({})
    property var roomMembersCacheUpdatedAt: ({})
    property var roomMembersCacheLastAccess: ({})
    // First member pages share the message-prefetch cache horizon.
    property int maxCachedMemberRooms: 256
    property int maxCachedMembersPerRoom: 1000
    property string pendingRoomDetailsRequestId: ""
    property string pendingRoomDetailsMode: "info"
    property string draggedRoomId: ""
    property string draggedRoomName: ""
    property string pendingDirectMessageRequestId: ""
    property string pendingDirectoryRoomId: ""
    property string pendingDirectoryRoomName: ""
    property bool pendingDirectoryIsSpace: false
    property string notificationText: ""
    property bool notificationIsError: false
    property int notificationUnreadCount: 0
    property bool systemNotificationsEnabled: true
    property bool systemInvitationNotificationsEnabled: true
    property bool systemMentionNotificationsEnabled: true
    property bool readReceiptsEnabled: true
    property var roomReadReceiptOverrides: ({})
    property bool typingNotificationsEnabled: true
    property var roomTypingNotificationOverrides: ({})
    // Direct QML runs do not install this context property.
    readonly property var nativeSystemNotifier: typeof systemNotifier === "undefined"
        ? null : systemNotifier

    property bool roundAvatars: true
    property bool showThreadsInSmallGroups: false
    property string messageDateFormat: "dd.MM.yyyy"
    property string messageTimeFormat: "HH:mm"
    property string themeMode: "dark"
    property string darkThemeId: "green"
    property string lightThemeId: "green"
    property int automaticLightStartMinutes: 7 * 60
    property int automaticDarkStartMinutes: 19 * 60
    property int automaticThemeMinutes: {
        var now = new Date()
        return now.getHours() * 60 + now.getMinutes()
    }
    readonly property bool automaticLightActive: {
        var lightStart = Math.max(0, Math.min(1439, automaticLightStartMinutes))
        var darkStart = Math.max(0, Math.min(1439, automaticDarkStartMinutes))
        if (lightStart === darkStart)
            return true
        if (lightStart < darkStart)
            return automaticThemeMinutes >= lightStart && automaticThemeMinutes < darkStart
        return automaticThemeMinutes >= lightStart || automaticThemeMinutes < darkStart
    }
    readonly property string effectiveThemeMode: themeMode === "automatic"
        ? (automaticLightActive ? "light" : "dark") : themeMode
    property color customAccentColor: "#20D500"
    property color customIconColor: customAccentColor
    property color customBackgroundColor: "#07100A"
    property color customSurfaceColor: "#0B1710"
    property color customElevatedColor: "#102016"
    property color customTextPrimary: "#F2FFF4"
    property color customTextSecondary: "#A7B8AA"
    property color customDividerColor: "#29402E"
    property real uiScale: 1.0
    property bool animationsEnabled: true
    property string windowWobbleMode: "off"
    property int windowSpringStrength: 100
    property int windowWobbleStrength: 50
    property int startupIntroVariant: 0
    property string languageCode: L10n.I18n.language
    property string connectionStatus: L10n.I18n.tr("Ожидание бэкенда...")
    property color connectionStatusColor: textSecondary
    property string avatarStatusText: ""
    property color avatarStatusColor: accentColor
    property string displayNameStatusText: ""
    property color displayNameStatusColor: accentColor
    property bool displayNameBusy: false
    property bool keyTransferBusy: false
    property string keyTransferStatus: ""
    property bool keyTransferError: false
    property string pendingKeyTransferRequestId: ""
    property double storageSqliteBytes: 0
    property double storageEventCacheBytes: 0
    property double storageMediaBytes: 0
    property double storageTotalCacheBytes: 0
    property int storageAutoCleanupDays: 0
    property int storageCacheLimitMb: 1024
    property string storageDownloadsDirectory: ""
    property bool storageAutoLoadImages: true
    property bool storageAutoLoadVideos: true
    property bool storageBusy: false
    property string storageStatus: ""
    property bool storageStatusError: false
    property int draftClearGeneration: 0
    property string pendingProfileDetailsRequestId: ""
    property string pendingDisplayNameRequestId: ""
    property string pendingInviteRoomId: ""
    property string pendingInviteRoomName: ""

    readonly property string mediaProxy: matrixConnection.mediaProxyBase

    SystemPalette {
        id: systemPalette
        colorGroup: SystemPalette.Active
    }

    function contrastingTextColor(value) {
        var luminance = value.r * 0.299 + value.g * 0.587 + value.b * 0.114
        return luminance > 0.58 ? "#071007" : "#FFFFFF"
    }

    readonly property var activeBuiltInTheme: Themes.ThemeCatalog.theme(
        effectiveThemeMode === "light" ? "light" : "dark",
        effectiveThemeMode === "light" ? lightThemeId : darkThemeId)

    readonly property color accentColor: themeMode === "custom"
        ? customAccentColor
        : themeMode === "system" ? systemPalette.highlight : activeBuiltInTheme.accent

    readonly property color iconColor: themeMode === "custom"
        ? customIconColor
        : themeMode === "system" ? systemPalette.highlight : activeBuiltInTheme.icons

    readonly property color accentTextColor: themeMode === "custom"
        ? contrastingTextColor(customAccentColor)
        : themeMode === "system" ? systemPalette.highlightedText : activeBuiltInTheme.accentText

    readonly property color textPrimary: themeMode === "custom"
        ? customTextPrimary
        : themeMode === "system" ? systemPalette.windowText
        : activeBuiltInTheme.textPrimary

    readonly property color textSecondary: themeMode === "custom"
        ? customTextSecondary
        : themeMode === "system"
            ? Qt.rgba(systemPalette.windowText.r, systemPalette.windowText.g,
                      systemPalette.windowText.b, 0.62)
            : activeBuiltInTheme.textSecondary

    readonly property color backgroundColor: themeMode === "custom"
        ? customBackgroundColor
        : themeMode === "system" ? systemPalette.window
        : activeBuiltInTheme.background

    readonly property color surfaceColor: themeMode === "custom"
        ? customSurfaceColor
        : themeMode === "system" ? systemPalette.base
        : activeBuiltInTheme.surface

    readonly property color elevatedColor: themeMode === "custom"
        ? customElevatedColor
        : themeMode === "system" ? systemPalette.button
        : activeBuiltInTheme.elevated

    readonly property color dividerColor: themeMode === "custom"
        ? customDividerColor
        : themeMode === "system" ? systemPalette.mid
        : activeBuiltInTheme.divider
    palette.window: backgroundColor
    palette.base: surfaceColor
    palette.alternateBase: elevatedColor
    palette.button: elevatedColor
    palette.windowText: textPrimary
    palette.text: textPrimary
    palette.buttonText: textPrimary
    palette.brightText: "#FFFFFF"
    palette.placeholderText: textSecondary
    palette.highlight: accentColor
    palette.highlightedText: accentTextColor

    function syncWindowDecoration() {
        if (typeof windowDecorationBridge === "undefined")
            return
        windowDecorationBridge.apply(surfaceColor, backgroundColor,
                                     textPrimary, textSecondary, accentColor)
    }

    onSurfaceColorChanged: windowDecorationSyncTimer.restart()
    onBackgroundColorChanged: windowDecorationSyncTimer.restart()
    onTextPrimaryChanged: windowDecorationSyncTimer.restart()
    onTextSecondaryChanged: windowDecorationSyncTimer.restart()
    onAccentColorChanged: windowDecorationSyncTimer.restart()

    Timer {
        id: windowDecorationSyncTimer
        interval: 40
        repeat: false
        onTriggered: appWindow.syncWindowDecoration()
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            var now = new Date()
            appWindow.automaticThemeMinutes = now.getHours() * 60 + now.getMinutes()
        }
    }

    Settings {
        id: appSettings
        category: "Appearance"
        property string themeMode: "dark"
        property string darkThemeId: "green"
        property string lightThemeId: "green"
        property int automaticLightStartMinutes: 420
        property int automaticDarkStartMinutes: 1140
        property bool roundAvatars: true
        property bool showSpaceRoomsInHome: false
        property bool showThreadsInSmallGroups: false
        property string messageDateFormat: "dd.MM.yyyy"
        property string messageTimeFormat: "HH:mm"
        property string languageCode: ""
        property real uiScale: 1.0
        property bool animationsEnabled: true
        // Legacy setting migrated to windowWobbleMode.
        property bool windowWobbleEnabled: false
        property string windowWobbleMode: ""
        property int windowSpringStrength: 100
        property int windowWobbleStrength: 50
        property bool windowWobbleStrengthDefaultMigrated: false
        property int startupIntroVariant: 0
        property real sidebarPanelWidth: 260
        property real membersPanelWidth: 230
        property string customAccentColor: "#20D500"
        property string customIconColor: ""
        property string customBackgroundColor: "#07100A"
        property string customSurfaceColor: "#0B1710"
        property string customElevatedColor: "#102016"
        property string customTextPrimary: "#F2FFF4"
        property string customTextSecondary: "#A7B8AA"
        property string customDividerColor: "#29402E"
        property string pinnedRoomIdsJson: "[]"
        property string archivedRoomIdsJson: "[]"
        property string mutedRoomIdsJson: "[]"
        property bool systemNotificationsEnabled: true
        property bool systemInvitationNotificationsEnabled: true
        property bool systemMentionNotificationsEnabled: true
        property bool readReceiptsEnabled: true
        property string roomReadReceiptOverridesJson: "{}"
        property bool typingNotificationsEnabled: true
        property string roomTypingNotificationOverridesJson: "{}"
        property string lastRoomIdsByProfileJson: "{}"
        property string roomReadingPositionsJson: "{}"
        property bool archiveInSpaceRail: false
        property int storageAutoCleanupDays: 0
        property int storageCacheLimitMb: 1024
        property string storageDownloadsDirectory: ""
        property bool storageAutoLoadImages: true
        property bool storageAutoLoadVideos: true
    }

    Component.onCompleted: {
        var initialLanguage = L10n.I18n.initialize(appSettings.languageCode)
        if (appSettings.languageCode === "")
            appSettings.languageCode = initialLanguage
        var storedThemeMode = String(appSettings.themeMode || "dark")
        var allowedThemeModes = ["system", "automatic", "dark", "light", "custom"]
        themeMode = allowedThemeModes.indexOf(storedThemeMode) !== -1
            ? storedThemeMode : "dark"
        darkThemeId = appSettings.darkThemeId === "crimson_night"
            ? "red" : String(appSettings.darkThemeId || "green")
        lightThemeId = appSettings.lightThemeId === "prism_garden"
            ? "green" : String(appSettings.lightThemeId || "green")
        var storedLightStart = Number(appSettings.automaticLightStartMinutes)
        var storedDarkStart = Number(appSettings.automaticDarkStartMinutes)
        automaticLightStartMinutes = isFinite(storedLightStart)
            ? Math.max(0, Math.min(1439, storedLightStart)) : 420
        automaticDarkStartMinutes = isFinite(storedDarkStart)
            ? Math.max(0, Math.min(1439, storedDarkStart)) : 1140
        appSettings.themeMode = themeMode
        appSettings.darkThemeId = darkThemeId
        appSettings.lightThemeId = lightThemeId
        appSettings.automaticLightStartMinutes = automaticLightStartMinutes
        appSettings.automaticDarkStartMinutes = automaticDarkStartMinutes
        appSettings.sync()
        customAccentColor = appSettings.customAccentColor
        customIconColor = appSettings.customIconColor !== ""
            ? appSettings.customIconColor : appSettings.customAccentColor
        customBackgroundColor = appSettings.customBackgroundColor
        customSurfaceColor = appSettings.customSurfaceColor
        customElevatedColor = appSettings.customElevatedColor
        customTextPrimary = appSettings.customTextPrimary
        customTextSecondary = appSettings.customTextSecondary
        customDividerColor = appSettings.customDividerColor
        try { roomReadingPositions = JSON.parse(appSettings.roomReadingPositionsJson || "{}") }
        catch (error) { roomReadingPositions = ({}) }
        try {
            var storedPinnedRooms = JSON.parse(appSettings.pinnedRoomIdsJson || "[]")
            pinnedRoomIds = Array.isArray(storedPinnedRooms) ? storedPinnedRooms : []
        } catch (error) {
            pinnedRoomIds = []
        }
        try {
            var storedArchivedRooms = JSON.parse(appSettings.archivedRoomIdsJson || "[]")
            archivedRoomIds = Array.isArray(storedArchivedRooms) ? storedArchivedRooms : []
        } catch (error) {
            archivedRoomIds = []
        }
        try {
            var storedMutedRooms = JSON.parse(appSettings.mutedRoomIdsJson || "[]")
            mutedRoomIds = Array.isArray(storedMutedRooms) ? storedMutedRooms : []
        } catch (error) {
            mutedRoomIds = []
        }
        try {
            var storedLastRooms = JSON.parse(appSettings.lastRoomIdsByProfileJson || "{}")
            lastRoomIdsByProfile = storedLastRooms
                    && typeof storedLastRooms === "object"
                    && !Array.isArray(storedLastRooms)
                ? storedLastRooms : ({})
        } catch (lastRoomError) {
            lastRoomIdsByProfile = ({})
        }
        systemNotificationsEnabled = appSettings.systemNotificationsEnabled
        systemInvitationNotificationsEnabled = appSettings.systemInvitationNotificationsEnabled
        systemMentionNotificationsEnabled = appSettings.systemMentionNotificationsEnabled
        readReceiptsEnabled = appSettings.readReceiptsEnabled
        try {
            var storedReceiptOverrides = JSON.parse(appSettings.roomReadReceiptOverridesJson || "{}")
            roomReadReceiptOverrides = storedReceiptOverrides && typeof storedReceiptOverrides === "object"
                ? storedReceiptOverrides : ({})
        } catch (receiptError) {
            roomReadReceiptOverrides = ({})
        }
        typingNotificationsEnabled = appSettings.typingNotificationsEnabled
        try {
            var storedTypingOverrides = JSON.parse(
                appSettings.roomTypingNotificationOverridesJson || "{}")
            roomTypingNotificationOverrides = storedTypingOverrides
                    && typeof storedTypingOverrides === "object"
                    && !Array.isArray(storedTypingOverrides)
                ? storedTypingOverrides : ({})
        } catch (typingError) {
            roomTypingNotificationOverrides = ({})
        }
        archiveInSpaceRail = appSettings.archiveInSpaceRail
        roundAvatars = appSettings.roundAvatars
        showSpaceRoomsInHome = appSettings.showSpaceRoomsInHome
        showThreadsInSmallGroups = appSettings.showThreadsInSmallGroups
        messageDateFormat = appSettings.messageDateFormat
        messageTimeFormat = appSettings.messageTimeFormat
        uiScale = Math.max(0.8, Math.min(1.4, Number(appSettings.uiScale || 1)))
        animationsEnabled = appSettings.animationsEnabled
        var savedWobbleMode = String(appSettings.windowWobbleMode || "")
        if (["off", "spring", "linux"].indexOf(savedWobbleMode) < 0)
            savedWobbleMode = appSettings.windowWobbleEnabled ? "spring" : "off"
        windowWobbleMode = savedWobbleMode
        if (!appSettings.windowWobbleStrengthDefaultMigrated) {
            appSettings.windowWobbleStrength = 50
            appSettings.windowWobbleStrengthDefaultMigrated = true
        }
        windowSpringStrength = Math.max(0,
            Math.min(100, Number(appSettings.windowSpringStrength)))
        windowWobbleStrength = Math.max(0,
            Math.min(100, Number(appSettings.windowWobbleStrength)))
        startupIntroVariant = Math.max(0,
            Math.min(10, Number(appSettings.startupIntroVariant || 0)))
        storageAutoCleanupDays = Math.max(0, Number(appSettings.storageAutoCleanupDays || 0))
        storageCacheLimitMb = Math.max(64, Number(appSettings.storageCacheLimitMb || 1024))
        storageDownloadsDirectory = appSettings.storageDownloadsDirectory || ""
        storageAutoLoadImages = appSettings.storageAutoLoadImages
        storageAutoLoadVideos = appSettings.storageAutoLoadVideos
        L10n.UiPreferences.animationsEnabled = animationsEnabled
        L10n.UiPreferences.windowWobbleMode = windowWobbleMode
        L10n.UiPreferences.windowSpringStrength = windowSpringStrength
        L10n.UiPreferences.windowWobbleStrength = windowWobbleStrength
    }

    function setCustomColor(key, colorValue) {
        var value = String(colorValue || "")
        if (value === "") return
        if (key === "accent") {
            customAccentColor = value
            appSettings.customAccentColor = value
            if (appSettings.customIconColor === "")
                customIconColor = value
        } else if (key === "icons") {
            customIconColor = value
            appSettings.customIconColor = value
        } else if (key === "background") {
            customBackgroundColor = value
            appSettings.customBackgroundColor = value
        } else if (key === "surface") {
            customSurfaceColor = value
            appSettings.customSurfaceColor = value
        } else if (key === "elevated") {
            customElevatedColor = value
            appSettings.customElevatedColor = value
        } else if (key === "text_primary") {
            customTextPrimary = value
            appSettings.customTextPrimary = value
        } else if (key === "text_secondary") {
            customTextSecondary = value
            appSettings.customTextSecondary = value
        } else if (key === "divider") {
            customDividerColor = value
            appSettings.customDividerColor = value
        }
    }

    function roomIsPinned(roomId) {
        return pinnedRoomIds.indexOf(roomId) !== -1
    }

    function roomIsArchived(roomId) {
        return archivedRoomIds.indexOf(roomId) !== -1
    }

    function roomIsMuted(roomId) {
        return mutedRoomIds.indexOf(roomId) !== -1
    }

    function roomRecord(roomId) {
        return Native.FrontendLogic.invoke("window.roomRecord", appWindow, [roomId])
    }

    function roomNameForId(roomId) {
        return Native.FrontendLogic.invoke("window.roomNameForId", appWindow, [roomId])
    }

    function updateCurrentRoomMemberCount() {
        return Native.FrontendLogic.invoke("window.updateCurrentRoomMemberCount", appWindow, [])
    }

    function updateCurrentRoomEncryptionState() {
        return Native.FrontendLogic.invoke("window.updateCurrentRoomEncryptionState", appWindow, [])
    }

    function rememberLastOpenedRoom(roomId) {
        return Native.FrontendLogic.invoke("window.rememberLastOpenedRoom", appWindow, [roomId])
    }

    function forgetLastOpenedRoom(profileId) {
        return Native.FrontendLogic.invoke("window.forgetLastOpenedRoom", appWindow, [profileId])
    }

    function restoreLastOpenedRoom() {
        return Native.FrontendLogic.invoke("window.restoreLastOpenedRoom", appWindow, [])
    }

    function activateRoomFromNotification(roomId) {
        return Native.FrontendLogic.invoke("window.activateRoomFromNotification", appWindow, [roomId])
    }

    function systemNotificationTypeEnabled(notificationType) {
        return Native.FrontendLogic.invoke("window.systemNotificationTypeEnabled", appWindow, [notificationType])
    }

    function systemNotificationAllowed(roomId, notificationType) {
        return Native.FrontendLogic.invoke("window.systemNotificationAllowed", appWindow, [roomId, notificationType])
    }

    function systemNotificationsAvailable() {
        return Native.FrontendLogic.invoke("window.systemNotificationsAvailable", appWindow, [])
    }

    function showSystemNotification(title, message, roomId) {
        return Native.FrontendLogic.invoke("window.showSystemNotification", appWindow, [title, message, roomId])
    }

    function bringApplicationToFront() {
        return Native.FrontendLogic.invoke("window.bringApplicationToFront", appWindow, [])
    }

    function notificationBody(message) {
        return Native.FrontendLogic.invoke("window.notificationBody", appWindow, [message])
    }

    function messageMentionsCurrentUser(message) {
        return Native.FrontendLogic.invoke("window.messageMentionsCurrentUser", appWindow, [message])
    }

    function centerNotificationModel(notificationType) {
        return Native.FrontendLogic.invoke("window.centerNotificationModel", appWindow, [notificationType])
    }

    function centerNotificationModelForId(notificationId) {
        return Native.FrontendLogic.invoke("window.centerNotificationModelForId", appWindow, [notificationId])
    }

    function centerNotificationIndex(notificationId, model) {
        return Native.FrontendLogic.invoke("window.centerNotificationIndex", appWindow, [notificationId, model])
    }

    function recalculateNotificationUnreadCount() {
        return Native.FrontendLogic.invoke("window.recalculateNotificationUnreadCount", appWindow, [])
    }

    function addCenterNotification(notificationId, notificationType, title, body,
                                   roomId, roomName) {
        return Native.FrontendLogic.invoke("window.addCenterNotification", appWindow,
                                           [notificationId, notificationType, title,
                                            body, roomId, roomName])
    }

    function markNotificationModelRead(model) {
        return Native.FrontendLogic.invoke("window.markNotificationModelRead", appWindow, [model])
    }

    function markCenterNotificationsRead(notificationType) {
        return Native.FrontendLogic.invoke("window.markCenterNotificationsRead", appWindow, [notificationType])
    }

    function markCenterNotificationRead(notificationId) {
        return Native.FrontendLogic.invoke("window.markCenterNotificationRead", appWindow, [notificationId])
    }

    function dismissCenterNotification(notificationId) {
        return Native.FrontendLogic.invoke("window.dismissCenterNotification", appWindow, [notificationId])
    }

    function clearCenterNotifications(notificationType) {
        return Native.FrontendLogic.invoke("window.clearCenterNotifications", appWindow, [notificationType])
    }

    function activateCenterNotification(notificationId, notificationType, roomId, roomName) {
        return Native.FrontendLogic.invoke("window.activateCenterNotification", appWindow,
                                           [notificationId, notificationType,
                                            roomId, roomName])
    }
    function roomIsDirect(roomId) {
        var room = roomRecord(roomId)
        return !!room && !!room.is_dm && !room.is_invited
    }

    function openProfileSettings(profileId) {
        if (!profileId || matrixConnection.profileSwitchInFlight) return
        if (profileId === currentProfileId) {
            openSettingsDialog(0)
        } else {
            pendingSettingsProfileId = profileId
            matrixConnection.switchProfile(profileId)
        }
    }

    function openSettingsDialog(tab) {
        if (tab !== undefined) settingsDialogLoader.initialTab = tab
        if (settingsDialogLoader.item) {
            if (tab !== undefined) settingsDialogLoader.item.currentTab = tab
            settingsDialogLoader.item.open()
            return
        }
        settingsDialogLoader.active = true
    }

    function openChatPreview(roomId, roomName, initialMessages) {
        chatPreviewLoader.roomId = roomId
        chatPreviewLoader.roomName = roomName
        chatPreviewLoader.initialMessages = initialMessages || []
        if (chatPreviewLoader.item) {
            chatPreviewLoader.item.openForRoom(roomId, roomName,
                                               chatPreviewLoader.initialMessages)
            return
        }
        chatPreviewLoader.active = true
    }

    function openDirectorySearch(mode) {
        directorySearchLoader.mode = mode || "users"
        if (directorySearchLoader.item)
            directorySearchLoader.item.openFor(directorySearchLoader.mode)
        else
            directorySearchLoader.active = true
    }

    function openCreateRoom(asSpace) {
        createRoomLoader.asSpace = !!asSpace
        if (createRoomLoader.item) {
            if (createRoomLoader.asSpace)
                createRoomLoader.item.openForSpaceCreation()
            else
                createRoomLoader.item.openForCreation()
        } else {
            createRoomLoader.active = true
        }
    }

    function openUserPicker(selectedUsers) {
        userPickerLoader.selectedUsers = selectedUsers || []
        if (userPickerLoader.item)
            userPickerLoader.item.openWithSelection(userPickerLoader.selectedUsers)
        else
            userPickerLoader.active = true
    }

    function setRoomPinned(roomId, pinned) {
        return Native.FrontendLogic.invoke("window.setRoomPinned", appWindow, [roomId, pinned])
    }

    function setRoomMuted(roomId, muted) {
        return Native.FrontendLogic.invoke("window.setRoomMuted", appWindow, [roomId, muted])
    }

    function setRoomArchived(roomId, archived) {
        return Native.FrontendLogic.invoke("window.setRoomArchived", appWindow, [roomId, archived])
    }

    function setArchiveInSpaceRail(enabled) {
        return Native.FrontendLogic.invoke("window.setArchiveInSpaceRail", appWindow, [enabled])
    }

    function openSpace(spaceId, spaceName) {
        return Native.FrontendLogic.invoke("window.openSpace", appWindow, [spaceId, spaceName])
    }

    function clearMainState() {
        return Native.FrontendLogic.invoke("window.clearMainState", appWindow, [])
    }

    function setAccountIdentity(userId, displayName, avatarUrl, known) {
        return Native.FrontendLogic.invoke("window.setAccountIdentity", appWindow,
                                           [userId, displayName, avatarUrl, known])
    }

    function applyAccountIdentityDetails(details) {
        return Native.FrontendLogic.invoke("window.applyAccountIdentityDetails", appWindow, [details])
    }

    function refreshAccountIdentity(suffix) {
        return Native.FrontendLogic.invoke("window.refreshAccountIdentity", appWindow, [suffix])
    }

    function showNotification(text, isError) {
        if (!text || text === "") return
        notificationText = text
        notificationIsError = !!isError
        notificationTimer.restart()
    }

    function requestRoomMembersIfNeeded(roomId) {
        return Native.FrontendLogic.invoke("window.requestRoomMembersIfNeeded", appWindow, [roomId])
    }

    function trimRoomMembersCache(preferredRoomId) {
        return Native.FrontendLogic.invoke("window.trimRoomMembersCache", appWindow, [preferredRoomId])
    }

    function updateCurrentDeviceIdFromProfiles() {
        return Native.FrontendLogic.invoke("window.updateCurrentDeviceIdFromProfiles", appWindow, [])
    }

    function maybeFinishStartupIntro() {
        return Native.FrontendLogic.invoke("window.maybeFinishStartupIntro", appWindow, [])
    }

    function showMain(userId, server, avatarUrl, profileId, resetUi) {
        return Native.FrontendLogic.invoke("window.showMain", appWindow,
                                           [userId, server, avatarUrl, profileId, resetUi])
    }

    function beginAddAccount() {
        return Native.FrontendLogic.invoke("window.beginAddAccount", appWindow, [])
    }

    function leaveLoginScreen() {
        return Native.FrontendLogic.invoke("window.leaveLoginScreen", appWindow, [])
    }

    function logout() {
        return Native.FrontendLogic.invoke("window.logout", appWindow, [])
    }

    function typingNotificationsEnabledForRoom(roomId) {
        var preference = String(
            roomTypingNotificationOverrides[String(roomId || "")] || "inherit")
        if (preference === "on") return true
        if (preference === "off") return false
        return typingNotificationsEnabled
    }

    ListModel {
        id: roomsModel
        onCountChanged: appWindow.updateCurrentRoomEncryptionState()
    }
    ListModel {
        id: invitationNotificationsModel
        dynamicRoles: true
    }
    ListModel {
        id: mentionNotificationsModel
        dynamicRoles: true
    }


    Connections {
        target: appWindow.nativeSystemNotifier
        function onApplicationActivationRequested() {
            appWindow.bringApplicationToFront()
        }
        function onNotificationActivated(roomId) {
            appWindow.activateRoomFromNotification(roomId)
        }
    }

    BackendConnection {
        id: matrixConnection
        window: appWindow
        appSettingsObject: appSettings
        chatPreviewLoaderObject: chatPreviewLoader
        chatViewObject: chatView
        createRoomLoaderObject: createRoomLoader
        directorySearchLoaderObject: directorySearchLoader
        globalVerificationLoaderObject: globalVerificationLoader
        roomsModelObject: roomsModel
        settingsDialogLoaderObject: settingsDialogLoader
        sidebarObject: sidebar
        spaceLobbyObject: spaceLobby
        userPickerLoaderObject: userPickerLoader
    }
    Loader {
        id: chatPreviewLoader
        anchors.fill: parent
        active: false
        property string roomId: ""
        property string roomName: ""
        property var initialMessages: []
        onLoaded: item.openForRoom(roomId, roomName, initialMessages)
        sourceComponent: Component {
            ChatPreviewPopup {
        currentUserId: appWindow.currentUserId
        messageDateFormat: appWindow.messageDateFormat
        messageTimeFormat: appWindow.messageTimeFormat
        accentColor: appWindow.accentColor
        accentTextColor: appWindow.accentTextColor
        backgroundColor: appWindow.backgroundColor
        surfaceColor: appWindow.surfaceColor
        elevatedColor: appWindow.elevatedColor
        textPrimary: appWindow.textPrimary
        textSecondary: appWindow.textSecondary
        dividerColor: appWindow.dividerColor

        onPageRequested: function(roomId, from, requestId) {
            matrixConnection.requestRoomPreview(roomId, from, requestId)
        }
            }
        }
        Connections {
            target: chatPreviewLoader.item
            function onClosed() {
                Qt.callLater(function() { chatPreviewLoader.active = false })
            }
        }
    }

    Loader {
        id: directorySearchLoader
        anchors.fill: parent
        active: false
        property string mode: "users"
        onLoaded: item.openFor(mode)
        sourceComponent: Component {
            DirectorySearchDialog {
        currentUserId: appWindow.currentUserId
        mediaProxy: appWindow.mediaProxy
        roundAvatars: appWindow.roundAvatars
        requestIdFactory: function(suffix) {
            return matrixConnection.nextRequestId(suffix)
        }

        accentColor: appWindow.accentColor
        iconColor: appWindow.iconColor
        accentTextColor: appWindow.accentTextColor
        backgroundColor: appWindow.backgroundColor
        surfaceColor: appWindow.surfaceColor
        elevatedColor: appWindow.elevatedColor
        textPrimary: appWindow.textPrimary
        textSecondary: appWindow.textSecondary
        dividerColor: appWindow.dividerColor

        onCreateRoomRequested: Qt.callLater(function() {
            appWindow.openCreateRoom(false)
        })

        onSearchRequested: function(mode, query, requestId) {
            if (mode === "rooms" || mode === "spaces")
                matrixConnection.searchPublicRooms(query, requestId,
                                                   mode === "spaces")
            else
                matrixConnection.searchUsers(query, requestId)
        }

        onUserRequested: function(userId) {
            if (userId === "" || userId === appWindow.currentUserId)
                return
            appWindow.pendingDirectMessageRequestId =
                matrixConnection.openDirectMessage(userId)
        }

        onRoomRequested: function(roomId, roomName, joined, joinRule) {
            if (roomId === "")
                return
            if (joined) {
                appWindow.spaceLobbyOpen = false
                appWindow.currentRoomId = roomId
                appWindow.currentRoomName = roomName || roomId
                appWindow.currentRoomMembers =
                    appWindow.roomMembersCache[roomId] || []
                matrixConnection.requestMessages(roomId)
                appWindow.requestRoomMembersIfNeeded(roomId)
                return
            }

            appWindow.pendingDirectoryRoomId = roomId
            appWindow.pendingDirectoryRoomName = roomName || roomId
            appWindow.pendingDirectoryIsSpace = false
            matrixConnection.joinSpaceRoom({
                room_id: roomId,
                via: []
            }, String(joinRule || "").indexOf("knock") !== -1)
        }

        onSpaceRequested: function(roomId, roomName, joined, joinRule) {
            if (roomId === "")
                return
            if (joined) {
                appWindow.openSpace(roomId, roomName || roomId)
                return
            }

            appWindow.pendingDirectoryRoomId = roomId
            appWindow.pendingDirectoryRoomName = roomName || roomId
            appWindow.pendingDirectoryIsSpace = true
            matrixConnection.joinSpaceRoom({
                room_id: roomId,
                via: []
            }, String(joinRule || "").indexOf("knock") !== -1)
        }
            }
        }
        Connections {
            target: directorySearchLoader.item
            function onClosed() {
                Qt.callLater(function() { directorySearchLoader.active = false })
            }
        }
    }


    Loader {
        id: userPickerLoader
        anchors.fill: parent
        active: false
        property var selectedUsers: []
        onLoaded: item.openWithSelection(selectedUsers)
        sourceComponent: Component {
            UserPickerDialog {
        anchors.centerIn: parent

        currentUserId: appWindow.currentUserId
        mediaProxy: appWindow.mediaProxy
        roundAvatars: appWindow.roundAvatars
        requestIdFactory: function(suffix) {
            return matrixConnection.nextRequestId(suffix)
        }

        accentColor: appWindow.accentColor
        iconColor: appWindow.iconColor
        accentTextColor: appWindow.accentTextColor
        backgroundColor: appWindow.backgroundColor
        surfaceColor: appWindow.surfaceColor
        elevatedColor: appWindow.elevatedColor
        textPrimary: appWindow.textPrimary
        textSecondary: appWindow.textSecondary
        dividerColor: appWindow.dividerColor

        onSearchRequested: function(query, requestId) {
            matrixConnection.searchUsers(query, requestId)
        }
        onSelectionAccepted: function(users) {
            if (createRoomLoader.item)
                createRoomLoader.item.setSelectedInviteUsers(users)
        }
            }
        }
        Connections {
            target: userPickerLoader.item
            function onClosed() {
                Qt.callLater(function() { userPickerLoader.active = false })
            }
        }
    }

    Loader {
        id: createRoomLoader
        anchors.fill: parent
        active: false
        property bool asSpace: false
        onLoaded: {
            if (asSpace) item.openForSpaceCreation()
            else item.openForCreation()
        }
        sourceComponent: Component {
            CreateRoomDialog {
        accentColor: appWindow.accentColor
        iconColor: appWindow.iconColor
        accentTextColor: appWindow.accentTextColor
        backgroundColor: appWindow.backgroundColor
        surfaceColor: appWindow.surfaceColor
        elevatedColor: appWindow.elevatedColor
        textPrimary: appWindow.textPrimary
        textSecondary: appWindow.textSecondary
        dividerColor: appWindow.dividerColor
        currentUserId: appWindow.currentUserId

        onCreateRequested: function(options) {
            matrixConnection.createRoom(options)
        }
        onUserPickerRequested: function(selectedUsers) {
            appWindow.openUserPicker(selectedUsers)
        }
            }
        }
        Connections {
            target: createRoomLoader.item
            function onClosed() {
                Qt.callLater(function() { createRoomLoader.active = false })
            }
        }
    }

    readonly property var loginScreen: loginScreenLoader.item
        ? loginScreenLoader.item.screenObject : null
    readonly property var registerScreen: registerScreenLoader.item
        ? registerScreenLoader.item.screenObject : null

    Loader {
        id: loginScreenLoader
        anchors.fill: parent
        active: appWindow.currentPage === "login"
        sourceComponent: Component {
    Item {
        property alias screenObject: loginScreenContent
        anchors.fill: parent

    LoginScreen {
        id: loginScreenContent
        width: parent.width / appWindow.uiScale
        height: parent.height / appWindow.uiScale
        transformOrigin: Item.TopLeft
        scale: appWindow.uiScale
        visible: appWindow.currentPage === "login"

        accentColor: appWindow.accentColor
        accentTextColor: appWindow.accentTextColor
        backgroundColor: appWindow.backgroundColor
        surfaceColor: appWindow.surfaceColor
        textPrimary: appWindow.textPrimary
        textSecondary: appWindow.textSecondary
        connectionStatus: appWindow.connectionStatus
        connectionStatusColor: appWindow.connectionStatusColor
        showBackButton: appWindow.addingAccountMode
        backendConnected: matrixConnection.connected

        onLoginRequested: function(server, nickname, password) {
            matrixConnection.sendCommand({
                type: "login",
                request_id: matrixConnection.nextRequestId("login"),
                server: server,
                nickname: nickname,
                password: password
            })
        }

        onRegisterRequested: appWindow.currentPage = "register"
        onBackRequested: appWindow.leaveLoginScreen()
    }
    }
        }
    }

    Loader {
        id: registerScreenLoader
        anchors.fill: parent
        active: appWindow.currentPage === "register"
        sourceComponent: Component {
    Item {
        property alias screenObject: registerScreenContent
        anchors.fill: parent

    RegisterScreen {
        id: registerScreenContent
        width: parent.width / appWindow.uiScale
        height: parent.height / appWindow.uiScale
        transformOrigin: Item.TopLeft
        scale: appWindow.uiScale
        visible: appWindow.currentPage === "register"

        accentColor: appWindow.accentColor
        accentTextColor: appWindow.accentTextColor
        backgroundColor: appWindow.backgroundColor
        surfaceColor: appWindow.surfaceColor
        textPrimary: appWindow.textPrimary
        textSecondary: appWindow.textSecondary
        backendConnected: matrixConnection.connected

        onRegistrationRequested: function(server, username, password) {
            matrixConnection.sendCommand({
                type: "register",
                request_id: matrixConnection.nextRequestId("register"),
                server: server,
                username: username,
                password: password
            })
        }

        onCopyRequested: function(text) { appWindow.copyText(text) }
        onLoginRequested: appWindow.currentPage = "login"
    }
    }
        }
    }

    Native.VoiceWebProfile { id: voiceWebProfile }
    VoiceSession {
        id: voiceSession
        connection: matrixConnection
        webProfile: voiceWebProfile
    }
    IncomingCallBanner {
        session: voiceSession
        z: 10001
        anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 16
        mediaProxy: appWindow.mediaProxy; roundAvatars: appWindow.roundAvatars
        surfaceColor: appWindow.surfaceColor; elevatedColor: appWindow.elevatedColor
        textPrimary: appWindow.textPrimary; textSecondary: appWindow.textSecondary
        accentColor: appWindow.accentColor
    }
    VoicePanel {
        session: voiceSession
        z: 10000
        width: voiceSession.panelFullscreen ? appWindow.width
            : Math.min(460, appWindow.width - 32)
        height: voiceSession.panelFullscreen ? appWindow.height
            : Math.min(520, appWindow.height - 32)
        surfaceColor: appWindow.surfaceColor
        elevatedColor: appWindow.elevatedColor
        dividerColor: appWindow.dividerColor
        textPrimary: appWindow.textPrimary
        textSecondary: appWindow.textSecondary
        accentColor: appWindow.accentColor
    }

    readonly property var mainScreen: mainUiLoader.item
        ? mainUiLoader.item.screenObject : null
    readonly property var spaceRail: mainScreen ? mainScreen.spaceRailObject : null
    readonly property var sidebar: mainScreen ? mainScreen.sidebarObject : null
    readonly property var chatView: mainScreen ? mainScreen.chatViewObject : null
    readonly property var spaceLobby: mainScreen ? mainScreen.spaceLobbyObject : null

    Loader {
        id: mainUiLoader
        anchors.fill: parent
        active: appWindow.currentPage === "main"
        sourceComponent: Component {
    Item {
        property alias screenObject: mainScreenContent
        anchors.fill: parent

    MainScreen {
        id: mainScreenContent
        window: appWindow
        appSettingsObject: appSettings
        invitationNotificationsModelObject: invitationNotificationsModel
        matrixConnectionObject: matrixConnection
        mentionNotificationsModelObject: mentionNotificationsModel
        roomsModelObject: roomsModel
    }
        }
    }
    }

    SettingsLoader {
        id: settingsDialogLoader
        window: appWindow
        appSettingsObject: appSettings
        matrixConnectionObject: matrixConnection
    }

    function openLogoutConfirm() {
        if (logoutConfirmLoader.item) {
            logoutConfirmLoader.item.open()
            return
        }
        logoutConfirmLoader.active = true
    }

    Loader {
        id: logoutConfirmLoader
        anchors.fill: parent
        active: false
        onLoaded: item.open()
        sourceComponent: Component {
            LogoutConfirmDialog {
                anchors.centerIn: parent
                backgroundColor: appWindow.backgroundColor
                textPrimary: appWindow.textPrimary
                textSecondary: appWindow.textSecondary
                onConfirmed: appWindow.logout()
                onClosed: Qt.callLater(function() {
                    if (!logoutConfirmLoader.item || !logoutConfirmLoader.item.opened)
                        logoutConfirmLoader.active = false
                })
            }
        }
    }

    function openGlobalVerification(update) {
        globalVerificationLoader.pendingUpdate = update
        if (globalVerificationLoader.item) {
            globalVerificationLoader.item.update = update
            globalVerificationLoader.item.open()
            return
        }
        globalVerificationLoader.active = true
    }

    Loader {
        id: globalVerificationLoader
        anchors.fill: parent
        active: false
        property var pendingUpdate: null
        property var dismissedFlowIds: ({})
        function dismissFlow(flowId) {
            if (!flowId) return
            var next = Object.assign({}, dismissedFlowIds)
            next[flowId] = true
            dismissedFlowIds = next
        }
        function shouldIgnore(update) {
            var flowId = update ? update.flow_id || "" : ""
            if (!flowId || !dismissedFlowIds[flowId]) return false
            if (update.state === "done" || update.state === "cancelled"
                    || update.state === "error") {
                var next = Object.assign({}, dismissedFlowIds)
                delete next[flowId]
                dismissedFlowIds = next
            }
            return true
        }
        onLoaded: {
            item.update = pendingUpdate
            item.open()
        }
        sourceComponent: Component {
            VerificationDialog {
                accentColor: appWindow.accentColor
                surfaceColor: appWindow.surfaceColor
                elevatedColor: appWindow.elevatedColor
                textPrimary: appWindow.textPrimary
                textSecondary: appWindow.textSecondary
                onActionRequested: function(flowId, action) {
                    matrixConnection.sendCommand({
                        type: "verification_action",
                        request_id: matrixConnection.nextRequestId("global-verification"),
                        flow_id: flowId,
                        action: action
                    })
                }
                onDismissalRequested: function(flowId) {
                    globalVerificationLoader.dismissFlow(flowId)
                }
                onClosed: Qt.callLater(function() {
                    if (globalVerificationLoader.item
                            && globalVerificationLoader.item.opened)
                        return
                    globalVerificationLoader.pendingUpdate = null
                    globalVerificationLoader.active = false
                })
            }
        }
    }

    function openMessageSource(jsonText) {
        sourceDialogLoader.messageText = jsonText
        if (sourceDialogLoader.item) {
            sourceDialogLoader.item.messageText = jsonText
            sourceDialogLoader.item.open()
            return
        }
        sourceDialogLoader.active = true
    }

    Loader {
        id: sourceDialogLoader
        anchors.fill: parent
        active: false
        property string messageText: ""
        onLoaded: {
            item.messageText = messageText
            item.open()
        }
        sourceComponent: Component {
            MessageSourceDialog {
                anchors.centerIn: parent
                backgroundColor: appWindow.backgroundColor
                surfaceColor: appWindow.surfaceColor
                textPrimary: appWindow.textPrimary
                onClosed: Qt.callLater(function() {
                    if (!sourceDialogLoader.item || !sourceDialogLoader.item.opened)
                        sourceDialogLoader.active = false
                })
            }
        }
    }

    Rectangle {
        id: notificationBanner
        z: 30000
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 16
        width: Math.min(Math.max(220, implicitWidth), parent.width - 32)
        implicitWidth: notificationLabel.implicitWidth + 28
        height: notificationLabel.implicitHeight + 20
        radius: 10
        color: appWindow.notificationIsError ? "#b83232" : appWindow.elevatedColor
        border.color: appWindow.notificationIsError
            ? Qt.rgba(1, 1, 1, 0.20)
            : appWindow.dividerColor
        visible: opacity > 0.01
        opacity: notificationTimer.running ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: L10n.UiPreferences.duration(140) }
        }

        Text {
            id: notificationLabel
            anchors.fill: parent
            anchors.margins: 10
            text: appWindow.notificationText
            color: "white"
            font.pointSize: 9
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }

        MouseArea {
            anchors.fill: parent
            onClicked: notificationTimer.stop()
        }
    }

    Timer {
        id: notificationTimer
        interval: 4200
    }

    function openAvatarDialog() {
        if (avatarDialogLoader.item) {
            avatarDialogLoader.item.open()
            return
        }
        avatarDialogLoader.active = true
    }

    Loader {
        id: avatarDialogLoader
        active: false
        onLoaded: item.open()
        sourceComponent: Component {
            AvatarFileDialog {
                onAvatarSelected: function(path, mimeType) {
            matrixConnection.sendCommand({
                type: "set_avatar",
                request_id: matrixConnection.nextRequestId("avatar"),
                path: path,
                            mime_type: mimeType
            })
        }
                onFinished: Qt.callLater(function() { avatarDialogLoader.active = false })
            }
        }
    }

    Loader {
        id: startupIntroLoader
        anchors.fill: parent
        z: 100000
        active: true

        sourceComponent: Component {
            StartupIntro {
                accentColor: appWindow.accentColor
                iconColor: appWindow.iconColor
                backgroundColor: appWindow.backgroundColor
                surfaceColor: appWindow.surfaceColor
                textPrimary: appWindow.textPrimary
                textSecondary: appWindow.textSecondary
                animationsEnabled: appWindow.animationsEnabled
                introVariant: appWindow.startupIntroVariant
                onFinished: {
                    appWindow.startupIntroMinimumFinished = true
                    appWindow.maybeFinishStartupIntro()
                }
            }
        }
    }
}
