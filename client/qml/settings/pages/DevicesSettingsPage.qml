import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../components/common"
import "../../components/devices"
import "../../utils" as L10n
import ".."

Flickable {
    id: root
    property var devices: []
    property var overview: null
    property bool loading: true
    property string errorText: ""
    property string query: ""
    property string filter: "all"
    property var selectedIds: ({})
    property var busyIds: ({})
    property var pendingRename: null
    property string deleteOperationId: ""
    property var deleteTargetIds: []
    property string deleteWebUrl: ""
    property string pendingVerificationRequestId: ""
    property string verificationStatus: ""
    property color accentColor: "#20D500"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    signal refreshRequested()
    signal commandRequested(var command)

    clip: true; contentWidth: width; contentHeight: content.implicitHeight

    function requestId(name) { return Date.now().toString() + "-devices-" + name }
    function currentDevice() { for (var i = 0; i < devices.length; i++) if (devices[i].is_current) return devices[i]; return null }
    function otherDevices() { var out = []; for (var i = 0; i < devices.length; i++) if (!devices[i].is_current && matches(devices[i])) out.push(devices[i]); return out }
    function isInactive(device) { return !!device.last_seen_ts && Date.now() - Number(device.last_seen_ts) >= 90 * 24 * 60 * 60 * 1000 }
    function matches(device) {
        var needle = query.trim().toLowerCase()
        if (needle !== "" && (String(device.display_name || "").toLowerCase().indexOf(needle) < 0 && String(device.device_id || "").toLowerCase().indexOf(needle) < 0)) return false
        if (filter === "verified" && device.verification_state !== "verified") return false
        if (filter === "unverified" && device.verification_state !== "unverified") return false
        if (filter === "inactive" && !isInactive(device)) return false
        return true
    }
    function countState(state) { var n = 0; for (var i = 0; i < devices.length; i++) if (!devices[i].is_current && devices[i].verification_state === state) n++; return n }
    function inactiveCount() { var n = 0; for (var i = 0; i < devices.length; i++) if (!devices[i].is_current && isInactive(devices[i])) n++; return n }
    function selectedCount() { return Object.keys(selectedIds).length }
    function toggleSelected(id) { var next = Object.assign({}, selectedIds); if (next[id]) delete next[id]; else next[id] = true; selectedIds = next }
    function setBusy(ids, value) { var next = Object.assign({}, busyIds); for (var i = 0; i < ids.length; i++) { if (value) next[ids[i]] = true; else delete next[ids[i]] } busyIds = next }
    function startRename(device) { renameDialog.device = device; renameField.text = device.display_name || ""; renameDialog.open() }
    function requestDelete(ids) { deleteTargetIds = ids; deleteConfirmDialog.open() }
    function receiveDevices(value, error) { loading = false; if (error) { errorText = error; return } devices = value || []; errorText = "" }
    function receiveOperation(operation, success, ids, error) {
        setBusy(ids || [], false)
        if (operation === "rename" && !success && pendingRename) {
            var restored = devices.slice(); for (var i = 0; i < restored.length; i++) if (restored[i].device_id === pendingRename.device_id) restored[i] = Object.assign({}, restored[i], { display_name: pendingRename.old_name }); devices = restored
        }
        pendingRename = null
        if (!success) errorText = error || L10n.I18n.tr("Операция не выполнена")
        else { errorText = ""; if (operation === "delete") selectedIds = ({}); refreshRequested() }
    }
    function receiveDeleteUiaa(operationId, flows, passwordSupported) {
        deleteOperationId = operationId
        if (!passwordSupported) { errorText = L10n.I18n.tr("Сервер требует способ подтверждения входа, который эта версия PrismChat пока не поддерживает. Сессии не были удалены."); setBusy(deleteTargetIds, false); return }
        deletePassword.clear(); deleteAuthDialog.open()
    }
    function receiveDeleteWeb(deviceIds, url) {
        deleteTargetIds = deviceIds || []
        deleteWebUrl = url || ""
        if (deleteWebUrl === "" || !Qt.openUrlExternally(deleteWebUrl)) {
            errorText = L10n.I18n.tr("Не удалось открыть web-управление устройствами сервера.")
            setBusy(deleteTargetIds, false)
            return
        }
        deleteWebDialog.open()
    }
    function requestVerification(deviceId) {
        var requestId = root.requestId("verify")
        root.pendingVerificationRequestId = requestId
        root.verificationStatus = ""
        var command = { type: "start_verification", request_id: requestId }
        if (deviceId) command.device_id = deviceId
        root.commandRequested(command)
    }
    function receiveLegacyAction(requestId, success, error) {
        if (requestId !== root.pendingVerificationRequestId) return
        root.pendingVerificationRequestId = ""
        root.verificationStatus = success
            ? L10n.I18n.tr("Запрос на подтверждение отправлен")
            : (error || L10n.I18n.tr("Не удалось отправить запрос"))
    }

    Column {
        id: content; width: root.width; spacing: 12
        Text { text: L10n.I18n.tr("Устройства"); color: root.textPrimary; font.pointSize: 13; font.bold: true }
        Text { width: parent.width; wrapMode: Text.Wrap; text: L10n.I18n.tr("Управляйте сессиями, подтверждайте знакомые устройства и завершайте доступ на потерянных устройствах."); color: root.textSecondary; font.pointSize: 8 }

        Rectangle {
            visible: !root.loading && (root.countState("unverified") > 0 || root.inactiveCount() > 0)
            width: parent.width; implicitHeight: recommendation.implicitHeight + 20; radius: 9
            color: Qt.rgba(0.94, 0.70, 0.35, 0.10); border.width: 1; border.color: Qt.rgba(0.94, 0.70, 0.35, 0.30)
            Row {
                id: recommendation; anchors.fill: parent; anchors.margins: 10; spacing: 10
                Text { text: "⚠"; color: "#f0b35a"; font.pointSize: 12 }
                Column { width: parent.width - showRecommendation.width - 36; spacing: 3
                    Text { text: root.countState("unverified") > 0 ? root.countState("unverified") + " " + L10n.I18n.tr("неподтверждённых устройства") : root.inactiveCount() + " " + L10n.I18n.tr("давно неактивных устройства"); color: root.textPrimary; font.bold: true; font.pointSize: 9 }
                    Text { width: parent.width; wrapMode: Text.Wrap; text: L10n.I18n.tr("Проверьте устройства, которые вам знакомы."); color: root.textSecondary; font.pointSize: 8 }
                }
                SettingsActionButton { id: showRecommendation; height: 30; accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Показать"); onClicked: root.filter = root.countState("unverified") > 0 ? "unverified" : "inactive" }
            }
        }

        Row { spacing: 8; visible: root.loading; PrismBusyIndicator { width: 18; height: 18; running: visible; accentColor: root.accentColor } Text { text: L10n.I18n.tr("Загрузка устройств…"); color: root.textSecondary; font.pointSize: 8 } }
        Rectangle { visible: root.errorText !== ""; width: parent.width; implicitHeight: errorLabel.implicitHeight + 20; radius: 8; color: Qt.rgba(1, 0.25, 0.25, 0.09); border.width: 1; border.color: Qt.rgba(1, 0.35, 0.35, 0.28); Text { id: errorLabel; anchors.fill: parent; anchors.margins: 10; width: parent.width; wrapMode: Text.Wrap; text: root.errorText; color: "#ff7777"; font.pointSize: 8 } }

        Text { visible: !root.loading && root.currentDevice(); text: L10n.I18n.tr("Текущее устройство"); color: root.textPrimary; font.bold: true; font.pointSize: 10 }
        CurrentDeviceCard {
            visible: !root.loading && !!root.currentDevice(); device: root.currentDevice()
            operationBusy: root.currentDevice() ? !!root.busyIds[root.currentDevice().device_id] : false
            canVerifyWithOtherDevice: root.overview ? !!root.overview.has_other_verified_device : false
            accentColor: root.accentColor; surfaceColor: root.surfaceColor; elevatedColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary
            onVerifyRequested: root.requestVerification("")
            onRenameRequested: root.startRename(root.currentDevice())
            onCopyRequested: function(value) { root.commandRequested({ type: "copy_text", request_id: root.requestId("copy-current"), text: value }) }
        }
        Text { visible: root.verificationStatus !== ""; width: parent.width; wrapMode: Text.Wrap; text: root.verificationStatus; color: root.verificationStatus === L10n.I18n.tr("Запрос на подтверждение отправлен") ? root.accentColor : "#ff7777"; font.pointSize: 8 }

        Text { visible: !root.loading; text: L10n.I18n.tr("Другие устройства"); color: root.textPrimary; font.bold: true; font.pointSize: 10 }
        DeviceFilters { visible: !root.loading; width: parent.width; query: root.query; filter: root.filter; accentColor: root.accentColor; elevatedColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; onQueryEdited: function(value) { root.query = value }; onFilterSelected: function(value) { root.filter = value } }

        Rectangle {
            visible: root.selectedCount() > 0; width: parent.width; height: 44; radius: 8; color: root.elevatedColor
            Row { anchors.fill: parent; anchors.margins: 7; spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - bulkLogout.width - 10; text: root.selectedCount() + " " + L10n.I18n.tr("выбрано"); color: root.textPrimary; font.pointSize: 9; font.bold: true }
                SettingsActionButton { id: bulkLogout; height: 30; destructive: true; accentColor: root.accentColor; surfaceColor: root.surfaceColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Выйти на устройствах"); onClicked: root.requestDelete(Object.keys(root.selectedIds)) }
            }
        }

        Repeater {
            model: root.otherDevices()
            delegate: DeviceRow {
                required property var modelData
                device: modelData; selected: !!root.selectedIds[modelData.device_id]; operationBusy: !!root.busyIds[modelData.device_id]
                accentColor: root.accentColor; surfaceColor: root.surfaceColor; elevatedColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary
                onSelectionToggled: root.toggleSelected(modelData.device_id)
                onVerifyRequested: root.requestVerification(modelData.device_id)
                onRenameRequested: root.startRename(modelData)
                onSignOutRequested: root.requestDelete([modelData.device_id])
                onCopyRequested: function(value) { root.commandRequested({ type: "copy_text", request_id: root.requestId("copy"), text: value }) }
            }
        }
        Text { visible: !root.loading && root.otherDevices().length === 0; text: root.devices.length <= 1 ? L10n.I18n.tr("Других устройств нет") : L10n.I18n.tr("По этому фильтру ничего не найдено"); color: root.textSecondary; font.pointSize: 8 }
    }

    SettingsModalDialog {
        id: renameDialog; objectName: "renameDialog"; preferredContentWidth: 360; property var device: null; parent: Overlay.overlay; anchors.centerIn: parent; modal: true; title: L10n.I18n.tr("Переименовать устройство"); standardButtons: Dialog.Ok | Dialog.Cancel
        contentItem: Basic.TextField { id: renameField; implicitWidth: 360; implicitHeight: 38; color: root.textPrimary; selectByMouse: true; background: Rectangle { radius: 8; color: root.elevatedColor; border.width: 1; border.color: renameField.activeFocus ? root.accentColor : root.textSecondary } }
        onAccepted: { var name = renameField.text.trim(); if (!device || name === "") return; root.pendingRename = { device_id: device.device_id, old_name: device.display_name || "" }; var changed = root.devices.slice(); for (var i = 0; i < changed.length; i++) if (changed[i].device_id === device.device_id) changed[i] = Object.assign({}, changed[i], { display_name: name }); root.devices = changed; root.setBusy([device.device_id], true); root.commandRequested({ type: "rename_matrix_device", request_id: root.requestId("rename"), device_id: device.device_id, display_name: name }) }
    }
    SettingsModalDialog {
        id: deleteConfirmDialog; objectName: "deleteConfirmDialog"; parent: Overlay.overlay; anchors.centerIn: parent; modal: true; title: root.deleteTargetIds.length > 1 ? L10n.I18n.tr("Выйти на выбранных устройствах?") : L10n.I18n.tr("Выйти на устройстве?"); standardButtons: Dialog.Ok | Dialog.Cancel
        preferredContentWidth: 398
        contentItem: Text { width: deleteConfirmDialog.contentWidth; wrapMode: Text.Wrap; text: L10n.I18n.tr("Сессия потеряет доступ к аккаунту. Локальные данные на удалённом устройстве физически удалить невозможно — PrismChat отзывает его Matrix-сессию на сервере."); color: root.textPrimary; font.pointSize: 8 }
        onAccepted: { root.setBusy(root.deleteTargetIds, true); root.commandRequested({ type: "delete_matrix_devices", request_id: root.requestId("delete"), device_ids: root.deleteTargetIds }) }
    }
    SettingsModalDialog {
        id: deleteAuthDialog; objectName: "deleteAuthDialog"; preferredContentWidth: 360; parent: Overlay.overlay; anchors.centerIn: parent; modal: true; title: L10n.I18n.tr("Подтвердите выход"); standardButtons: Dialog.Ok | Dialog.Cancel
        contentItem: Basic.TextField { id: deletePassword; implicitWidth: 360; implicitHeight: 38; echoMode: TextInput.Password; placeholderText: L10n.I18n.tr("Пароль Matrix"); color: root.textPrimary; selectByMouse: true; background: Rectangle { radius: 8; color: root.elevatedColor } }
        onAccepted: { var password = deletePassword.text; deletePassword.clear(); root.commandRequested({ type: "submit_device_delete_uiaa", request_id: root.requestId("delete-uiaa"), operation_id: root.deleteOperationId, auth_type: "m.login.password", password: password }) }
        onRejected: { deletePassword.clear(); root.setBusy(root.deleteTargetIds, false) }
    }
    SettingsModalDialog {
        id: deleteWebDialog; objectName: "deleteWebDialog"
        property bool refreshOnClose: false
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        preferredContentWidth: 418
        title: L10n.I18n.tr("Завершите выход в браузере")
        standardButtons: Dialog.NoButton
        onOpened: refreshOnClose = false
        onClosed: {
            root.setBusy(root.deleteTargetIds, false)
            if (refreshOnClose)
                root.refreshRequested()
        }
        contentItem: Column {
            width: deleteWebDialog.contentWidth
            spacing: 12
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: root.deleteTargetIds.length > 1
                    ? L10n.I18n.tr("Сервер открыл web-страницу устройств. Завершите выбранные сессии там, затем обновите список.")
                    : L10n.I18n.tr("Сервер открыл защищённую страницу завершения этой сессии. После подтверждения вернитесь в PrismChat.")
                color: root.textPrimary
                font.pointSize: 8
            }
            Row {
                spacing: 8
                SettingsActionButton {
                    accentColor: root.accentColor
                    surfaceColor: root.elevatedColor
                    textPrimary: root.textPrimary
                    textSecondary: root.textSecondary
                    text: L10n.I18n.tr("Открыть снова")
                    onClicked: Qt.openUrlExternally(root.deleteWebUrl)
                }
                SettingsActionButton {
                    primary: true
                    accentColor: root.accentColor
                    surfaceColor: root.elevatedColor
                    textPrimary: root.textPrimary
                    textSecondary: root.textSecondary
                    text: L10n.I18n.tr("Обновить список")
                    onClicked: {
                        deleteWebDialog.refreshOnClose = true
                        deleteWebDialog.close()
                    }
                }
            }
        }
    }
}
