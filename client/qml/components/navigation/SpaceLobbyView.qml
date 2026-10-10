import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../common"
import "../../utils" as L10n
import "../../assets/icons" as Icons

Rectangle {
    id: root

    property var roomModel
    property var hierarchyRooms: []
    property bool hierarchyReady: false
    property string hierarchyNextBatch: ""
    property bool hierarchyLoading: false
    property string hierarchyError: ""
    property string selectedSpaceId: ""
    property string selectedSpaceName: ""
    property string mediaProxy: ""
    property bool roundAvatars: true
    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color accentTextColor: "#071007"
    property color backgroundColor: "#07100A"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"
    readonly property string searchQuery: lobbySearchField.text.trim().toLowerCase()

    signal roomSelected(string roomId, string roomName)
    signal roomInfoRequested(var room)
    signal joinRequested(var room)
    signal moreRoomsRequested()

    color: backgroundColor

    onSelectedSpaceIdChanged: lobbySearchField.clear()
    onHierarchyLoadingChanged: {
        if (!hierarchyLoading && hierarchyReady && hierarchyNextBatch !== ""
                && lobbyRooms.contentHeight <= lobbyRooms.height) {
            Qt.callLater(function() {
                if (!root.hierarchyLoading && root.hierarchyNextBatch !== ""
                        && lobbyRooms.contentHeight <= lobbyRooms.height)
                    root.moreRoomsRequested()
            })
        }
    }

    function belongsToSpace(parentSpaceKey) {
        var parents = String(parentSpaceKey || "").split("\u001f")
        return parents.indexOf(selectedSpaceId) !== -1
    }

    function roomMatchesSearch(room) {
        if (!room || String(room.room_id || "") === selectedSpaceId)
            return false
        if (searchQuery === "")
            return true
        var haystack = [
            room.name || "",
            room.topic || "",
            room.room_id || ""
        ].join("\n").toLowerCase()
        return haystack.indexOf(searchQuery) !== -1
    }

    function filteredHierarchyRooms() {
        var result = []
        var source = hierarchyRooms || []
        for (var i = 0; i < source.length; i++) {
            if (roomMatchesSearch(source[i]))
                result.push(source[i])
        }
        return result
    }

    function spaceRoomCount() {
        if (hierarchyReady) {
            var source = hierarchyRooms || []
            var count = 0
            for (var hierarchyIndex = 0; hierarchyIndex < source.length; hierarchyIndex++) {
                if (String(source[hierarchyIndex].room_id || "") !== selectedSpaceId)
                    count++
            }
            return count
        }
        if (!roomModel) return 0
        var fallbackCount = 0
        for (var i = 0; i < roomModel.count; i++) {
            var room = roomModel.get(i)
            if (!room.is_space && belongsToSpace(room.parent_space_key))
                fallbackCount++
        }
        return fallbackCount
    }

    function visibleRoomCount() {
        return filteredHierarchyRooms().length
    }

    Column {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 14

        Column {
            width: parent.width
            spacing: 5

            Text {
                text: root.selectedSpaceName || L10n.I18n.tr("Пространство")
                color: root.textPrimary
                font.pointSize: 18
                font.bold: true
            }
            Text {
                text: L10n.I18n.tr("Лобби пространства")
                color: root.textSecondary
                font.pointSize: 9
            }
        }

        Basic.TextField {
            id: lobbySearchField
            width: parent.width
            height: 40
            leftPadding: 42
            rightPadding: clearSearchButton.visible ? 38 : 14
            verticalAlignment: TextInput.AlignVCenter
            color: root.textPrimary
            placeholderText: L10n.I18n.tr("Поиск в пространстве")
            placeholderTextColor: root.textSecondary
            selectionColor: root.accentColor
            selectedTextColor: root.accentTextColor
            font.pointSize: 10

            background: Rectangle {
                radius: 10
                color: root.surfaceColor
                border.width: lobbySearchField.activeFocus ? 1 : 0
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

            Basic.ToolButton {
                id: clearSearchButton
                visible: lobbySearchField.text !== ""
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                padding: 0
                hoverEnabled: true
                focusPolicy: Qt.NoFocus

                contentItem: Icons.CloseIcon {
                    width: 12
                    height: 12
                    color: clearSearchButton.hovered ? root.textPrimary : root.textSecondary
                }
                background: Item {}
                onClicked: lobbySearchField.clear()
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: root.dividerColor
        }

        ListView {
            id: lobbyRooms
            width: parent.width
            height: parent.height - y
            model: root.hierarchyReady ? root.filteredHierarchyRooms() : []
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            onContentYChanged: {
                if (root.hierarchyReady && root.hierarchyNextBatch !== ""
                        && !root.hierarchyLoading
                        && contentY + height >= contentHeight - Math.max(180, height * 0.35)) {
                    root.moreRoomsRequested()
                }
            }
            onHeightChanged: {
                if (root.hierarchyReady && root.hierarchyNextBatch !== ""
                        && !root.hierarchyLoading && contentHeight <= height)
                    root.moreRoomsRequested()
            }
            onContentHeightChanged: {
                // Search deeper pages only when loaded results do not fill the view.
                if (root.hierarchyReady && root.hierarchyNextBatch !== ""
                        && !root.hierarchyLoading && contentHeight <= height)
                    root.moreRoomsRequested()
            }

            delegate: Rectangle {
                id: lobbyRoom
                required property var modelData
                readonly property var roomData: modelData || ({})
                readonly property string joinRule: String(roomData.join_rule || "").toLowerCase()
                readonly property bool isKnockable: joinRule.indexOf("knock") !== -1
                readonly property bool isInviteOnly: joinRule === "invite"
                    || joinRule.indexOf("invite") !== -1
                readonly property bool isInvited: !!roomData.invited
                readonly property bool isKnocked: !!roomData.knocked
                readonly property bool canJoinDirectly: isInvited
                    || joinRule.indexOf("public") !== -1
                    || (joinRule.indexOf("restricted") !== -1 && !isKnockable)
                readonly property bool canRequestAccess: isKnockable && !isKnocked
                readonly property bool canAct: roomData.joined !== false
                    || canJoinDirectly || canRequestAccess
                width: lobbyRooms.width
                height: 56
                radius: 10
                color: lobbyHover.hovered
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, 0.10)
                    : root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                      root.dividerColor.b, 0.75)

                Item {
                    anchors.fill: parent
                    anchors.margins: 10

                    AvatarItem {
                        id: lobbyAvatar
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        mxcUrl: roomData.avatar_url || ""
                        fallbackId: roomData.room_id || ""
                        mediaProxy: root.mediaProxy
                        roundAvatars: root.roundAvatars
                        size: 36
                    }

                    Text {
                        id: lobbyText
                        anchors.left: lobbyAvatar.right
                        anchors.right: actions.left
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(roomData.name || roomData.room_id || "").replace(/[\r\n]+/g, " ")
                            + (roomData.topic
                                ? "  —  " + String(roomData.topic).replace(/[\r\n]+/g, " • ")
                                : "")
                        color: root.textPrimary
                        font.pointSize: 10
                        font.bold: true
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        wrapMode: Text.NoWrap
                        textFormat: Text.PlainText
                        clip: true
                    }

                    Row {
                        id: actions
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Basic.Button {
                            id: roomInfoButton
                            width: 42
                            height: 32
                            hoverEnabled: true
                            focusPolicy: Qt.NoFocus
                            onClicked: root.roomInfoRequested(roomData)
                            background: Rectangle {
                                radius: 8
                                color: roomInfoButton.down
                                    ? Qt.darker(root.elevatedColor, 1.12)
                                    : roomInfoButton.hovered ? root.elevatedColor : "transparent"
                                border.width: 1
                                border.color: roomInfoButton.hovered || roomInfoButton.down
                                    ? root.dividerColor : "transparent"
                                Behavior on color {
                                    ColorAnimation { duration: L10n.UiPreferences.duration(100) }
                                }
                            }
                            contentItem: Icons.InfoIcon {
                                width: 18
                                height: 18
                                color: root.iconColor
                            }
                        }

                        Basic.Button {
                            id: roomActionButton
                            width: lobbyRoom.isInvited || lobbyRoom.isKnocked
                                ? 138 : 108
                            height: 32
                            scale: down ? 0.92 : 1
                            Behavior on scale {
                                NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                            }
                            hoverEnabled: true
                            focusPolicy: Qt.NoFocus
                            text: roomData.joined !== false
                                ? L10n.I18n.tr("Открыть")
                                : lobbyRoom.isInvited
                                    ? L10n.I18n.tr("Принять приглашение")
                                    : lobbyRoom.isKnocked
                                        ? L10n.I18n.tr("Заявка отправлена")
                                        : lobbyRoom.isInviteOnly
                                            ? L10n.I18n.tr("Только по приглашению")
                                            : lobbyRoom.isKnockable
                                                ? L10n.I18n.tr("Подать заявку")
                                                : lobbyRoom.canJoinDirectly
                                                    ? L10n.I18n.tr("Вступить")
                                                    : L10n.I18n.tr("Недоступно")
                            enabled: lobbyRoom.canAct
                            onClicked: {
                                if (roomData.joined === false) root.joinRequested(roomData)
                                else root.roomSelected(roomData.room_id || "",
                                                        roomData.name || roomData.room_id || "")
                            }
                            background: Rectangle {
                                radius: 8
                                color: !roomActionButton.enabled
                                    ? root.elevatedColor
                                    : roomActionButton.down
                                        ? Qt.darker(root.accentColor, 1.18)
                                        : roomActionButton.hovered
                                            ? Qt.darker(root.accentColor, 1.08)
                                            : root.accentColor
                                border.width: roomActionButton.enabled ? 0 : 1
                                border.color: root.dividerColor
                                Behavior on color {
                                    ColorAnimation { duration: L10n.UiPreferences.duration(100) }
                                }
                            }
                            contentItem: Text {
                                text: roomActionButton.text
                                color: roomActionButton.enabled
                                    ? root.accentTextColor : root.textSecondary
                                font.pointSize: 8
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }

                HoverHandler {
                    id: lobbyHover
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onDoubleTapped: {
                        if (roomData.joined !== false)
                            root.roomSelected(roomData.room_id || "",
                                              roomData.name || roomData.room_id || "")
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.hierarchyReady && root.visibleRoomCount() === 0
                text: root.hierarchyError !== "" ? root.hierarchyError
                    : root.searchQuery !== ""
                        ? L10n.I18n.tr("Ничего не найдено в пространстве")
                        : L10n.I18n.tr("В пространстве пока нет доступных комнат")
                color: root.textSecondary
                font.pointSize: 9
            }

            PrismBusyIndicator {
                anchors.centerIn: parent
                visible: !root.hierarchyReady || root.hierarchyLoading
                running: visible
                accentColor: root.accentColor
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                visible: root.hierarchyLoading && root.hierarchyReady
                text: L10n.I18n.tr("Загружаем ещё комнаты…")
                color: root.textSecondary
                font.pointSize: 8
            }
        }
    }
}
