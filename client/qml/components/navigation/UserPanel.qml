import QtQuick
import "../common"
import "../../settings"
import "../../utils" as L10n
import "../../utils/PrismUtils.js" as Utils

Rectangle {
    id: root

    property string currentUserId: ""
    property string currentDisplayName: ""
    property string currentUserAvatar: ""
    property string mediaProxy: ""
    property bool roundAvatars: true

    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"
    readonly property color profileColor: root.accentColor

    signal settingsRequested()
    signal accountMenuRequested()

    implicitHeight: 60
    color: surfaceColor

    Rectangle {
        width: parent.width
        height: 1
        color: root.dividerColor
        opacity: 0.7
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 7
        anchors.rightMargin: 7
        anchors.topMargin: 7
        anchors.bottomMargin: 7
        spacing: 8

        Rectangle {
            id: accountButton
            scale: accountMouse.pressed ? 0.96 : 1

            Behavior on scale {
                NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
            }

            width: parent.width - settingsButton.width - parent.spacing
            height: parent.height
            color: accountMouse.pressed
                ? Qt.rgba(root.profileColor.r, root.profileColor.g,
                          root.profileColor.b, 0.18)
                : accountMouse.containsMouse
                    ? Qt.rgba(root.profileColor.r, root.profileColor.g,
                              root.profileColor.b, 0.12)
                    : "transparent"
            radius: 12

            Behavior on color {
                ColorAnimation { duration: L10n.UiPreferences.duration(110) }
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 9

                Rectangle {
                    width: 46
                    height: 46
                    anchors.verticalCenter: parent.verticalCenter
                    radius: root.roundAvatars ? 23 : 12
                    color: root.elevatedColor
                    border.width: 2
                    border.color: Qt.rgba(root.profileColor.r,
                                          root.profileColor.g,
                                          root.profileColor.b, 0.72)

                    AvatarItem {
                        anchors.centerIn: parent
                        width: 40
                        height: 40
                        mxcUrl: root.currentUserAvatar
                        fallbackId: root.currentUserId
                        mediaProxy: root.mediaProxy
                        roundAvatars: root.roundAvatars
                        size: 40
                    }
                }

                Column {
                    width: Math.max(0, parent.width - 46 - parent.spacing)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: root.currentDisplayName !== ""
                            ? root.currentDisplayName : Utils.displayName(root.currentUserId)
                        color: root.textPrimary
                        font.bold: true
                        font.pointSize: 10.5
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: root.currentUserId
                        color: root.textSecondary
                        font.pointSize: 7.5
                        elide: Text.ElideRight
                    }
                }

            }

            MouseArea {
                id: accountMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.accountMenuRequested()
            }
        }

        SettingsIconButton {
            id: settingsButton
            accentColor: root.accentColor
            iconColor: root.iconColor
            elevatedColor: root.elevatedColor
            textPrimary: root.textPrimary
            textSecondary: root.textSecondary
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.settingsRequested()
        }
    }
}
