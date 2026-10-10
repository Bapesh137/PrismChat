#include "clipboard_bridge.h"

#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QMimeData>
#include <QMimeDatabase>
#include <QTemporaryFile>
#include <QUrl>
#include <QVariantList>

namespace {
constexpr qsizetype kMaxClipboardFiles = 16;
constexpr qint64 kMaxClipboardFileBytes = 100LL * 1024LL * 1024LL;
constexpr qsizetype kMaxClipboardTextBytes = 1024 * 1024;
constexpr int kMaxClipboardImageSide = 4096;

QVariantMap result(bool success,
                   const QString &text = {},
                   const QVariantList &attachments = {},
                   const QString &error = {})
{
    return {
        {QStringLiteral("success"), success},
        {QStringLiteral("text"), text},
        {QStringLiteral("attachments"), attachments},
        {QStringLiteral("error"), error},
    };
}

QVariantMap attachmentForFile(const QString &path)
{
    const QFileInfo info(path);
    QMimeDatabase mimeDatabase;
    const QString mimeType = mimeDatabase.mimeTypeForFile(path).name();
    return {
        {QStringLiteral("path"), info.absoluteFilePath()},
        {QStringLiteral("filename"), info.fileName()},
        {QStringLiteral("is_image"), mimeType.startsWith(QStringLiteral("image/"))},
        {QStringLiteral("mime_type"), mimeType},
        {QStringLiteral("size"), info.size()},
    };
}
} // namespace

ClipboardBridge::ClipboardBridge(QObject *parent)
    : QObject(parent)
{
}

QString ClipboardBridge::mimeTypeForFile(const QString &path) const
{
    if (path.trimmed().isEmpty())
        return QStringLiteral("application/octet-stream");

    QMimeDatabase mimeDatabase;
    const QString mimeType = mimeDatabase.mimeTypeForFile(path).name();
    return mimeType.isEmpty() ? QStringLiteral("application/octet-stream") : mimeType;
}

qint64 ClipboardBridge::fileSizeForPath(const QString &path) const
{
    const QFileInfo info(path);
    if (!info.exists() || !info.isFile() || info.isSymLink())
        return -1;
    return info.size();
}

QVariantMap ClipboardBridge::pasteContents() const
{
    QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboard)
        return result(false, {}, {}, QStringLiteral("Буфер обмена Qt недоступен"));

    const QMimeData *mimeData = clipboard->mimeData(QClipboard::Clipboard);
    if (!mimeData)
        return result(true);

    if (mimeData->hasUrls()) {
        QVariantList attachments;
        bool hadLocalFileUrl = false;
        bool hadMissingLocalFile = false;
        bool hadRejectedLocalFile = false;

        const QList<QUrl> urls = mimeData->urls();
        for (const QUrl &url : urls) {
            if (attachments.size() >= kMaxClipboardFiles)
                break;
            if (!url.isLocalFile())
                continue;

            hadLocalFileUrl = true;
            const QFileInfo info(url.toLocalFile());
            if (!info.exists()) {
                hadMissingLocalFile = true;
                continue;
            }
            if (!info.isFile() || info.isSymLink() || info.size() > kMaxClipboardFileBytes) {
                hadRejectedLocalFile = true;
                continue;
            }

            attachments.push_back(attachmentForFile(info.absoluteFilePath()));
        }

        if (!attachments.isEmpty())
            return result(true, {}, attachments);

        if (hadLocalFileUrl && hadMissingLocalFile) {
            return result(false, {}, {},
                          QStringLiteral("Файл из буфера обмена недоступен в этой системе. "
                                         "Если PrismChat запущен в виртуальной машине, "
                                         "передайте файл в гостевую ОС или включите общий каталог."));
        }
        if (hadLocalFileUrl && hadRejectedLocalFile) {
            return result(false, {}, {},
                          QStringLiteral("Файл из буфера не является обычным файлом, является "
                                         "символической ссылкой или превышает лимит 100 МиБ."));
        }
    }

    if (mimeData->hasImage()) {
        const QImage image = qvariant_cast<QImage>(mimeData->imageData());
        if (!image.isNull()) {
            if (image.width() > kMaxClipboardImageSide || image.height() > kMaxClipboardImageSide) {
                return result(false, {}, {},
                              QStringLiteral("Изображение из буфера превышает 4096×4096"));
            }

            QTemporaryFile temporaryFile(
                QDir::tempPath() + QStringLiteral("/prismchat-clipboard-XXXXXX.png"));
            temporaryFile.setAutoRemove(false);
            if (!temporaryFile.open()) {
                return result(false, {}, {},
                              QStringLiteral("Не удалось создать временный файл для изображения"));
            }
            const QString path = temporaryFile.fileName();
            temporaryFile.close();

            if (!image.save(path, "PNG")) {
                QFile::remove(path);
                return result(false, {}, {},
                              QStringLiteral("Не удалось сохранить изображение из буфера"));
            }

            QVariantList attachments;
            attachments.push_back(attachmentForFile(path));
            return result(true, {}, attachments);
        }
    }

    if (mimeData->hasText()) {
        const QString text = mimeData->text();
        if (text.toUtf8().size() > kMaxClipboardTextBytes)
            return result(false, {}, {}, QStringLiteral("Текст из буфера превышает лимит 1 МиБ"));
        return result(true, text);
    }

    return result(true);
}
