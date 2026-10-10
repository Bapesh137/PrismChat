import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../common"
import "../../assets/icons" as Icons
import "../../utils" as L10n

Dialog {
    id: root

    property var results: []
    property var selectedUsers: []
    property bool loading: false
    property bool limited: false
    property string errorText: ""
    property string activeRequestId: ""
    property string currentUserId: ""
    property string mediaProxy: ""
    property bool roundAvatars: true
    property var requestIdFactory: null
    property int localRequestSequence: 0

    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color accentTextColor: "#071007"
    property color backgroundColor: "#07100A"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"

    signal searchRequested(string query, string requestId)
    signal selectionAccepted(var users)

    width: Math.min(600, parent ? parent.width - 32 : 600)
    height: Math.min(620, parent ? parent.height - 32 : 620)
    modal: true
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function cloneUsers(users) {
        var copy = []
        var source = users || []
        for (var index = 0; index < source.length; index++) {
            var user = source[index] || {}
            if (!user.user_id) continue
            copy.push({
                user_id: String(user.user_id),
                display_name: String(user.display_name || ""),
                avatar_url: String(user.avatar_url || "")
            })
        }
        return copy
    }

    function openWithSelection(users) {
        selectedUsers = cloneUsers(users)
        results = []
        loading = false
        limited = false
        errorText = ""
        activeRequestId = ""
        queryField.text = ""
        open()
    }

    function nextRequestId() {
        if (requestIdFactory)
            return requestIdFactory("invite-user-picker")
        localRequestSequence++
        return Date.now().toString() + "-invite-user-picker-" + localRequestSequence
    }

    function meaningfulQueryLength(value) {
        var query = String(value || "").trim()
        if (query.charAt(0) === "@") query = query.substring(1)
        return query.length
    }

    function dispatchSearch() {
        var query = queryField.text.trim()
        if (meaningfulQueryLength(query) < 1) {
            results = []
            loading = false
            activeRequestId = ""
            return
        }
        activeRequestId = nextRequestId()
        loading = true
        limited = false
        errorText = ""
        searchRequested(query, activeRequestId)
    }

    function receiveResults(items, isLimited, error, requestId) {
        if (!opened || requestId !== activeRequestId) return
        loading = false
        results = items || []
        limited = !!isLimited
        errorText = error || ""
    }

    function selectedIndex(userId) {
        for (var index = 0; index < selectedUsers.length; index++) {
            if (String(selectedUsers[index].user_id || "") === String(userId || ""))
                return index
        }
        return -1
    }

    function isSelected(userId) {
        return selectedIndex(userId) >= 0
    }

    function toggleUser(user) {
        var userId = String((user || {}).user_id || "")
        if (userId === "" || userId === currentUserId) return
        var copy = cloneUsers(selectedUsers)
        var index = selectedIndex(userId)
        if (index >= 0) {
            copy.splice(index, 1)
        } else {
            copy.push({
                user_id: userId,
                display_name: String(user.display_name || ""),
                avatar_url: String(user.avatar_url || "")
            })
        }
        selectedUsers = copy
    }

    onOpened: Qt.callLater(function() { queryField.forceActiveFocus() })
    onClosed: {
        searchTimer.stop()
        activeRequestId = ""
        loading = false
    }

    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.56) }

    background: Rectangle {
        radius: 16
        color: root.backgroundColor
        border.width: 1
        border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                              root.textSecondary.b, 0.20)
    }

    contentItem: Item {
        Rectangle {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 72
            radius: 16
            color: root.surfaceColor

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
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.I18n.tr("Выбор пользователей")
                color: root.textPrimary
                font.bold: true
                font.pointSize: 13
            }

            PopupCloseButton {
                id: closeButton
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                accentColor: root.accentColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                onClicked: root.close()
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
            placeholderText: L10n.I18n.tr("Поиск пользователей")
            placeholderTextColor: root.textSecondary
            selectionColor: root.accentColor
            selectedTextColor: root.accentTextColor

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
                activeRequestId = ""
                results = []
                loading = false
                limited = false
                errorText = ""
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
                contentItem: Icons.CloseIcon {
                    width: 12
                    height: 12
                    color: root.textSecondary
                }
                background: Item {}
                onClicked: queryField.clear()
            }
        }

        ListView {
            id: resultList
            anchors.top: queryField.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.bottomMargin: 8
            clip: true
            spacing: 4
            model: root.meaningfulQueryLength(queryField.text) < 1
                ? root.selectedUsers : root.results
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: PrismScrollBar {
                policy: ScrollBar.AsNeeded
                autoHide: true
                handleColor: root.textSecondary
                handleHoverColor: root.accentColor
            }

            delegate: Rectangle {
                id: userDelegate
                required property var modelData
                width: resultList.width
                height: 70
                radius: 11
                readonly property string userId: String(modelData.user_id || "")
                readonly property bool isSelf: userId === root.currentUserId
                readonly property bool chosen: root.isSelected(userId)
                color: userMouse.containsMouse || chosen
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b,
                              chosen ? 0.15 : 0.08)
                    : "transparent"

                Rectangle {
                    id: selectionMark
                    anchors.left: parent.left
                    anchors.leftMargin: 9
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    radius: 10
                    color: userDelegate.chosen ? root.accentColor : "transparent"
                    border.width: 1.5
                    border.color: userDelegate.chosen ? root.accentColor : root.textSecondary
                    Icons.CheckIcon {
                        visible: userDelegate.chosen
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        color: root.accentTextColor
                    }
                }

                AvatarItem {
                    id: avatar
                    anchors.left: selectionMark.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    size: 44
                    mxcUrl: userDelegate.modelData.avatar_url || ""
                    fallbackId: userDelegate.userId
                    mediaProxy: root.mediaProxy
                    roundAvatars: root.roundAvatars
                }

                Text {
                    anchors.left: avatar.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.top: parent.top
                    anchors.topMargin: 13
                    text: userDelegate.modelData.display_name || userDelegate.userId
                    color: root.textPrimary
                    font.bold: true
                    font.pointSize: 10
                    elide: Text.ElideRight
                }

                Text {
                    anchors.left: avatar.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 13
                    text: userDelegate.isSelf ? L10n.I18n.tr("Это вы") : userDelegate.userId
                    color: root.textSecondary
                    font.pointSize: 8
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: userMouse
                    anchors.fill: parent
                    enabled: !userDelegate.isSelf
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.toggleUser(userDelegate.modelData)
                }
            }
        }

        PrismBusyIndicator {
            anchors.centerIn: resultList
            running: root.loading
            width: 26
            height: 26
            strokeWidth: 2.2
            accentColor: root.accentColor
        }

        Text {
            anchors.centerIn: resultList
            visible: !root.loading && root.errorText !== ""
            width: resultList.width - 50
            text: root.errorText
            color: "#ff6b6b"
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: 9
        }

        Text {
            anchors.centerIn: resultList
            visible: !root.loading && root.errorText === ""
                && root.meaningfulQueryLength(queryField.text) < 1
                && root.selectedUsers.length === 0
            width: resultList.width - 50
            text: L10n.I18n.tr("Начните вводить имя или Matrix ID")
            color: root.textSecondary
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: 9
        }

        Text {
            anchors.centerIn: resultList
            visible: !root.loading && root.errorText === ""
                && root.meaningfulQueryLength(queryField.text) >= 1
                && root.results.length === 0
            text: L10n.I18n.tr("Ничего не найдено")
            color: root.textSecondary
            font.pointSize: 9
        }

        Rectangle {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 76
            radius: 16
            color: root.surfaceColor

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 16
                color: parent.color
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: root.dividerColor
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.I18n.tr("Выбрано пользователей: ") + root.selectedUsers.length
                color: root.textSecondary
                font.pointSize: 9
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Basic.Button {
                    width: 110
                    height: 40
                    text: L10n.I18n.tr("Отмена")
                    onClicked: root.close()
                    contentItem: Text {
                        text: parent.text
                        color: root.textPrimary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 9
                        color: parent.hovered ? root.elevatedColor : "transparent"
                        border.width: 1
                        border.color: root.dividerColor
                    }
                }

                Basic.Button {
                    width: 130
                    height: 40
                    text: L10n.I18n.tr("Готово")
                    onClicked: {
                        root.selectionAccepted(root.cloneUsers(root.selectedUsers))
                        root.close()
                    }
                    contentItem: Text {
                        text: parent.text
                        color: root.accentTextColor
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 9
                        color: parent.down ? Qt.darker(root.accentColor, 1.18) : root.accentColor
                    }
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
