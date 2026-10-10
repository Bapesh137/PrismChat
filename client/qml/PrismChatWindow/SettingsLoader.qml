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

Loader {
    required property var window
    readonly property var ownerWindow: window
    required property var appSettingsObject
    required property var matrixConnectionObject
    id: settingsDialogLoader
    property int initialTab: 0
    anchors.fill: parent
    active: false
    onLoaded: {
        item.currentTab = initialTab
        item.open()
    }

    sourceComponent: Component {
        SettingsDialog {
    currentUserId: ownerWindow.currentUserId
    currentUserAvatar: ownerWindow.currentUserAvatar
    currentDisplayName: ownerWindow.currentDisplayName
    sessionServer: ownerWindow.sessionServer
    currentProfileId: ownerWindow.currentProfileId
    currentDeviceId: ownerWindow.currentDeviceId
    mediaProxy: ownerWindow.mediaProxy
    themeMode: ownerWindow.themeMode
    darkThemeId: ownerWindow.darkThemeId
    lightThemeId: ownerWindow.lightThemeId
    automaticLightStartMinutes: ownerWindow.automaticLightStartMinutes
    automaticDarkStartMinutes: ownerWindow.automaticDarkStartMinutes
    roundAvatars: ownerWindow.roundAvatars
    showSpaceRoomsInHome: ownerWindow.showSpaceRoomsInHome
    showThreadsInSmallGroups: ownerWindow.showThreadsInSmallGroups
    messageDateFormat: ownerWindow.messageDateFormat
    messageTimeFormat: ownerWindow.messageTimeFormat
    languageCode: ownerWindow.languageCode
    uiScale: ownerWindow.uiScale
    animationsEnabled: ownerWindow.animationsEnabled
    windowWobbleMode: ownerWindow.windowWobbleMode
    windowSpringStrength: ownerWindow.windowSpringStrength
    windowWobbleStrength: ownerWindow.windowWobbleStrength
    startupIntroVariant: ownerWindow.startupIntroVariant
    avatarStatusText: ownerWindow.avatarStatusText
    avatarStatusColor: ownerWindow.avatarStatusColor
    displayNameStatusText: ownerWindow.displayNameStatusText
    displayNameStatusColor: ownerWindow.displayNameStatusColor
    displayNameBusy: ownerWindow.displayNameBusy
    keyTransferBusy: ownerWindow.keyTransferBusy
    keyTransferStatus: ownerWindow.keyTransferStatus
    keyTransferError: ownerWindow.keyTransferError
    systemNotificationsEnabled: ownerWindow.systemNotificationsEnabled
    systemInvitationNotificationsEnabled: ownerWindow.systemInvitationNotificationsEnabled
    systemMentionNotificationsEnabled: ownerWindow.systemMentionNotificationsEnabled
    readReceiptsEnabled: ownerWindow.readReceiptsEnabled
    typingNotificationsEnabled: ownerWindow.typingNotificationsEnabled
    storageSqliteBytes: ownerWindow.storageSqliteBytes
    storageEventCacheBytes: ownerWindow.storageEventCacheBytes
    storageMediaBytes: ownerWindow.storageMediaBytes
    storageTotalCacheBytes: ownerWindow.storageTotalCacheBytes
    storageAutoCleanupDays: ownerWindow.storageAutoCleanupDays
    storageCacheLimitMb: ownerWindow.storageCacheLimitMb
    storageDownloadsDirectory: ownerWindow.storageDownloadsDirectory
    storageAutoLoadImages: ownerWindow.storageAutoLoadImages
    storageAutoLoadVideos: ownerWindow.storageAutoLoadVideos
    storageBusy: ownerWindow.storageBusy
    storageStatus: ownerWindow.storageStatus
    storageStatusError: ownerWindow.storageStatusError
    accentColor: ownerWindow.accentColor
    iconColor: ownerWindow.iconColor
    backgroundColor: ownerWindow.backgroundColor
    surfaceColor: ownerWindow.surfaceColor
    elevatedColor: ownerWindow.elevatedColor
    textPrimary: ownerWindow.textPrimary
    textSecondary: ownerWindow.textSecondary
    dividerColor: ownerWindow.dividerColor
    customAccentColor: ownerWindow.customAccentColor
    customIconColor: ownerWindow.customIconColor
    customBackgroundColor: ownerWindow.customBackgroundColor
    customSurfaceColor: ownerWindow.customSurfaceColor
    customElevatedColor: ownerWindow.customElevatedColor
    customTextPrimary: ownerWindow.customTextPrimary
    customTextSecondary: ownerWindow.customTextSecondary
    customDividerColor: ownerWindow.customDividerColor

    onAvatarChangeRequested: ownerWindow.openAvatarDialog()
    onProfileRefreshRequested: {
        ownerWindow.refreshAccountIdentity("settings-profile")
    }
    onDisplayNameChangeRequested: function(displayName, clearDisplayName) {
        ownerWindow.displayNameStatusText = ""
        ownerWindow.displayNameBusy = true
        ownerWindow.pendingDisplayNameRequestId =
            matrixConnectionObject.nextRequestId("display-name")
        if (!matrixConnectionObject.sendCommand({
            type: "update_own_profile",
            request_id: ownerWindow.pendingDisplayNameRequestId,
            display_name: clearDisplayName ? undefined : displayName,
            clear_display_name: clearDisplayName
        })) {
            ownerWindow.pendingDisplayNameRequestId = ""
            ownerWindow.displayNameBusy = false
        }
    }
    onLogoutRequested: ownerWindow.openLogoutConfirm()
    onExportKeysRequested: function(path, passphrase) {
        ownerWindow.keyTransferStatus = ""
        ownerWindow.keyTransferError = false
        ownerWindow.keyTransferBusy = true
        ownerWindow.pendingKeyTransferRequestId =
            matrixConnectionObject.nextRequestId("export-room-keys")
        if (!matrixConnectionObject.sendCommand({
            type: "export_room_keys",
            request_id: ownerWindow.pendingKeyTransferRequestId,
            path: path,
            passphrase: passphrase
        })) {
            ownerWindow.pendingKeyTransferRequestId = ""
            ownerWindow.keyTransferBusy = false
            ownerWindow.keyTransferError = true
            ownerWindow.keyTransferStatus =
                L10n.I18n.tr("Не удалось отправить команду экспорта ключей")
        }
    }
    onImportKeysRequested: function(path, passphrase) {
        ownerWindow.keyTransferStatus = ""
        ownerWindow.keyTransferError = false
        ownerWindow.keyTransferBusy = true
        ownerWindow.pendingKeyTransferRequestId =
            matrixConnectionObject.nextRequestId("import-room-keys")
        if (!matrixConnectionObject.sendCommand({
            type: "import_room_keys",
            request_id: ownerWindow.pendingKeyTransferRequestId,
            path: path,
            passphrase: passphrase
        })) {
            ownerWindow.pendingKeyTransferRequestId = ""
            ownerWindow.keyTransferBusy = false
            ownerWindow.keyTransferError = true
            ownerWindow.keyTransferStatus =
                L10n.I18n.tr("Не удалось отправить команду импорта ключей")
        }
    }
    onEncryptionRefreshRequested: {
        matrixConnectionObject.sendCommand({ type: "get_encryption_overview", request_id: matrixConnectionObject.nextRequestId("encryption-overview") })
        matrixConnectionObject.sendCommand({ type: "get_matrix_devices", request_id: matrixConnectionObject.nextRequestId("matrix-devices") })
    }
    onE2eeCommandRequested: function(command) {
        if (!command.request_id)
            command.request_id = matrixConnectionObject.nextRequestId("e2ee")
        matrixConnectionObject.sendCommand(command)
    }

    onSystemNotificationPreferencesChanged: function(enabled, invitationsEnabled,
                                                     mentionsEnabled) {
        ownerWindow.systemNotificationsEnabled = !!enabled
        ownerWindow.systemInvitationNotificationsEnabled = !!invitationsEnabled
        ownerWindow.systemMentionNotificationsEnabled = !!mentionsEnabled
        appSettingsObject.systemNotificationsEnabled = ownerWindow.systemNotificationsEnabled
        appSettingsObject.systemInvitationNotificationsEnabled =
            ownerWindow.systemInvitationNotificationsEnabled
        appSettingsObject.systemMentionNotificationsEnabled =
            ownerWindow.systemMentionNotificationsEnabled
        appSettingsObject.sync()
    }

    onPrivacyPreferencesChanged: function(sendReadReceipts, sendTypingNotifications) {
        ownerWindow.readReceiptsEnabled = !!sendReadReceipts
        ownerWindow.typingNotificationsEnabled = !!sendTypingNotifications
        appSettingsObject.readReceiptsEnabled = ownerWindow.readReceiptsEnabled
        appSettingsObject.typingNotificationsEnabled = ownerWindow.typingNotificationsEnabled
        appSettingsObject.sync()
    }

    onStorageRefreshRequested: {
        ownerWindow.storageBusy = true
        ownerWindow.storageStatus = L10n.I18n.tr("Подсчёт размера хранилища…")
        ownerWindow.storageStatusError = false
        matrixConnectionObject.sendCommand({
            type: "get_storage_stats",
            request_id: matrixConnectionObject.nextRequestId("storage-stats")
        })
    }

    onStorageClearCacheRequested: function(clearMedia, clearEventCache, clearSqlite) {
        ownerWindow.storageBusy = true
        ownerWindow.storageStatus = L10n.I18n.tr("Очистка кэша…")
        ownerWindow.storageStatusError = false
        matrixConnectionObject.sendCommand({
            type: "clear_cache",
            request_id: matrixConnectionObject.nextRequestId("clear-cache"),
            clear_media: !!clearMedia,
            clear_event_cache: !!clearEventCache,
            clear_sqlite: !!clearSqlite
        })
    }

    onStoragePreferencesChanged: function(autoCleanupDays, cacheLimitMb,
                                          downloadsDirectory,
                                          autoLoadImages, autoLoadVideos) {
        ownerWindow.storageAutoCleanupDays = Math.max(0, Number(autoCleanupDays || 0))
        ownerWindow.storageCacheLimitMb = Math.max(64, Number(cacheLimitMb || 1024))
        ownerWindow.storageDownloadsDirectory = downloadsDirectory || ""
        ownerWindow.storageAutoLoadImages = !!autoLoadImages
        ownerWindow.storageAutoLoadVideos = !!autoLoadVideos
        appSettingsObject.storageAutoCleanupDays = ownerWindow.storageAutoCleanupDays
        appSettingsObject.storageCacheLimitMb = ownerWindow.storageCacheLimitMb
        appSettingsObject.storageDownloadsDirectory = ownerWindow.storageDownloadsDirectory
        appSettingsObject.storageAutoLoadImages = ownerWindow.storageAutoLoadImages
        appSettingsObject.storageAutoLoadVideos = ownerWindow.storageAutoLoadVideos
        matrixConnectionObject.sendCommand({
            type: "set_storage_preferences",
            request_id: matrixConnectionObject.nextRequestId("storage-preferences"),
            auto_cleanup_days: ownerWindow.storageAutoCleanupDays,
            cache_limit_mb: ownerWindow.storageCacheLimitMb,
            downloads_dir: ownerWindow.storageDownloadsDirectory,
            auto_load_images: ownerWindow.storageAutoLoadImages,
            auto_load_videos: ownerWindow.storageAutoLoadVideos
        })
    }

    onStorageClearTemporaryDataRequested: {
        ownerWindow.draftClearGeneration++
        ownerWindow.storageBusy = true
        ownerWindow.storageStatus = L10n.I18n.tr("Очистка временных данных…")
        ownerWindow.storageStatusError = false
        matrixConnectionObject.sendCommand({
            type: "clear_temporary_data",
            request_id: matrixConnectionObject.nextRequestId("clear-temporary")
        })
    }

    onStorageExportDiagnosticsRequested: function(path) {
        ownerWindow.storageBusy = true
        ownerWindow.storageStatus = L10n.I18n.tr("Формирование диагностического отчёта…")
        ownerWindow.storageStatusError = false
        matrixConnectionObject.sendCommand({
            type: "export_diagnostics",
            request_id: matrixConnectionObject.nextRequestId("diagnostics"),
            path: path
        })
    }

    onThemeModeSelected: function(mode) {
        ownerWindow.themeMode = mode
        appSettingsObject.themeMode = mode
        appSettingsObject.sync()
    }

    onThemeVariantSelected: function(mode, themeId) {
        if (mode === "light") {
            ownerWindow.lightThemeId = themeId
            appSettingsObject.lightThemeId = themeId
        } else {
            ownerWindow.darkThemeId = themeId
            appSettingsObject.darkThemeId = themeId
        }
        appSettingsObject.sync()
    }

    onAutomaticScheduleSelected: function(lightStartMinutes, darkStartMinutes) {
        var lightStart = Math.max(0, Math.min(1439, Number(lightStartMinutes)))
        var darkStart = Math.max(0, Math.min(1439, Number(darkStartMinutes)))
        if (lightStart === darkStart) {
            ownerWindow.showNotification(
                L10n.I18n.tr("Время включения светлой и тёмной темы не должно совпадать"), true)
            return
        }
        ownerWindow.automaticLightStartMinutes = lightStart
        ownerWindow.automaticDarkStartMinutes = darkStart
        appSettingsObject.automaticLightStartMinutes = lightStart
        appSettingsObject.automaticDarkStartMinutes = darkStart
        appSettingsObject.sync()
        var now = new Date()
        ownerWindow.automaticThemeMinutes = now.getHours() * 60 + now.getMinutes()
    }

    onCustomColorSelected: function(key, colorValue) {
        ownerWindow.setCustomColor(key, colorValue)
    }

    onRoundAvatarsSelected: function(enabled) {
        ownerWindow.roundAvatars = enabled
        appSettingsObject.roundAvatars = enabled
    }

    onSpaceRoomsInHomeSelected: function(enabled) {
        ownerWindow.showSpaceRoomsInHome = !!enabled
        appSettingsObject.showSpaceRoomsInHome = ownerWindow.showSpaceRoomsInHome
        appSettingsObject.sync()
    }

    onThreadsInSmallGroupsSelected: function(enabled) {
        ownerWindow.showThreadsInSmallGroups = !!enabled
        appSettingsObject.showThreadsInSmallGroups =
            ownerWindow.showThreadsInSmallGroups
        appSettingsObject.sync()
    }

    onDateFormatSelected: function(format) {
        ownerWindow.messageDateFormat = format
        appSettingsObject.messageDateFormat = format
    }

    onTimeFormatSelected: function(format) {
        ownerWindow.messageTimeFormat = format
        appSettingsObject.messageTimeFormat = format
    }

    onLanguageSelected: function(code) {
        var selectedLanguage = L10n.I18n.setLanguage(code)
        appSettingsObject.languageCode = selectedLanguage
        if (ownerWindow.currentRoomId === "")
            ownerWindow.currentRoomName = L10n.I18n.tr("Выберите чат")
        if (ownerWindow.selectedSpaceId === "")
            ownerWindow.selectedSpaceName = L10n.I18n.tr("Чаты")
    }

    onUiScaleSelected: function(scale) {
        ownerWindow.uiScale = Math.max(0.8, Math.min(1.4, Number(scale || 1)))
        appSettingsObject.uiScale = ownerWindow.uiScale
    }

    onAnimationsSelected: function(enabled) {
        ownerWindow.animationsEnabled = enabled
        appSettingsObject.animationsEnabled = enabled
        L10n.UiPreferences.animationsEnabled = enabled
    }
    onWindowWobbleModeSelected: function(mode) {
        ownerWindow.windowWobbleMode = mode
        appSettingsObject.windowWobbleMode = mode
        L10n.UiPreferences.windowWobbleMode = mode
        appSettingsObject.sync()
    }
    onWindowSpringStrengthSelected: function(strength) {
        ownerWindow.windowSpringStrength = Math.max(0, Math.min(100,
            Math.round(Number(strength))))
        appSettingsObject.windowSpringStrength = ownerWindow.windowSpringStrength
        L10n.UiPreferences.windowSpringStrength = ownerWindow.windowSpringStrength
        appSettingsObject.sync()
    }
    onWindowWobbleStrengthSelected: function(strength) {
        ownerWindow.windowWobbleStrength = Math.max(0, Math.min(100,
            Math.round(Number(strength))))
        appSettingsObject.windowWobbleStrength = ownerWindow.windowWobbleStrength
        L10n.UiPreferences.windowWobbleStrength = ownerWindow.windowWobbleStrength
        appSettingsObject.sync()
    }
    onStartupIntroVariantSelected: function(variant) {
        ownerWindow.startupIntroVariant = Math.max(0, Math.min(10, variant))
        appSettingsObject.startupIntroVariant = ownerWindow.startupIntroVariant
        appSettingsObject.sync()
    }
    onClosed: Qt.callLater(function() {
        if (!settingsDialogLoader.item || !settingsDialogLoader.item.opened)
            settingsDialogLoader.active = false
    })
        }
    }
}
