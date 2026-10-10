import QtQuick
import QtQuick.Controls

Dialog {
    property real preferredContentWidth: 390

    // Fusion derives implicitWidth from its content, header and footer. Wrapped
    // content uses the dialog's availableWidth, so give that width one owner.
    implicitWidth: preferredContentWidth + leftPadding + rightPadding
    width: Math.min(implicitWidth, parent ? Math.max(0, parent.width - 32) : implicitWidth)
    contentWidth: availableWidth
    // Read the natural content height, never the height assigned by Popup.
    contentHeight: contentItem ? contentItem.implicitHeight : 0
    implicitHeight: topPadding + bottomPadding + contentHeight
        + (header && header.visible ? header.implicitHeight + spacing : 0)
        + (footer && footer.visible ? footer.implicitHeight + spacing : 0)
}
