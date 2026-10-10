import QtQuick
import "../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Dialogs
import "../../components/common"
import "../../utils/PrismUtils.js" as Utils
import ".."

Flickable {
    id: root

    // SettingsDialog API compatibility.
    property string currentUserId: ""
    property string currentProfileId: ""
    property string sessionServer: ""
    property string currentDeviceId: ""

    property color accentColor: "#20D500"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property bool keyTransferBusy: false
    property string keyTransferStatus: ""
    property bool keyTransferError: false
    property string localValidationError: ""
    property var encryptionOverview: null
    property bool recoveryBusy: false
    property string recoveryStatus: ""
    property bool recoveryError: false
    property string pendingRecoveryRequestId: ""
    property string pendingRecoveryOperation: ""
    property string pendingUiaaSession: ""
    property string pendingOAuthApprovalUrl: ""

    signal exportKeysRequested(string path, string passphrase)
    signal importKeysRequested(string path, string passphrase)
    signal commandRequested(var command)
    signal refreshRequested()

    function recoveryStateLabel() {
        if (!encryptionOverview) return L10n.I18n.tr("Статус неизвестен")
        if (encryptionOverview.recovery_state === "enabled") return L10n.I18n.tr("Recovery включено")
        if (encryptionOverview.recovery_state === "incomplete") return L10n.I18n.tr("Recovery требует восстановления")
        if (encryptionOverview.recovery_state === "disabled") return L10n.I18n.tr("Recovery не настроено")
        return L10n.I18n.tr("Статус Recovery неизвестен")
    }

    function recoveryStateValue() {
        return encryptionOverview ? (encryptionOverview.recovery_state || "unknown") : "unknown"
    }

    function recoveryStateDescription() {
        if (recoveryStateValue() === "disabled")
            return L10n.I18n.tr("Recovery ещё не создано. Настройте его и сохраните новый recovery key.")
        if (recoveryStateValue() === "incomplete")
            return L10n.I18n.tr("Secret Storage уже существует, но этому устройству не хватает секретов. Введите ранее сохранённый recovery key. Не создавайте новый поверх существующего Recovery.")
        if (recoveryStateValue() === "enabled")
            return L10n.I18n.tr("Устройство имеет cross-signing secrets и подключено к Matrix Recovery.")
        return L10n.I18n.tr("PrismChat ожидает актуальное состояние шифрования от Matrix SDK.")
    }

    function hasPendingIdentityReset() {
        return pendingOAuthApprovalUrl !== ""
            || (encryptionOverview && encryptionOverview.identity_reset_pending === true)
    }

    function requestIdentityReset() {
        recoveryBusy = true
        recoveryError = false
        recoveryStatus = ""
        pendingRecoveryOperation = "reset_identity"
        pendingRecoveryRequestId = Date.now().toString() + "-reset-identity"
        commandRequested({
            type: "reset_crypto_identity",
            request_id: pendingRecoveryRequestId
        })
    }

    function openIdentityResetApproval() {
        if (pendingOAuthApprovalUrl === "") {
            requestIdentityReset()
            return
        }
        if (!Qt.openUrlExternally(pendingOAuthApprovalUrl)) {
            recoveryError = true
            recoveryStatus = L10n.I18n.tr("Linux не смог открыть системный браузер. Откройте ссылку вручную из окна подтверждения.")
        }
    }

    function finishOAuthIdentityReset() {
        pendingRecoveryRequestId = Date.now().toString() + "-reset-oauth"
        pendingRecoveryOperation = "reset_identity"
        recoveryBusy = true
        recoveryError = false
        commandRequested({
            type: "reset_crypto_identity",
            request_id: pendingRecoveryRequestId,
            oauth_approved: true
        })
    }

    function cancelIdentityReset() {
        pendingRecoveryRequestId = Date.now().toString() + "-cancel-identity-reset"
        pendingRecoveryOperation = "cancel_reset"
        recoveryBusy = true
        commandRequested({
            type: "cancel_crypto_identity_reset",
            request_id: pendingRecoveryRequestId
        })
    }

    function handleRecoveryAction(requestId, success, uiaaSession, authType, approvalUrl, recoveryKey, errorText) {
        if (requestId !== pendingRecoveryRequestId) return
        recoveryBusy = false
        if (!success && authType === "uiaa" && uiaaSession) {
            pendingUiaaSession = uiaaSession
            matrixPassword.clear()
            matrixPasswordDialog.open()
            return
        }
        if (!success && authType === "oauth" && approvalUrl) {
            pendingRecoveryRequestId = ""
            pendingOAuthApprovalUrl = approvalUrl
            if (!Qt.openUrlExternally(approvalUrl)) {
                recoveryError = true
                recoveryStatus = L10n.I18n.tr("Не удалось открыть системный браузер. Ссылку можно открыть вручную в следующем окне.")
            }
            oauthApprovalDialog.open()
            // Continue the same reset while the SDK polls for browser approval.
            finishOAuthIdentityReset()
            return
        }
        if (!success && authType === "refresh") {
            pendingRecoveryRequestId = ""
            pendingOAuthApprovalUrl = ""
            pendingUiaaSession = ""
            recoveryError = false
            recoveryStatus = errorText || L10n.I18n.tr("Новая identity отправлена. Matrix SDK ещё обновляет подпись текущего устройства; нажмите «Проверить состояние» через несколько секунд.")
            refreshRequested()
            return
        }
        pendingRecoveryRequestId = ""
        recoveryError = !success
        if (success) {
            if (pendingRecoveryOperation === "setup")
                recoveryStatus = L10n.I18n.tr("Recovery настроено. Сохраните recovery key.")
            else if (pendingRecoveryOperation === "change_key")
                recoveryStatus = L10n.I18n.tr("Recovery key сменён. Старый ключ больше не работает.")
            else if (pendingRecoveryOperation === "repair_backup")
                recoveryStatus = L10n.I18n.tr("Хранилище ключей восстановлено.")
            else if (pendingRecoveryOperation === "reset_identity") {
                oauthApprovalDialog.close()
                recoveryStatus = L10n.I18n.tr("Новая identity опубликована, а это устройство подписано её self-signing key. Старые клиенты не начнут доверять новой identity автоматически: восстановите их новым recovery key или подтвердите заново. Теперь настройте Recovery.")
            }
            else if (pendingRecoveryOperation === "cancel_reset")
                recoveryStatus = L10n.I18n.tr("Ожидание подтверждения остановлено. Проверьте состояние Recovery и backup: SDK мог изменить их до запроса авторизации.")
            else
                recoveryStatus = L10n.I18n.tr("Ключи успешно восстановлены.")
        } else {
            recoveryStatus = errorText || L10n.I18n.tr("Операция не выполнена")
        }
        if (success && (pendingRecoveryOperation === "reset_identity"
                        || pendingRecoveryOperation === "cancel_reset")) {
            pendingOAuthApprovalUrl = ""
            pendingUiaaSession = ""
        }
        if (success && recoveryKey) { recoveryKeyDialog.recoveryKey = recoveryKey; recoveryKeyDialog.open() }
        if (success) refreshRequested()
    }

    function beginExport() {
        localValidationError = ""
        if (passphraseField.text.length < 8) {
            localValidationError = L10n.I18n.tr("Кодовая фраза должна содержать не менее 8 символов")
            return
        }
        if (passphraseField.text !== passphraseConfirmationField.text) {
            localValidationError = L10n.I18n.tr("Кодовые фразы не совпадают")
            return
        }
        exportKeysDialog.open()
    }

    function beginImport() {
        localValidationError = ""
        if (passphraseField.text.length === 0) {
            localValidationError = L10n.I18n.tr("Введите кодовую фразу от файла ключей")
            return
        }
        importKeysDialog.open()
    }

    clip: true
    contentWidth: width
    contentHeight: contentColumn.implicitHeight

    Column {
        id: contentColumn
        width: root.width
        spacing: 14

        Text {
            text: L10n.I18n.tr("Шифрование")
            color: root.textPrimary
            font.bold: true
            font.pointSize: 13
        }

        Rectangle {
            width: parent.width; radius: 8; color: root.surfaceColor
            border.width: 1; border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.10)
            implicitHeight: recoveryColumn.implicitHeight + 24
            Column {
                id: recoveryColumn; anchors.fill: parent; anchors.margins: 12; spacing: 9
                Text { text: L10n.I18n.tr("Восстановление"); color: root.textPrimary; font.pointSize: 10; font.bold: true }
                Text { width: parent.width; wrapMode: Text.Wrap; text: root.recoveryStateLabel(); color: root.accentColor; font.pointSize: 8; font.bold: true }
                Text { width: parent.width; wrapMode: Text.Wrap; text: root.recoveryStateDescription(); color: root.textSecondary; font.pointSize: 8 }
                Flow {
                    width: parent.width; spacing: 8
                    SettingsActionButton { visible: root.recoveryStateValue() === "disabled"; enabled: !root.recoveryBusy && !root.hasPendingIdentityReset(); primary: true; accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Настроить Recovery"); onClicked: setupRecoveryDialog.open() }
                    SettingsActionButton { visible: root.recoveryStateValue() === "incomplete"; enabled: !root.recoveryBusy && !root.hasPendingIdentityReset(); primary: true; softPress: true; accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Восстановить устройство"); onClicked: recoverKeysDialog.open() }
                    SettingsActionButton { visible: root.recoveryStateValue() === "enabled"; enabled: !root.recoveryBusy && !root.hasPendingIdentityReset(); accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Сменить recovery key"); onClicked: changeRecoveryKeyDialog.open() }
                    SettingsActionButton { visible: root.recoveryStateValue() === "enabled" || root.recoveryStateValue() === "incomplete"; enabled: !root.recoveryBusy && !root.hasPendingIdentityReset(); accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Починить backup"); onClicked: repairBackupDialog.open() }
                    SettingsActionButton { enabled: root.recoveryStateValue() !== "unknown" && !root.recoveryBusy && !root.hasPendingIdentityReset(); destructive: true; accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Сбросить личность"); onClicked: resetIdentityDialog.open() }
                }
                Rectangle {
                    visible: root.hasPendingIdentityReset()
                    width: parent.width
                    implicitHeight: pendingResetColumn.implicitHeight + 20
                    radius: 8
                    color: Qt.rgba(0.94, 0.55, 0.19, 0.09)
                    border.width: 1
                    border.color: Qt.rgba(0.94, 0.55, 0.19, 0.35)
                    Column {
                        id: pendingResetColumn
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 7
                        Text { width: parent.width; wrapMode: Text.Wrap; text: root.pendingOAuthApprovalUrl !== "" ? L10n.I18n.tr("PrismChat уже продолжает тот же identity reset и ожидает разрешение homeserver. Если вкладка закрыта, откройте страницу снова.") : L10n.I18n.tr("Сброс личности выполняется в Rust backend. При повторном открытии настроек операция продолжится, а не начнётся заново."); color: "#f0b35a"; font.pointSize: 8 }
                        Flow {
                            width: parent.width
                            spacing: 7
                            SettingsActionButton { enabled: !root.recoveryBusy; primary: true; accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: root.pendingOAuthApprovalUrl !== "" ? L10n.I18n.tr("Открыть страницу снова") : L10n.I18n.tr("Продолжить ожидание"); onClicked: root.openIdentityResetApproval() }
                            SettingsActionButton { enabled: !root.recoveryBusy; destructive: true; accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Остановить попытку"); onClicked: root.cancelIdentityReset() }
                        }
                    }
                }
                Row { visible: root.recoveryBusy; spacing: 8; PrismBusyIndicator { width: 18; height: 18; running: parent.visible; accentColor: root.accentColor } Text { anchors.verticalCenter: parent.verticalCenter; text: L10n.I18n.tr("Выполняется защищённая операция…"); color: root.textSecondary; font.pointSize: 8 } }
                Text { visible: root.recoveryStatus !== ""; width: parent.width; wrapMode: Text.Wrap; text: root.recoveryStatus; color: root.recoveryError ? "#ff7777" : root.accentColor; font.pointSize: 8 }
            }
        }


        Rectangle {
            width: parent.width
            radius: 8
            color: root.surfaceColor
            border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                  root.textSecondary.b, 0.10)
            border.width: 1
            implicitHeight: keysColumn.implicitHeight + 24

            Column {
                id: keysColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Text {
                    text: L10n.I18n.tr("Ключи шифрования")
                    color: root.textPrimary
                    font.pointSize: 10
                    font.bold: true
                }

                Basic.TextField {
                    id: passphraseField
                    width: parent.width
                    height: 36
                    enabled: !root.keyTransferBusy
                    echoMode: TextInput.Password
                    placeholderText: L10n.I18n.tr("Кодовая фраза")
                    color: root.textPrimary
                    placeholderTextColor: root.textSecondary
                    selectByMouse: true
                    leftPadding: 11
                    rightPadding: 11
                    onTextChanged: root.localValidationError = ""
                    background: Rectangle {
                        radius: 8
                        color: root.elevatedColor
                        border.width: 1
                        border.color: passphraseField.activeFocus
                            ? root.accentColor
                            : Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                      root.textSecondary.b, 0.15)
                    }
                }

                Basic.TextField {
                    id: passphraseConfirmationField
                    width: parent.width
                    height: 36
                    enabled: !root.keyTransferBusy
                    echoMode: TextInput.Password
                    placeholderText: L10n.I18n.tr("Повторите кодовую фразу для экспорта")
                    color: root.textPrimary
                    placeholderTextColor: root.textSecondary
                    selectByMouse: true
                    leftPadding: 11
                    rightPadding: 11
                    onTextChanged: root.localValidationError = ""
                    background: Rectangle {
                        radius: 8
                        color: root.elevatedColor
                        border.width: 1
                        border.color: passphraseConfirmationField.activeFocus
                            ? root.accentColor
                            : Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                      root.textSecondary.b, 0.15)
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8

                    Basic.Button {
                        id: exportKeysButton
                        width: (parent.width - parent.spacing) / 2
                        height: 36
                        enabled: !root.keyTransferBusy
                        hoverEnabled: true
                        text: L10n.I18n.tr("Экспортировать…")
                        onClicked: root.beginExport()
                        contentItem: Text {
                            text: exportKeysButton.text
                            color: exportKeysButton.enabled ? root.textPrimary : root.textSecondary
                            font.pointSize: 8
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 8
                            color: exportKeysButton.down
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                          root.accentColor.b, 0.20)
                                : exportKeysButton.hovered
                                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                              root.accentColor.b, 0.12)
                                    : root.elevatedColor
                            border.width: 1
                            border.color: root.accentColor
                        }
                    }

                    Basic.Button {
                        id: importKeysButton
                        width: (parent.width - parent.spacing) / 2
                        height: 36
                        enabled: !root.keyTransferBusy
                        hoverEnabled: true
                        text: L10n.I18n.tr("Импортировать…")
                        onClicked: root.beginImport()
                        contentItem: Text {
                            text: importKeysButton.text
                            color: importKeysButton.enabled ? root.accentColor : root.textSecondary
                            font.pointSize: 8
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 8
                            color: importKeysButton.down
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                          root.accentColor.b, 0.20)
                                : importKeysButton.hovered
                                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                              root.accentColor.b, 0.12)
                                    : root.elevatedColor
                            border.width: 1
                            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                                  root.accentColor.b, 0.65)
                        }
                    }
                }

                Row {
                    visible: root.keyTransferBusy
                    spacing: 8
                    PrismBusyIndicator {
                        width: 18
                        height: 18
                        running: parent.visible
                        accentColor: root.accentColor
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: L10n.I18n.tr("Обработка файла ключей…")
                        color: root.textSecondary
                        font.pointSize: 8
                    }
                }

                Text {
                    visible: !root.keyTransferBusy
                        && (root.localValidationError !== "" || root.keyTransferStatus !== "")
                    width: parent.width
                    text: root.localValidationError !== ""
                        ? root.localValidationError : root.keyTransferStatus
                    color: root.localValidationError !== "" || root.keyTransferError
                        ? "#ff6b6b" : root.accentColor
                    font.pointSize: 8
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    FileDialog {
        id: exportKeysDialog
        title: L10n.I18n.tr("Сохранить ключи шифрования")
        fileMode: FileDialog.SaveFile
        nameFilters: [L10n.I18n.tr("Файл ключей Matrix (*.txt)"),
                      L10n.I18n.tr("Все файлы (*)")]
        onAccepted: {
            var path = Utils.localPath(selectedFile)
            var passphrase = passphraseField.text
            passphraseField.clear()
            passphraseConfirmationField.clear()
            root.exportKeysRequested(path, passphrase)
        }
    }

    FileDialog {
        id: importKeysDialog
        title: L10n.I18n.tr("Выберите файл ключей шифрования")
        fileMode: FileDialog.OpenFile
        nameFilters: [L10n.I18n.tr("Файл ключей Matrix (*.txt)"),
                      L10n.I18n.tr("Все файлы (*)")]
        onAccepted: {
            var path = Utils.localPath(selectedFile)
            var passphrase = passphraseField.text
            passphraseField.clear()
            passphraseConfirmationField.clear()
            root.importKeysRequested(path, passphrase)
        }
    }

    SettingsModalDialog {
        id: setupRecoveryDialog; objectName: "setupRecoveryDialog"; parent: Overlay.overlay; anchors.centerIn: parent; modal: true; title: L10n.I18n.tr("Настроить Recovery"); standardButtons: Dialog.Ok | Dialog.Cancel
        preferredContentWidth: 390; contentItem: Column { spacing: 9
            Text { width: parent.width; wrapMode: Text.Wrap; text: L10n.I18n.tr("PrismChat создаст recovery key через Matrix SDK и покажет его один раз. Passphrase можно оставить пустой."); color: root.textSecondary; font.pointSize: 8 }
            Basic.TextField { id: setupPassphraseInput; width: parent.width; height: 38; echoMode: TextInput.Password; selectByMouse: true; placeholderText: L10n.I18n.tr("Passphrase, необязательно"); color: root.textPrimary; placeholderTextColor: root.textSecondary; background: Rectangle { radius: 8; color: root.elevatedColor } }
            Basic.TextField { id: setupPassphraseConfirm; width: parent.width; height: 38; echoMode: TextInput.Password; selectByMouse: true; placeholderText: L10n.I18n.tr("Повторите passphrase"); color: root.textPrimary; placeholderTextColor: root.textSecondary; background: Rectangle { radius: 8; color: root.elevatedColor } }
        }
        onAccepted: {
            var passphrase = setupPassphraseInput.text
            var confirm = setupPassphraseConfirm.text
            setupPassphraseInput.clear()
            setupPassphraseConfirm.clear()
            if (passphrase !== confirm) { root.recoveryError = true; root.recoveryStatus = L10n.I18n.tr("Passphrase не совпадает"); return }
            root.recoveryBusy = true; root.recoveryError = false; root.recoveryStatus = ""; root.pendingRecoveryOperation = "setup"; root.pendingRecoveryRequestId = Date.now().toString() + "-enable-recovery"; root.commandRequested({ type: "enable_recovery", request_id: root.pendingRecoveryRequestId, passphrase: passphrase })
        }
        onRejected: { setupPassphraseInput.clear(); setupPassphraseConfirm.clear() }
    }

    SettingsModalDialog {
        id: recoverKeysDialog; objectName: "recoverKeysDialog"; parent: Overlay.overlay; anchors.centerIn: parent; modal: true; title: L10n.I18n.tr("Восстановить ключи"); standardButtons: Dialog.Ok | Dialog.Cancel
        preferredContentWidth: 370; contentItem: Column { spacing: 9
            Text { width: parent.width; wrapMode: Text.Wrap; text: L10n.I18n.tr("Введите recovery key. Он будет передан Rust backend только для этой операции и не будет сохранён."); color: root.textSecondary; font.pointSize: 8 }
            Basic.TextField { id: recoveryKeyInput; width: parent.width; height: 38; echoMode: TextInput.Password; selectByMouse: true; placeholderText: L10n.I18n.tr("Recovery key"); color: root.textPrimary; placeholderTextColor: root.textSecondary; background: Rectangle { radius: 8; color: root.elevatedColor } }
        }
        onAccepted: { var value = recoveryKeyInput.text; recoveryKeyInput.clear(); if (!value) return; root.recoveryBusy = true; root.recoveryError = false; root.recoveryStatus = ""; root.pendingRecoveryOperation = "recover"; root.pendingRecoveryRequestId = Date.now().toString() + "-recover-encryption"; root.commandRequested({ type: "recover_encryption", request_id: root.pendingRecoveryRequestId, recovery_key: value }) }
        onRejected: recoveryKeyInput.clear()
    }

    SettingsModalDialog {
        id: changeRecoveryKeyDialog; objectName: "changeRecoveryKeyDialog"; parent: Overlay.overlay; anchors.centerIn: parent; modal: true; title: L10n.I18n.tr("Сменить recovery key"); standardButtons: Dialog.Ok | Dialog.Cancel
        preferredContentWidth: 390; contentItem: Column { spacing: 9
            Text { width: parent.width; wrapMode: Text.Wrap; text: L10n.I18n.tr("Если Recovery включено и устройство полностью восстановлено, старый ключ можно не вводить. Если состояние неполное — введите старый recovery key."); color: root.textSecondary; font.pointSize: 8 }
            Basic.TextField { id: oldRecoveryKeyInput; width: parent.width; height: 38; echoMode: TextInput.Password; selectByMouse: true; placeholderText: L10n.I18n.tr("Старый recovery key, если нужен"); color: root.textPrimary; placeholderTextColor: root.textSecondary; background: Rectangle { radius: 8; color: root.elevatedColor } }
            Basic.TextField { id: newRecoveryPassphrase; width: parent.width; height: 38; echoMode: TextInput.Password; selectByMouse: true; placeholderText: L10n.I18n.tr("Новая passphrase, необязательно"); color: root.textPrimary; placeholderTextColor: root.textSecondary; background: Rectangle { radius: 8; color: root.elevatedColor } }
            Basic.TextField { id: newRecoveryPassphraseConfirm; width: parent.width; height: 38; echoMode: TextInput.Password; selectByMouse: true; placeholderText: L10n.I18n.tr("Повторите passphrase"); color: root.textPrimary; placeholderTextColor: root.textSecondary; background: Rectangle { radius: 8; color: root.elevatedColor } }
        }
        onAccepted: {
            var oldKey = oldRecoveryKeyInput.text
            var passphrase = newRecoveryPassphrase.text
            var confirm = newRecoveryPassphraseConfirm.text
            oldRecoveryKeyInput.clear()
            newRecoveryPassphrase.clear()
            newRecoveryPassphraseConfirm.clear()
            if (passphrase !== confirm) { root.recoveryError = true; root.recoveryStatus = L10n.I18n.tr("Passphrase не совпадает"); return }
            root.recoveryBusy = true; root.recoveryError = false; root.recoveryStatus = ""; root.pendingRecoveryOperation = "change_key"; root.pendingRecoveryRequestId = Date.now().toString() + "-change-recovery-key"; root.commandRequested({ type: "change_recovery_key", request_id: root.pendingRecoveryRequestId, old_recovery_key: oldKey, passphrase: passphrase })
        }
        onRejected: { oldRecoveryKeyInput.clear(); newRecoveryPassphrase.clear(); newRecoveryPassphraseConfirm.clear() }
    }

    SettingsModalDialog {
        id: repairBackupDialog; objectName: "repairBackupDialog"; parent: Overlay.overlay; anchors.centerIn: parent; modal: true; title: L10n.I18n.tr("Починить хранилище ключей"); standardButtons: Dialog.Ok | Dialog.Cancel
        preferredContentWidth: 390; contentItem: Column { spacing: 9
            Text { width: parent.width; wrapMode: Text.Wrap; text: L10n.I18n.tr("Используйте это только если backup/Recovery рассинхронизированы. SDK восстановит secrets и при несовпадении может пересоздать серверный backup."); color: "#f0b35a"; font.pointSize: 8 }
            Basic.TextField { id: repairRecoveryKeyInput; width: parent.width; height: 38; echoMode: TextInput.Password; selectByMouse: true; placeholderText: L10n.I18n.tr("Recovery key"); color: root.textPrimary; placeholderTextColor: root.textSecondary; background: Rectangle { radius: 8; color: root.elevatedColor } }
        }
        onAccepted: { var value = repairRecoveryKeyInput.text; repairRecoveryKeyInput.clear(); if (!value) return; root.recoveryBusy = true; root.recoveryError = false; root.recoveryStatus = ""; root.pendingRecoveryOperation = "repair_backup"; root.pendingRecoveryRequestId = Date.now().toString() + "-repair-key-backup"; root.commandRequested({ type: "repair_key_backup", request_id: root.pendingRecoveryRequestId, recovery_key: value }) }
        onRejected: repairRecoveryKeyInput.clear()
    }

    SettingsModalDialog {
        id: resetIdentityDialog; objectName: "resetIdentityDialog"; parent: Overlay.overlay; anchors.centerIn: parent; modal: true; title: L10n.I18n.tr("Сбросить cryptographic identity?"); standardButtons: Dialog.Ok | Dialog.Cancel
        preferredContentWidth: 390
        contentItem: Text { width: resetIdentityDialog.contentWidth; wrapMode: Text.Wrap; text: L10n.I18n.tr("Это крайний случай: SDK удалит active key backup, выключит Recovery и заменит cross-signing identity. Старые сообщения останутся читаемыми только если ключи уже есть локально. Другие клиенты сохранят старую identity как ранее доверенную и потребуют восстановление новым recovery key либо повторное подтверждение — автоматически доверять новому master key они не имеют права. Новый Recovery настраивается отдельно после reset."); color: root.textPrimary; font.pointSize: 8 }
        onAccepted: root.requestIdentityReset()
    }

    SettingsModalDialog {
        id: matrixPasswordDialog; objectName: "matrixPasswordDialog"; preferredContentWidth: 360; parent: Overlay.overlay; anchors.centerIn: parent; modal: true; title: L10n.I18n.tr("Подтвердите пароль Matrix"); standardButtons: Dialog.Ok | Dialog.Cancel
        contentItem: Basic.TextField { id: matrixPassword; implicitWidth: 360; implicitHeight: 38; echoMode: TextInput.Password; selectByMouse: true; color: root.textPrimary; placeholderText: L10n.I18n.tr("Пароль Matrix"); placeholderTextColor: root.textSecondary; background: Rectangle { radius: 8; color: root.elevatedColor } }
        onAccepted: { var password = matrixPassword.text; matrixPassword.clear(); root.pendingRecoveryRequestId = Date.now().toString() + "-reset-uiaa"; root.recoveryBusy = true; root.commandRequested({ type: "reset_crypto_identity", request_id: root.pendingRecoveryRequestId, password: password, uiaa_session: root.pendingUiaaSession }) }
        onRejected: { matrixPassword.clear(); root.pendingRecoveryRequestId = ""; root.recoveryBusy = false }
    }

    SettingsModalDialog {
        id: oauthApprovalDialog; objectName: "oauthApprovalDialog"; parent: Overlay.overlay; anchors.centerIn: parent; modal: true; title: L10n.I18n.tr("Подтвердите сброс в браузере"); standardButtons: Dialog.NoButton
        preferredContentWidth: 390
        contentItem: Column {
            width: oauthApprovalDialog.contentWidth
            spacing: 9
            Text { width: parent.width; wrapMode: Text.Wrap; text: L10n.I18n.tr("Подтвердите действие на странице homeserver. PrismChat уже ожидает разрешение и автоматически продолжит тот же IdentityResetHandle — дополнительно нажимать «я подтвердил» не нужно."); color: root.textPrimary; font.pointSize: 8 }
            Basic.TextField { width: parent.width; height: 36; readOnly: true; selectByMouse: true; text: root.pendingOAuthApprovalUrl; color: root.textSecondary; font.family: "monospace"; background: Rectangle { radius: 8; color: root.elevatedColor } }
            Flow {
                width: parent.width
                spacing: 7
                SettingsActionButton { accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Открыть снова"); onClicked: root.openIdentityResetApproval() }
                SettingsActionButton { accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Вернуться позже"); onClicked: oauthApprovalDialog.close() }
                SettingsActionButton { visible: !root.recoveryBusy; primary: true; accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Повторить ожидание"); onClicked: root.finishOAuthIdentityReset() }
            }
        }
        onRejected: {
            root.recoveryBusy = false
            root.recoveryError = false
            root.recoveryStatus = L10n.I18n.tr("Сброс ожидает подтверждения. Вернуться к нему можно из блока Recovery.")
        }
    }


    SettingsModalDialog {
        id: recoveryKeyDialog; objectName: "recoveryKeyDialog"; property string recoveryKey: ""; parent: Overlay.overlay; anchors.centerIn: parent; preferredContentWidth: 418; modal: true; title: L10n.I18n.tr("Сохраните recovery key"); standardButtons: Dialog.Close
        contentItem: Column { width: recoveryKeyDialog.availableWidth; spacing: 8
            Text { width: parent.width; wrapMode: Text.Wrap; text: L10n.I18n.tr("Ключ показывается один раз. Сохраните его вне PrismChat."); color: "#f0b35a"; font.pointSize: 8 }
            Basic.TextField { width: parent.width; readOnly: true; selectByMouse: true; text: recoveryKeyDialog.recoveryKey; color: root.textPrimary; font.family: "monospace"; background: Rectangle { radius: 8; color: root.elevatedColor } }
        }
        onClosed: recoveryKey = ""
    }
}
