import QtQuick
import "../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtCore
import "../common"

Basic.Popup {
    id: root

    property color accentColor: "#20D500"
    property color accentTextColor: "#071007"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"

    property bool quickReactionsMode: false
    property string quickReactionTarget: ""
    property int selectedCategory: 0
    property bool addingFavorite: false
    property var favoriteEmojis: []
    property var manualFavorites: []
    property var emojiUsage: ({})
    property var hiddenPopularEmojis: []
    property int maxPopularEmojis: 24
    readonly property string emojiFontFamily: L10n.UiPreferences.emojiFontFamily
    readonly property var emojiCategories: [
        { name: L10n.I18n.tr("Избранные"), icon: "★", emojis: [] },
        { name: L10n.I18n.tr("Смайлы"), icon: "☺", emojis: [
            "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇",
            "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😋", "😜", "🤪",
            "🤨", "🧐", "🤓", "😎", "🥳", "😏", "😒", "😔", "😢", "😭",
            "😤", "😡", "🤯", "😳", "🥺", "😱", "😴", "🤔", "🤗", "🫡"
        ] },
        { name: L10n.I18n.tr("Люди и жесты"), icon: "👋", emojis: [
            "👋", "🤚", "🖐️", "✋", "🖖", "👌", "🤌", "🤏", "✌️", "🤞",
            "🫰", "🤟", "🤘", "🤙", "👈", "👉", "👆", "👇", "☝️", "👍",
            "👎", "✊", "👊", "🤛", "🤜", "👏", "🙌", "🫶", "👐", "🤝",
            "🙏", "💪", "🫂", "👀", "🧠", "💅"
        ] },
        { name: L10n.I18n.tr("Животные"), icon: "🐾", emojis: [
            "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐻‍❄️", "🐨",
            "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🙈", "🙉", "🙊", "🐔",
            "🐧", "🐦", "🦄", "🐝", "🦋", "🐌", "🐞", "🐢", "🐍", "🦎",
            "🐙", "🦑", "🦀", "🐠", "🐬", "🌸", "🌻", "🌵", "🌲", "🍀"
        ] },
        { name: L10n.I18n.tr("Еда"), icon: "🍕", emojis: [
            "🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐",
            "🍒", "🥭", "🍍", "🥝", "🍅", "🥑", "🍔", "🍟", "🍕", "🌭",
            "🥪", "🌮", "🍜", "🍣", "🍱", "🍙", "🍦", "🍩", "🍪", "🎂",
            "🍫", "🍿", "☕", "🍵", "🥤", "🍺", "🍷", "🥂", "🧋", "🧃"
        ] },
        { name: L10n.I18n.tr("Активности"), icon: "⚽", emojis: [
            "⚽", "🏀", "🏈", "⚾", "🎾", "🏐", "🏉", "🥏", "🎱", "🏓",
            "🏸", "🥅", "⛳", "🛹", "🎣", "🎿", "🏂", "🏋️", "🚴", "🏆",
            "🥇", "🎯", "🎮", "🎲", "🎸", "🎹", "🎧", "🎤", "🎬", "🎨"
        ] },
        { name: L10n.I18n.tr("Путешествия"), icon: "🚗", emojis: [
            "🚗", "🚕", "🚌", "🏎️", "🚓", "🚑", "🚒", "🚚", "🏍️", "🚲",
            "✈️", "🚀", "🚁", "🛸", "🚢", "⛵", "🚂", "🚇", "🗺️", "🧭",
            "🏠", "🏢", "🏰", "🗼", "🗽", "⛲", "🌋", "🏕️", "🏖️", "🌅",
            "🌇", "🌃", "🌍", "🌙", "⭐", "🌈"
        ] },
        { name: L10n.I18n.tr("Предметы"), icon: "💡", emojis: [
            "⌚", "📱", "💻", "⌨️", "🖥️", "🖨️", "📷", "📹", "🎥", "📞",
            "💡", "🔦", "📚", "📖", "📝", "✏️", "📌", "📎", "🔒", "🔑",
            "🔨", "🛠️", "🧲", "🧪", "💊", "🩹", "🎁", "🎈", "🧸", "🛍️",
            "📦", "✉️", "💌", "🔔", "⏰", "🧭"
        ] },
        { name: L10n.I18n.tr("Символы"), icon: "♥", emojis: [
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔",
            "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟", "☮️",
            "✝️", "☯️", "☸️", "♾️", "‼️", "⁉️", "❓", "❗", "✅", "❌",
            "⭕", "💯", "🔥", "✨", "⚡", "💥", "💫", "🎵", "♻️", "🔞"
        ] },
        { name: L10n.I18n.tr("Флаги"), icon: "🏳", emojis: [
            "🏳️", "🏴", "🏁", "🚩", "🏳️‍🌈", "🏳️‍⚧️", "🇷🇺", "🇺🇦", "🇧🇾", "🇰🇿",
            "🇦🇲", "🇬🇪", "🇺🇿", "🇺🇸", "🇬🇧", "🇩🇪", "🇫🇷", "🇮🇹", "🇪🇸", "🇵🇹",
            "🇨🇳", "🇯🇵", "🇰🇷", "🇮🇳", "🇧🇷", "🇨🇦", "🇦🇺", "🇹🇷", "🇵🇱", "🇳🇱"
        ] }
    ]

    readonly property string currentCategoryName: selectedCategory >= 0
        && selectedCategory < emojiCategories.length
        ? emojiCategories[selectedCategory].name : ""

    signal emojiChosen(string emoji)

    width: 380
    height: 350
    padding: 0
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Settings {
        id: emojiSettings
        category: "EmojiPicker"
        property string favoriteEmojisJson: "[]"
        property string emojiUsageJson: "{}"
        property string hiddenPopularEmojisJson: "[]"
    }

    function loadFavorites() {
        try {
            var parsedFavorites = JSON.parse(emojiSettings.favoriteEmojisJson || "[]")
            manualFavorites = Array.isArray(parsedFavorites) ? parsedFavorites : []
        } catch (favoritesError) {
            manualFavorites = []
        }
        try {
            var parsedUsage = JSON.parse(emojiSettings.emojiUsageJson || "{}")
            emojiUsage = parsedUsage && typeof parsedUsage === "object" ? parsedUsage : ({})
        } catch (usageError) {
            emojiUsage = ({})
        }
        try {
            var parsedHidden = JSON.parse(emojiSettings.hiddenPopularEmojisJson || "[]")
            hiddenPopularEmojis = Array.isArray(parsedHidden) ? parsedHidden : []
        } catch (hiddenError) {
            hiddenPopularEmojis = []
        }
        refreshFavorites()
    }

    function saveFavorites() {
        emojiSettings.favoriteEmojisJson = JSON.stringify(manualFavorites)
        emojiSettings.emojiUsageJson = JSON.stringify(emojiUsage)
        emojiSettings.hiddenPopularEmojisJson = JSON.stringify(hiddenPopularEmojis)
    }

    function refreshFavorites() {
        var result = manualFavorites.slice(0)
        var keys = Object.keys(emojiUsage)
        keys.sort(function(left, right) {
            var countDifference = Number(emojiUsage[right] || 0)
                - Number(emojiUsage[left] || 0)
            if (countDifference !== 0) return countDifference
            return left < right ? -1 : left > right ? 1 : 0
        })
        var automaticCount = 0
        for (var i = 0; i < keys.length && automaticCount < maxPopularEmojis; i++) {
            var emoji = keys[i]
            if (Number(emojiUsage[emoji] || 0) <= 0
                    || result.indexOf(emoji) !== -1
                    || hiddenPopularEmojis.indexOf(emoji) !== -1)
                continue
            result.push(emoji)
            automaticCount++
        }
        favoriteEmojis = result
    }

    function recordEmojiUse(emoji) {
        var value = String(emoji || "")
        if (value === "") return
        var nextUsage = ({})
        for (var key in emojiUsage)
            nextUsage[key] = Number(emojiUsage[key] || 0)
        nextUsage[value] = Number(nextUsage[value] || 0) + 1
        emojiUsage = nextUsage
        saveFavorites()
        refreshFavorites()
    }

    function emojisForCurrentCategory() {
        if (selectedCategory === 0)
            return favoriteEmojis
        if (selectedCategory < 0 || selectedCategory >= emojiCategories.length)
            return []
        return emojiCategories[selectedCategory].emojis
    }

    function beginAddingFavorite() {
        addingFavorite = true
        selectedCategory = 1
        customFavoriteField.text = ""
        customFavoriteField.forceActiveFocus()
    }

    function finishAddingFavorite() {
        addingFavorite = false
        selectedCategory = 0
        customFavoriteField.text = ""
    }

    function addFavorite(emoji) {
        var value = String(emoji || "").trim()
        if (value === "") return
        var nextManual = manualFavorites.slice(0)
        if (nextManual.indexOf(value) === -1)
            nextManual.push(value)
        manualFavorites = nextManual

        var nextHidden = hiddenPopularEmojis.slice(0)
        var hiddenIndex = nextHidden.indexOf(value)
        if (hiddenIndex !== -1)
            nextHidden.splice(hiddenIndex, 1)
        hiddenPopularEmojis = nextHidden

        saveFavorites()
        refreshFavorites()
        finishAddingFavorite()
    }

    function removeFavorite(emoji) {
        var value = String(emoji || "")
        var nextManual = manualFavorites.slice(0)
        var manualIndex = nextManual.indexOf(value)
        if (manualIndex !== -1)
            nextManual.splice(manualIndex, 1)
        manualFavorites = nextManual

        var nextHidden = hiddenPopularEmojis.slice(0)
        if (nextHidden.indexOf(value) === -1)
            nextHidden.push(value)
        hiddenPopularEmojis = nextHidden

        saveFavorites()
        refreshFavorites()
    }

    function activateEmoji(emoji) {
        if (quickReactionsMode) {
            var replacement = String(emoji || "").trim()
            if (L10n.QuickReactionStore.replaceKey(quickReactionTarget, replacement)
                    || L10n.QuickReactionStore.keys.indexOf(replacement) >= 0) {
                quickReactionTarget = replacement
                customFavoriteField.text = ""
            }
            return
        }
        if (addingFavorite) {
            addFavorite(emoji)
            return
        }
        var value = String(emoji)
        recordEmojiUse(value)
        emojiChosen(value)
    }

    function addCustomFavorite() {
        if (quickReactionsMode) activateEmoji(customFavoriteField.text)
        else addFavorite(customFavoriteField.text)
    }

    Component.onCompleted: loadFavorites()
    onOpened: {
        selectedCategory = quickReactionsMode ? 1 : 0
        quickReactionTarget = quickReactionsMode ? L10n.QuickReactionStore.orderedKeys[0] : ""
        addingFavorite = false
        customFavoriteField.text = ""
    }
    onClosed: addingFavorite = false

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

    background: Rectangle {
        color: root.surfaceColor
        radius: 14
        border.width: 1
        border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                              root.dividerColor.b, 0.78)
    }

    contentItem: ColumnLayout {
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            color: root.elevatedColor
            radius: 14

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 14
                color: parent.color
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: root.quickReactionsMode ? L10n.I18n.tr("Быстрые реакции")
                        : root.addingFavorite
                        ? L10n.I18n.tr("Добавить · ") + root.currentCategoryName
                        : root.currentCategoryName
                    color: root.textPrimary
                    font.bold: true
                    font.pointSize: 10
                    elide: Text.ElideRight
                }

                Basic.Button {
                    id: addFavoriteButton
                    visible: !root.quickReactionsMode && root.selectedCategory === 0 && !root.addingFavorite
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    padding: 0
                    hoverEnabled: true
                    scale: down ? 0.84 : 1

                    contentItem: Item {
                        rotation: addFavoriteButton.hovered ? 90 : 0
                        Behavior on rotation {
                            NumberAnimation { duration: L10n.UiPreferences.duration(140); easing.type: Easing.OutCubic }
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 13
                            height: 1.5
                            radius: height / 2
                            color: addFavoriteButton.down || addFavoriteButton.hovered
                                ? root.accentColor : root.textSecondary
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 1.5
                            height: 13
                            radius: width / 2
                            color: addFavoriteButton.down || addFavoriteButton.hovered
                                ? root.accentColor : root.textSecondary
                        }
                    }
                    background: Rectangle {
                        radius: 8
                        color: addFavoriteButton.down
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                            : addFavoriteButton.hovered
                                ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                                : "transparent"
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                    }
                    onClicked: root.beginAddingFavorite()
                }

                Basic.Button {
                    id: finishFavoriteButton
                    visible: root.addingFavorite
                    Layout.preferredWidth: 58
                    Layout.preferredHeight: 28
                    padding: 0
                    hoverEnabled: true
                    scale: down ? 0.90 : 1
                    contentItem: Text {
                        text: L10n.I18n.tr("Назад")
                        color: root.textPrimary
                        font.pointSize: 8
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 8
                        color: finishFavoriteButton.down
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                            : finishFavoriteButton.hovered
                                ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                                : "transparent"
                    }
                    Behavior on scale {
                        NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                    }
                    onClicked: root.finishAddingFavorite()
                }

                Basic.Button {
                    id: closeButton
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    padding: 0
                    hoverEnabled: true
                    scale: down ? 0.84 : 1
                    contentItem: Item {
                        Rectangle {
                            anchors.centerIn: parent
                            width: 12
                            height: 1.2
                            rotation: 45
                            color: closeButton.down || closeButton.hovered
                                ? root.accentColor : root.textSecondary
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 12
                            height: 1.2
                            rotation: -45
                            color: closeButton.down || closeButton.hovered
                                ? root.accentColor : root.textSecondary
                        }
                    }
                    background: Rectangle {
                        radius: 8
                        color: closeButton.down
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                            : closeButton.hovered
                                ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                                : "transparent"
                    }
                    Behavior on scale {
                        NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                    }
                    onClicked: root.close()
                }
            }
        }

        ColumnLayout {
            visible: root.quickReactionsMode
            Layout.fillWidth: true
            Layout.margins: visible ? 8 : 0
            spacing: 5

            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 5
                LayoutMirroring.enabled: false
                Repeater {
                    model: L10n.QuickReactionStore.orderedKeys
                    delegate: Basic.Button {
                        id: quickSlot
                        required property string modelData
                        objectName: "quickSlot_" + modelData
                        readonly property bool selected: root.quickReactionTarget === modelData
                        width: 42; height: 38; padding: 0
                        hoverEnabled: true
                        scale: down ? 0.88 : 1
                        contentItem: Text {
                            text: quickSlot.modelData
                            font.family: root.emojiFontFamily
                            font.pointSize: 16
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        background: Rectangle {
                            radius: 8
                            color: quickSlot.down || quickSlot.selected
                                ? Qt.rgba(root.accentColor.r,root.accentColor.g,root.accentColor.b,0.18)
                                : quickSlot.hovered
                                    ? Qt.rgba(root.textPrimary.r,root.textPrimary.g,root.textPrimary.b,0.08)
                                    : "transparent"
                            border.width: quickSlot.selected ? 1 : 0
                            border.color: root.accentColor
                            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(90) } }
                        }
                        Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(90) } }
                        onClicked: root.quickReactionTarget = modelData
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: L10n.I18n.tr("Выберите реакцию сверху, затем новый эмодзи")
                color: root.textSecondary
                font.pointSize: 8
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
        }

        ListView {
            id: categoriesList
            Layout.fillWidth: true
            Layout.preferredHeight: 43
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            orientation: ListView.Horizontal
            spacing: 1
            clip: true
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds
            model: root.emojiCategories

            delegate: Basic.Button {
                id: categoryButton
                required property var modelData
                required property int index
                width: 35
                height: 39
                padding: 0
                hoverEnabled: true
                scale: down ? 0.88 : 1
                contentItem: Text {
                    text: categoryButton.modelData.icon
                    color: categoryButton.index === root.selectedCategory
                        ? root.accentColor : root.textSecondary
                    font.family: root.emojiFontFamily
                    font.pixelSize: 17
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 8
                    color: categoryButton.down
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                        : categoryButton.index === root.selectedCategory
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.13)
                            : categoryButton.hovered
                                ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.06)
                                : "transparent"
                    Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                }
                Behavior on scale {
                    NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                }
                onClicked: {
                    root.selectedCategory = categoryButton.index
                    if (categoryButton.index === 0)
                        root.addingFavorite = false
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                           root.dividerColor.b, 0.55)
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 48 : 0
            visible: root.addingFavorite || root.quickReactionsMode

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                spacing: 8

                Basic.TextField {
                    id: customFavoriteField
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    placeholderText: L10n.I18n.tr("Вставьте любой эмодзи")
                    color: root.textPrimary
                    placeholderTextColor: root.textSecondary
                    font.family: root.emojiFontFamily
                    selectByMouse: true
                    maximumLength: root.quickReactionsMode ? 64 : 32767
                    leftPadding: 10
                    rightPadding: 10
                    background: Rectangle {
                        radius: 8
                        color: root.elevatedColor
                        border.width: 1
                        border.color: customFavoriteField.activeFocus
                            ? root.accentColor
                            : Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                      root.dividerColor.b, 0.72)
                    }
                    onAccepted: root.addCustomFavorite()
                }

                Basic.Button {
                    id: customAddButton
                    Layout.preferredWidth: 74
                    Layout.fillHeight: true
                    enabled: customFavoriteField.text.trim() !== ""
                    padding: 0
                    hoverEnabled: true
                    scale: down ? 0.90 : 1
                    contentItem: Text {
                        text: root.quickReactionsMode ? L10n.I18n.tr("Заменить") : L10n.I18n.tr("Добавить")
                        color: customAddButton.enabled ? root.accentTextColor : root.textSecondary
                        font.bold: true
                        font.pointSize: 8
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 8
                        color: customAddButton.enabled
                            ? customAddButton.down
                                ? Qt.darker(root.accentColor, 1.12)
                                : customAddButton.hovered
                                    ? Qt.lighter(root.accentColor, 1.08)
                                    : root.accentColor
                            : Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                      root.textSecondary.b, 0.15)
                    }
                    Behavior on scale {
                        NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                    }
                    onClicked: root.addCustomFavorite()
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
                id: emojiGrid
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                clip: true
                cellWidth: 44
                cellHeight: 44
                boundsBehavior: Flickable.StopAtBounds
                model: root.emojisForCurrentCategory()

                delegate: Basic.Button {
                    id: emojiButton
                    required property var modelData
                    readonly property string emoji: String(modelData)
                    width: 40
                    height: 40
                    padding: 0
                    hoverEnabled: true
                    scale: down ? 0.86 : 1
                    contentItem: Text {
                        text: emojiButton.emoji
                        font.family: root.emojiFontFamily
                        font.pixelSize: 23
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 9
                        color: emojiButton.down
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                            : emojiButton.hovered
                                ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.075)
                                : "transparent"
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(90) } }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                    }
                    onClicked: root.activateEmoji(emojiButton.emoji)

                    Basic.Button {
                        id: removeFavoriteButton
                        visible: !root.quickReactionsMode && root.selectedCategory === 0 && emojiButton.hovered
                        anchors.top: parent.top
                        anchors.right: parent.right
                        width: 16
                        height: 16
                        padding: 0
                        hoverEnabled: true
                        z: 3
                        scale: down ? 0.76 : 1
                        contentItem: Item {
                            rotation: removeFavoriteButton.hovered ? 90 : 0
                            Behavior on rotation {
                                NumberAnimation { duration: L10n.UiPreferences.duration(120); easing.type: Easing.OutCubic }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 8
                                height: 1
                                rotation: 45
                                color: root.textPrimary
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 8
                                height: 1
                                rotation: -45
                                color: root.textPrimary
                            }
                        }
                        background: Rectangle {
                            radius: 8
                            color: removeFavoriteButton.down
                                ? Qt.rgba(1, 0.32, 0.32, 0.32)
                                : Qt.rgba(root.elevatedColor.r, root.elevatedColor.g,
                                          root.elevatedColor.b, 0.94)
                        }
                        Behavior on scale {
                            NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic }
                        }
                        onClicked: root.removeFavorite(emojiButton.emoji)
                    }
                }

                ScrollBar.vertical: PrismScrollBar {
                    autoHide: true
                    revealOnActive: true
                    handleColor: root.textSecondary
                    handleHoverColor: root.accentColor
                    trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                        root.textSecondary.b, 0.16)
                }
            }

            Column {
                visible: root.selectedCategory === 0
                    && root.favoriteEmojis.length === 0
                    && !root.addingFavorite
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: L10n.I18n.tr("Избранное пока пусто")
                    color: root.textPrimary
                    font.bold: true
                    font.pointSize: 10
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: L10n.I18n.tr("Нажмите +, чтобы добавить эмодзи")
                    color: root.textSecondary
                    font.pointSize: 8
                }
            }
        }
    }
}
