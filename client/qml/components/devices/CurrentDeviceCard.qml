import QtQuick
import "../../settings"
import "../../utils" as L10n
import "../common"

Rectangle {
    id: root

    property var device: null
    property bool canVerifyWithOtherDevice: false
    property bool detailsExpanded: false
    property bool operationBusy: false
    property color accentColor: "#20D500"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"

    readonly property string verificationState: root.device
        ? String(root.device.verification_state || "unknown") : "unknown"
    readonly property bool needsVerification: root.verificationState === "unverified"
    readonly property color securityColor: root.verificationState === "verified"
        ? root.accentColor
        : root.verificationState === "unverified" ? "#f0b35a" : root.textSecondary
    readonly property string displayName: root.device
        ? (root.device.display_name
           || L10n.I18n.tr("PrismChat на этом устройстве"))
        : L10n.I18n.tr("Загрузка…")

    signal verifyRequested()
    signal renameRequested()
    signal copyRequested(string text)

    width: parent ? parent.width : 520
    implicitHeight: cardContent.implicitHeight
    radius: 12
    // Animate an opaque blend: changing alpha here causes a bright flash.
    color: Qt.tint(root.surfaceColor,
                   Qt.rgba(root.accentColor.r, root.accentColor.g,
                           root.accentColor.b,
                           summaryMouse.pressed ? 0.18 : summaryMouse.containsMouse ? 0.08 : 0))
    scale: summaryMouse.pressed ? 0.99 : 1
    Behavior on scale {
        NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
    }
    border.width: 1
    border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                          root.textSecondary.b, 0.18)
    clip: true

    Behavior on color {
        ColorAnimation { duration: L10n.UiPreferences.duration(110) }
    }

    Column {
        id: cardContent
        width: parent.width
        spacing: 0

        Item {
            id: summary
            width: parent.width
            height: 92

            MouseArea {
                id: summaryMouse
                anchors.left: parent.left
                anchors.right: menuButton.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.rightMargin: 4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.detailsExpanded = !root.detailsExpanded
            }

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 1
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 54
                radius: 2
                color: root.securityColor
            }

            Rectangle {
                id: deviceIconFrame
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 50
                height: 50
                radius: 14
                color: root.elevatedColor
                border.width: 1
                border.color: Qt.rgba(root.securityColor.r,
                                      root.securityColor.g,
                                      root.securityColor.b, 0.38)

                Canvas {
                    id: currentDeviceIcon
                    anchors.centerIn: parent
                    width: 28
                    height: 28
                    antialiasing: true
                    property color iconColor: root.securityColor

                    onIconColorChanged: requestPaint()
                    onPaint: {
                        var context = getContext("2d")
                        context.reset()
                        context.strokeStyle = iconColor
                        context.lineWidth = 1.8
                        context.lineCap = "round"
                        context.lineJoin = "round"
                        context.beginPath()
                        context.roundedRect(3.5, 3, 21, 17, 2, 2)
                        context.stroke()
                        context.beginPath()
                        context.moveTo(9, 25)
                        context.lineTo(19, 25)
                        context.moveTo(14, 20)
                        context.lineTo(14, 25)
                        context.stroke()
                    }
                }
            }

            Column {
                anchors.left: deviceIconFrame.right
                anchors.leftMargin: 14
                anchors.right: menuButton.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    width: parent.width
                    text: root.displayName
                    color: root.textPrimary
                    font.pointSize: 11
                    font.bold: true
                    elide: Text.ElideRight
                }

                Row {
                    width: parent.width
                    spacing: 9

                    Rectangle {
                        width: currentSessionText.implicitWidth + 14
                        height: 21
                        radius: 7
                        color: Qt.rgba(root.accentColor.r,
                                       root.accentColor.g,
                                       root.accentColor.b, 0.13)

                        Text {
                            id: currentSessionText
                            anchors.centerIn: parent
                            text: L10n.I18n.tr("Текущая сессия")
                            color: root.accentColor
                            font.pointSize: 7
                            font.bold: true
                        }
                    }

                    DeviceSecurityBadge {
                        anchors.verticalCenter: parent.verticalCenter
                        verificationState: root.verificationState
                        accentColor: root.accentColor
                        textSecondary: root.textSecondary
                    }
                }

                Text {
                    visible: root.device && !!root.device.last_seen_ts
                    width: parent.width
                    text: L10n.I18n.tr("Последняя активность: ")
                        + (root.device
                           ? new Date(Number(root.device.last_seen_ts)).toLocaleString(Qt.locale())
                           : "")
                    color: root.textSecondary
                    font.pointSize: 7
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                id: menuButton
                z: 10
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 12
                width: 30
                height: 30
                radius: 9
                color: menuMouse.containsMouse
                    ? Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                              root.textPrimary.b, 0.09)
                    : "transparent"
                scale: menuMouse.pressed ? 0.92 : 1

                Behavior on color {
                    ColorAnimation { duration: L10n.UiPreferences.duration(100) }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: L10n.UiPreferences.duration(90)
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 1
                    visible: !root.operationBusy
                    text: "⋮"
                    color: root.textSecondary
                    font.pointSize: 15
                }

                PrismBusyIndicator {
                    anchors.centerIn: parent
                    visible: root.operationBusy
                    running: visible
                    width: 16
                    height: 16
                    strokeWidth: 2
                    accentColor: root.accentColor
                }

                MouseArea {
                    id: menuMouse
                    anchors.fill: parent
                    enabled: !root.operationBusy
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        currentMenu.toggle(menuButton)
                    }
                }
            }
        }

        Rectangle {
            visible: root.needsVerification
            x: 12
            width: parent.width - 24
            height: visible ? verificationColumn.implicitHeight + 20 : 0
            radius: 9
            color: Qt.rgba(0.94, 0.70, 0.35, 0.09)
            border.width: 1
            border.color: Qt.rgba(0.94, 0.70, 0.35, 0.25)

            Column {
                id: verificationColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 9

                Text {
                    width: parent.width
                    text: L10n.I18n.tr("Это устройство пока не подтверждено. Подтвердите его с другого доверенного устройства.")
                    color: "#f0b35a"
                    font.pointSize: 8
                    wrapMode: Text.Wrap
                }

                SettingsActionButton {
                    visible: root.canVerifyWithOtherDevice
                    width: parent.width
                    height: visible ? 34 : 0
                    primary: true
                    softPress: true
                    enabled: !root.operationBusy
                    accentColor: root.accentColor
                    surfaceColor: root.elevatedColor
                    textPrimary: root.textPrimary
                    textSecondary: root.textSecondary
                    text: L10n.I18n.tr("Запросить подтверждение")
                    onClicked: root.verifyRequested()
                }
            }
        }

        Item {
            visible: root.detailsExpanded
            width: parent.width
            height: visible ? deviceDetails.implicitHeight + 31 : 0

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                height: 1
                color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                               root.textSecondary.b, 0.14)
            }

            DeviceDetails {
                id: deviceDetails
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                device: root.device
                accentColor: root.accentColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                onCopyRequested: function(value) { root.copyRequested(value) }
            }
        }

        Item {
            width: 1
            height: root.needsVerification || root.detailsExpanded ? 12 : 0
        }
    }

    DeviceContextMenu {
        id: currentMenu
        device: root.device
        elevatedColor: root.elevatedColor
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        onRenameRequested: root.renameRequested()
        onVerifyRequested: root.verifyRequested()
        onDetailsRequested: root.detailsExpanded = true
    }
}
