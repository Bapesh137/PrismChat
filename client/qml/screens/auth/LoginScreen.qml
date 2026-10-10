import QtQuick
import "../../utils" as L10n
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

    property string connectionStatus: L10n.I18n.tr("Ожидание бэкенда...")
    property color connectionStatusColor: textSecondary
    property string errorText: ""

    property bool loginInFlight: false
    property bool showBackButton: false
    property bool backendConnected: false

    signal loginRequested(string server, string nickname, string password)
    signal registerRequested()
    signal backRequested()

    function submitLogin() {
        if (loginInFlight)
            return

        if (!backendConnected) {
            root.errorText = L10n.I18n.tr("Нет связи с бэкендом")
            return
        }

        if (serverInput.text.trim() === ""
                || nicknameInput.text.trim() === ""
                || passwordInput.text === "") {
            root.errorText = L10n.I18n.tr("Заполните все поля")
            return
        }

        root.errorText = ""
        loginInFlight = true
        root.loginRequested(
            serverInput.text.trim(),
            nicknameInput.text.trim(),
            passwordInput.text
        )
    }

    function setLoginFailed(message) {
        root.errorText = message || L10n.I18n.tr("Ошибка входа")
        loginInFlight = false
    }

    function resetLoginState() {
        loginInFlight = false
    }

    function completeLogin() {
        errorText = ""
        loginInFlight = false
        passwordInput.clear()
    }

    onVisibleChanged: {
        if (!visible) {
            resetLoginState()
            passwordInput.clear()
        }
    }

    color: backgroundColor

    Rectangle {
        width: 380
        height: 380
        radius: 190
        x: -110
        y: -110
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
    }

    Rectangle {
        width: 520
        height: 520
        radius: 260
        x: parent.width - 260
        y: parent.height - 260
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.07)
    }

    Column {
        anchors.centerIn: parent
        width: 320
        spacing: 16

        Rectangle {
            width: parent.width
            height: 44
            radius: 12
            color: root.surfaceColor
            border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.12)
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 10

                Rectangle {
                    width: 28
                    height: 28
                    radius: 8
                    color: root.accentColor

                    Text {
                        anchors.centerIn: parent
                        text: "◐"
                        color: root.accentTextColor
                        font.bold: true
                    }
                }

                Text {
                    text: "PrismChat"
                    font.pointSize: 18
                    font.bold: true
                    color: root.textPrimary
                }
            }
        }

        Column {
            width: parent.width
            spacing: 4

            Text {
                text: root.connectionStatus
                color: root.connectionStatusColor
                font.pointSize: 9
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
        }

        Column {
            width: parent.width
            spacing: 10

            Text {
                text: L10n.I18n.tr("Сервер")
                color: root.textSecondary
                font.pointSize: 9
            }

            Basic.TextField {
                id: serverInput
                width: parent.width
                text: "https://matrix.org"
                color: root.textPrimary
                padding: 11
                enabled: !root.loginInFlight

                background: Rectangle {
                    radius: 10
                    color: root.surfaceColor
                    border.color: serverInput.activeFocus
                        ? root.accentColor
                        : Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.15)
                    border.width: 1.2
                }
            }

            Text {
                text: L10n.I18n.tr("Никнейм")
                color: root.textSecondary
                font.pointSize: 9
            }

            Basic.TextField {
                id: nicknameInput
                width: parent.width
                placeholderText: L10n.I18n.tr("Введите ник пользователя")
                color: root.textPrimary
                padding: 11
                enabled: !root.loginInFlight

                background: Rectangle {
                    radius: 10
                    color: root.surfaceColor
                    border.color: nicknameInput.activeFocus
                        ? root.accentColor
                        : Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.15)
                    border.width: 1.2
                }
            }

            Text {
                text: L10n.I18n.tr("Пароль")
                color: root.textSecondary
                font.pointSize: 9
            }

            Basic.TextField {
                id: passwordInput
                width: parent.width
                echoMode: TextInput.Password
                color: root.textPrimary
                padding: 11
                enabled: !root.loginInFlight

                background: Rectangle {
                    radius: 10
                    color: root.surfaceColor
                    border.color: passwordInput.activeFocus
                        ? root.accentColor
                        : Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.15)
                    border.width: 1.2
                }

                Keys.onReturnPressed: root.submitLogin()
            }
        }

        Basic.Button {
            id: loginButton
            width: parent.width
            height: 40
            enabled: !root.loginInFlight && root.backendConnected

            background: Rectangle {
                radius: 10
                color: root.accentColor
                opacity: loginButton.enabled
                    ? (loginButton.hovered ? 0.9 : 1)
                    : 0.45
            }

            contentItem: Text {
                text: root.loginInFlight
                    ? L10n.I18n.tr("Вход...")
                    : root.backendConnected ? L10n.I18n.tr("Войти") : L10n.I18n.tr("Бэкенд недоступен")
                color: root.accentTextColor
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.bold: true
            }

            onClicked: root.submitLogin()
        }

        Text {
            text: L10n.I18n.tr("Создать аккаунт")
            color: root.accentColor
            font.pointSize: 9
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: root.loginInFlight ? 0.5 : 1

            MouseArea {
                anchors.fill: parent
                enabled: !root.loginInFlight
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                onClicked: {
                    root.errorText = ""
                    root.registerRequested()
                }
            }
        }

        Text {
            visible: root.showBackButton
            text: L10n.I18n.tr("Назад")
            color: root.textSecondary
            font.pointSize: 9
            anchors.horizontalCenter: parent.horizontalCenter

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.backRequested()
            }
        }
    }
}
