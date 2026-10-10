import ".." as Chat
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../../utils/PrismUtils.js" as Utils

Rectangle {
    required property var chat
    readonly property var root: chat
    required property var dividerObject
    required property var headerObject
    id: searchPanel
    readonly property bool expanded: root.searchLoading
        || root.activeSearchQuery !== "" || root.searchError !== ""
    visible: headerObject.searchVisible
    z: 300
    anchors.top: dividerObject.bottom
    anchors.topMargin: 6
    width: Math.min(expanded ? 380 : 300,
                    root.width - root.rightPanelWidth - 32)
    // Align with the search field, not the full header control group.
    x: Math.max(10, Math.min(root.width - root.rightPanelWidth - width - 10,
                            headerObject.searchFieldRightX - width - 6))
    height: expanded ? Math.min(440, root.height - headerObject.height - 24) : 44
    radius: 12
    Behavior on width { NumberAnimation { duration: L10n.UiPreferences.duration(140); easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: L10n.UiPreferences.duration(160); easing.type: Easing.OutCubic } }
    color: root.elevatedColor
    border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g, root.dividerColor.b, 0.9)
    clip: true

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Row {
            width: parent.width
            Text {
                width: parent.width
                text: root.searchLoading ? L10n.I18n.tr("Ищем сообщения…")
                    : root.searchError !== "" ? root.searchError
                    : root.activeSearchQuery === "" ? L10n.I18n.tr("Введите запрос и нажмите Enter")
                    : L10n.I18n.tr("Результаты: ") + root.searchResults.length
                color: root.searchError !== "" ? "#ff6b6b" : root.textSecondary
                font.pointSize: 8
                elide: Text.ElideRight
            }
        }

        ListView {
            visible: searchPanel.expanded
            width: parent.width
            height: Math.max(0, parent.height - 24)
            model: root.searchResults
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: 66
                radius: 8
                color: searchMouse.containsMouse
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.09)
                    : Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.035)
                Column {
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 4
                    Row {
                        spacing: 7
                        Text { text: root.authorDisplayName(modelData.sender || "", modelData.sender_display_name || ""); color: Utils.avatarColor(modelData.sender || ""); font.bold: true; font.pointSize: 8 }
                        Text { text: Utils.formatMessageTimestamp(modelData.timestamp || 0, root.messageDateFormat, root.messageTimeFormat, L10n.I18n.tr("вчера")); color: root.textSecondary; font.pointSize: 7 }
                    }
                    Text { width: parent.width; text: modelData.body || ""; color: root.textPrimary; font.pointSize: 9; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap }
                }
                MouseArea {
                    id: searchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openSearchResult(modelData)
                }
            }
            footer: Item {
                visible: root.searchNextBatch !== ""
                width: ListView.view ? ListView.view.width : 0
                height: visible ? 40 : 0

                Basic.Button {
                    id: searchMoreButton
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 4
                    height: 36
                    text: root.searchLoading ? L10n.I18n.tr("Загрузка…") : L10n.I18n.tr("Показать ещё")
                    enabled: !root.searchLoading
                    hoverEnabled: true
                    scale: down ? 0.92 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: L10n.UiPreferences.duration(90)
                            easing.type: Easing.OutCubic
                        }
                    }
                    onClicked: {
                        root.searchLoading = true
                        root.searchAppendPending = true
                        root.activeSearchRequestId = root.nextRequestId("search-more")
                        root.searchRequested(root.currentRoomId, root.activeSearchQuery,
                                             root.searchNextBatch, root.activeSearchRequestId)
                    }
                    background: Rectangle { radius: 8; color: root.surfaceColor }
                    contentItem: Text { text: parent.text; color: root.accentColor; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pointSize: 8 }
                }
            }
        }
    }
}
