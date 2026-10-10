import ".." as Navigation
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../common"
import "../../../assets/icons" as Icons
import "../../../utils/PrismUtils.js" as Utils

Rectangle {
    required property var sidebar
    readonly property var root: sidebar
    required property var userPanelObject
    id: accountPopup
    visible: root.accountPopupVisible && !root.collapsed
    z: 100
    width: parent.width - 16
    height: Math.min(contentColumn.implicitHeight + 16, 320)
    anchors.left: parent.left
    anchors.leftMargin: 8
    anchors.bottom: userPanelObject.top
    anchors.bottomMargin: 8
    radius: 12
    color: root.elevatedColor
    border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g, root.dividerColor.b, 0.85)
    border.width: 1

    Column {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        Text {
            text: root.accountSwitchInFlight ? L10n.I18n.tr("Переключаем аккаунт...") : L10n.I18n.tr("Аккаунты")
            color: root.textPrimary
            font.bold: true
            font.pointSize: 10
        }

        Flickable {
            width: parent.width
            height: Math.min(accountListColumn.implicitHeight, 220)
            contentWidth: width
            contentHeight: accountListColumn.implicitHeight
            clip: true

            Column {
                id: accountListColumn
                width: parent.width
                spacing: 4

                Repeater {
                    model: root.profiles || []

                    delegate: Rectangle {
                        required property var modelData

                        width: accountListColumn.width
                        height: 54
                        radius: 10
                        color: modelData.is_active
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                            : (accountHover.containsMouse
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.07)
                                : "transparent")
                        border.color: modelData.is_active
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                            : "transparent"
                        border.width: modelData.is_active ? 1 : 0
                        opacity: root.accountSwitchInFlight ? 0.65 : 1.0

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            AvatarItem {
                                mxcUrl: modelData.is_active
                                    ? root.currentUserAvatar
                                    : (modelData.avatar_url || "")
                                fallbackId: modelData.user_id || modelData.profile_id
                                mediaProxy: root.mediaProxy
                                roundAvatars: root.roundAvatars
                                size: 34
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                width: Math.max(0, parent.width - 34 - 8 - 38)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: modelData.is_active && root.currentDisplayName !== ""
                                        ? root.currentDisplayName
                                        : (modelData.display_name
                                            || Utils.displayName(modelData.user_id || modelData.profile_id))
                                    color: root.textPrimary
                                    font.bold: true
                                    font.pointSize: 9
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.user_id || modelData.profile_id
                                    color: root.textSecondary
                                    font.pointSize: 8
                                    elide: Text.ElideRight
                                }
                            }

                        }

                        MouseArea {
                            id: accountHover
                            anchors.fill: parent
                            anchors.rightMargin: 46
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !modelData.is_active && !root.accountSwitchInFlight

                            onClicked: {
                                root.accountPopupVisible = false
                                root.switchProfileRequested(modelData.profile_id)
                            }
                        }

                        Basic.Button {
                            id: accountSettingsButton
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 30
                            padding: 0
                            enabled: !root.accountSwitchInFlight
                            hoverEnabled: true
                            scale: down ? 0.88 : 1
                            Accessible.name: L10n.I18n.tr("Профиль")
                            background: Rectangle {
                                radius: 8
                                color: accountSettingsButton.down
                                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                                    : accountSettingsButton.hovered
                                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
                                        : "transparent"
                                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                            }
                            contentItem: Text {
                                text: "⋮"
                                transform: Translate { y: -1 }
                                color: accountSettingsButton.hovered ? root.textPrimary : root.textSecondary
                                font.pointSize: 15
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            Behavior on scale {
                                NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                            }
                            PrismToolTip {
                                visible: accountSettingsButton.hovered
                                text: L10n.I18n.tr("Профиль")
                                surfaceColor: root.elevatedColor
                                textColor: root.textPrimary
                                dividerColor: root.dividerColor
                            }
                            onClicked: {
                                root.accountPopupVisible = false
                                root.profileSettingsRequested(modelData.profile_id)
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: root.dividerColor
            opacity: 0.7
        }

        Basic.Button {
            id: addButton
            width: parent.width
            height: 36
            enabled: !root.accountSwitchInFlight
            hoverEnabled: true
            scale: down ? 0.96 : 1

            Behavior on scale {
                NumberAnimation {
                    duration: L10n.UiPreferences.duration(100)
                    easing.type: Easing.OutCubic
                }
            }

            background: Rectangle {
                radius: 10
                color: addButton.hovered
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                    : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
            }

            contentItem: Text {
                text: L10n.I18n.tr("Добавить аккаунт")
                color: root.accentColor
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: {
                root.accountPopupVisible = false
                root.addAccountRequested()
            }
        }
    }
}
