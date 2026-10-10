import QtQuick
import "../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../assets/icons" as Icons
import "../common"

Rectangle {
    id: root

    property string roomId: ""
    property string roomName: L10n.I18n.tr("Выберите чат")
    // -1 = state is not loaded, 0 = unencrypted, 1 = Matrix E2EE enabled.
    property int roomEncryptionState: -1
    property int selectedCount: 0
    property bool multiSelectMode: false
    property bool chatsPanelCollapsed: false
    property bool membersPanelCollapsed: false
    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property bool searchVisible: false
    property int pinnedCount: 0
    property bool hasNewPinnedMessages: false
    property int threadUnreadCount: 0
    property bool threadsPanelOpen: false
    property bool threadsEnabled: true
    property bool markingThreadsRead: false
    property bool directCallAvailable: false
    property bool directCallActive: false
    property var searchMembers: []
    property var searchSuggestions: []
    property int searchSuggestionIndex: 0
    readonly property color roomIdentityColor: root.accentColor
    readonly property color encryptionStatusColor: root.roomEncryptionState === 1
        ? "#45c978" : root.roomEncryptionState === 0
            ? "#e45d68" : root.textSecondary
    readonly property string encryptionStatusText: root.roomEncryptionState === 1
        ? L10n.I18n.tr("Сквозное шифрование включено. Содержимое сообщений защищено Matrix E2EE.")
        : root.roomEncryptionState === 0
            ? L10n.I18n.tr("Сквозное шифрование выключено. Сообщения этой комнаты не защищены Matrix E2EE.")
            : L10n.I18n.tr("Состояние шифрования комнаты ещё загружается.")

    readonly property real searchFieldLeftX: headerActions.x + searchField.x
    readonly property real searchFieldRightX: searchFieldLeftX + searchField.width

    // Optical alignment controls. Negative values move an element up.
    // Positive values move it down inside its 32 px header slot.
    property real leftArrowVerticalOffset: 0
    property real hashVerticalOffset: -1.0
    property real roomNameVerticalOffset: 0.75
    property real searchIconVerticalOffset: 0
    property real pinnedIconVerticalOffset: 0
    property real rightArrowVerticalOffset: 0

    signal chatsPanelToggleRequested()
    signal clearSelectionRequested()
    signal membersPanelToggleRequested()
    signal searchRequested(string query)
    signal searchVisibilityChanged(bool visible)
    signal pinnedRequested()
    signal threadsRequested()
    signal threadsReadRequested()
    signal callRequested()

    onRoomIdChanged: threadsMenu.close()
    onThreadsEnabledChanged: if (!threadsEnabled) threadsMenu.close()

    function closeSearch() {
        if (!searchVisible) return
        searchVisible = false
        searchField.text = ""
        searchVisibilityChanged(false)
    }

    function focusMessageSearch() {
        if (!searchVisible) {
            searchVisible = true
            searchVisibilityChanged(true)
        }
        searchField.forceActiveFocus()
        if (searchField.text !== "")
            searchField.selectAll()
    }

    function dateText(offsetDays) {
        var date = new Date(Date.now() + offsetDays * 86400000)
        return date.getFullYear() + "-"
            + String(date.getMonth() + 1).padStart(2, "0") + "-"
            + String(date.getDate()).padStart(2, "0")
    }

    function updateSearchSuggestions() {
        var text = searchField.text || ""
        var start = Math.max(text.lastIndexOf(" "), text.lastIndexOf("\n")) + 1
        var token = text.slice(start).toLowerCase()
        var suggestions = []
        if (token.indexOf("has:") === 0) {
            var media = ["image", "video", "audio", "file", "link"]
            var mediaNeedle = token.slice(4)
            for (var i = 0; i < media.length; i++)
                if (media[i].indexOf(mediaNeedle) === 0)
                    suggestions.push({ value: "has:" + media[i], title: "has:" + media[i], description: L10n.I18n.tr("Фильтр по типу вложения") })
        } else if (token.indexOf("from:") === 0) {
            var senderNeedle = token.slice(5)
            var members = root.searchMembers || []
            for (var memberIndex = 0; memberIndex < members.length && suggestions.length < 8; memberIndex++) {
                var member = members[memberIndex] || ({})
                var userId = String(member.user_id || "")
                var name = String(member.display_name || userId)
                if (userId.toLowerCase().indexOf(senderNeedle) !== -1
                        || name.toLowerCase().indexOf(senderNeedle) !== -1)
                    suggestions.push({ value: "from:" + userId, title: name, description: userId })
            }
        } else if (token.indexOf("before:") === 0 || token.indexOf("after:") === 0) {
            var prefix = token.indexOf("before:") === 0 ? "before:" : "after:"
            suggestions = [
                { value: prefix + root.dateText(0), title: prefix + root.dateText(0), description: L10n.I18n.tr("Сегодня") },
                { value: prefix + root.dateText(-1), title: prefix + root.dateText(-1), description: L10n.I18n.tr("Вчера") },
                { value: prefix + root.dateText(-7), title: prefix + root.dateText(-7), description: L10n.I18n.tr("Неделю назад") }
            ]
        } else {
            var operators = [
                { value: "from:", title: "from:", description: L10n.I18n.tr("Сообщения от пользователя") },
                { value: "has:", title: "has:", description: L10n.I18n.tr("Сообщения с вложением") },
                { value: "before:", title: "before:", description: L10n.I18n.tr("До указанной даты") },
                { value: "after:", title: "after:", description: L10n.I18n.tr("После указанной даты") }
            ]
            for (var operatorIndex = 0; operatorIndex < operators.length; operatorIndex++)
                if (operators[operatorIndex].value.indexOf(token) === 0)
                    suggestions.push(operators[operatorIndex])
        }
        root.searchSuggestions = suggestions
        root.searchSuggestionIndex = 0
    }

    function applySearchSuggestion(value) {
        var text = searchField.text || ""
        var start = Math.max(text.lastIndexOf(" "), text.lastIndexOf("\n")) + 1
        searchField.text = text.slice(0, start) + value + (value.endsWith(":") ? "" : " ")
        searchField.cursorPosition = searchField.text.length
        searchField.forceActiveFocus()
        root.updateSearchSuggestions()
    }

    implicitHeight: 44
    color: surfaceColor

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(root.roomIdentityColor.r, root.roomIdentityColor.g,
                       root.roomIdentityColor.b, 0.045)
    }

    Basic.ToolButton {
        id: chatsPanelButton
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        height: 32
        padding: 0
        hoverEnabled: true
        scale: down ? 0.88 : 1
        ToolTip {
            id: chatsPanelToolTip
            visible: chatsPanelButton.hovered
            text: root.chatsPanelCollapsed ? L10n.I18n.tr("Показать чаты") : L10n.I18n.tr("Скрыть чаты")
            delay: 300
            timeout: 3000
            x: 0
            y: chatsPanelButton.height + 4
            leftPadding: 10
            rightPadding: 10
            topPadding: 7
            bottomPadding: 7

            contentItem: Text {
                text: chatsPanelToolTip.text
                color: root.textPrimary
                font.pointSize: 8
            }

            background: Rectangle {
                radius: 8
                color: root.elevatedColor
                border.width: 1
                border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                      root.textSecondary.b, 0.38)
            }

            enter: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: L10n.UiPreferences.duration(110) }
            }
            exit: Transition {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: L10n.UiPreferences.duration(90) }
            }
        }

        contentItem: Item {
            Icons.ChevronIcon {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: root.leftArrowVerticalOffset
                width: 20
                height: 20
                direction: root.chatsPanelCollapsed ? "right" : "left"
                color: chatsPanelButton.down
                    ? Qt.darker(root.iconColor, 1.12)
                    : chatsPanelButton.hovered ? root.textPrimary : root.iconColor
                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
            }
        }

        background: Rectangle {
            radius: 8
            color: chatsPanelButton.down
                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                : chatsPanelButton.hovered
                    ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                    : "transparent"
            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
        }

        Behavior on scale {
            NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
        }
        onClicked: root.chatsPanelToggleRequested()
    }

    Row {
        id: titleRow
        anchors.left: chatsPanelButton.right
        anchors.leftMargin: 4
        anchors.right: root.multiSelectMode ? selectionBox.left : headerActions.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        height: 32
        spacing: 8

        Rectangle {
            id: roomIdentityBadge
            width: 30
            height: 30
            anchors.verticalCenter: titleRow.verticalCenter
            anchors.verticalCenterOffset: root.hashVerticalOffset
            radius: 9
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(root.roomIdentityColor.r,
                                  root.roomIdentityColor.g,
                                  root.roomIdentityColor.b, 0.72)

            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: 7
                color: root.roomIdentityColor

                Behavior on color {
                    ColorAnimation { duration: L10n.UiPreferences.duration(160) }
                }

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -0.5
                    text: "#"
                    color: "white"
                    font.pointSize: 12
                    font.bold: true
                    renderType: Text.NativeRendering
                }
            }
        }

        Text {
            height: titleRow.height
            width: Math.min(implicitWidth, Math.max(0, titleRow.width - roomIdentityBadge.width
                            - titleRow.spacing
                            - (encryptionStatus.visible
                               ? encryptionStatus.width + titleRow.spacing : 0)))
            anchors.verticalCenter: titleRow.verticalCenter
            anchors.verticalCenterOffset: root.roomNameVerticalOffset
            text: root.roomName
            color: root.textPrimary
            font.bold: true
            font.pointSize: 11
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            renderType: Text.NativeRendering
        }
        Item {
            id: encryptionStatus
            visible: root.roomId !== ""
            width: visible ? 28 : 0
            height: titleRow.height

            Icons.LockStatusIcon {
                anchors.centerIn: parent
                width: 20
                height: 20
                encryptionState: root.roomEncryptionState
                color: root.encryptionStatusColor
                strokeWidth: 1.65
            }

            MouseArea {
                id: encryptionStatusMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.WhatsThisCursor
            }

            ToolTip {
                id: encryptionStatusToolTip
                visible: encryptionStatusMouse.containsMouse
                delay: 250
                timeout: 7000
                x: -4
                y: encryptionStatus.height + 5
                leftPadding: 11
                rightPadding: 11
                topPadding: 8
                bottomPadding: 8

                contentItem: Text {
                    width: 270
                    text: root.encryptionStatusText
                    color: root.textPrimary
                    font.pointSize: 8
                    wrapMode: Text.Wrap
                }

                background: Rectangle {
                    radius: 9
                    color: root.elevatedColor
                    border.width: 1
                    border.color: Qt.rgba(root.encryptionStatusColor.r,
                                          root.encryptionStatusColor.g,
                                          root.encryptionStatusColor.b, 0.48)
                }

                enter: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: L10n.UiPreferences.duration(110)
                    }
                }
                exit: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 1
                        to: 0
                        duration: L10n.UiPreferences.duration(90)
                    }
                }
            }
        }
    }

    Rectangle {
        id: selectionBox
        visible: root.multiSelectMode
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 32
        width: selectionRow.width + 16
        radius: 8
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15)

        Row {
            id: selectionRow
            anchors.centerIn: parent
            spacing: 8
            Text {
                text: L10n.I18n.tr("Выбрано: ") + root.selectedCount
                color: root.accentColor
                font.pointSize: 9
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Basic.Button {
                id: clearSelectionButton
                width: 24
                height: 24
                padding: 0
                flat: true
                hoverEnabled: true
                scale: down ? 0.88 : 1
                property color iconColor: down
                    ? Qt.darker(root.iconColor, 1.12)
                    : hovered ? root.textPrimary : root.iconColor

                contentItem: Item {
                    implicitWidth: 18
                    implicitHeight: 18

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) * 0.66
                        height: 1.6
                        radius: 0
                        color: clearSelectionButton.iconColor
                        rotation: 45
                        antialiasing: true
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) * 0.66
                        height: 1.6
                        radius: 0
                        color: clearSelectionButton.iconColor
                        rotation: -45
                        antialiasing: true
                    }
                }

                background: Rectangle {
                    radius: 8
                    color: clearSelectionButton.down
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                        : clearSelectionButton.hovered
                            ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                            : "transparent"
                    Behavior on color {
                        ColorAnimation { duration: L10n.UiPreferences.duration(110) }
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: L10n.UiPreferences.duration(100)
                        easing.type: Easing.OutCubic
                    }
                }

                onClicked: root.clearSelectionRequested()
            }
        }
    }

    Basic.ToolButton {
        id: membersPanelButton
        visible: !root.multiSelectMode
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        height: 32
        padding: 0
        hoverEnabled: true
        scale: down ? 0.88 : 1
        ToolTip {
            id: membersPanelToolTip
            visible: membersPanelButton.hovered
            text: root.membersPanelCollapsed ? L10n.I18n.tr("Показать участников") : L10n.I18n.tr("Скрыть участников")
            delay: 300
            timeout: 3000
            x: membersPanelButton.width - width
            y: membersPanelButton.height + 4
            leftPadding: 10
            rightPadding: 10
            topPadding: 7
            bottomPadding: 7

            contentItem: Text {
                text: membersPanelToolTip.text
                color: root.textPrimary
                font.pointSize: 8
            }

            background: Rectangle {
                radius: 8
                color: root.elevatedColor
                border.width: 1
                border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                      root.textSecondary.b, 0.38)
            }

            enter: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: L10n.UiPreferences.duration(110) }
            }
            exit: Transition {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: L10n.UiPreferences.duration(90) }
            }
        }

        contentItem: Item {
            Icons.ChevronIcon {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: root.rightArrowVerticalOffset
                width: 20
                height: 20
                direction: root.membersPanelCollapsed ? "left" : "right"
                color: membersPanelButton.down
                    ? Qt.darker(root.iconColor, 1.12)
                    : membersPanelButton.hovered ? root.textPrimary : root.iconColor
                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
            }
        }

        background: Rectangle {
            radius: 8
            color: membersPanelButton.down
                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                : membersPanelButton.hovered
                    ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                    : "transparent"
            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
        }

        Behavior on scale {
            NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
        }
        onClicked: root.membersPanelToggleRequested()
    }
    Row {
        id: headerActions
        z: 1
        visible: !root.multiSelectMode
        anchors.right: membersPanelButton.visible ? membersPanelButton.left : parent.right
        anchors.rightMargin: membersPanelButton.visible ? 4 : 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Basic.Button {
            id: callButton
            visible: root.directCallAvailable
            width: 32; height: 32; padding: 0; flat: true; hoverEnabled: true
            scale: down ? 0.88 : 1
            PrismToolTip {
                visible: callButton.hovered
                text: root.directCallActive ? L10n.I18n.tr("Открыть звонок") : L10n.I18n.tr("Позвонить")
                surfaceColor: root.elevatedColor
                textColor: root.textPrimary
                dividerColor: root.textSecondary
            }
            contentItem: Item {
                Icons.CallIcon {
                    anchors.centerIn: parent; width: 18; height: 18; strokeWidth: 1.55
                    color: callButton.hovered || root.directCallActive ? root.textPrimary : root.iconColor
                }
            }
            background: Rectangle {
                radius: 8
                color: root.directCallActive
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                    : callButton.hovered ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08) : "transparent"
            }
            onClicked: root.callRequested()
        }

        Basic.TextField {
            id: searchField
            visible: root.searchVisible
            width: 220
            height: 32
            placeholderText: L10n.I18n.tr("Поиск сообщений")
            color: root.textPrimary
            placeholderTextColor: root.textSecondary
            selectByMouse: true
            leftPadding: 11
            rightPadding: 30
            topPadding: 7
            bottomPadding: 7
            background: Rectangle {
                radius: 8
                // Keep the expanding search field opaque so the title icons
                // below it never bleed through during the transition.
                color: Qt.tint(Qt.tint(root.surfaceColor,
                    Qt.rgba(root.roomIdentityColor.r, root.roomIdentityColor.g,
                            root.roomIdentityColor.b, 0.045)),
                    Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                            root.textPrimary.b, 0.055))
                border.color: searchField.activeFocus
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.55)
                    : Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.22)
            }
            onTextChanged: root.updateSearchSuggestions()
            onAccepted: if (text.trim() !== "") root.searchRequested(text.trim())
            Keys.onPressed: function(event) {
                if (root.searchSuggestions.length === 0) return
                if (event.key === Qt.Key_Down) {
                    root.searchSuggestionIndex = Math.min(root.searchSuggestions.length - 1,
                                                          root.searchSuggestionIndex + 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                    root.searchSuggestionIndex = Math.max(0, root.searchSuggestionIndex - 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Tab
                           || event.key === Qt.Key_Return
                           || event.key === Qt.Key_Enter) {
                    root.applySearchSuggestion(root.searchSuggestions[root.searchSuggestionIndex].value)
                    event.accepted = true
                }
            }
        }

        Item {
            width: 0; height: 0
        Rectangle {
            id: searchSuggestionsPopup
            visible: root.searchVisible && root.searchSuggestions.length > 0
            z: 5000
            width: 280
            height: visible ? Math.min(240, suggestionsColumn.implicitHeight + 12) : 0
            x: -searchField.width - headerActions.spacing
            y: searchField.height + 5
            radius: 9
            color: root.elevatedColor
            border.width: 1
            border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                  root.textSecondary.b, 0.25)
            Column {
                id: suggestionsColumn
                anchors.fill: parent; anchors.margins: 6; spacing: 2
                Repeater {
                    model: root.searchSuggestions
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: suggestionsColumn.width; height: 40; radius: 6
                        color: index === root.searchSuggestionIndex
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                            : suggestionMouse.containsMouse
                                ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.06)
                                : "transparent"
                        Column { anchors.fill: parent; anchors.leftMargin: 9; anchors.rightMargin: 9; anchors.topMargin: 5
                            Text { width: parent.width; text: modelData.title || modelData.value; color: root.textPrimary; font.pointSize: 8; font.bold: true; elide: Text.ElideRight }
                            Text { width: parent.width; text: modelData.description || ""; color: root.textSecondary; font.pointSize: 7; elide: Text.ElideRight }
                        }
                        MouseArea { id: suggestionMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.applySearchSuggestion(modelData.value) }
                    }
                }
            }
        }
        }

        Basic.Button {
            id: searchToggleButton
            width: 32
            height: 32
            padding: 0
            flat: true
            hoverEnabled: true
            scale: down ? 0.88 : 1
            property color iconColor: down
                ? Qt.darker(root.iconColor, 1.12)
                : hovered ? root.textPrimary : root.iconColor
            ToolTip {
                id: searchToolTip
                visible: searchToggleButton.hovered
                text: root.searchVisible ? L10n.I18n.tr("Закрыть поиск") : L10n.I18n.tr("Найти сообщения")
                delay: 300
                timeout: 3000
                x: Math.round((searchToggleButton.width - width) / 2)
                y: searchToggleButton.height + 4
                leftPadding: 10
                rightPadding: 10
                topPadding: 7
                bottomPadding: 7

                contentItem: Text {
                    text: searchToolTip.text
                    color: root.textPrimary
                    font.pointSize: 8
                }

                background: Rectangle {
                    radius: 8
                    color: root.elevatedColor
                    border.width: 1
                    border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                          root.textSecondary.b, 0.38)
                }

                enter: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: L10n.UiPreferences.duration(110) }
                }
                exit: Transition {
                    NumberAnimation { property: "opacity"; from: 1; to: 0; duration: L10n.UiPreferences.duration(90) }
                }
            }

            contentItem: Item {
                Icons.SearchIcon {
                    id: messageSearchIcon
                    visible: !root.searchVisible
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: root.searchIconVerticalOffset
                    width: 15
                    height: 15
                    color: searchToggleButton.iconColor
                    strokeWidth: 1.45
                }

                Icons.CloseIcon {
                    id: messageSearchCloseIcon
                    visible: root.searchVisible
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    strokeWidth: 1.6
                    color: searchToggleButton.iconColor
                }
            }

            onClicked: {
                if (root.searchVisible) {
                    root.closeSearch()
                } else {
                    root.focusMessageSearch()
                }
            }

            background: Rectangle {
                radius: 8
                color: searchToggleButton.down
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                    : searchToggleButton.hovered
                        ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                        : "transparent"
                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
            }
            Behavior on scale {
                NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
            }
        }

        Basic.Button {
            id: threadsButton
            objectName: "threadsButton"
            visible: root.threadsEnabled
            width: 32
            height: 32
            padding: 0
            flat: true
            hoverEnabled: true
            scale: down ? 0.88 : 1
            ToolTip {
                id: threadsToolTip
                visible: threadsButton.hovered
                text: L10n.I18n.tr("Треды")
                delay: 300
                timeout: 3000
                x: Math.round((threadsButton.width - width) / 2)
                y: threadsButton.height + 4
                leftPadding: 10
                rightPadding: 10
                topPadding: 7
                bottomPadding: 7

                contentItem: Text {
                    text: threadsToolTip.text
                    color: root.textPrimary
                    font.pointSize: 8
                }

                background: Rectangle {
                    radius: 8
                    color: root.elevatedColor
                    border.width: 1
                    border.color: Qt.rgba(root.textSecondary.r,
                                          root.textSecondary.g,
                                          root.textSecondary.b, 0.38)
                }

                enter: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: L10n.UiPreferences.duration(110)
                    }
                }
                exit: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 1
                        to: 0
                        duration: L10n.UiPreferences.duration(90)
                    }
                }
            }
            contentItem: Item {
                Rectangle {
                    x: 7; y: 8; width: 14; height: 10; radius: 4
                    color: "transparent"
                    border.width: 1.5
                    border.color: threadsButton.hovered ? root.textPrimary : root.iconColor
                    Rectangle {
                        x: 2; anchors.top: parent.bottom; anchors.topMargin: -1
                        width: 4; height: 4; rotation: 35
                        color: parent.border.color
                    }
                }
                Rectangle {
                    visible: root.threadUnreadCount > 0
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: Math.max(14, threadBadge.implicitWidth + 6)
                    height: 14
                    radius: 7
                    color: root.accentColor
                    Text {
                        id: threadBadge
                        anchors.centerIn: parent
                        text: root.threadUnreadCount > 99 ? "99+" : String(root.threadUnreadCount)
                        color: "#071007"
                        font.pixelSize: 9
                        font.bold: true
                    }
                }
            }
            background: Rectangle {
                radius: 8
                color: root.threadsPanelOpen
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                    : threadsButton.hovered
                        ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                        : "transparent"
            }
            onClicked: root.threadsRequested()
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: threadsMenu.popup()
            }
            Basic.Menu {
                id: threadsMenu
                objectName: "threadActionsMenu"
                width: 250
                x: threadsButton.width - width
                y: threadsButton.height + 4
                padding: 6
                background: Rectangle {
                    radius: 10
                    color: root.elevatedColor
                    border.color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.12)
                }
                Basic.MenuItem {
                    id: markThreadsReadAction
                    objectName: "markThreadsReadAction"
                    text: L10n.I18n.tr("Пометить как прочитанное")
                    enabled: root.roomId !== "" && !root.markingThreadsRead
                    height: 38
                    onTriggered: root.threadsReadRequested()
                    contentItem: Text {
                        text: markThreadsReadAction.text
                        color: root.textPrimary
                        opacity: markThreadsReadAction.enabled ? 1 : 0.45
                        font.pointSize: 9
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 6
                        color: markThreadsReadAction.down
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                            : markThreadsReadAction.highlighted
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.13)
                                : "transparent"
                    }
                }
            }
        }

        Basic.Button {
            id: pinnedButton
            width: 32
            height: 32
            padding: 0
            flat: true
            hoverEnabled: true
            scale: down ? 0.88 : 1
            property color iconColor: down ? Qt.darker(root.iconColor, 1.12)
                : hovered ? root.textPrimary : root.iconColor
            ToolTip {
                id: pinnedMessagesToolTip
                visible: pinnedButton.hovered
                text: L10n.I18n.tr("Закреплённые сообщения")
                delay: 300
                timeout: 3000
                x: Math.max(-8, pinnedButton.width - implicitWidth)
                y: pinnedButton.height + 5
                leftPadding: 10
                rightPadding: 10
                topPadding: 7
                bottomPadding: 7

                contentItem: Text {
                    text: pinnedMessagesToolTip.text
                    color: root.textPrimary
                    font.pointSize: 8
                }

                background: Rectangle {
                    radius: 8
                    color: root.elevatedColor
                    border.width: 1
                    border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                          root.textSecondary.b, 0.38)
                }

                enter: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: L10n.UiPreferences.duration(110)
                    }
                }
                exit: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 1
                        to: 0
                        duration: L10n.UiPreferences.duration(90)
                    }
                }
            }
            contentItem: Item {
                Icons.PinIcon {
                    id: pinnedIcon
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: root.pinnedIconVerticalOffset
                    width: 18
                    height: 18
                    color: pinnedButton.iconColor
                    filled: root.hasNewPinnedMessages
                }
            }
            background: Rectangle {
                radius: 8
                color: pinnedButton.down
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                    : pinnedButton.hovered
                        ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                        : "transparent"
                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
            }
            Behavior on scale {
                NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
            }
            onClicked: root.pinnedRequested()
        }
    }
}
