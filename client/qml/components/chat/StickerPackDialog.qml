import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "../common"
import "../../utils" as L10n
import "../../utils/PrismUtils.js" as Utils

Basic.Popup {
    id: root

    property color accentColor: "#20D500"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"
    property string mediaProxy: ""
    property string accountId: ""
    property var pack: null

    readonly property bool builtinPack: !!pack && !!pack.builtin
    readonly property bool installedPack: !!pack && !!L10n.StickerPackStore.packById(accountId, pack.id || "")
    readonly property var stickers: pack && pack.images ? pack.images : []
    readonly property string packName: pack
        ? String(pack.display_name || L10n.I18n.tr(pack.display_name_source || "Набор стикеров"))
        : L10n.I18n.tr("Набор стикеров")
    readonly property string emojiFontFamily: L10n.UiPreferences.emojiFontFamily

    signal installRequested(var pack)
    signal shareRequested(var pack)
    signal stickerChosen(var sticker)

    parent: Overlay.overlay
    width: Math.min(430, parent ? parent.width - 28 : 430)
    height: Math.min(500, parent ? parent.height - 36 : 500)
    x: parent ? Math.max(14, (parent.width - width) / 2) : 0
    y: parent ? Math.max(18, (parent.height - height) / 2) : 0
    modal: true
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function openFor(value) {
        root.pack = value || null
        if (root.pack)
            root.open()
    }

    function preview(sticker) {
        if (!sticker || !sticker.media_url)
            return ""
        return sticker.preview_url || Utils.proxyUrl(sticker.media_url, root.mediaProxy,
                                                     sticker.media_file || undefined,
                                                     sticker.media_mime_type || "image/webp")
    }

    function symbolUsesEmojiFont(symbol) {
        var value = String(symbol || "")
        return ["👍", "🔥", "🚀", "😂", "👋", "👏", "☕", "💡", "👎", "😍", "😎",
                "😡", "😭", "😴", "🤔", "⚡", "✨", "🎁", "🏆", "🍕", "🔔", "⛔"].indexOf(value) !== -1
    }

    function symbolOffsetX(symbol) {
        var value = String(symbol || "")
        if (value === "☕" || value === "♛") return -1
        if (value === "✓" || value === "✕" || value === "♪") return 1
        return 0
    }

    function symbolOffsetY(symbol) {
        var value = String(symbol || "")
        return ["♥", "★", "✓", "!", "☺", "✦", "○", "?", "♪", "☀", "☾", "♛", "☁", "☂", "▣"].indexOf(value) !== -1 ? -1 : 0
    }

    background: Rectangle {
        color: root.surfaceColor
        radius: 16
        border.width: 1
        border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g, root.dividerColor.b, 0.9)
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: L10n.UiPreferences.duration(130) }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: L10n.UiPreferences.duration(150); easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: L10n.UiPreferences.duration(100) }
            NumberAnimation { property: "scale"; from: 1; to: 0.98; duration: L10n.UiPreferences.duration(100); easing.type: Easing.InCubic }
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 58
            color: root.elevatedColor
            radius: 16
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 16
                color: parent.color
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 15
                anchors.right: actionRow.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    width: parent.width
                    text: root.packName
                    color: root.textPrimary
                    font.pointSize: 10.5
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: L10n.I18n.tr("Стикеров: ") + String(root.stickers.length)
                    color: root.textSecondary
                    font.pointSize: 7.5
                    elide: Text.ElideRight
                }
            }

            Row {
                id: actionRow
                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                Basic.Button {
                    id: shareButton
                    visible: !root.builtinPack && root.stickers.length > 0
                    width: 34
                    height: 34
                    padding: 0
                    hoverEnabled: true
                    scale: down ? 0.86 : 1
                    onClicked: root.shareRequested(root.pack)
                    contentItem: Text {
                        text: "↗"
                        color: shareButton.down || shareButton.hovered ? root.accentColor : root.textSecondary
                        font.pixelSize: 18
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 9
                        color: shareButton.down ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                            : shareButton.hovered ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                            : "transparent"
                    }
                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic } }
                    PrismToolTip {
                        visible: shareButton.hovered
                        text: L10n.I18n.tr("Поделиться набором")
                        surfaceColor: root.elevatedColor
                        textColor: root.textPrimary
                        dividerColor: root.dividerColor
                    }
                }

                Basic.Button {
                    id: closeButton
                    width: 34
                    height: 34
                    padding: 0
                    hoverEnabled: true
                    scale: down ? 0.86 : 1
                    onClicked: root.close()
                    contentItem: Item {
                        Rectangle { anchors.centerIn: parent; width: 13; height: 1.4; rotation: 45; color: closeButton.down || closeButton.hovered ? root.accentColor : root.textSecondary }
                        Rectangle { anchors.centerIn: parent; width: 13; height: 1.4; rotation: -45; color: closeButton.down || closeButton.hovered ? root.accentColor : root.textSecondary }
                    }
                    background: Rectangle {
                        radius: 9
                        color: closeButton.down ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                            : closeButton.hovered ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                            : "transparent"
                    }
                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic } }
                    PrismToolTip {
                        visible: closeButton.hovered
                        text: L10n.I18n.tr("Закрыть")
                        surfaceColor: root.elevatedColor
                        textColor: root.textPrimary
                        dividerColor: root.dividerColor
                    }
                }
            }
        }

        GridView {
            id: packGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 8
            clip: true
            model: root.stickers
            cellWidth: Math.max(86, width / 4)
            cellHeight: 88
            boundsBehavior: Flickable.StopAtBounds

            delegate: Basic.Button {
                id: stickerButton
                required property var modelData
                width: Math.min(82, packGrid.cellWidth - 4)
                height: 82
                x: Math.max(0, (packGrid.cellWidth - width) / 2)
                y: 3
                padding: 0
                hoverEnabled: true
                scale: down ? 0.90 : hovered ? 1.025 : 1
                onClicked: {
                    var item = Object.assign({}, modelData, {
                        pack_id: root.pack ? root.pack.id || "" : "",
                        pack_name: root.packName,
                        body: modelData.body || L10n.I18n.tr(modelData.body_source || "Стикер")
                    })
                    root.stickerChosen(item)
                    root.close()
                }

                contentItem: Item {
                    AnimatedImage {
                        anchors.fill: parent
                        anchors.margins: 6
                        visible: !stickerButton.modelData.builtin_id
                        source: root.preview(stickerButton.modelData)
                        fillMode: Image.PreserveAspectFit
                        horizontalAlignment: Image.AlignHCenter
                        verticalAlignment: Image.AlignVCenter
                        asynchronous: true
                        playing: visible
                    }
                    Text {
                        anchors.centerIn: parent
                        width: 66
                        height: 66
                        visible: !!stickerButton.modelData.builtin_id
                        text: stickerButton.modelData.symbol || "★"
                        color: stickerButton.modelData.color || root.accentColor
                        font.family: root.symbolUsesEmojiFont(stickerButton.modelData.symbol)
                            ? root.emojiFontFamily : "Sans Serif"
                        font.pixelSize: 45
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        anchors.horizontalCenterOffset: root.symbolOffsetX(stickerButton.modelData.symbol)
                        anchors.verticalCenterOffset: root.symbolOffsetY(stickerButton.modelData.symbol)
                    }
                }

                background: Rectangle {
                    radius: 12
                    color: stickerButton.down ? Qt.rgba(0, 0, 0, 0.26)
                        : stickerButton.hovered ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.075)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                }
                Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(95); easing.type: Easing.OutCubic } }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.builtinPack || root.installedPack ? 48 : 62
            color: root.elevatedColor
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: Qt.rgba(root.dividerColor.r, root.dividerColor.g, root.dividerColor.b, 0.7)
            }

            Basic.Button {
                id: installButton
                visible: !root.builtinPack && !root.installedPack && root.stickers.length > 0
                anchors.centerIn: parent
                width: Math.min(230, parent.width - 30)
                height: 38
                hoverEnabled: true
                scale: down ? 0.94 : 1
                onClicked: root.installRequested(root.pack)
                contentItem: Text {
                    text: L10n.I18n.tr("Добавить набор")
                    color: root.accentColor
                    font.pointSize: 9
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 10
                    color: installButton.down ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                        : installButton.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.13)
                        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.07)
                    border.width: 1
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.23)
                }
                Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic } }
            }

            Text {
                visible: root.builtinPack || root.installedPack
                anchors.centerIn: parent
                text: root.builtinPack ? L10n.I18n.tr("Встроенный набор Prism") : L10n.I18n.tr("Набор уже добавлен")
                color: root.textSecondary
                font.pointSize: 8
            }
        }
    }
}
