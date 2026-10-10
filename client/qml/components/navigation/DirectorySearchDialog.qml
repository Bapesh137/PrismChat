import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../common"
import "../../assets/icons" as Icons
import "../../utils" as L10n

Dialog {
    id: root

    property string searchMode: "users"
    property var results: []
    property bool loading: false
    property bool limited: false
    property string errorText: ""
    property string activeRequestId: ""
    property string currentUserId: ""
    property string mediaProxy: ""
    property bool roundAvatars: true
    property var requestIdFactory: null
    property int localRequestSequence: 0
    property real dragOffsetX: 0
    property real dragOffsetY: 0

    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color accentTextColor: "#071007"
    property color backgroundColor: "#07100A"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"

    signal searchRequested(string mode, string query, string requestId)
    signal userRequested(string userId)
    signal roomRequested(string roomId, string roomName, bool joined, string joinRule)
    signal spaceRequested(string roomId, string roomName, bool joined, string joinRule)
    signal createRoomRequested()

    width: 560
    height: 570
    x: parent ? Math.round((parent.width - width) / 2 + dragOffsetX) : 0
    y: parent ? Math.round((parent.height - height) / 2 + dragOffsetY) : 0
    modal: true
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function nextRequestId() {
        if (requestIdFactory)
            return requestIdFactory(searchMode === "users"
                ? "user-directory"
                : searchMode === "spaces" ? "space-directory" : "room-directory")
        localRequestSequence++
        return Date.now().toString() + "-directory-" + localRequestSequence
    }

    function meaningfulQueryLength(value) {
        var query = String(value || "").trim()
        if (searchMode === "users" && query.charAt(0) === "@")
            query = query.substring(1)
        else if ((searchMode === "rooms" || searchMode === "spaces")
                 && (query.charAt(0) === "#" || query.charAt(0) === "!"))
            query = query.substring(1)
        return query.length
    }


    function openFor(mode) {
        dragOffsetX = 0
        dragOffsetY = 0
        directoryMoveArea.resetMotion()
        searchMode = mode === "spaces" ? "spaces" : mode === "rooms" ? "rooms" : "users"
        queryField.text = ""
        results = []
        loading = false
        limited = false
        errorText = ""
        activeRequestId = ""
        open()
    }

    function setMode(mode) {
        if (searchMode === "spaces")
            return
        if (mode === searchMode)
            return
        searchMode = mode
        results = []
        limited = false
        errorText = ""
        activeRequestId = ""
        searchTimer.stop()
        if (meaningfulQueryLength(queryField.text) >= 1)
            searchTimer.restart()
        queryField.forceActiveFocus()
    }

    function dispatchSearch() {
        var query = queryField.text.trim()
        if (meaningfulQueryLength(query) < 1) {
            loading = false
            results = []
            activeRequestId = ""
            return
        }
        activeRequestId = nextRequestId()
        loading = true
        limited = false
        errorText = ""
        searchRequested(searchMode, query, activeRequestId)
    }

    function receiveResults(mode, items, isLimited, error, requestId) {
        if (!opened || mode !== searchMode || requestId !== activeRequestId)
            return
        loading = false
        results = items || []
        limited = !!isLimited
        errorText = error || ""
    }

    function resultTitle(entry) {
        if (searchMode === "users")
            return entry.display_name || entry.user_id || ""
        return entry.name || entry.canonical_alias || entry.room_id || ""
    }

    function entryJoinRule(entry) {
        return String((entry && entry.join_rule) || "").toLowerCase()
    }

    function entryIsKnockable(entry) {
        return entryJoinRule(entry).indexOf("knock") !== -1
    }

    function entryIsInviteOnly(entry) {
        var rule = entryJoinRule(entry)
        return rule === "invite" || rule.indexOf("invite") !== -1
    }

    function entryActionEnabled(entry) {
        if (searchMode === "users")
            return true
        if (entry.joined || entry.invited)
            return true
        if (entry.knocked || entryIsInviteOnly(entry))
            return false
        var rule = entryJoinRule(entry)
        return entryIsKnockable(entry)
            || rule.indexOf("public") !== -1
            || rule.indexOf("restricted") !== -1
    }

    function entryActionLabel(entry) {
        if (searchMode === "users")
            return L10n.I18n.tr("Написать")
        if (entry.joined)
            return L10n.I18n.tr("Открыть")
        if (entry.invited)
            return L10n.I18n.tr("Принять приглашение")
        if (entry.knocked)
            return L10n.I18n.tr("Заявка отправлена")
        if (entryIsInviteOnly(entry))
            return L10n.I18n.tr("Только по приглашению")
        if (entryIsKnockable(entry))
            return L10n.I18n.tr("Подать заявку")
        return L10n.I18n.tr("Вступить")
    }

    function exactPrivateSpaceAddress() {
        var query = queryField.text.trim()
        return searchMode === "spaces"
            && query.length > 2
            && (query.charAt(0) === "!" || query.charAt(0) === "#")
            && query.indexOf(":") > 1
            && query.indexOf(" ") === -1
    }

    function resultSubtitle(entry) {
        if (searchMode === "users")
            return entry.user_id || ""
        var alias = entry.canonical_alias || entry.room_id || ""
        var members = Number(entry.member_count || 0)
        var result = alias + (members > 0
            ? " · " + members + L10n.I18n.tr(" участников")
            : "")
        if (entry.invited)
            return result + " · " + L10n.I18n.tr("есть приглашение")
        if (entry.knocked)
            return result + " · " + L10n.I18n.tr("заявка отправлена")
        if (entryIsInviteOnly(entry))
            return result + " · " + L10n.I18n.tr("только по приглашению")
        if (entryIsKnockable(entry))
            return result + " · " + L10n.I18n.tr("можно подать заявку")
        return result
    }

    onOpened: Qt.callLater(function() { queryField.forceActiveFocus() })
    onClosed: {
        searchTimer.stop()
        activeRequestId = ""
        loading = false
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: L10n.UiPreferences.duration(90)
            }
            NumberAnimation {
                property: "scale"
                from: 0.97
                to: 1
                duration: L10n.UiPreferences.duration(120)
                easing.type: Easing.OutCubic
            }
        }
    }

    exit: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: L10n.UiPreferences.duration(70)
            }
            NumberAnimation {
                property: "scale"
                from: 1
                to: 0.985
                duration: L10n.UiPreferences.duration(70)
            }
        }
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.52)
    }

    background: Rectangle {
        radius: 16
        color: root.backgroundColor
        border.width: 1
        border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                              root.textSecondary.b, 0.18)
        transform: Matrix4x4 {
            matrix: PlanarTransform.fromShear(
                        Math.tan(directoryMoveArea.visualShearAngle * Math.PI / 180),
                        0, width / 2, 0)
        }
    }

    contentItem: Item {
        transform: Matrix4x4 {
            matrix: PlanarTransform.fromShear(
                        Math.tan(directoryMoveArea.visualShearAngle * Math.PI / 180),
                        0, width / 2, 0)
        }

        Rectangle {
            id: header
            anchors.top: parent.top
            width: parent.width
            height: root.searchMode === "spaces" ? 60 : 104
            color: root.surfaceColor
            radius: 16

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 16
                color: parent.color
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.top: parent.top
                anchors.topMargin: 15
                text: root.searchMode === "spaces"
                    ? L10n.I18n.tr("Присоединиться к пространству")
                    : L10n.I18n.tr("Новый чат")
                color: root.textPrimary
                font.bold: true
                font.pointSize: 13
            }

            PopupMoveArea {
                id: directoryMoveArea
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.right: closeButton.left
                height: 52
                moveTarget: root
                movementBoundary: root.parent
            }

            PopupCloseButton {
                id: closeButton
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 9
                anchors.rightMargin: 10
                accentColor: root.accentColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                onClicked: root.close()
            }

            Row {
                visible: root.searchMode !== "spaces"
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                height: 42
                spacing: 8

                Basic.Button {
                    id: usersTab
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    hoverEnabled: true
                    scale: down ? 0.96 : 1
                    text: L10n.I18n.tr("Пользователи")
                    onClicked: root.setMode("users")

                    Behavior on scale {
                        NumberAnimation {
                            duration: L10n.UiPreferences.duration(90)
                            easing.type: Easing.OutCubic
                        }
                    }

                    contentItem: Text {
                        text: usersTab.text
                        color: root.searchMode === "users"
                            ? root.accentTextColor : root.textSecondary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.bold: root.searchMode === "users"
                        font.pointSize: 9
                    }

                    background: Rectangle {
                        radius: 10
                        color: root.searchMode === "users"
                            ? root.accentColor
                            : usersTab.hovered ? root.elevatedColor : "transparent"
                        Behavior on color {
                            ColorAnimation { duration: L10n.UiPreferences.duration(100) }
                        }
                    }
                }

                Basic.Button {
                    id: roomsTab
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    hoverEnabled: true
                    scale: down ? 0.96 : 1
                    text: L10n.I18n.tr("Комнаты")
                    onClicked: root.setMode("rooms")

                    Behavior on scale {
                        NumberAnimation {
                            duration: L10n.UiPreferences.duration(90)
                            easing.type: Easing.OutCubic
                        }
                    }

                    contentItem: Text {
                        text: roomsTab.text
                        color: root.searchMode === "rooms"
                            ? root.accentTextColor : root.textSecondary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.bold: root.searchMode === "rooms"
                        font.pointSize: 9
                    }

                    background: Rectangle {
                        radius: 10
                        color: root.searchMode === "rooms"
                            ? root.accentColor
                            : roomsTab.hovered ? root.elevatedColor : "transparent"
                        Behavior on color {
                            ColorAnimation { duration: L10n.UiPreferences.duration(100) }
                        }
                    }
                }
            }
        }

        Basic.TextField {
            id: queryField
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 16
            anchors.topMargin: 14
            height: 42
            leftPadding: 42
            rightPadding: clearButton.visible ? 40 : 14
            verticalAlignment: TextInput.AlignVCenter
            color: root.textPrimary
            placeholderText: root.searchMode === "users"
                ? L10n.I18n.tr("Введите ник пользователя")
                : root.searchMode === "spaces"
                    ? L10n.I18n.tr("Введите название пространства")
                    : L10n.I18n.tr("Введите название комнаты")
            placeholderTextColor: root.textSecondary
            selectionColor: root.accentColor
            selectedTextColor: root.accentTextColor
            font.pointSize: 10

            background: Rectangle {
                radius: 11
                color: root.elevatedColor
                border.width: queryField.activeFocus ? 1 : 0
                border.color: root.accentColor

                Icons.SearchIcon {
                    anchors.left: parent.left
                    anchors.leftMargin: 13
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17
                    height: 17
                    color: root.iconColor
                }
            }

            onTextChanged: {
                searchTimer.stop()
                root.activeRequestId = ""
                root.results = []
                root.loading = false
                root.limited = false
                root.errorText = ""
                if (root.meaningfulQueryLength(text) >= 1)
                    searchTimer.restart()
            }
            onAccepted: {
                searchTimer.stop()
                root.dispatchSearch()
            }

            Basic.ToolButton {
                id: clearButton
                visible: queryField.text !== ""
                anchors.right: parent.right
                anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                padding: 0
                hoverEnabled: true
                scale: down ? 0.86 : 1

                contentItem: Icons.CloseIcon {
                    width: 12
                    height: 12
                    color: clearButton.hovered ? root.textPrimary : root.textSecondary
                }
                background: Item {}
                onClicked: queryField.clear()
            }
        }

        Item {
            id: resultArea
            anchors.top: queryField.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            ListView {
                id: resultList
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.bottomMargin: privateKnockRow.visible
                    ? 88 : root.searchMode === "spaces" ? 18 : 72
                clip: true
                spacing: 4
                model: root.results
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: PrismScrollBar {
                    policy: ScrollBar.AsNeeded
                    autoHide: true
                    autoHideDelay: 1800
                    handleColor: root.textSecondary
                    handleHoverColor: root.accentColor
                    trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                        root.textSecondary.b, 0.14)
                }

                delegate: Rectangle {
                    id: resultDelegate
                    required property var modelData

                    width: resultList.width
                    height: 70
                    radius: 11
                    color: resultMouse.containsMouse
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                  root.accentColor.b, 0.10)
                        : "transparent"

                    readonly property bool isSelf: root.searchMode === "users"
                        && (modelData.user_id || "") === root.currentUserId

                    Behavior on color {
                        ColorAnimation { duration: L10n.UiPreferences.duration(90) }
                    }

                    AvatarItem {
                        id: avatar
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        size: 44
                        mxcUrl: resultDelegate.modelData.avatar_url || ""
                        fallbackId: resultDelegate.modelData.user_id
                            || resultDelegate.modelData.room_id || ""
                        mediaProxy: root.mediaProxy
                        roundAvatars: root.roundAvatars
                    }

                    Text {
                        id: resultName
                        anchors.left: avatar.right
                        anchors.leftMargin: 12
                        anchors.right: actionLabel.left
                        anchors.rightMargin: 10
                        anchors.top: parent.top
                        anchors.topMargin: 13
                        text: root.resultTitle(resultDelegate.modelData)
                        color: root.textPrimary
                        font.bold: true
                        font.pointSize: 10
                        elide: Text.ElideRight
                    }

                    Text {
                        anchors.left: resultName.left
                        anchors.right: actionLabel.left
                        anchors.rightMargin: 10
                        anchors.top: resultName.bottom
                        anchors.topMargin: 5
                        text: root.resultSubtitle(resultDelegate.modelData)
                        color: root.textSecondary
                        font.pointSize: 8
                        elide: Text.ElideRight
                    }

                    Text {
                        id: actionLabel
                        anchors.right: actionArrow.left
                        anchors.rightMargin: 5
                        anchors.verticalCenter: parent.verticalCenter
                        text: resultDelegate.isSelf
                            ? L10n.I18n.tr("Это вы")
                            : root.entryActionLabel(resultDelegate.modelData)
                        color: resultDelegate.isSelf
                            || !root.entryActionEnabled(resultDelegate.modelData)
                            ? root.textSecondary : root.accentColor
                        font.pointSize: 8
                    }

                    Icons.ChevronIcon {
                        id: actionArrow
                        visible: !resultDelegate.isSelf
                            && root.entryActionEnabled(resultDelegate.modelData)
                        anchors.right: parent.right
                        anchors.rightMargin: 11
                        anchors.verticalCenter: parent.verticalCenter
                        width: 17
                        height: 17
                        direction: "right"
                        color: root.iconColor
                    }

                    MouseArea {
                        id: resultMouse
                        anchors.fill: parent
                        enabled: !resultDelegate.isSelf
                            && root.entryActionEnabled(resultDelegate.modelData)
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            var entry = resultDelegate.modelData
                            root.close()
                            if (root.searchMode === "users") {
                                root.userRequested(entry.user_id || "")
                            } else if (root.searchMode === "spaces") {
                                root.spaceRequested(
                                    entry.room_id || "",
                                    entry.name || entry.canonical_alias || entry.room_id || "",
                                    !!entry.joined,
                                    entry.join_rule || "public"
                                )
                            } else {
                                root.roomRequested(
                                    entry.room_id || "",
                                    entry.name || entry.canonical_alias || entry.room_id || "",
                                    !!entry.joined,
                                    entry.join_rule || "public"
                                )
                            }
                        }
                    }
                }
            }

            PrismBusyIndicator {
                anchors.centerIn: parent
                running: root.loading
                width: 26
                height: 26
                strokeWidth: 2.2
                accentColor: root.accentColor
            }

            Text {
                anchors.centerIn: parent
                visible: !root.loading && root.errorText !== ""
                width: parent.width - 60
                text: root.errorText
                color: "#ff6b6b"
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.pointSize: 9
            }

            Text {
                anchors.centerIn: parent
                visible: !root.loading && root.errorText === ""
                    && root.meaningfulQueryLength(queryField.text) < 1
                width: parent.width - 60
                text: root.searchMode === "spaces"
                    ? L10n.I18n.tr("Начните вводить название пространства")
                    : L10n.I18n.tr("Начните вводить ник или название")
                color: root.textSecondary
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.pointSize: 9
            }

            Text {
                anchors.centerIn: parent
                visible: !root.loading && root.errorText === ""
                    && root.meaningfulQueryLength(queryField.text) >= 1
                    && root.results.length === 0
                width: parent.width - 60
                text: L10n.I18n.tr("Ничего не найдено")
                color: root.textSecondary
                horizontalAlignment: Text.AlignHCenter
                font.pointSize: 9
            }

            Rectangle {
                id: privateKnockRow
                visible: !root.loading && root.results.length === 0
                    && root.exactPrivateSpaceAddress()
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.bottomMargin: 16
                height: 58
                radius: 11
                color: root.surfaceColor
                border.width: 1
                border.color: root.dividerColor

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: privateKnockButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: L10n.I18n.tr("Если пространство поддерживает knock, заявку можно отправить по ID или alias")
                    color: root.textSecondary
                    font.pointSize: 8
                    elide: Text.ElideRight
                }

                Basic.Button {
                    id: privateKnockButton
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 122
                    height: 38
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    text: L10n.I18n.tr("Подать заявку")
                    onClicked: {
                        var roomAddress = queryField.text.trim()
                        root.close()
                        root.spaceRequested(roomAddress, roomAddress, false, "knock")
                    }
                    background: Rectangle {
                        radius: 9
                        color: privateKnockButton.down
                            ? Qt.darker(root.accentColor, 1.18)
                            : privateKnockButton.hovered
                                ? Qt.darker(root.accentColor, 1.08)
                                : root.accentColor
                    }
                    contentItem: Text {
                        text: privateKnockButton.text
                        color: root.accentTextColor
                        font.pointSize: 8
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 7
                visible: root.limited && root.results.length > 0
                text: L10n.I18n.tr("Показаны первые результаты")
                color: root.textSecondary
                font.pointSize: 7
            }

            Basic.ToolButton {
                id: createRoomButton
                visible: root.searchMode !== "spaces"
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                width: 48
                height: 48
                padding: 0
                hoverEnabled: true
                z: 20
                scale: down ? 0.94 : 1

                Behavior on scale {
                    NumberAnimation {
                        duration: L10n.UiPreferences.duration(90)
                        easing.type: Easing.OutCubic
                    }
                }

                contentItem: Icons.PlusIcon {
                    width: 17
                    height: 17
                    strokeWidth: 1.5
                    color: root.accentTextColor
                }

                background: Rectangle {
                    radius: width / 2
                    color: createRoomButton.down
                        ? Qt.darker(root.accentColor, 1.22)
                        : createRoomButton.hovered
                            ? Qt.darker(root.accentColor, 1.10)
                            : root.accentColor
                    border.width: 0
                    Behavior on color {
                        ColorAnimation { duration: L10n.UiPreferences.duration(110) }
                    }
                }

                ToolTip {
                    id: createRoomToolTip
                    visible: createRoomButton.hovered
                    text: L10n.I18n.tr("Создать комнату")
                    delay: 300
                    timeout: 3000
                    x: createRoomButton.width - implicitWidth
                    y: -implicitHeight - 7
                    leftPadding: 10
                    rightPadding: 10
                    topPadding: 7
                    bottomPadding: 7
                    z: 10000

                    contentItem: Text {
                        text: createRoomToolTip.text
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
                }

                onClicked: {
                    root.close()
                    root.createRoomRequested()
                }
            }
        }
    }

    Timer {
        id: searchTimer
        interval: 280
        repeat: false
        onTriggered: root.dispatchSearch()
    }
}
