import QtQuick
import QtQuick.Controls.Basic as Basic
import "../../utils" as L10n

Column {
    id: root
    property var device: null
    property bool advanced: false
    property color accentColor: "#20D500"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    signal copyRequested(string text)
    spacing: 7

    function row(label, value) { return label + ":  " + (value || L10n.I18n.tr("Нет данных")) }

    Text { text: root.row(L10n.I18n.tr("Название"), root.device ? root.device.display_name : ""); color: root.textSecondary; font.pointSize: 8 }
    Row {
        spacing: 6
        Basic.TextField {
            readOnly: true; selectByMouse: true
            text: root.row(L10n.I18n.tr("ID устройства"), root.device ? root.device.device_id : "")
            color: root.textSecondary; font.family: "monospace"; font.pointSize: 8
            background: null; padding: 0; implicitHeight: 20
        }
        Text { text: L10n.I18n.tr("Копировать"); color: root.accentColor; font.pointSize: 8; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.device) root.copyRequested(root.device.device_id) } }
    }
    Text { visible: root.device && root.device.first_seen_ts; text: root.row(L10n.I18n.tr("Дата появления"), root.device ? new Date(Number(root.device.first_seen_ts)).toLocaleString(Qt.locale()) : ""); color: root.textSecondary; font.pointSize: 8 }
    Text { visible: root.device && root.device.last_seen_ts; text: root.row(L10n.I18n.tr("Последняя активность"), root.device ? new Date(Number(root.device.last_seen_ts)).toLocaleString(Qt.locale()) : ""); color: root.textSecondary; font.pointSize: 8 }
    Text { text: root.advanced ? L10n.I18n.tr("Скрыть технические сведения") : L10n.I18n.tr("Технические сведения"); color: root.accentColor; font.pointSize: 8; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.advanced = !root.advanced } }
    Column {
        visible: root.advanced; spacing: 5
        Text { text: L10n.I18n.tr("Перекрёстная подпись: ") + (root.device && root.device.cross_signed ? L10n.I18n.tr("да") : L10n.I18n.tr("нет")); color: root.textSecondary; font.pointSize: 8 }
        Text { visible: root.device && root.device.is_dehydrated !== null && root.device.is_dehydrated !== undefined; text: L10n.I18n.tr("Dehydrated-сессия: ") + (root.device && root.device.is_dehydrated ? L10n.I18n.tr("да") : L10n.I18n.tr("нет")); color: root.textSecondary; font.pointSize: 8 }
        Row {
            visible: root.device && !!root.device.ed25519_fingerprint; spacing: 6
            Basic.TextField { width: 420; readOnly: true; selectByMouse: true; text: "Ed25519: " + (root.device ? root.device.ed25519_fingerprint || "" : ""); color: root.textSecondary; font.family: "monospace"; font.pointSize: 8; background: null; padding: 0; implicitHeight: 20 }
            Text { text: L10n.I18n.tr("Копировать"); color: root.accentColor; font.pointSize: 8; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.device) root.copyRequested(root.device.ed25519_fingerprint) } }
        }
    }
}
