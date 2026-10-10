import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../assets/icons" as Icons
import "../../components/common"
import "../../utils" as L10n
import "../../utils/PrismUtils.js" as Utils

Column {
    id: root

    property string currentUserId: ""
    property string currentUserAvatar: ""
    property string currentDisplayName: ""
    property string sessionServer: ""
    property string mediaProxy: ""
    property bool roundAvatars: true
    property string avatarStatusText: ""
    property color avatarStatusColor: accentColor
    property string displayNameStatusText: ""
    property color displayNameStatusColor: accentColor
    property bool displayNameBusy: false
    property bool editingDisplayName: false
    property color accentColor: "#20D500"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"

    readonly property string profileName: root.currentDisplayName !== ""
        ? root.currentDisplayName : Utils.displayName(root.currentUserId)

    signal avatarChangeRequested()
    signal displayNameChangeRequested(string displayName, bool clearDisplayName)

    function beginDisplayNameEdit() {
        if (root.displayNameBusy)
            return
        displayNameEditor.text = root.currentDisplayName
        root.editingDisplayName = true
        Qt.callLater(function() {
            displayNameEditor.forceActiveFocus()
            displayNameEditor.selectAll()
        })
    }

    function cancelDisplayNameEdit() {
        displayNameEditor.text = root.currentDisplayName
        root.editingDisplayName = false
    }

    function saveDisplayName() {
        if (root.displayNameBusy)
            return
        var value = displayNameEditor.text.trim()
        root.editingDisplayName = false
        root.displayNameChangeRequested(value, value === "")
    }

    onCurrentDisplayNameChanged: {
        if (!root.editingDisplayName)
            displayNameEditor.text = root.currentDisplayName
    }

    spacing: 14

    Column {
        width: parent.width
        spacing: 4

        Text {
            text: L10n.I18n.tr("Профиль")
            color: root.textPrimary
            font.pointSize: 13
            font.bold: true
        }

        Text {
            width: parent.width
            text: L10n.I18n.tr("Настройте, как вас видят другие пользователи Matrix.")
            color: root.textSecondary
            font.pointSize: 8
            wrapMode: Text.Wrap
        }
    }

    Rectangle {
        id: profileCard
        width: parent.width
        implicitHeight: profileContent.implicitHeight + 30
        radius: 14
        color: root.surfaceColor
        border.width: 1
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, 0.24)

        Column {
            id: profileContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 15
            spacing: 9

            Row {
                id: profileRow
                width: parent.width
                height: 76
                spacing: 14

                Item {
                    id: avatarFrame
                    width: 76
                    height: 76
                    scale: avatarMouse.pressed ? 0.94 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: L10n.UiPreferences.duration(avatarMouse.pressed ? 90 : 130)
                            easing.type: Easing.OutCubic
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: root.roundAvatars ? width / 2 : 18
                        color: root.elevatedColor
                        border.width: 2
                        border.color: avatarMouse.containsMouse
                            ? root.accentColor
                            : Qt.rgba(root.accentColor.r,
                                      root.accentColor.g,
                                      root.accentColor.b, 0.34)

                        Behavior on border.color {
                            ColorAnimation {
                                duration: L10n.UiPreferences.duration(110)
                            }
                        }
                    }

                    AvatarItem {
                        anchors.centerIn: parent
                        mxcUrl: root.currentUserAvatar
                        fallbackId: root.currentUserId
                        mediaProxy: root.mediaProxy
                        roundAvatars: root.roundAvatars
                        size: 68
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 68
                        height: 68
                        radius: root.roundAvatars ? width / 2 : 15
                        visible: avatarMouse.containsMouse
                        color: Qt.rgba(0, 0, 0, 0.48)

                        Icons.PencilIcon {
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            color: "white"
                            strokeWidth: 1.8
                        }
                    }

                    MouseArea {
                        id: avatarMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.avatarChangeRequested()
                    }

                    PrismToolTip {
                        visible: avatarMouse.containsMouse
                        delay: 300
                        text: L10n.I18n.tr("Сменить аватар")
                        surfaceColor: root.elevatedColor
                        textColor: root.textPrimary
                        dividerColor: root.textSecondary
                    }
                }

                Item {
                    width: parent.width - avatarFrame.width - parent.spacing
                    height: parent.height

                    Item {
                        id: displayNameLine
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 8
                        height: 34

                        Text {
                            id: displayNameLabel
                            visible: !root.editingDisplayName
                            anchors.left: parent.left
                            width: Math.min(implicitWidth, Math.max(0, parent.width - editNameButton.width - 7))
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.profileName
                            color: root.textPrimary
                            font.bold: true
                            font.pointSize: 13
                            elide: Text.ElideRight
                        }

                        Basic.TextField {
                            id: displayNameEditor
                            visible: root.editingDisplayName
                            anchors.left: parent.left
                            anchors.right: cancelEditButton.left
                            anchors.rightMargin: 7
                            height: 34
                            color: root.textPrimary
                            placeholderText: Utils.displayName(root.currentUserId)
                            placeholderTextColor: root.textSecondary
                            selectByMouse: true
                            leftPadding: 10
                            rightPadding: 10
                            onAccepted: root.saveDisplayName()
                            Keys.onEscapePressed: function(event) {
                                root.cancelDisplayNameEdit()
                                event.accepted = true
                            }

                            background: Rectangle {
                                radius: 8
                                color: root.elevatedColor
                                border.width: 1
                                border.color: displayNameEditor.activeFocus
                                    ? root.accentColor
                                    : Qt.rgba(root.textSecondary.r,
                                              root.textSecondary.g,
                                              root.textSecondary.b, 0.22)
                            }
                        }

                        Rectangle {
                            id: editNameButton
                            visible: !root.editingDisplayName
                            anchors.left: displayNameLabel.right
                            anchors.leftMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 30
                            radius: 9
                            scale: editNameMouse.pressed ? 0.94 : 1
                            Behavior on scale {
                                NumberAnimation {
                                    duration: L10n.UiPreferences.duration(editNameMouse.pressed ? 90 : 130)
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on color {
                                ColorAnimation { duration: L10n.UiPreferences.duration(110) }
                            }
                            color: editNameMouse.pressed || editNameMouse.containsMouse
                                ? Qt.rgba(root.accentColor.r,
                                          root.accentColor.g,
                                          root.accentColor.b, editNameMouse.pressed ? 0.26 : 0.16)
                                : "transparent"

                            Icons.PencilIcon {
                                anchors.centerIn: parent
                                visible: !root.displayNameBusy
                                width: 15
                                height: 15
                                color: editNameMouse.containsMouse
                                    ? root.accentColor : root.textSecondary
                            }

                            PrismBusyIndicator {
                                anchors.centerIn: parent
                                visible: root.displayNameBusy
                                running: visible
                                width: 15
                                height: 15
                                strokeWidth: 2
                                accentColor: root.accentColor
                            }

                            MouseArea {
                                id: editNameMouse
                                anchors.fill: parent
                                enabled: !root.displayNameBusy
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.beginDisplayNameEdit()
                            }

                            PrismToolTip {
                                visible: editNameMouse.containsMouse
                                delay: 300
                                text: L10n.I18n.tr("Изменить имя")
                                surfaceColor: root.elevatedColor
                                textColor: root.textPrimary
                                dividerColor: root.textSecondary
                            }
                        }

                        Rectangle {
                            id: confirmEditButton
                            visible: root.editingDisplayName
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 30
                            radius: 9
                            color: confirmEditMouse.containsMouse
                                ? Qt.rgba(root.accentColor.r,
                                          root.accentColor.g,
                                          root.accentColor.b, 0.20)
                                : Qt.rgba(root.accentColor.r,
                                          root.accentColor.g,
                                          root.accentColor.b, 0.12)

                            Icons.CheckIcon {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                color: root.accentColor
                            }

                            MouseArea {
                                id: confirmEditMouse
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.saveDisplayName()
                            }
                        }

                        Rectangle {
                            id: cancelEditButton
                            visible: root.editingDisplayName
                            anchors.right: confirmEditButton.left
                            anchors.rightMargin: 5
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 30
                            radius: 9
                            color: cancelEditMouse.containsMouse
                                ? Qt.rgba(root.textSecondary.r,
                                          root.textSecondary.g,
                                          root.textSecondary.b, 0.13)
                                : "transparent"

                            Icons.CloseIcon {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                color: root.textSecondary
                                strokeWidth: 1.6
                            }

                            MouseArea {
                                id: cancelEditMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.cancelDisplayNameEdit()
                            }
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: displayNameLine.bottom
                        anchors.topMargin: 3
                        text: root.currentUserId
                        color: root.textSecondary
                        font.pointSize: 8
                        elide: Text.ElideMiddle
                    }
                }
            }

            Text {
                visible: root.avatarStatusText !== ""
                width: parent.width
                text: root.avatarStatusText
                color: root.avatarStatusColor
                font.pointSize: 8
                wrapMode: Text.Wrap
            }

            Text {
                visible: root.displayNameStatusText !== ""
                width: parent.width
                text: root.displayNameStatusText
                color: root.displayNameStatusColor
                font.pointSize: 8
                wrapMode: Text.Wrap
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 58
        radius: 12
        color: root.surfaceColor
        border.width: 1
        border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                              root.textSecondary.b, 0.14)

        Rectangle {
            id: serverIconFrame
            anchors.left: parent.left
            anchors.leftMargin: 13
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 34
            radius: 10
            color: root.elevatedColor

            Canvas {
                anchors.centerIn: parent
                width: 18
                height: 18
                antialiasing: true

                onPaint: {
                    var context = getContext("2d")
                    context.reset()
                    context.strokeStyle = root.accentColor
                    context.lineWidth = 1.5
                    context.lineCap = "round"
                    context.lineJoin = "round"
                    context.beginPath()
                    context.roundedRect(2, 2, 14, 5, 1.5, 1.5)
                    context.roundedRect(2, 11, 14, 5, 1.5, 1.5)
                    context.stroke()
                    context.fillStyle = root.accentColor
                    context.beginPath()
                    context.arc(5, 4.5, 1, 0, Math.PI * 2)
                    context.arc(5, 13.5, 1, 0, Math.PI * 2)
                    context.fill()
                }
            }
        }

        Column {
            anchors.left: serverIconFrame.right
            anchors.leftMargin: 11
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
                text: L10n.I18n.tr("Домашний сервер")
                color: root.textSecondary
                font.pointSize: 7
                font.bold: true
            }

            Text {
                width: parent.width
                text: root.sessionServer
                color: root.textPrimary
                font.pointSize: 9
                elide: Text.ElideMiddle
            }
        }
    }
}
