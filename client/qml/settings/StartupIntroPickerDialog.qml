import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "../components/common"
import "../assets/icons" as Icons
import "../utils" as L10n

Dialog {
    id: root

    property real dragOffsetX: 0
    property real dragOffsetY: 0
    property int selectedVariant: 0
    property bool animationsEnabled: true
    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color backgroundColor: "#07100A"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"

    signal variantSelected(int variant)

    width: Math.min(560, Math.max(360, (parent ? parent.width : 608) - 48))
    height: Math.min(470, Math.max(340, (parent ? parent.height : 518) - 48))
    x: parent ? Math.round((parent.width - width) / 2 + dragOffsetX) : 0
    y: parent ? Math.round((parent.height - height) / 2 + dragOffsetY) : 0
    padding: 0
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape

    onOpened: {
        dragOffsetX = 0
        dragOffsetY = 0
        pickerMoveArea.resetMotion()
    }

    background: Rectangle {
        radius: 13
        color: root.backgroundColor
        border.width: 1
        border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                              root.dividerColor.b, 0.86)
        transform: Matrix4x4 {
            matrix: PlanarTransform.fromShear(
                        Math.tan(pickerMoveArea.visualShearAngle * Math.PI / 180),
                        0, root.width / 2, 0)
        }
    }

    contentItem: Item {
        transform: Matrix4x4 {
            matrix: PlanarTransform.fromShear(
                        Math.tan(pickerMoveArea.visualShearAngle * Math.PI / 180),
                        0, root.width / 2, 0)
        }

        Rectangle {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 48
            color: "transparent"

            PopupMoveArea {
                id: pickerMoveArea
                anchors.fill: parent
                moveTarget: root
                movementBoundary: root.parent
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.I18n.tr("Варианты загрузки")
                color: root.textPrimary
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }

            PopupCloseButton {
                id: closeButton
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                z: 2
                accentColor: root.accentColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                onClicked: root.close()
            }
        }

        GridLayout {
            id: previewGrid
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 2
            anchors.bottomMargin: 12
            columns: 2
            columnSpacing: 8
            rowSpacing: 8

            Repeater {
                model: 11

                delegate: Rectangle {
                    id: previewCard
                    required property int index
                    scale: previewMouse.pressed
                        ? 0.96
                        : previewMouse.containsMouse ? 1.01 : 1

                    Behavior on scale {
                        NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                    }

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 150
                    Layout.minimumHeight: 48
                    radius: 9
                    color: root.surfaceColor

                    StartupIntro {
                        anchors.fill: parent
                        anchors.margins: 2
                        previewMode: true
                        introVariant: previewCard.index
                        animationsEnabled: root.animationsEnabled
                        accentColor: root.accentColor
                        iconColor: root.iconColor
                        backgroundColor: root.surfaceColor
                        surfaceColor: root.elevatedColor
                        textPrimary: root.textPrimary
                        textSecondary: root.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        id: previewMouse
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.variantSelected(previewCard.index)
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        border.width: root.selectedVariant === previewCard.index ? 2 : 1
                        border.color: root.selectedVariant === previewCard.index
                            ? root.accentColor
                            : previewMouse.containsMouse
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                          root.accentColor.b, 0.55)
                                : Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                          root.textSecondary.b, 0.18)
                        Behavior on border.color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                    }

                }
            }
        }
    }
}
