import QtQuick
import QtQuick.Dialogs
import "../utils/PrismUtils.js" as Utils
import "../utils" as L10n

FileDialog {
    id: root

    signal avatarSelected(string path, string mimeType)
    signal finished()

    title: L10n.I18n.tr("Выберите аватарку")

    onAccepted: {
        var path = Utils.localPath(selectedFile)
        var filename = path.split("/").pop()
        root.avatarSelected(path, Utils.guessMime(filename))
        root.finished()
    }
    onRejected: root.finished()
}
