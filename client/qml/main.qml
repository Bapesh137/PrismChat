import QtQuick

Window {
    id: bootstrap

    visible: true
    width: 760
    height: 260
    title: "PrismChat"
    color: "#08110c"

    property var applicationComponent: null
    property var applicationWindow: null
    property string loadError: ""

    function finishLoading() {
        if (!applicationComponent)
            return

        if (applicationComponent.status === Component.Error) {
            loadError = applicationComponent.errorString()
            console.error("PrismChat QML load error:\n" + loadError)
            return
        }

        if (applicationComponent.status !== Component.Ready)
            return

        applicationWindow = applicationComponent.createObject(null)
        if (!applicationWindow) {
            loadError = applicationComponent.errorString()
            console.error("PrismChat QML object creation error:\n" + loadError)
            return
        }

        visible = false
    }

    Component.onCompleted: {
        applicationComponent = Qt.createComponent(
            Qt.resolvedUrl("PrismChatWindow.qml"), Component.PreferSynchronous)
        if (applicationComponent.status === Component.Loading)
            applicationComponent.statusChanged.connect(finishLoading)
        finishLoading()
    }

    Text {
        anchors.fill: parent
        anchors.margins: 24
        visible: bootstrap.loadError !== ""
        text: bootstrap.loadError
        color: "#ff7b7b"
        wrapMode: Text.WrapAnywhere
        font.family: "monospace"
        font.pixelSize: 13
    }
}
