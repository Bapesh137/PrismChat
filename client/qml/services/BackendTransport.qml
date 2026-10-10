import QtQuick
import "../utils" as L10n
import QtWebSockets
import Prism.Ipc 1.0 as Native

Item {
    id: root

    property color accentColor: "#20D500"
    property bool autoConnect: true
    property string activeTransport: ""
    property var nativeSocket: null
    property bool nativeModuleAvailable: true
    property bool nativeAttemptActive: false
    // Replaced by the backend-advertised values after connecting.
    property int nativeFallbackDelayMs: 500
    property int reconnectDelayMs: 1000
    readonly property bool connected: activeTransport !== ""

    signal connectionStateChanged(string text, var stateColor)
    signal textMessageReceived(string message)

    width: 0
    height: 0
    visible: false

    function sendTextMessage(message) {
        if (activeTransport === "native" && nativeSocket)
            return nativeSocket.sendTextMessage(message)
        if (activeTransport === "websocket" && webSocket.status === WebSocket.Open) {
            webSocket.sendTextMessage(message)
            return true
        }
        return false
    }

    function start() {
        reconnectTimer.stop()
        activeTransport = ""
        if (nativeModuleAvailable && startNative())
            return
        startWebSocket()
    }

    function createNativeSocket() {
        // Prism.Ipc is registered by PrismChatUi or the deployed QML module.
        return nativeSocketComponent.createObject(root)
    }

    function startNative() {
        destroyNativeSocket()

        try {
            nativeSocket = createNativeSocket()
        } catch (error) {
            nativeModuleAvailable = false
            console.info(L10n.I18n.tr("Нативный IPC-модуль недоступен, используется WebSocket:"), error)
            return false
        }

        nativeAttemptActive = true
        nativeSocket.opened.connect(nativeOpened)
        nativeSocket.closed.connect(nativeClosed)
        nativeSocket.errorOccurred.connect(nativeError)
        nativeSocket.textMessageReceived.connect(function(message) {
            root.textMessageReceived(message)
        })
        connectionStateChanged(L10n.I18n.tr("Подключение к локальному IPC..."), "#a7b8aa")
        nativeSocket.connectToServer()
        if (nativeAttemptActive)
            nativeFallbackTimer.restart()
        return true
    }

    function nativeOpened() {
        if (!nativeAttemptActive) {
            if (nativeSocket) nativeSocket.abort()
            return
        }

        nativeAttemptActive = false
        nativeFallbackTimer.stop()
        webSocket.active = false
        activeTransport = "native"
        connectionStateChanged(L10n.I18n.tr("Подключено (локальный IPC)"), accentColor)
    }

    function nativeClosed() {
        if (nativeAttemptActive) {
            fallbackToWebSocket()
            return
        }
        if (activeTransport === "native") {
            activeTransport = ""
            connectionStateChanged(L10n.I18n.tr("Связь с бэкендом потеряна"), "#ff5252")
            reconnectTimer.restart()
        }
    }

    function nativeError(errorText) {
        if (nativeAttemptActive) {
            fallbackToWebSocket()
            return
        }
        if (activeTransport === "native") {
            activeTransport = ""
            connectionStateChanged(L10n.I18n.language === "ru" && errorText !== ""
                                   ? errorText : L10n.I18n.tr("Ошибка локального IPC"), "#ff5252")
            reconnectTimer.restart()
        }
    }

    function fallbackToWebSocket() {
        if (!nativeAttemptActive)
            return
        nativeAttemptActive = false
        nativeFallbackTimer.stop()
        if (nativeSocket) nativeSocket.abort()
        startWebSocket()
    }

    function startWebSocket() {
        if (webSocket.status === WebSocket.Open) {
            activeTransport = "websocket"
            return
        }
        connectionStateChanged(L10n.I18n.tr("Подключение через WebSocket..."), "#a7b8aa")
        webSocket.active = true
    }

    function destroyNativeSocket() {
        if (!nativeSocket)
            return
        nativeSocket.abort()
        nativeSocket.destroy()
        nativeSocket = null
    }

    Component.onCompleted: if (autoConnect) start()
    Component.onDestruction: {
        reconnectTimer.stop()
        nativeFallbackTimer.stop()
        webSocket.active = false
        destroyNativeSocket()
    }

    Component {
        id: nativeSocketComponent
        Native.LocalSocket {}
    }

    WebSocket {
        id: webSocket
        url: "ws://127.0.0.1:3042"
        active: false

        onStatusChanged: function(socketStatus) {
            if (socketStatus === WebSocket.Open) {
                reconnectTimer.stop()
                root.activeTransport = "websocket"
                root.connectionStateChanged(L10n.I18n.tr("Подключено (WebSocket)"), root.accentColor)
            } else if (socketStatus === WebSocket.Error) {
                if (root.activeTransport === "websocket")
                    root.activeTransport = ""
                root.connectionStateChanged(L10n.I18n.tr("Бэкенд не запущен"), "#ff5252")
                active = false
                reconnectTimer.restart()
            } else if (socketStatus === WebSocket.Closed && root.activeTransport === "websocket") {
                activeTransport = ""
                root.connectionStateChanged(L10n.I18n.tr("Связь с бэкендом потеряна"), "#ff5252")
                reconnectTimer.restart()
            }
        }

        onTextMessageReceived: function(message) {
            root.textMessageReceived(message)
        }
    }

    Timer {
        id: nativeFallbackTimer
        interval: root.nativeFallbackDelayMs
        onTriggered: root.fallbackToWebSocket()
    }

    Timer {
        id: reconnectTimer
        interval: root.reconnectDelayMs
        onTriggered: root.start()
    }
}
