import QtQuick
import QtTest
import "../services" as Services
import "../components/chat" as Chat

TestCase {
    name: "NativeModule"
    Component { id: transportFactory; Services.BackendTransport { autoConnect: false } }
    Component { id: composerFactory; Chat.MessageComposer {} }

    function test_bundledFactoriesResolveTheirOwnImportPath() {
        // Neither object connects to the backend or reads the clipboard.
        var transport = createTemporaryObject(transportFactory, this)
        var socket = transport.createNativeSocket()
        verify(socket !== null)
        compare(socket.connected, false)
        var composer = createTemporaryObject(composerFactory, this)
        verify(composer.nativeClipboardHelper !== null)
        compare(typeof composer.nativeClipboardHelper.pasteContents, "function")
    }


    function test_localSocketAndClipboardLoad() {
        // Loading only: do not connect to the user's backend or read clipboard.
        var socket = createTemporaryQmlObject("import Prism.Ipc 1.0; LocalSocket {}", this)
        verify(socket !== null)
        compare(socket.connected, false)
        compare(typeof socket.connectToServer, "function")
        var clipboard = createTemporaryQmlObject("import Prism.Ipc 1.0; ClipboardBridge {}", this)
        verify(clipboard !== null)
        compare(typeof clipboard.pasteContents, "function")
        var logic = createTemporaryQmlObject(
            "import QtQuick; import Prism.Ipc 1.0 as Native; QtObject { property var api: Native.FrontendLogic }",
            this)
        verify(logic !== null)
        verify(logic.api !== null)
        compare(typeof logic.api.invoke, "function")
    }
}
