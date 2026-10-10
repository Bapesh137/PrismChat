import QtQuick
import Qt5Compat.GraphicalEffects
import "../../utils/PrismUtils.js" as Utils

Item {
    id: root

    property string mxcUrl: ""
    property string fallbackId: ""
    property string mediaProxy: ""
    property bool roundAvatars: true
    property int size: 36

    readonly property int avatarRadius: roundAvatars ? size / 2 : Math.round(size * 0.22)
    readonly property int thumbnailSize: size <= 64 ? 128 : 256
    readonly property string originalSource: Utils.proxyUrl(mxcUrl, mediaProxy)
    readonly property string thumbnailSource: Utils.proxyUrl(mxcUrl, mediaProxy, null, "",
                                                              thumbnailSize, thumbnailSize)
    property int retryAttempt: 0

    onOriginalSourceChanged: {
        retryTimer.stop()
        retryAttempt = 0
    }

    Timer {
        id: retryTimer
        interval: root.retryAttempt === 0 ? 1000 : 3000
        onTriggered: root.retryAttempt++
    }

    width: size
    height: size

    Rectangle {
        id: fallbackAvatar
        anchors.fill: parent
        radius: root.avatarRadius
        color: Utils.avatarColor(root.fallbackId)
        visible: avatarImage.status !== Image.Ready

        Text {
            anchors.centerIn: parent
            text: Utils.displayName(root.fallbackId).charAt(0).toUpperCase()
            color: "white"
            font.pointSize: Math.max(8, root.width * 0.38)
            font.bold: true
        }
    }

    Image {
        id: avatarImage
        objectName: "avatarImage"
        anchors.fill: parent
        // Retry thumbnails twice, then use the original image.
        source: root.originalSource === "" ? ""
            : (root.retryAttempt >= 2 ? root.originalSource : root.thumbnailSource)
                + (root.retryAttempt > 0 ? "&retry=" + root.retryAttempt : "")
        sourceSize: Qt.size(root.thumbnailSize, root.thumbnailSize)
        onStatusChanged: {
            if (status === Image.Error && root.retryAttempt < 2)
                retryTimer.restart()
            else if (status === Image.Ready)
                retryTimer.stop()
        }
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        mipmap: true

        // OpacityMask still needs a visible source item.
        visible: true
        opacity: 0.0
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.avatarRadius
        visible: false
    }

    OpacityMask {
        id: maskedAvatar
        anchors.fill: parent
        source: avatarImage
        maskSource: mask
        cached: true
        visible: avatarImage.status === Image.Ready
    }
}
