import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import QtCore
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
    property string accountId: ""
    property string mediaProxy: ""
    property var stickerProvider: null
    property var stickerPackProvider: null
    property var historyStickers: []
    property var installedPacks: []
    property var sharedPacks: []
    property var packTabs: []
    property int packIndex: 0
    property string searchQuery: ""
    property int recentLimit: 24
    property string pendingStickerPath: ""
    property string pendingStickerFilename: ""
    property string pendingStickerMime: ""
    property var contextSticker: null
    property var contextPack: null

    readonly property string emojiFontFamily: L10n.UiPreferences.emojiFontFamily

    signal stickerChosen(var sticker)
    signal stickerAssetCreateRequested(var draft)
    signal sharePackRequested(var pack)
    signal saveStickerRequested(var sticker)
    signal viewPackRequested(var pack)

    width: 390
    height: 460
    padding: 0
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function localizedBuiltinSticker(sticker, pack) {
        var item = sticker || ({})
        return Object.assign({}, item, {
            body: L10n.I18n.tr(item.body_source || "Стикер"),
            pack_id: pack ? pack.id : "",
            pack_name: pack ? L10n.I18n.tr(pack.display_name_source || "Набор стикеров") : "",
            builtin_pack: true
        })
    }

    function localizedBuiltinPack(pack) {
        var source = pack || ({})
        var images = []
        var raw = source.images || []
        for (var index = 0; index < raw.length; index++)
            images.push(localizedBuiltinSticker(raw[index], source))
        return {
            id: source.id || "prism",
            display_name: L10n.I18n.tr(source.display_name_source || "Набор стикеров"),
            icon: source.icon || "◆",
            icon_kind: source.icon_kind || "pack",
            source: "builtin",
            builtin: true,
            images: images
        }
    }

    function builtinPacks() {
        var result = []
        var source = L10n.StickerCatalog.builtinPacks || []
        for (var index = 0; index < source.length; index++)
            result.push(localizedBuiltinPack(source[index]))
        return result
    }

    function reload() {
        var provided = root.stickerProvider ? root.stickerProvider() : []
        root.historyStickers = Array.isArray(provided) ? provided : []
        root.installedPacks = L10n.StickerPackStore.packsFor(root.accountId)
        var shared = root.stickerPackProvider ? root.stickerPackProvider() : []
        root.sharedPacks = Array.isArray(shared) ? shared : []
        root.rebuildTabs()
    }

    function packKey(pack) {
        var value = pack || ({})
        return String(value.id || value.display_name || "")
    }

    function packContainsSticker(pack, sticker) {
        if (!pack || !sticker)
            return false
        var builtinId = String(sticker.builtin_id || "")
        var mediaUrl = String(sticker.media_url || "")
        var images = pack.images || []
        for (var index = 0; index < images.length; index++) {
            var candidate = images[index] || ({})
            if (builtinId !== "" && String(candidate.builtin_id || "") === builtinId)
                return true
            if (mediaUrl !== "" && String(candidate.media_url || "") === mediaUrl)
                return true
        }
        return false
    }

    function allKnownPacks() {
        var result = root.builtinPacks()
        var seen = ({})
        for (var builtinIndex = 0; builtinIndex < result.length; builtinIndex++)
            seen[root.packKey(result[builtinIndex])] = true
        var sources = [root.installedPacks || [], root.sharedPacks || []]
        for (var sourceIndex = 0; sourceIndex < sources.length; sourceIndex++) {
            var packs = sources[sourceIndex]
            for (var packIndex = 0; packIndex < packs.length; packIndex++) {
                var pack = packs[packIndex] || ({})
                var key = root.packKey(pack)
                if (key === "" || seen[key])
                    continue
                seen[key] = true
                result.push(pack)
            }
        }
        return result
    }

    function looseChatStickers() {
        var packs = root.allKnownPacks()
        var result = []
        var history = root.historyStickers || []
        for (var stickerIndex = 0; stickerIndex < history.length; stickerIndex++) {
            var sticker = history[stickerIndex]
            var matched = false
            for (var packIndex = 0; packIndex < packs.length; packIndex++) {
                if (root.packContainsSticker(packs[packIndex], sticker)) {
                    matched = true
                    break
                }
            }
            if (!matched)
                result.push(sticker)
        }
        return result
    }

    function rebuildTabs() {
        var previous = root.currentTab()
        var previousKey = previous.kind === "recent" ? "__recent__"
            : previous.kind === "loose" ? "__loose__" : root.packKey(previous.pack)
        var tabs = [{ kind: "recent", label: L10n.I18n.tr("Недавние"), icon: "◷", icon_kind: "recent" }]
        var seen = ({})

        var builtin = root.builtinPacks()
        for (var builtinIndex = 0; builtinIndex < builtin.length; builtinIndex++) {
            var builtinPack = builtin[builtinIndex]
            tabs.push({ kind: "pack", label: builtinPack.display_name, icon: builtinPack.icon || "◆", icon_kind: builtinPack.icon_kind || "pack", pack: builtinPack })
            seen[root.packKey(builtinPack)] = true
        }

        var installed = root.installedPacks || []
        for (var installedIndex = 0; installedIndex < installed.length; installedIndex++) {
            var installedPack = installed[installedIndex] || ({})
            var installedKey = root.packKey(installedPack)
            if (installedKey === "" || seen[installedKey])
                continue
            seen[installedKey] = true
            tabs.push({ kind: "pack", label: installedPack.display_name || L10n.I18n.tr("Набор стикеров"), icon: "▦", icon_kind: "pack", pack: installedPack })
        }

        var shared = root.sharedPacks || []
        for (var sharedIndex = 0; sharedIndex < shared.length; sharedIndex++) {
            var sharedPack = shared[sharedIndex] || ({})
            var sharedKey = root.packKey(sharedPack)
            if (sharedKey === "" || seen[sharedKey])
                continue
            seen[sharedKey] = true
            tabs.push({ kind: "pack", label: sharedPack.display_name || L10n.I18n.tr("Набор стикеров"), icon: "▦", icon_kind: "pack", pack: sharedPack })
        }

        if (root.looseChatStickers().length > 0)
            tabs.push({ kind: "loose", label: L10n.I18n.tr("Из чата"), icon: "☰", icon_kind: "chat" })

        root.packTabs = tabs
        var nextIndex = -1
        for (var tabIndex = 0; tabIndex < tabs.length; tabIndex++) {
            var key = tabs[tabIndex].kind === "recent" ? "__recent__"
                : tabs[tabIndex].kind === "loose" ? "__loose__" : root.packKey(tabs[tabIndex].pack)
            if (key === previousKey) {
                nextIndex = tabIndex
                break
            }
        }
        if (nextIndex < 0)
            nextIndex = root.historyStickers.length > 0 ? 0 : Math.min(1, tabs.length - 1)
        root.packIndex = Math.max(0, nextIndex)
    }

    function currentTab() {
        return root.packTabs.length > 0 && root.packIndex >= 0 && root.packIndex < root.packTabs.length
            ? root.packTabs[root.packIndex] : ({ kind: "recent", label: L10n.I18n.tr("Недавние") })
    }

    function currentPack() {
        var tab = root.currentTab()
        return tab.kind === "pack" ? tab.pack : null
    }

    function stickerPreview(sticker) {
        if (!sticker || !sticker.media_url)
            return ""
        return sticker.preview_url || Utils.proxyUrl(sticker.media_url, root.mediaProxy,
                                                     sticker.media_file || undefined,
                                                     sticker.media_mime_type || "image/webp")
    }

    function mappedPackImages(pack) {
        var packImages = (pack && pack.images) ? pack.images : []
        var mapped = []
        for (var index = 0; index < packImages.length; index++) {
            var image = packImages[index] || ({})
            mapped.push(Object.assign({}, image, {
                pack_id: pack.id || "",
                pack_name: pack.display_name || "",
                preview_url: root.stickerPreview(image)
            }))
        }
        return mapped
    }

    function currentSource() {
        var tab = root.currentTab()
        if (tab.kind === "pack")
            return root.mappedPackImages(tab.pack)
        if (tab.kind === "recent")
            return (root.historyStickers || []).slice(0, root.recentLimit)
        if (tab.kind === "loose")
            return root.looseChatStickers()
        return []
    }

    function filteredStickers() {
        var source = root.currentSource()
        var query = String(root.searchQuery || "").trim().toLowerCase()
        if (query === "")
            return source
        var result = []
        for (var index = 0; index < source.length; index++) {
            var sticker = source[index] || ({})
            var name = (String(sticker.body || sticker.body_source || "") + " "
                        + String(sticker.shortcode || "")).toLowerCase()
            if (name.indexOf(query) !== -1)
                result.push(sticker)
        }
        return result
    }

    function packForSticker(sticker) {
        var packs = root.allKnownPacks()
        for (var index = 0; index < packs.length; index++) {
            if (root.packContainsSticker(packs[index], sticker))
                return packs[index]
        }
        return null
    }

    function packChoiceModel() {
        var choices = []
        for (var index = 0; index < root.installedPacks.length; index++)
            choices.push({ id: root.installedPacks[index].id, name: root.installedPacks[index].display_name })
        choices.push({ id: "__new__", name: L10n.I18n.tr("Новый набор…") })
        return choices
    }

    function selectedCreationPackId() {
        var model = createPackCombo.model || []
        var item = createPackCombo.currentIndex >= 0 && createPackCombo.currentIndex < model.length
            ? model[createPackCombo.currentIndex] : null
        return item ? String(item.id || "") : "__new__"
    }

    function openCreationDialog() {
        stickerNameField.text = root.pendingStickerFilename.replace(/\.[^.]+$/, "") || L10n.I18n.tr("Стикер")
        stickerShortcodeField.text = L10n.StickerPackStore.sanitizeShortcode(stickerNameField.text.toLowerCase(), "sticker")
        createPackCombo.model = root.packChoiceModel()
        createPackCombo.currentIndex = Math.max(0, createPackCombo.count - 1)
        newPackNameField.text = L10n.I18n.tr("Мои стикеры")
        createStickerDialog.open()
    }

    function openStickerContext(sticker, item, mouseX, mouseY) {
        root.contextSticker = sticker
        root.contextPack = root.packForSticker(sticker)
        var point = item.mapToItem(root, mouseX, mouseY)
        stickerContextMenu.x = Math.max(6, Math.min(root.width - stickerContextMenu.width - 6, point.x))
        stickerContextMenu.y = Math.max(6, Math.min(root.height - stickerContextMenu.height - 6, point.y))
        stickerContextMenu.open()
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
        if (["♥", "★", "✓", "!", "☺", "✦", "○", "?", "♪", "☀", "☾", "♛", "☁", "☂", "▣"].indexOf(value) !== -1)
            return -1
        return 0
    }

    readonly property var visibleStickers: filteredStickers()
    readonly property var selectedPack: currentPack()
    readonly property string currentPackName: String(currentTab().label || L10n.I18n.tr("Стикеры"))

    onOpened: {
        root.searchQuery = ""
        reload()
        Qt.callLater(function() { searchField.forceActiveFocus() })
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: L10n.UiPreferences.duration(130) }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: L10n.UiPreferences.duration(150); easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: L10n.UiPreferences.duration(95) }
            NumberAnimation { property: "scale"; from: 1; to: 0.98; duration: L10n.UiPreferences.duration(95); easing.type: Easing.InCubic }
        }
    }

    background: Rectangle {
        color: root.surfaceColor
        radius: 15
        border.width: 1
        border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g, root.dividerColor.b, 0.82)
    }

    contentItem: ColumnLayout {
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: root.elevatedColor
            radius: 15

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 15
                color: parent.color
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: actionRow.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.currentPackName
                color: root.textPrimary
                font.pointSize: 10
                font.bold: true
                elide: Text.ElideRight
            }

            Row {
                id: actionRow
                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Basic.Button {
                    id: shareButton
                    visible: !!root.selectedPack && !root.selectedPack.builtin
                        && (root.selectedPack.images || []).length > 0
                    width: 32
                    height: 32
                    hoverEnabled: true
                    scale: down ? 0.86 : 1
                    padding: 0
                    onClicked: root.sharePackRequested(root.selectedPack)
                    contentItem: Item {
                        Canvas {
                            anchors.centerIn: parent
                            width: 17
                            height: 17
                            property color iconColor: shareButton.down || shareButton.hovered
                                ? root.accentColor : root.textSecondary
                            onIconColorChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.strokeStyle = iconColor
                                ctx.lineWidth = 1.7
                                ctx.lineCap = "round"
                                ctx.lineJoin = "round"
                                ctx.beginPath()
                                ctx.moveTo(4, 13)
                                ctx.lineTo(13, 4)
                                ctx.moveTo(8, 4)
                                ctx.lineTo(13, 4)
                                ctx.lineTo(13, 9)
                                ctx.stroke()
                            }
                            Component.onCompleted: requestPaint()
                        }
                    }
                    background: Rectangle {
                        radius: 8
                        color: shareButton.down ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                            : shareButton.hovered ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
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
                    id: addStickerButton
                    width: 32
                    height: 32
                    hoverEnabled: true
                    scale: down ? 0.86 : 1
                    padding: 0
                    onClicked: createStickerFileDialog.open()
                    contentItem: Item {
                        rotation: addStickerButton.hovered ? 90 : 0
                        Behavior on rotation { NumberAnimation { duration: L10n.UiPreferences.duration(140); easing.type: Easing.OutCubic } }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 13
                            height: 1.5
                            radius: height / 2
                            color: addStickerButton.down || addStickerButton.hovered ? root.accentColor : root.textSecondary
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 1.5
                            height: 13
                            radius: width / 2
                            color: addStickerButton.down || addStickerButton.hovered ? root.accentColor : root.textSecondary
                        }
                    }
                    background: Rectangle {
                        radius: 8
                        color: addStickerButton.down ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                            : addStickerButton.hovered ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                    }
                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic } }
                    PrismToolTip {
                        visible: addStickerButton.hovered
                        text: L10n.I18n.tr("Создать стикер")
                        surfaceColor: root.elevatedColor
                        textColor: root.textPrimary
                        dividerColor: root.dividerColor
                    }
                }

                Basic.Button {
                    id: closeButton
                    width: 32
                    height: 32
                    hoverEnabled: true
                    scale: down ? 0.86 : 1
                    padding: 0
                    onClicked: root.close()
                    contentItem: Item {
                        Rectangle { anchors.centerIn: parent; width: 12; height: 1.3; rotation: 45; color: closeButton.down || closeButton.hovered ? root.accentColor : root.textSecondary }
                        Rectangle { anchors.centerIn: parent; width: 12; height: 1.3; rotation: -45; color: closeButton.down || closeButton.hovered ? root.accentColor : root.textSecondary }
                    }
                    background: Rectangle {
                        radius: 8
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

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            Basic.TextField {
                id: searchField
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 6
                anchors.bottomMargin: 5
                leftPadding: 12
                rightPadding: 12
                color: root.textPrimary
                placeholderText: L10n.I18n.tr("Поиск стикеров")
                placeholderTextColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.78)
                selectionColor: root.accentColor
                selectedTextColor: root.surfaceColor
                onTextChanged: root.searchQuery = text
                background: Rectangle {
                    radius: 9
                    color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, searchField.activeFocus ? 0.085 : 0.055)
                    border.width: 1
                    border.color: searchField.activeFocus
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.62)
                        : Qt.rgba(root.dividerColor.r, root.dividerColor.g, root.dividerColor.b, 0.72)
                    Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                    Behavior on border.color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                }
            }
        }

        ListView {
            id: packTabsView
            Layout.fillWidth: true
            Layout.preferredHeight: 43
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            orientation: ListView.Horizontal
            spacing: 1
            clip: true
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds
            model: root.packTabs

            delegate: Basic.Button {
                id: packButton
                required property int index
                required property var modelData
                readonly property var firstSticker: modelData.pack && (modelData.pack.images || []).length > 0
                    ? modelData.pack.images[0] : null
                width: 38
                height: 39
                padding: 0
                hoverEnabled: true
                scale: down ? 0.88 : 1
                onClicked: root.packIndex = index

                contentItem: Item {
                    AnimatedImage {
                        id: packPreviewImage
                        anchors.centerIn: parent
                        width: 25
                        height: 25
                        visible: !!packButton.firstSticker && !!packButton.firstSticker.media_url
                        source: visible ? root.stickerPreview(packButton.firstSticker) : ""
                        fillMode: Image.PreserveAspectFit
                        horizontalAlignment: Image.AlignHCenter
                        verticalAlignment: Image.AlignVCenter
                        asynchronous: true
                        cache: true
                        playing: visible
                    }
                    Canvas {
                        id: packIconCanvas
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        visible: !packPreviewImage.visible
                        property color iconColor: packButton.index === root.packIndex ? root.accentColor : root.textSecondary
                        property string iconKind: String(packButton.modelData.icon_kind || "pack")
                        onIconColorChanged: requestPaint()
                        onIconKindChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = iconColor
                            ctx.fillStyle = iconColor
                            ctx.lineWidth = 1.8
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            var kind = iconKind
                            if (kind === "recent") {
                                ctx.beginPath(); ctx.arc(12, 12, 7.5, 0, Math.PI * 2); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(12, 7.5); ctx.lineTo(12, 12); ctx.lineTo(15.5, 14); ctx.stroke()
                            } else if (kind === "classic") {
                                ctx.beginPath(); ctx.moveTo(12, 3.2); ctx.lineTo(20.8, 12); ctx.lineTo(12, 20.8); ctx.lineTo(3.2, 12); ctx.closePath(); ctx.fill()
                            } else if (kind === "reactions") {
                                ctx.beginPath(); ctx.arc(12, 12, 8, 0, Math.PI * 2); ctx.stroke()
                                ctx.beginPath(); ctx.arc(9, 10, 1.1, 0, Math.PI * 2); ctx.arc(15, 10, 1.1, 0, Math.PI * 2); ctx.fill()
                                ctx.beginPath(); ctx.arc(12, 12.5, 4.2, 0.18 * Math.PI, 0.82 * Math.PI); ctx.stroke()
                            } else if (kind === "animated") {
                                ctx.beginPath(); ctx.moveTo(12, 2.8); ctx.lineTo(14.3, 9.7); ctx.lineTo(21.2, 12); ctx.lineTo(14.3, 14.3); ctx.lineTo(12, 21.2); ctx.lineTo(9.7, 14.3); ctx.lineTo(2.8, 12); ctx.lineTo(9.7, 9.7); ctx.closePath(); ctx.fill()
                            } else if (kind === "signs") {
                                ctx.beginPath(); ctx.arc(12, 12, 5.2, 0, Math.PI * 2); ctx.stroke()
                                for (var i = 0; i < 8; i++) {
                                    var a = i * Math.PI / 4
                                    ctx.beginPath(); ctx.moveTo(12 + Math.cos(a) * 8, 12 + Math.sin(a) * 8); ctx.lineTo(12 + Math.cos(a) * 10.2, 12 + Math.sin(a) * 10.2); ctx.stroke()
                                }
                            } else if (kind === "chat") {
                                ctx.beginPath(); ctx.moveTo(4, 5.5); ctx.lineTo(20, 5.5); ctx.moveTo(4, 12); ctx.lineTo(17, 12); ctx.moveTo(4, 18.5); ctx.lineTo(14, 18.5); ctx.stroke()
                            } else {
                                for (var row = 0; row < 2; row++) for (var col = 0; col < 2; col++) {
                                    ctx.fillRect(5 + col * 8, 5 + row * 8, 5, 5)
                                }
                            }
                        }
                        Component.onCompleted: requestPaint()
                    }
                }

                background: Rectangle {
                    radius: 8
                    color: packButton.down
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                        : packButton.index === root.packIndex
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.13)
                            : packButton.hovered
                                ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.06)
                                : "transparent"
                    Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                }
                Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic } }

                PrismToolTip {
                    visible: packButton.hovered
                    text: String(packButton.modelData.label || "")
                    surfaceColor: root.elevatedColor
                    textColor: root.textPrimary
                    dividerColor: root.dividerColor
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.rgba(root.dividerColor.r, root.dividerColor.g, root.dividerColor.b, 0.55)
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
                id: stickerGrid
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                clip: true
                cellWidth: Math.max(78, width / 4)
                cellHeight: 80
                model: root.visibleStickers
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: stickerDelegate
                    required property var modelData
                    width: stickerGrid.cellWidth
                    height: stickerGrid.cellHeight
                    readonly property var sticker: modelData || ({})

                    Rectangle {
                        id: stickerTile
                        anchors.centerIn: parent
                        width: Math.min(72, parent.width - 6)
                        height: 72
                        radius: 12
                        scale: stickerMouse.pressed ? 0.90 : stickerMouse.containsMouse ? 1.035 : 1.0
                        color: stickerMouse.pressed ? Qt.rgba(0, 0, 0, 0.28)
                            : stickerMouse.containsMouse ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.075)
                            : "transparent"
                        Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(95); easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(105) } }

                        AnimatedImage {
                            id: mediaSticker
                            anchors.fill: parent
                            anchors.margins: 5
                            visible: !stickerDelegate.sticker.builtin_id
                            source: root.stickerPreview(stickerDelegate.sticker)
                            fillMode: Image.PreserveAspectFit
                            horizontalAlignment: Image.AlignHCenter
                            verticalAlignment: Image.AlignVCenter
                            asynchronous: true
                            cache: true
                            smooth: true
                            playing: visible
                        }

                        Text {
                            id: builtinText
                            anchors.centerIn: parent
                            width: 62
                            height: 62
                            visible: !!stickerDelegate.sticker.builtin_id
                            text: stickerDelegate.sticker.symbol || "★"
                            color: stickerDelegate.sticker.color || root.accentColor
                            font.family: root.symbolUsesEmojiFont(stickerDelegate.sticker.symbol)
                                ? root.emojiFontFamily : "Sans Serif"
                            font.pixelSize: 43
                            font.bold: false
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            anchors.horizontalCenterOffset: root.symbolOffsetX(stickerDelegate.sticker.symbol)
                            anchors.verticalCenterOffset: root.symbolOffsetY(stickerDelegate.sticker.symbol)
                            transformOrigin: Item.Center
                        }

                        SequentialAnimation {
                            running: !!stickerDelegate.sticker.animated && builtinText.visible && root.opened
                            loops: Animation.Infinite
                            NumberAnimation { target: builtinText; property: "scale"; from: 1; to: 1.14; duration: 280; easing.type: Easing.OutCubic }
                            NumberAnimation { target: builtinText; property: "scale"; from: 1.14; to: 0.97; duration: 240; easing.type: Easing.InOutCubic }
                            NumberAnimation { target: builtinText; property: "scale"; from: 0.97; to: 1; duration: 220; easing.type: Easing.OutCubic }
                            PauseAnimation { duration: 180 }
                        }

                        MouseArea {
                            id: stickerMouse
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton) {
                                    root.openStickerContext(stickerDelegate.sticker, stickerTile, mouse.x, mouse.y)
                                    return
                                }
                                root.stickerChosen(stickerDelegate.sticker)
                                root.close()
                            }
                        }

                        PrismToolTip {
                            visible: stickerMouse.containsMouse && !stickerContextMenu.visible
                                && String(stickerDelegate.sticker.body || stickerDelegate.sticker.body_source || "") !== ""
                            text: L10n.I18n.tr(String(stickerDelegate.sticker.body || stickerDelegate.sticker.body_source || ""))
                            surfaceColor: root.elevatedColor
                            textColor: root.textPrimary
                            dividerColor: root.dividerColor
                            delay: 430
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                visible: root.visibleStickers.length === 0
                width: Math.min(285, parent.width - 30)
                spacing: 7
                Text {
                    width: parent.width
                    text: root.searchQuery !== "" ? L10n.I18n.tr("Ничего не найдено") : L10n.I18n.tr("Пока нет стикеров")
                    color: root.textPrimary
                    font.pointSize: 10
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    visible: root.searchQuery === ""
                    text: root.currentTab().kind === "pack" && root.currentPack() && !root.currentPack().builtin
                        ? L10n.I18n.tr("Добавьте PNG, WebP, GIF или APNG кнопкой +")
                        : L10n.I18n.tr("Стикеры из переписки появятся здесь автоматически")
                    color: root.textSecondary
                    font.pointSize: 8.5
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Basic.Menu {
        id: stickerContextMenu
        parent: root
        width: 236
        padding: 6
        background: Rectangle {
            color: root.elevatedColor
            radius: 10
            border.width: 1
            border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g, root.dividerColor.b, 0.92)
        }
        contentItem: Column {
            width: stickerContextMenu.availableWidth
            ContextMenuAction {
                visible: !!root.contextSticker && !root.contextSticker.builtin_id
                text: L10n.I18n.tr("Добавить в мои стикеры")
                iconKind: "reaction"
                accentColor: root.accentColor
                textColor: root.textPrimary
                onClicked: {
                    stickerContextMenu.close()
                    root.saveStickerRequested(root.contextSticker)
                }
            }
            ContextMenuAction {
                visible: !!root.contextPack
                text: L10n.I18n.tr("Посмотреть набор")
                iconKind: "source"
                accentColor: root.accentColor
                textColor: root.textPrimary
                onClicked: {
                    var pack = root.contextPack
                    stickerContextMenu.close()
                    root.viewPackRequested(pack)
                }
            }
        }
    }

    FileDialog {
        id: createStickerFileDialog
        title: L10n.I18n.tr("Создать стикер")
        fileMode: FileDialog.OpenFile
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        nameFilters: [
            L10n.I18n.tr("Стикеры и анимации") + " (*.png *.jpg *.jpeg *.webp *.gif *.apng)",
            L10n.I18n.tr("Все файлы") + " (*)"
        ]
        onAccepted: {
            root.pendingStickerPath = Utils.localPath(selectedFile)
            root.pendingStickerFilename = root.pendingStickerPath.split("/").pop()
            root.pendingStickerMime = Utils.guessMime(root.pendingStickerFilename)
            root.openCreationDialog()
        }
    }

    Dialog {
        id: createStickerDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 350
        height: 390
        modal: true
        title: L10n.I18n.tr("Новый стикер")
        standardButtons: Dialog.Ok | Dialog.Cancel

        contentItem: ColumnLayout {
            spacing: 10
            Text {
                Layout.fillWidth: true
                text: L10n.I18n.tr("Файл будет загружен без изменения формата. GIF/WebP/APNG сохраняют анимацию, если формат поддерживается Qt на устройстве.")
                color: root.textSecondary
                font.pointSize: 8
                wrapMode: Text.Wrap
            }
            Text { text: L10n.I18n.tr("Название"); color: root.textSecondary; font.pointSize: 8 }
            Basic.TextField {
                id: stickerNameField
                Layout.fillWidth: true
                color: root.textPrimary
                selectByMouse: true
                background: Rectangle { radius: 8; color: root.elevatedColor; border.color: root.dividerColor }
            }
            Text { text: L10n.I18n.tr("Короткое имя"); color: root.textSecondary; font.pointSize: 8 }
            Basic.TextField {
                id: stickerShortcodeField
                Layout.fillWidth: true
                color: root.textPrimary
                selectByMouse: true
                validator: RegularExpressionValidator { regularExpression: /[a-zA-Z0-9_-]{1,80}/ }
                background: Rectangle { radius: 8; color: root.elevatedColor; border.color: root.dividerColor }
            }
            Text { text: L10n.I18n.tr("Набор"); color: root.textSecondary; font.pointSize: 8 }
            Basic.ComboBox {
                id: createPackCombo
                Layout.fillWidth: true
                textRole: "name"
                valueRole: "id"
                background: Rectangle { radius: 8; color: root.elevatedColor; border.color: root.dividerColor }
            }
            Basic.TextField {
                id: newPackNameField
                Layout.fillWidth: true
                visible: root.selectedCreationPackId() === "__new__"
                placeholderText: L10n.I18n.tr("Название нового набора")
                color: root.textPrimary
                background: Rectangle { radius: 8; color: root.elevatedColor; border.color: root.dividerColor }
            }
            Item { Layout.fillHeight: true }
        }

        onAccepted: {
            var packId = root.selectedCreationPackId()
            var draft = {
                path: root.pendingStickerPath,
                filename: root.pendingStickerFilename,
                mime_type: root.pendingStickerMime,
                body: stickerNameField.text.trim() || L10n.I18n.tr("Стикер"),
                shortcode: L10n.StickerPackStore.sanitizeShortcode(stickerShortcodeField.text, "sticker"),
                pack_id: packId === "__new__" ? "" : packId,
                pack_name: packId === "__new__" ? (newPackNameField.text.trim() || L10n.I18n.tr("Мои стикеры")) : ""
            }
            root.stickerAssetCreateRequested(draft)
        }
    }
}
