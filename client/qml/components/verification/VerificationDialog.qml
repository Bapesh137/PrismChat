import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../settings"
import "../common"
import "../../utils" as L10n
import "../../assets/icons" as Icons

Basic.Dialog {
    id: root
    property var update: null
    property color accentColor: "#20D500"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property bool dismissalSent: false
    readonly property bool failedState: root.update
        && (root.update.state === "cancelled" || root.update.state === "error")
    readonly property color statusColor: failedState ? "#ff7777" : accentColor
    readonly property bool terminalState: root.update
        && (root.update.state === "done" || root.update.state === "cancelled"
            || root.update.state === "error")
    signal actionRequested(string flowId, string action)
    signal dismissalRequested(string flowId)

    parent: Overlay.overlay; anchors.centerIn: parent; modal: true
    width: Math.min(460, parent ? parent.width - 32 : 460)
    padding: 24
    topPadding: 18
    dim: true
    closePolicy: Popup.CloseOnEscape
    background: Rectangle {
        radius: 18
        color: root.surfaceColor
        border.width: 1
        border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.22)
    }
    Overlay.modal: Rectangle { color: "#99000000" }
    header: Item {
        implicitHeight: 64
        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 24
            anchors.rightMargin: 66
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            Rectangle {
                width: 32; height: 32; radius: 10
                color: Qt.rgba(root.statusColor.r, root.statusColor.g, root.statusColor.b, 0.12)
                Icons.CheckIcon {
                    anchors.centerIn: parent
                    visible: !root.failedState
                    width: 20; height: 20
                    color: root.statusColor
                    capStyle: "butt"
                }
                Icons.CloseIcon {
                    anchors.centerIn: parent
                    visible: root.failedState
                    width: 24; height: 24
                    color: root.statusColor
                    strokeWidth: 2
                    capStyle: "butt"
                }
            }
            Text {
                width: Math.max(0, parent.width - 44)
                anchors.verticalCenter: parent.verticalCenter
                text: root.title
                color: root.textPrimary
                font.pointSize: 10
                font.bold: true
                elide: Text.ElideRight
            }
        }
        PopupCloseButton {
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            accentColor: root.accentColor
            textPrimary: root.textPrimary
            textSecondary: root.textSecondary
            onClicked: root.close()
        }
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 24; anchors.rightMargin: 24
            height: 1
            color: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.14)
        }
    }
    footer: Item { implicitHeight: 0 }
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: L10n.UiPreferences.duration(140) }
            NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: L10n.UiPreferences.duration(160); easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: L10n.UiPreferences.duration(100) }
    }
    title: L10n.I18n.tr("Подтверждение устройства")
    standardButtons: Dialog.NoButton
    onOpened: dismissalSent = false
    onClosed: {
        if (!root.terminalState && !root.dismissalSent
                && root.update && root.update.flow_id) {
            root.dismissalSent = true
            root.dismissalRequested(root.update.flow_id)
            root.actionRequested(root.update.flow_id, "cancel")
        }
    }

    contentItem: Item {
        implicitWidth: 390
        implicitHeight: content.implicitHeight
        Column {
            id: content; width: parent.width; spacing: 12
            Column {
                visible: root.update && (root.update.state === "requested" || root.update.state === "ready" || root.update.state === "sas_waiting")
                width: parent.width; spacing: 10
                Text { text: root.update && root.update.direction === "incoming" ? L10n.I18n.tr("Запрос подтверждения устройства") : L10n.I18n.tr("Проверка устройства"); color: root.textPrimary; font.pointSize: 12; font.bold: true }
                Text { visible: root.update && !!root.update.device_name; width: parent.width; elide: Text.ElideRight; text: root.update ? root.update.device_name || "" : ""; color: root.textPrimary; font.pointSize: 9; font.bold: true }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: root.update && root.update.direction === "incoming"
                            && root.update.state === "requested"
                        ? (root.update.device_id
                            ? L10n.I18n.tr("Другое ваше устройство хочет подтвердить эту сессию. Device ID: ") + root.update.device_id
                            : L10n.I18n.tr("Другое ваше устройство хочет подтвердить эту сессию."))
                        : root.update && (root.update.state === "ready"
                                          || root.update.state === "sas_waiting")
                            ? L10n.I18n.tr("Подготовка проверки… Ожидаем второе устройство.")
                            : L10n.I18n.tr("Ожидаем подтверждения на втором устройстве…")
                    color: root.textSecondary
                    font.pointSize: 8
                }
                PrismBusyIndicator {
                    visible: root.update && (root.update.state === "ready"
                        || root.update.state === "sas_waiting"
                        || (root.update.state === "requested"
                            && root.update.direction !== "incoming"))
                    running: visible
                    width: 20
                    height: 20
                    strokeWidth: 2
                    accentColor: root.accentColor
                }
                Row {
                    spacing: 8
                    SettingsActionButton { destructive: true; accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: root.update && root.update.direction === "incoming" && root.update.state === "requested" ? L10n.I18n.tr("Отклонить") : L10n.I18n.tr("Отмена"); onClicked: root.close() }
                    SettingsActionButton { visible: root.update && root.update.direction === "incoming" && root.update.state === "requested"; primary: true; accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Начать проверку"); onClicked: root.actionRequested(root.update.flow_id, "accept") }
                }
            }
            SasVerificationPage {
                visible: root.update && root.update.state === "sas"
                width: parent.width
                emojis: root.update ? root.update.emoji || [] : []
                emojiDescriptions: root.update ? root.update.emoji_descriptions || [] : []
                decimals: root.update ? root.update.decimals || [] : []
                accentColor: root.accentColor; elevatedColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary
                onConfirmed: root.actionRequested(root.update.flow_id, "confirm")
                onMismatched: root.actionRequested(root.update.flow_id, "mismatch")
            }
            VerificationSuccessPage {
                visible: root.update && root.update.state === "done"
                width: parent.width
                accentColor: root.accentColor; elevatedColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary
                onDone: root.close()
            }
            Column {
                visible: root.update && (root.update.state === "cancelled" || root.update.state === "error")
                width: parent.width; spacing: 10
                Text { text: L10n.I18n.tr("Подтверждение завершено"); color: root.textPrimary; font.pointSize: 12; font.bold: true }
                Text { width: parent.width; wrapMode: Text.Wrap; text: root.update ? root.update.error || L10n.I18n.tr("Запрос был отменён") : ""; color: "#ff7777"; font.pointSize: 8 }
                SettingsActionButton { accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Закрыть"); onClicked: root.close() }
            }
        }
    }
}
