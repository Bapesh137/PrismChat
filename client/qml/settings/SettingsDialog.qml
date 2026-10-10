import QtQuick
import "../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "../components/common"
import "pages"

Dialog {
    id: root

    property int currentTab: 0
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    property string currentUserId: ""
    property string currentUserAvatar: ""
    property string currentDisplayName: ""
    property string sessionServer: ""
    property string currentProfileId: ""
    property string currentDeviceId: ""
    property string mediaProxy: ""
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
    property string languageCode: "en"
    property real uiScale: 1.0
    property bool animationsEnabled: true
    property string windowWobbleMode: "off"
    property int windowSpringStrength: 100
    property int windowWobbleStrength: 50
    property int startupIntroVariant: 0
    property string avatarStatusText: ""
    property color avatarStatusColor: accentColor
    property string displayNameStatusText: ""
    property color displayNameStatusColor: accentColor
    property bool displayNameBusy: false
    property bool keyTransferBusy: false
    property string keyTransferStatus: ""
    property bool keyTransferError: false
    property var encryptionOverview: null
    property var matrixDevices: []
    property bool matrixDevicesLoading: true
    property bool systemNotificationsEnabled: true
    property bool systemInvitationNotificationsEnabled: true
    property bool systemMentionNotificationsEnabled: true
    property bool readReceiptsEnabled: true
    property bool typingNotificationsEnabled: true
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
    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color backgroundColor: "#07100A"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"
    property color customAccentColor: "#20D500"
    property color customIconColor: customAccentColor
    property color customBackgroundColor: "#07100A"
    property color customSurfaceColor: "#0B1710"
    property color customElevatedColor: "#102016"
    property color customTextPrimary: "#F2FFF4"
    property color customTextSecondary: "#A7B8AA"
    property color customDividerColor: "#29402E"

    signal avatarChangeRequested()
    signal displayNameChangeRequested(string displayName, bool clearDisplayName)
    signal profileRefreshRequested()
    signal logoutRequested()
    signal themeModeSelected(string mode)
    signal themeVariantSelected(string mode, string themeId)
    signal automaticScheduleSelected(int lightStartMinutes, int darkStartMinutes)
    signal roundAvatarsSelected(bool enabled)
    signal spaceRoomsInHomeSelected(bool enabled)
    signal threadsInSmallGroupsSelected(bool enabled)
    signal dateFormatSelected(string format)
    signal timeFormatSelected(string format)
    signal languageSelected(string code)
    signal uiScaleSelected(real scale)
    signal animationsSelected(bool enabled)
    signal windowWobbleModeSelected(string mode)
    signal windowSpringStrengthSelected(int strength)
    signal windowWobbleStrengthSelected(int strength)
    signal startupIntroVariantSelected(int variant)
    signal customColorSelected(string key, string colorValue)
    signal exportKeysRequested(string path, string passphrase)
    signal importKeysRequested(string path, string passphrase)
    signal encryptionRefreshRequested()
    signal e2eeCommandRequested(var command)
    signal systemNotificationPreferencesChanged(bool enabled,
                                                bool invitationsEnabled,
                                                bool mentionsEnabled)
    signal privacyPreferencesChanged(bool sendReadReceipts,
                                     bool sendTypingNotifications)
    signal storageRefreshRequested()
    signal storageClearCacheRequested(bool clearMedia, bool clearEventCache, bool clearSqlite)
    signal storagePreferencesChanged(int autoCleanupDays, int cacheLimitMb,
                                     string downloadsDirectory,
                                     bool autoLoadImages, bool autoLoadVideos)
    signal storageClearTemporaryDataRequested()
    signal storageExportDiagnosticsRequested(string path)

    function receiveEncryptionOverview(overview, errorText) {
        root.encryptionOverview = overview
        if (errorText !== "" && devicesSettingsPage)
            devicesSettingsPage.errorText = errorText
    }

    function receiveMatrixDevices(devices, errorText) {
        root.matrixDevices = devices || []
        root.matrixDevicesLoading = false
        if (devicesSettingsPage)
            devicesSettingsPage.receiveDevices(root.matrixDevices, errorText)
    }

    function receiveE2eeAction(requestId, success, uiaaSession, authType, approvalUrl, recoveryKey, flowId, errorText) {
        if (devicesSettingsPage)
            devicesSettingsPage.receiveLegacyAction(requestId, success, errorText)
        if (encryptionSettingsPage)
            encryptionSettingsPage.handleRecoveryAction(requestId, success, uiaaSession,
                                                        authType, approvalUrl,
                                                        recoveryKey, errorText)
    }

    function receiveDeviceOperation(operation, success, deviceIds, errorText) {
        if (devicesSettingsPage)
            devicesSettingsPage.receiveOperation(operation, success, deviceIds, errorText)
    }

    function receiveDeviceDeleteUiaa(operationId, flows, passwordSupported) {
        if (devicesSettingsPage)
            devicesSettingsPage.receiveDeleteUiaa(operationId, flows, passwordSupported)
    }

    function receiveDeviceDeleteWeb(deviceIds, url) {
        if (devicesSettingsPage)
            devicesSettingsPage.receiveDeleteWeb(deviceIds, url)
    }

    function blendedButtonColor(base, overlay, amount) {
        var alpha = Math.max(0, Math.min(1, amount))
        return Qt.rgba(base.r * (1 - alpha) + overlay.r * alpha,
                       base.g * (1 - alpha) + overlay.g * alpha,
                       base.b * (1 - alpha) + overlay.b * alpha, 1)
    }

    width: 680
    height: 520
    x: parent ? Math.round((parent.width - width) / 2 + dragOffsetX) : 0
    y: parent ? Math.round((parent.height - height) / 2 + dragOffsetY) : 0
    modal: true
    onOpened: {
        root.dragOffsetX = 0
        root.dragOffsetY = 0
        settingsNavigation.resetMoveMotion()
        root.profileRefreshRequested()
        if (root.currentTab === 3 || root.currentTab === 4) {
            root.matrixDevicesLoading = root.matrixDevices.length === 0
            root.encryptionRefreshRequested()
        }
        Qt.callLater(function() { appearanceSettingsPage.syncThemeModeCombo() })
        if (root.currentTab === 6)
            root.storageRefreshRequested()
    }
    onCurrentTabChanged: {
        if (root.visible && (root.currentTab === 3 || root.currentTab === 4))
            root.encryptionRefreshRequested()
        if (root.visible && root.currentTab === 6)
            root.storageRefreshRequested()
    }
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: L10n.UiPreferences.duration(55) }
            NumberAnimation { property: "scale"; from: 0.985; to: 1; duration: L10n.UiPreferences.duration(65); easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: L10n.UiPreferences.duration(45) }
    }

    background: Rectangle {
        color: root.backgroundColor
        radius: 14
        border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.12)
        border.width: 1
        transform: Matrix4x4 {
            matrix: PlanarTransform.fromShear(
                        Math.tan(settingsNavigation.moveShearAngle * Math.PI / 180),
                        0, width / 2, 0)
        }
    }

    contentItem: Row {
        transform: Matrix4x4 {
            matrix: PlanarTransform.fromShear(
                        Math.tan(settingsNavigation.moveShearAngle * Math.PI / 180),
                        0, width / 2, 0)
        }

        SettingsNavigation {
            id: settingsNavigation
            width: 190
            height: implicitHeight
            currentTab: root.currentTab
            accentColor: root.accentColor
            iconColor: root.iconColor
            elevatedColor: root.elevatedColor
            textPrimary: root.textPrimary
            textSecondary: root.textSecondary
            moveTarget: root
            movementBoundary: root.parent
            onTabSelected: function(tabIndex) { root.currentTab = tabIndex }
            onLogoutRequested: {
                root.close()
                root.logoutRequested()
            }
        }

        Item {
            width: parent.width - 190
            height: parent.height

            StackLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.topMargin: 18
                anchors.rightMargin: 18
                anchors.bottomMargin: 56
                currentIndex: root.currentTab

                ProfileSettingsPage {
                    currentUserId: root.currentUserId
                    currentUserAvatar: root.currentUserAvatar
                    currentDisplayName: root.currentDisplayName
                    sessionServer: root.sessionServer
                    mediaProxy: root.mediaProxy
                    roundAvatars: root.roundAvatars
                    avatarStatusText: root.avatarStatusText
                    avatarStatusColor: root.avatarStatusColor
                    displayNameStatusText: root.displayNameStatusText
                    displayNameStatusColor: root.displayNameStatusColor
                    displayNameBusy: root.displayNameBusy
                    accentColor: root.accentColor
                    surfaceColor: root.surfaceColor
                    elevatedColor: root.elevatedColor
                    textPrimary: root.textPrimary
                    textSecondary: root.textSecondary
                    onAvatarChangeRequested: root.avatarChangeRequested()
                    onDisplayNameChangeRequested: function(displayName, clearDisplayName) {
                        root.displayNameChangeRequested(displayName, clearDisplayName)
                    }
                }

                AppearanceSettingsPage {
                    id: appearanceSettingsPage
                    themeMode: root.themeMode
                    darkThemeId: root.darkThemeId
                    lightThemeId: root.lightThemeId
                    automaticLightStartMinutes: root.automaticLightStartMinutes
                    automaticDarkStartMinutes: root.automaticDarkStartMinutes
                    roundAvatars: root.roundAvatars
                    showSpaceRoomsInHome: root.showSpaceRoomsInHome
                    showThreadsInSmallGroups: root.showThreadsInSmallGroups
                    messageDateFormat: root.messageDateFormat
                    messageTimeFormat: root.messageTimeFormat
                    uiScale: root.uiScale
                    animationsEnabled: root.animationsEnabled
                    windowWobbleMode: root.windowWobbleMode
                    windowSpringStrength: root.windowSpringStrength
                    windowWobbleStrength: root.windowWobbleStrength
                    startupIntroVariant: root.startupIntroVariant
                    accentColor: root.accentColor
                    iconColor: root.iconColor
                    surfaceColor: root.surfaceColor
                    elevatedColor: root.elevatedColor
                    textPrimary: root.textPrimary
                    textSecondary: root.textSecondary
                    backgroundColor: root.backgroundColor
                    dividerColor: root.dividerColor
                    customAccentColor: root.customAccentColor
                    customIconColor: root.customIconColor
                    customBackgroundColor: root.customBackgroundColor
                    customSurfaceColor: root.customSurfaceColor
                    customElevatedColor: root.customElevatedColor
                    customTextPrimary: root.customTextPrimary
                    customTextSecondary: root.customTextSecondary
                    customDividerColor: root.customDividerColor
                    onCustomColorSelected: function(key, colorValue) {
                        root.customColorSelected(key, colorValue)
                    }
                    onThemeModeSelected: function(mode) { root.themeModeSelected(mode) }
                    onThemeVariantSelected: function(mode, themeId) {
                        root.themeVariantSelected(mode, themeId)
                    }
                    onAutomaticScheduleSelected: function(lightStartMinutes, darkStartMinutes) {
                        root.automaticScheduleSelected(lightStartMinutes, darkStartMinutes)
                    }
                    onRoundAvatarsSelected: function(enabled) { root.roundAvatarsSelected(enabled) }
                    onSpaceRoomsInHomeSelected: function(enabled) {
                        root.spaceRoomsInHomeSelected(enabled)
                    }
                    onThreadsInSmallGroupsSelected: function(enabled) {
                        root.threadsInSmallGroupsSelected(enabled)
                    }
                    onDateFormatSelected: function(format) { root.dateFormatSelected(format) }
                    onTimeFormatSelected: function(format) { root.timeFormatSelected(format) }
                    onUiScaleSelected: function(scale) { root.uiScaleSelected(scale) }
                    onAnimationsSelected: function(enabled) { root.animationsSelected(enabled) }
                    onWindowWobbleModeSelected: function(mode) {
                        root.windowWobbleModeSelected(mode)
                    }
                    onWindowSpringStrengthSelected: function(strength) {
                        root.windowSpringStrengthSelected(strength)
                    }
                    onWindowWobbleStrengthSelected: function(strength) {
                        root.windowWobbleStrengthSelected(strength)
                    }
                    onStartupIntroVariantSelected: function(variant) {
                        root.startupIntroVariantSelected(variant)
                    }
                    onStartupIntroPickerRequested: {
                        startupIntroPicker.open()
                    }
                }

                LanguageSettingsPage {
                    currentLanguage: root.languageCode
                    accentColor: root.accentColor
                    surfaceColor: root.surfaceColor
                    elevatedColor: root.elevatedColor
                    textPrimary: root.textPrimary
                    textSecondary: root.textSecondary
                    onLanguageSelected: function(code) { root.languageSelected(code) }
                }

                EncryptionSettingsPage {
                    id: encryptionSettingsPage
                    currentUserId: root.currentUserId
                    currentProfileId: root.currentProfileId
                    sessionServer: root.sessionServer
                    currentDeviceId: root.currentDeviceId
                    accentColor: root.accentColor
                    surfaceColor: root.surfaceColor
                    elevatedColor: root.elevatedColor
                    textPrimary: root.textPrimary
                    textSecondary: root.textSecondary
                    keyTransferBusy: root.keyTransferBusy
                    keyTransferStatus: root.keyTransferStatus
                    keyTransferError: root.keyTransferError
                    encryptionOverview: root.encryptionOverview
                    onCommandRequested: function(command) { root.e2eeCommandRequested(command) }
                    onRefreshRequested: root.encryptionRefreshRequested()
                    onExportKeysRequested: function(path, passphrase) {
                        root.exportKeysRequested(path, passphrase)
                    }
                    onImportKeysRequested: function(path, passphrase) {
                        root.importKeysRequested(path, passphrase)
                    }
                }

                DevicesSettingsPage {
                    id: devicesSettingsPage
                    overview: root.encryptionOverview
                    devices: root.matrixDevices
                    loading: root.matrixDevicesLoading
                    accentColor: root.accentColor
                    surfaceColor: root.surfaceColor
                    elevatedColor: root.elevatedColor
                    textPrimary: root.textPrimary
                    textSecondary: root.textSecondary
                    onRefreshRequested: root.encryptionRefreshRequested()
                    onCommandRequested: function(command) { root.e2eeCommandRequested(command) }
                }

                PlaceholderSettingsPage {
                    title: L10n.I18n.tr("Уведомления")
                    systemNotificationsEnabled: root.systemNotificationsEnabled
                    systemInvitationNotificationsEnabled:
                        root.systemInvitationNotificationsEnabled
                    systemMentionNotificationsEnabled:
                        root.systemMentionNotificationsEnabled
                    accentColor: root.accentColor
                    surfaceColor: root.surfaceColor
                    elevatedColor: root.elevatedColor
                    textPrimary: root.textPrimary
                    textSecondary: root.textSecondary
                    dividerColor: root.dividerColor
                    onPreferencesChanged: function(enabled, invitationsEnabled,
                                                   mentionsEnabled) {
                        root.systemNotificationPreferencesChanged(
                            enabled, invitationsEnabled, mentionsEnabled)
                    }
                }

                StorageSettingsPage {
                    sqliteBytes: root.storageSqliteBytes
                    eventCacheBytes: root.storageEventCacheBytes
                    mediaBytes: root.storageMediaBytes
                    totalCacheBytes: root.storageTotalCacheBytes
                    autoCleanupDays: root.storageAutoCleanupDays
                    cacheLimitMb: root.storageCacheLimitMb
                    downloadsDirectory: root.storageDownloadsDirectory
                    autoLoadImages: root.storageAutoLoadImages
                    autoLoadVideos: root.storageAutoLoadVideos
                    busy: root.storageBusy
                    statusText: root.storageStatus
                    statusError: root.storageStatusError
                    accentColor: root.accentColor
                    surfaceColor: root.surfaceColor
                    elevatedColor: root.elevatedColor
                    textPrimary: root.textPrimary
                    textSecondary: root.textSecondary
                    dividerColor: root.dividerColor
                    onRefreshRequested: root.storageRefreshRequested()
                    onClearCacheRequested: function(clearMedia, clearEventCache, clearSqlite) {
                        root.storageClearCacheRequested(clearMedia, clearEventCache, clearSqlite)
                    }
                    onPreferencesChanged: function(autoCleanupDays, cacheLimitMb,
                                                   downloadsDirectory,
                                                   autoLoadImages, autoLoadVideos) {
                        root.storagePreferencesChanged(autoCleanupDays, cacheLimitMb,
                                                       downloadsDirectory,
                                                       autoLoadImages, autoLoadVideos)
                    }
                    onClearTemporaryDataRequested: root.storageClearTemporaryDataRequested()
                    onExportDiagnosticsRequested: function(path) {
                        root.storageExportDiagnosticsRequested(path)
                    }
                }

                AboutSettingsPage {
                    textPrimary: root.textPrimary
                    textSecondary: root.textSecondary
                }

                PrivacySettingsPage {
                    sendReadReceipts: root.readReceiptsEnabled
                    sendTypingNotifications: root.typingNotificationsEnabled
                    accentColor: root.accentColor
                    surfaceColor: root.surfaceColor
                    elevatedColor: root.elevatedColor
                    textPrimary: root.textPrimary
                    textSecondary: root.textSecondary
                    onPreferencesChanged: function(readReceipts, typingNotifications) {
                        root.privacyPreferencesChanged(readReceipts, typingNotifications)
                    }
                }
            }

            Basic.Button {
                id: closeButton
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                width: 88
                height: 30
                text: L10n.I18n.tr("Закрыть")
                hoverEnabled: true
                scale: down ? 0.88 : 1
                onClicked: root.close()

                background: Rectangle {
                    radius: 8
                    color: closeButton.down
                        ? root.blendedButtonColor(root.elevatedColor, root.accentColor, 0.18)
                        : closeButton.hovered
                            ? root.blendedButtonColor(root.elevatedColor, root.textPrimary, 0.10)
                            : root.elevatedColor
                    border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.16)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                }

                contentItem: Text {
                    text: closeButton.text
                    color: root.textPrimary
                    font.pointSize: 9
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Behavior on scale {
                    NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                }
            }
        }
    }

    StartupIntroPickerDialog {
        id: startupIntroPicker
        parent: Overlay.overlay
        selectedVariant: root.startupIntroVariant
        animationsEnabled: root.animationsEnabled
        accentColor: root.accentColor
        iconColor: root.iconColor
        backgroundColor: root.backgroundColor
        surfaceColor: root.surfaceColor
        elevatedColor: root.elevatedColor
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        dividerColor: root.dividerColor

        onVariantSelected: function(variant) {
            root.startupIntroVariantSelected(variant)
        }
    }
}
