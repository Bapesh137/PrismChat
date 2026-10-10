import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "../../components/common"
import "../../utils" as L10n
import "../../utils/PrismUtils.js" as Utils

Flickable {
    id: root

    property double sqliteBytes: 0
    property double eventCacheBytes: 0
    property double mediaBytes: 0
    property double totalCacheBytes: 0
    property int autoCleanupDays: 0
    property int cacheLimitMb: 1024
    property string downloadsDirectory: ""
    property bool autoLoadImages: true
    property bool autoLoadVideos: true
    property bool busy: false
    property string statusText: ""
    property bool statusError: false

    property color accentColor: "#20D500"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"

    signal refreshRequested()
    signal clearCacheRequested(bool clearMedia, bool clearEventCache, bool clearSqlite)
    signal preferencesChanged(int autoCleanupDays, int cacheLimitMb,
                              string downloadsDirectory,
                              bool autoLoadImages, bool autoLoadVideos)
    signal clearTemporaryDataRequested()
    signal exportDiagnosticsRequested(string path)

    function formatBytes(value) {
        var bytes = Math.max(0, Number(value || 0))
        if (bytes < 1024) return Math.round(bytes) + " B"
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
        if (bytes < 1024 * 1024 * 1024)
            return (bytes / (1024 * 1024)).toFixed(1) + " MB"
        return (bytes / (1024 * 1024 * 1024)).toFixed(2) + " GB"
    }

    function blendedColor(base, overlay, amount) {
        var ratio = Math.max(0, Math.min(1, Number(amount || 0)))
        return Qt.rgba(base.r + (overlay.r - base.r) * ratio,
                       base.g + (overlay.g - base.g) * ratio,
                       base.b + (overlay.b - base.b) * ratio, 1)
    }

    onAutoCleanupDaysChanged: Qt.callLater(function() {
        if (daysBox.value !== root.autoCleanupDays)
            daysBox.value = root.autoCleanupDays
    })
    onCacheLimitMbChanged: Qt.callLater(function() {
        if (limitBox.value !== root.cacheLimitMb)
            limitBox.value = root.cacheLimitMb
    })
    onAutoLoadImagesChanged: Qt.callLater(function() {
        if (imageAutoSwitch.checked !== root.autoLoadImages)
            imageAutoSwitch.checked = root.autoLoadImages
    })
    onAutoLoadVideosChanged: Qt.callLater(function() {
        if (videoAutoSwitch.checked !== root.autoLoadVideos)
            videoAutoSwitch.checked = root.autoLoadVideos
    })

    clip: true
    contentWidth: width
    contentHeight: contentColumn.implicitHeight + 8

    Column {
        id: contentColumn
        width: root.width
        spacing: 12

        RowLayout {
            width: parent.width
            Text {
                Layout.fillWidth: true
                text: L10n.I18n.tr("Хранилище")
                color: root.textPrimary
                font.bold: true
                font.pointSize: 13
            }
            Basic.Button {
                id: refreshButton
                enabled: !root.busy
                implicitWidth: 92
                implicitHeight: 30
                hoverEnabled: true
                scale: down ? 0.94 : 1
                onClicked: root.refreshRequested()
                background: Rectangle {
                    radius: 8
                    color: refreshButton.down
                        ? root.blendedColor(root.elevatedColor, root.accentColor, 0.18)
                        : refreshButton.hovered
                            ? root.blendedColor(root.elevatedColor, root.textPrimary, 0.08)
                            : root.elevatedColor
                    border.width: 1
                    border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                          root.textSecondary.b, 0.16)
                    Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                }
                contentItem: Text {
                    text: L10n.I18n.tr("Обновить")
                    color: root.textPrimary
                    font.pointSize: 8
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(95); easing.type: Easing.OutCubic } }
            }
        }

        Rectangle {
            width: parent.width
            implicitHeight: sizeColumn.implicitHeight + 24
            radius: 10
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                  root.textSecondary.b, 0.12)
            Column {
                id: sizeColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 9
                Text { text: L10n.I18n.tr("Использование диска"); color: root.textPrimary; font.bold: true; font.pointSize: 10 }
                RowLayout {
                    width: parent.width
                    Text { Layout.fillWidth: true; text: L10n.I18n.tr("SQLite"); color: root.textSecondary; font.pointSize: 8 }
                    Text { text: root.formatBytes(root.sqliteBytes); color: root.textPrimary; font.bold: true; font.pointSize: 8 }
                }
                RowLayout {
                    width: parent.width
                    Text { Layout.fillWidth: true; text: L10n.I18n.tr("Event cache"); color: root.textSecondary; font.pointSize: 8 }
                    Text { text: root.formatBytes(root.eventCacheBytes); color: root.textPrimary; font.bold: true; font.pointSize: 8 }
                }
                RowLayout {
                    width: parent.width
                    Text { Layout.fillWidth: true; text: L10n.I18n.tr("Media cache"); color: root.textSecondary; font.pointSize: 8 }
                    Text { text: root.formatBytes(root.mediaBytes); color: root.textPrimary; font.bold: true; font.pointSize: 8 }
                }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.dividerColor.r, root.dividerColor.g, root.dividerColor.b, 0.65) }
                RowLayout {
                    width: parent.width
                    Text { Layout.fillWidth: true; text: L10n.I18n.tr("Всего занято"); color: root.textPrimary; font.pointSize: 9 }
                    Text { text: root.formatBytes(root.totalCacheBytes); color: root.accentColor; font.bold: true; font.pointSize: 9 }
                }
                Basic.Button {
                    id: clearCacheButton
                    width: parent.width
                    height: 34
                    enabled: !root.busy
                    hoverEnabled: true
                    scale: down ? 0.98 : 1
                    onClicked: clearCacheDialog.open()
                    background: Rectangle {
                        radius: 8
                        color: clearCacheButton.down
                            ? root.blendedColor(root.elevatedColor, root.accentColor, 0.20)
                            : clearCacheButton.hovered
                                ? root.blendedColor(root.elevatedColor, root.accentColor, 0.09)
                                : root.elevatedColor
                        border.width: 1
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                              root.accentColor.b, 0.42)
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                    }
                    contentItem: Text {
                        text: L10n.I18n.tr("Выбрать данные для очистки")
                        color: root.textPrimary
                        font.pointSize: 9
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(95); easing.type: Easing.OutCubic } }
                }
            }
        }

        Rectangle {
            width: parent.width
            implicitHeight: policyColumn.implicitHeight + 24
            radius: 10
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                  root.textSecondary.b, 0.12)
            Column {
                id: policyColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10
                Text { text: L10n.I18n.tr("Автоматическая очистка"); color: root.textPrimary; font.bold: true; font.pointSize: 10 }
                Text {
                    width: parent.width
                    text: L10n.I18n.tr("Значение 0 отключает автоматическую очистку.")
                    color: root.textSecondary
                    font.pointSize: 8
                    wrapMode: Text.Wrap
                }
                Text {
                    width: parent.width
                    text: L10n.I18n.tr("Автоочистка и лимит применяются только к media cache.")
                    color: root.textSecondary
                    opacity: 0.76
                    font.pointSize: 7
                    wrapMode: Text.Wrap
                }
                RowLayout {
                    width: parent.width
                    Text { Layout.fillWidth: true; text: L10n.I18n.tr("Удалять файлы старше, дней"); color: root.textPrimary; font.pointSize: 8 }
                    Basic.SpinBox {
                        id: daysBox
                        from: 0
                        to: 3650
                        value: root.autoCleanupDays
                        editable: true
                        enabled: !root.busy
                        hoverEnabled: true
                        implicitWidth: 112
                        implicitHeight: 32
                        onValueModified: root.preferencesChanged(
                            value, root.cacheLimitMb, root.downloadsDirectory,
                            root.autoLoadImages, root.autoLoadVideos)
                        contentItem: TextInput {
                            text: daysBox.textFromValue(daysBox.value, daysBox.locale)
                            color: root.textPrimary
                            selectionColor: root.accentColor
                            selectedTextColor: "white"
                            leftPadding: 8
                            rightPadding: 32
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: daysBox.validator
                        }
                        up.indicator: Rectangle {
                            x: daysBox.width - width
                            y: 0
                            width: 28
                            height: daysBox.height / 2
                            radius: 7
                            color: daysBox.up.pressed
                                ? root.blendedColor(root.elevatedColor, root.accentColor, 0.22)
                                : daysBox.up.hovered
                                    ? root.blendedColor(root.elevatedColor, root.textPrimary, 0.09)
                                    : "transparent"
                            Text { anchors.centerIn: parent; text: "+"; color: root.textPrimary; font.pointSize: 8 }
                            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                        }
                        down.indicator: Rectangle {
                            x: daysBox.width - width
                            y: daysBox.height / 2
                            width: 28
                            height: daysBox.height / 2
                            radius: 7
                            color: daysBox.down.pressed
                                ? root.blendedColor(root.elevatedColor, root.accentColor, 0.22)
                                : daysBox.down.hovered
                                    ? root.blendedColor(root.elevatedColor, root.textPrimary, 0.09)
                                    : "transparent"
                            Text { anchors.centerIn: parent; text: "−"; color: root.textPrimary; font.pointSize: 8 }
                            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                        }
                        background: Rectangle {
                            radius: 8
                            color: root.elevatedColor
                            border.width: 1
                            border.color: daysBox.activeFocus
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.7)
                                : Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.18)
                            Behavior on border.color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                        }
                    }
                }
                RowLayout {
                    width: parent.width
                    Text { Layout.fillWidth: true; text: L10n.I18n.tr("Лимит кэша, МБ"); color: root.textPrimary; font.pointSize: 8 }
                    Basic.SpinBox {
                        id: limitBox
                        from: 64
                        to: 1048576
                        stepSize: 64
                        value: root.cacheLimitMb
                        editable: true
                        enabled: !root.busy
                        hoverEnabled: true
                        implicitWidth: 112
                        implicitHeight: 32
                        onValueModified: root.preferencesChanged(
                            root.autoCleanupDays, value, root.downloadsDirectory,
                            root.autoLoadImages, root.autoLoadVideos)
                        contentItem: TextInput {
                            text: limitBox.textFromValue(limitBox.value, limitBox.locale)
                            color: root.textPrimary
                            selectionColor: root.accentColor
                            selectedTextColor: "white"
                            leftPadding: 8
                            rightPadding: 32
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: limitBox.validator
                        }
                        up.indicator: Rectangle {
                            x: limitBox.width - width
                            y: 0
                            width: 28
                            height: limitBox.height / 2
                            radius: 7
                            color: limitBox.up.pressed
                                ? root.blendedColor(root.elevatedColor, root.accentColor, 0.22)
                                : limitBox.up.hovered
                                    ? root.blendedColor(root.elevatedColor, root.textPrimary, 0.09)
                                    : "transparent"
                            Text { anchors.centerIn: parent; text: "+"; color: root.textPrimary; font.pointSize: 8 }
                            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                        }
                        down.indicator: Rectangle {
                            x: limitBox.width - width
                            y: limitBox.height / 2
                            width: 28
                            height: limitBox.height / 2
                            radius: 7
                            color: limitBox.down.pressed
                                ? root.blendedColor(root.elevatedColor, root.accentColor, 0.22)
                                : limitBox.down.hovered
                                    ? root.blendedColor(root.elevatedColor, root.textPrimary, 0.09)
                                    : "transparent"
                            Text { anchors.centerIn: parent; text: "−"; color: root.textPrimary; font.pointSize: 8 }
                            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                        }
                        background: Rectangle {
                            radius: 8
                            color: root.elevatedColor
                            border.width: 1
                            border.color: limitBox.activeFocus
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.7)
                                : Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.18)
                            Behavior on border.color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            implicitHeight: downloadColumn.implicitHeight + 24
            radius: 10
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                  root.textSecondary.b, 0.12)
            Column {
                id: downloadColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10
                Text { text: L10n.I18n.tr("Загрузки и медиа"); color: root.textPrimary; font.bold: true; font.pointSize: 10 }
                Text { width: parent.width; text: L10n.I18n.tr("Папка загрузок"); color: root.textSecondary; font.pointSize: 8 }
                RowLayout {
                    width: parent.width
                    Rectangle {
                        Layout.fillWidth: true
                        height: 34
                        radius: 8
                        color: root.elevatedColor
                        border.width: 1
                        border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                              root.textSecondary.b, 0.16)
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            text: root.downloadsDirectory !== "" ? root.downloadsDirectory : "—"
                            color: root.textPrimary
                            font.pointSize: 8
                            elide: Text.ElideMiddle
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Basic.Button {
                        id: folderButton
                        implicitWidth: 94
                        implicitHeight: 34
                        enabled: !root.busy
                        hoverEnabled: true
                        scale: down ? 0.94 : 1
                        onClicked: downloadsFolderDialog.open()
                        background: Rectangle {
                            radius: 8
                            color: folderButton.down
                                ? root.blendedColor(root.elevatedColor, root.accentColor, 0.18)
                                : folderButton.hovered
                                    ? root.blendedColor(root.elevatedColor, root.textPrimary, 0.08)
                                    : root.elevatedColor
                            border.width: 1
                            border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                                  root.textSecondary.b, 0.16)
                            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                        }
                        contentItem: Text { text: L10n.I18n.tr("Выбрать"); color: root.textPrimary; font.pointSize: 8; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(95); easing.type: Easing.OutCubic } }
                    }
                }
                RowLayout {
                    width: parent.width
                    Text { Layout.fillWidth: true; text: L10n.I18n.tr("Автозагрузка изображений"); color: root.textPrimary; font.pointSize: 8 }
                    StyledSwitch {
                        id: imageAutoSwitch
                        checked: root.autoLoadImages
                        enabled: !root.busy
                        accentColor: root.accentColor
                        inactiveColor: root.textSecondary
                        onToggled: root.preferencesChanged(
                            root.autoCleanupDays, root.cacheLimitMb,
                            root.downloadsDirectory, checked, root.autoLoadVideos)
                    }
                }
                RowLayout {
                    width: parent.width
                    Text { Layout.fillWidth: true; text: L10n.I18n.tr("Автозагрузка видео"); color: root.textPrimary; font.pointSize: 8 }
                    StyledSwitch {
                        id: videoAutoSwitch
                        checked: root.autoLoadVideos
                        enabled: !root.busy
                        accentColor: root.accentColor
                        inactiveColor: root.textSecondary
                        onToggled: root.preferencesChanged(
                            root.autoCleanupDays, root.cacheLimitMb,
                            root.downloadsDirectory, root.autoLoadImages, checked)
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            implicitHeight: maintenanceColumn.implicitHeight + 24
            radius: 10
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                  root.textSecondary.b, 0.12)
            Column {
                id: maintenanceColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 9
                Text { text: L10n.I18n.tr("Обслуживание"); color: root.textPrimary; font.bold: true; font.pointSize: 10 }
                Basic.Button {
                    id: clearTempButton
                    width: parent.width
                    height: 34
                    enabled: !root.busy
                    hoverEnabled: true
                    scale: down ? 0.98 : 1
                    onClicked: root.clearTemporaryDataRequested()
                    background: Rectangle {
                        radius: 8
                        color: clearTempButton.down
                            ? root.blendedColor(root.elevatedColor, root.accentColor, 0.18)
                            : clearTempButton.hovered
                                ? root.blendedColor(root.elevatedColor, root.textPrimary, 0.08)
                                : root.elevatedColor
                        border.width: 1
                        border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                              root.textSecondary.b, 0.16)
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                    }
                    contentItem: Text { text: L10n.I18n.tr("Очистить черновики и временные голосовые"); color: root.textPrimary; font.pointSize: 8; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(95); easing.type: Easing.OutCubic } }
                }
                Basic.Button {
                    id: diagnosticsButton
                    width: parent.width
                    height: 34
                    enabled: !root.busy
                    hoverEnabled: true
                    scale: down ? 0.98 : 1
                    onClicked: diagnosticsDialog.open()
                    background: Rectangle {
                        radius: 8
                        color: diagnosticsButton.down
                            ? root.blendedColor(root.elevatedColor, root.accentColor, 0.18)
                            : diagnosticsButton.hovered
                                ? root.blendedColor(root.elevatedColor, root.textPrimary, 0.08)
                                : root.elevatedColor
                        border.width: 1
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                              root.accentColor.b, 0.34)
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                    }
                    contentItem: Text { text: L10n.I18n.tr("Экспортировать диагностический отчёт"); color: root.textPrimary; font.pointSize: 8; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(95); easing.type: Easing.OutCubic } }
                }
                Text {
                    width: parent.width
                    text: L10n.I18n.tr("Отчёт не содержит токены, пароли, ключи комнат и тексты сообщений.")
                    color: root.textSecondary
                    font.pointSize: 7
                    wrapMode: Text.Wrap
                }
            }
        }

        Row {
            visible: root.busy || root.statusText !== ""
            width: parent.width
            spacing: 8
            PrismBusyIndicator { visible: root.busy; running: visible; width: 18; height: 18; accentColor: root.accentColor }
            Text {
                width: parent.width - (root.busy ? 26 : 0)
                text: root.statusText
                color: root.statusError ? "#ff6b6b" : root.textSecondary
                font.pointSize: 8
                wrapMode: Text.Wrap
            }
        }
    }

    Dialog {
        id: clearCacheDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(430, root.width - 24)
        modal: true
        closePolicy: Popup.CloseOnEscape
        padding: 18

        onOpened: {
            clearMediaSwitch.checked = true
            clearEventSwitch.checked = false
            clearSqliteSwitch.checked = false
        }

        background: Rectangle {
            radius: 12
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                  root.dividerColor.b, 0.8)
        }

        contentItem: Column {
            spacing: 12

            Text {
                width: parent.width
                text: L10n.I18n.tr("Выберите данные для очистки")
                color: root.textPrimary
                font.bold: true
                font.pointSize: 12
            }

            RowLayout {
                width: parent.width
                Text { Layout.fillWidth: true; text: L10n.I18n.tr("Media cache"); color: root.textPrimary; font.pointSize: 9 }
                StyledSwitch {
                    id: clearMediaSwitch
                    checked: true
                    accentColor: root.accentColor
                    inactiveColor: root.textSecondary
                }
            }
            RowLayout {
                width: parent.width
                Text { Layout.fillWidth: true; text: L10n.I18n.tr("Event cache"); color: root.textPrimary; font.pointSize: 9 }
                StyledSwitch {
                    id: clearEventSwitch
                    accentColor: root.accentColor
                    inactiveColor: root.textSecondary
                }
            }
            RowLayout {
                width: parent.width
                Text { Layout.fillWidth: true; text: L10n.I18n.tr("SQLite"); color: root.textPrimary; font.pointSize: 9 }
                StyledSwitch {
                    id: clearSqliteSwitch
                    accentColor: root.accentColor
                    inactiveColor: root.textSecondary
                }
            }

            Text {
                width: parent.width
                visible: clearEventSwitch.checked || clearSqliteSwitch.checked
                text: L10n.I18n.tr("SQLite и event cache очищаются при следующем запуске приложения.")
                color: root.textSecondary
                font.pointSize: 8
                wrapMode: Text.Wrap
            }
            Text {
                width: parent.width
                visible: clearSqliteSwitch.checked
                text: L10n.I18n.tr("Внимание: SQLite содержит локальное состояние и ключи шифрования. После очистки для старых зашифрованных сообщений может потребоваться восстановление ключей.")
                color: "#ffb86b"
                font.pointSize: 8
                wrapMode: Text.Wrap
            }

            RowLayout {
                width: parent.width
                Item { Layout.fillWidth: true }
                Basic.Button {
                    id: cancelClearButton
                    implicitWidth: 92
                    implicitHeight: 32
                    hoverEnabled: true
                    scale: down ? 0.95 : 1
                    onClicked: clearCacheDialog.close()
                    background: Rectangle {
                        radius: 8
                        color: cancelClearButton.down
                            ? root.blendedColor(root.elevatedColor, root.textPrimary, 0.14)
                            : cancelClearButton.hovered
                                ? root.blendedColor(root.elevatedColor, root.textPrimary, 0.08)
                                : root.elevatedColor
                        border.width: 1
                        border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.16)
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                    }
                    contentItem: Text {
                        text: L10n.I18n.tr("Отмена")
                        color: root.textPrimary
                        font.pointSize: 8
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(95); easing.type: Easing.OutCubic } }
                }
                Basic.Button {
                    id: confirmClearButton
                    implicitWidth: 142
                    implicitHeight: 32
                    enabled: clearMediaSwitch.checked || clearEventSwitch.checked || clearSqliteSwitch.checked
                    hoverEnabled: true
                    scale: down ? 0.95 : 1
                    onClicked: {
                        root.clearCacheRequested(clearMediaSwitch.checked,
                                                 clearEventSwitch.checked,
                                                 clearSqliteSwitch.checked)
                        clearCacheDialog.close()
                    }
                    background: Rectangle {
                        radius: 8
                        color: !confirmClearButton.enabled
                            ? root.elevatedColor
                            : confirmClearButton.down
                                ? root.blendedColor(root.elevatedColor, root.accentColor, 0.24)
                                : confirmClearButton.hovered
                                    ? root.blendedColor(root.elevatedColor, root.accentColor, 0.12)
                                    : root.elevatedColor
                        border.width: 1
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b,
                                              confirmClearButton.enabled ? 0.48 : 0.18)
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                    }
                    contentItem: Text {
                        text: L10n.I18n.tr("Очистить выбранное")
                        color: confirmClearButton.enabled ? root.textPrimary : root.textSecondary
                        font.pointSize: 8
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(95); easing.type: Easing.OutCubic } }
                }
            }
        }
    }

    FolderDialog {
        id: downloadsFolderDialog
        title: L10n.I18n.tr("Выберите папку загрузок")
        onAccepted: {
            var selectedPath = Utils.localPath(selectedFolder)
            root.preferencesChanged(root.autoCleanupDays, root.cacheLimitMb,
                                    selectedPath,
                                    root.autoLoadImages, root.autoLoadVideos)
        }
    }

    FileDialog {
        id: diagnosticsDialog
        title: L10n.I18n.tr("Сохранить диагностический отчёт")
        fileMode: FileDialog.SaveFile
        nameFilters: [L10n.I18n.tr("JSON-файлы (*.json)")]
        defaultSuffix: "json"
        onAccepted: root.exportDiagnosticsRequested(Utils.localPath(selectedFile))
    }
}
