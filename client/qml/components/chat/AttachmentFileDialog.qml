import QtQuick
import QtQuick.Dialogs
import QtCore
import "../../utils" as L10n

FileDialog {
    id: root

    signal filesSelected(var files)
    signal finished()

    title: L10n.I18n.tr("Выберите файлы")
    fileMode: FileDialog.OpenFiles
    currentFolder: StandardPaths.writableLocation(StandardPaths.HomeLocation)
    nameFilters: [
        L10n.I18n.tr("Все файлы") + " (*)",
        L10n.I18n.tr("Видео") + " (*.mp4 *.m4v *.mov *.mkv *.webm *.avi *.mpeg *.mpg *.ogv *.ts *.mts *.m2ts *.3gp *.3g2 *.flv)",
        L10n.I18n.tr("Изображения") + " (*.png *.jpg *.jpeg *.webp *.gif *.bmp *.avif)",
        L10n.I18n.tr("Аудио") + " (*.mp3 *.m4a *.aac *.ogg *.opus *.wav *.flac)"
    ]

    onAccepted: {
        root.filesSelected(selectedFiles)
        root.finished()
    }
    onRejected: root.finished()
}
