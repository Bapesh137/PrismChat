import QtQuick
import "../../utils" as L10n
import "../../components/common"
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic

Rectangle {
    id: root

    property color accentColor: "#20D500"
    property color accentTextColor: "#071007"
    property color backgroundColor: "#07100A"
    property color surfaceColor: "#0B1710"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property string errorText: ""
    property bool registrationInFlight: false
    property bool backendConnected: false
    property bool registrationLinkCopied: false
    readonly property string officialRegistrationUrl: "https://account.matrix.org/register"

    signal registrationRequested(string server, string username, string password)
    signal copyRequested(string text)
    signal loginRequested()

    function selectedServer() { return serverInput.text.trim() }

    function submitRegistration() {
        if (registrationInFlight) return
        if (!backendConnected) {
            errorText = L10n.I18n.tr("Нет связи с бэкендом")
            return
        }
        if (selectedServer() === ""
                || usernameInput.text.trim() === ""
                || passwordInput.text === ""
                || confirmPasswordInput.text === "") {
            errorText = L10n.I18n.tr("Заполните все поля")
            return
        }
        if (passwordInput.text !== confirmPasswordInput.text) {
            errorText = L10n.I18n.tr("Пароли не совпадают")
            confirmPasswordInput.forceActiveFocus()
            return
        }

        errorText = ""
        registrationInFlight = true
        registrationRequested(selectedServer(),
                              usernameInput.text.trim(),
                              passwordInput.text)
    }

    function setRegistrationFailed(message) {
        errorText = message || L10n.I18n.tr("Ошибка регистрации")
        registrationInFlight = false
    }

    function completeRegistration() {
        errorText = ""
        registrationInFlight = false
        passwordInput.clear()
        confirmPasswordInput.clear()
    }

    onVisibleChanged: {
        if (!visible) {
            registrationInFlight = false
            registrationLinkCopied = false
            copiedStateTimer.stop()
            passwordInput.clear()
            confirmPasswordInput.clear()
        }
    }

    color: backgroundColor

    Timer {
        id: copiedStateTimer
        interval: 1800
        onTriggered: root.registrationLinkCopied = false
    }

    Rectangle {
        width: 380
        height: 380
        radius: 190
        x: -110
        y: -110
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
    }

    Column {
        anchors.centerIn: parent
        width: 320
        spacing: 16

        Text {
            text: L10n.I18n.tr("Регистрация")
            font.pointSize: 20
            font.bold: true
            color: root.textPrimary
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            visible: root.errorText !== ""
            text: root.errorText
            color: "#ff5252"
            font.pointSize: 9
            wrapMode: Text.Wrap
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
        }

        Column {
            width: parent.width
            spacing: 10

            Row {
                width: parent.width
                height: 40
                spacing: 8

                Basic.Button {
                    id: matrixOrgRegistrationButton
                    width: parent.width - copyRegistrationLinkButton.width - parent.spacing
                    height: parent.height
                    enabled: !root.registrationInFlight
                    scale: down ? 0.97 : 1
                    background: Rectangle {
                        radius: 10
                        color: matrixOrgRegistrationButton.down
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.24)
                            : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                        border.width: 1
                        border.color: root.accentColor
                    }
                    contentItem: Text {
                        text: L10n.I18n.tr("Создать аккаунт на Matrix.org ↗")
                        color: root.accentColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pointSize: 9
                        font.weight: Font.DemiBold
                    }
                    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                    onClicked: Qt.openUrlExternally(root.officialRegistrationUrl)
                }

                Basic.Button {
                    id: copyRegistrationLinkButton
                    width: 42
                    height: parent.height
                    enabled: !root.registrationInFlight
                    hoverEnabled: true
                    scale: down ? 0.97 : 1
                    Accessible.name: root.registrationLinkCopied
                        ? L10n.I18n.tr("Ссылка скопирована")
                        : L10n.I18n.tr("Копировать ссылку")
                    HoverHandler {
                        cursorShape: copyRegistrationLinkButton.enabled
                            ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                    background: Rectangle {
                        radius: 10
                        color: copyRegistrationLinkButton.down
                            ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.10)
                            : root.surfaceColor
                        border.width: 1
                        border.color: root.registrationLinkCopied
                            ? root.accentColor
                            : Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                      root.textSecondary.b, 0.24)
                    }
                    contentItem: Item {
                        implicitWidth: 20
                        implicitHeight: 20

                        Canvas {
                            id: copyRegistrationLinkIcon
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            property bool copied: root.registrationLinkCopied
                            property color strokeColor: copied ? root.accentColor : root.textPrimary

                            onCopiedChanged: requestPaint()
                            onStrokeColorChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.strokeStyle = strokeColor
                                ctx.lineWidth = 1.7
                                ctx.lineCap = "round"
                                ctx.lineJoin = "round"
                                ctx.beginPath()
                                if (copied) {
                                    ctx.moveTo(3.5, 10)
                                    ctx.lineTo(8, 14.5)
                                    ctx.lineTo(16.5, 5.5)
                                } else {
                                    ctx.rect(6, 3, 10, 12)
                                    ctx.moveTo(12, 6)
                                    ctx.lineTo(3, 6)
                                    ctx.lineTo(3, 17)
                                    ctx.lineTo(13, 17)
                                    ctx.lineTo(13, 15)
                                }
                                ctx.stroke()
                            }
                        }
                    }
                    PrismToolTip {
                        visible: copyRegistrationLinkButton.hovered
                        text: root.registrationLinkCopied
                            ? L10n.I18n.tr("Ссылка скопирована")
                            : L10n.I18n.tr("Копировать ссылку")
                        surfaceColor: root.surfaceColor
                        textColor: root.textPrimary
                        dividerColor: Qt.rgba(root.textSecondary.r,
                                              root.textSecondary.g,
                                              root.textSecondary.b, 0.24)
                    }
                    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                    onClicked: {
                        root.copyRequested(root.officialRegistrationUrl)
                        root.registrationLinkCopied = true
                        copiedStateTimer.restart()
                    }
                }
            }

            Text {
                width: parent.width
                text: L10n.I18n.tr("Официальная регистрация откроется в браузере")
                color: root.textSecondary
                font.pointSize: 8
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: L10n.I18n.tr("Или зарегистрируйтесь на другом сервере")
                color: root.textSecondary
                font.pointSize: 9
                horizontalAlignment: Text.AlignHCenter
            }
            Basic.TextField {
                id: serverInput
                width: parent.width
                text: ""
                placeholderText: L10n.I18n.tr("https://matrix.example.org")
                color: root.textPrimary
                padding: 11
                enabled: !root.registrationInFlight
                background: Rectangle {
                    radius: 10
                    color: root.surfaceColor
                    border.color: serverInput.activeFocus
                        ? root.accentColor
                        : Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.15)
                    border.width: 1.2
                }
            }

            Text { text: L10n.I18n.tr("Имя пользователя"); color: root.textSecondary; font.pointSize: 9 }
            Basic.TextField {
                id: usernameInput
                width: parent.width
                placeholderText: L10n.I18n.tr("Введите ник пользователя")
                color: root.textPrimary
                padding: 11
                enabled: !root.registrationInFlight
                background: Rectangle {
                    radius: 10
                    color: root.surfaceColor
                    border.color: usernameInput.activeFocus
                        ? root.accentColor
                        : Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.15)
                    border.width: 1.2
                }
            }

            Text { text: L10n.I18n.tr("Пароль"); color: root.textSecondary; font.pointSize: 9 }
            Basic.TextField {
                id: passwordInput
                width: parent.width
                echoMode: TextInput.Password
                color: root.textPrimary
                padding: 11
                enabled: !root.registrationInFlight
                background: Rectangle {
                    radius: 10
                    color: root.surfaceColor
                    border.color: passwordInput.activeFocus
                        ? root.accentColor
                        : Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.15)
                    border.width: 1.2
                }
                Keys.onReturnPressed: root.submitRegistration()
            }

            Text { text: L10n.I18n.tr("Повторите пароль"); color: root.textSecondary; font.pointSize: 9 }
            Basic.TextField {
                id: confirmPasswordInput
                width: parent.width
                echoMode: TextInput.Password
                color: root.textPrimary
                padding: 11
                enabled: !root.registrationInFlight
                background: Rectangle {
                    radius: 10
                    color: root.surfaceColor
                    border.color: confirmPasswordInput.activeFocus
                        ? root.accentColor
                        : Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.15)
                    border.width: 1.2
                }
                Keys.onReturnPressed: root.submitRegistration()
            }
        }

        Basic.Button {
            id: registerButton
            width: parent.width
            height: 40
            enabled: !root.registrationInFlight && root.backendConnected
            background: Rectangle {
                radius: 10
                color: root.accentColor
                opacity: registerButton.enabled ? 1 : 0.45
            }
            contentItem: Text {
                text: root.registrationInFlight
                    ? L10n.I18n.tr("Регистрация...")
                    : root.backendConnected ? L10n.I18n.tr("Зарегистрироваться") : L10n.I18n.tr("Бэкенд недоступен")
                color: root.accentTextColor
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.bold: true
            }
            onClicked: root.submitRegistration()
        }

        Text {
            text: L10n.I18n.tr("Уже есть аккаунт")
            color: root.accentColor
            font.pointSize: 9
            anchors.horizontalCenter: parent.horizontalCenter
            MouseArea {
                anchors.fill: parent
                enabled: !root.registrationInFlight
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    root.errorText = ""
                    root.loginRequested()
                }
            }
        }
    }

}
