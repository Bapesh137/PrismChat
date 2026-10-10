#include "window_decoration_bridge.h"

#include <QCoreApplication>
#include <QDir>
#include <QEvent>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTextStream>
#include <QVariant>

namespace {
QColor opaqueColor(const QColor &color, const QColor &background)
{
    if (!color.isValid())
        return background;
    if (color.alpha() >= 255)
        return color;

    const qreal alpha = color.alphaF();
    return QColor::fromRgbF(color.redF() * alpha + background.redF() * (1.0 - alpha),
                            color.greenF() * alpha + background.greenF() * (1.0 - alpha),
                            color.blueF() * alpha + background.blueF() * (1.0 - alpha));
}

QString rgb(const QColor &color)
{
    return QStringLiteral("%1,%2,%3")
        .arg(color.red())
        .arg(color.green())
        .arg(color.blue());
}

void writeColorSet(QTextStream &stream,
                   const QString &name,
                   const QColor &normalBackground,
                   const QColor &alternateBackground,
                   const QColor &normalForeground,
                   const QColor &inactiveForeground,
                   const QColor &accent)
{
    stream << '[' << name << "]\n"
           << "BackgroundAlternate=" << rgb(alternateBackground) << '\n'
           << "BackgroundNormal=" << rgb(normalBackground) << '\n'
           << "DecorationFocus=" << rgb(accent) << '\n'
           << "DecorationHover=" << rgb(accent) << '\n'
           << "ForegroundActive=" << rgb(accent) << '\n'
           << "ForegroundInactive=" << rgb(inactiveForeground) << '\n'
           << "ForegroundLink=" << rgb(accent) << '\n'
           << "ForegroundNegative=218,68,83\n"
           << "ForegroundNeutral=246,116,0\n"
           << "ForegroundNormal=" << rgb(normalForeground) << '\n'
           << "ForegroundPositive=39,174,96\n"
           << "ForegroundVisited=" << rgb(accent) << "\n\n";
}
} // namespace

WindowDecorationBridge::WindowDecorationBridge(QObject *parent)
    : QObject(parent)
{
}

bool WindowDecorationBridge::apply(const QColor &surfaceValue,
                                   const QColor &backgroundValue,
                                   const QColor &textPrimaryValue,
                                   const QColor &textSecondaryValue,
                                   const QColor &accentValue)
{
    const QColor background = opaqueColor(backgroundValue, QColor(QStringLiteral("#07100A")));
    const QColor surface = opaqueColor(surfaceValue, background);
    const QColor textPrimary = opaqueColor(textPrimaryValue, surface);
    const QColor textSecondary = opaqueColor(textSecondaryValue, background);
    const QColor accent = opaqueColor(accentValue, surface);
    const QString signature = surface.name(QColor::HexRgb)
        + background.name(QColor::HexRgb)
        + textPrimary.name(QColor::HexRgb)
        + textSecondary.name(QColor::HexRgb)
        + accent.name(QColor::HexRgb);
    if (signature == m_lastSignature)
        return true;

    const QString directoryPath = QStandardPaths::writableLocation(
        QStandardPaths::AppConfigLocation);
    if (directoryPath.isEmpty() || !QDir().mkpath(directoryPath))
        return false;

    // Alternate between two files so KWin always receives a changed palette
    // path, while repeated custom-color edits cannot leave unbounded files.
    m_useAlternateFile = !m_useAlternateFile;
    const QString filePath = QDir(directoryPath).filePath(
        m_useAlternateFile ? QStringLiteral("window-decoration-a.colors")
                           : QStringLiteral("window-decoration-b.colors"));
    QSaveFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;

    QTextStream stream(&file);
    stream << "[ColorEffects:Inactive]\n"
           << "ChangeSelectionColor=true\n"
           << "Enable=false\n\n";
    writeColorSet(stream, QStringLiteral("Colors:Window"), surface, background,
                  textPrimary, textSecondary, accent);
    writeColorSet(stream, QStringLiteral("Colors:Button"), surface, background,
                  textPrimary, textSecondary, accent);
    writeColorSet(stream, QStringLiteral("Colors:Header"), surface, background,
                  textPrimary, textSecondary, accent);
    writeColorSet(stream, QStringLiteral("Colors:Header][Inactive"), background, surface,
                  textSecondary, textSecondary, accent);
    stream << "[General]\n"
           << "ColorScheme=PrismChat\n"
           << "Name=PrismChat\n"
           << "shadeSortColumn=true\n\n"
           << "[KDE]\n"
           << "contrast=4\n\n"
           << "[WM]\n"
           << "activeBackground=" << rgb(surface) << '\n'
           << "activeBlend=" << rgb(accent) << '\n'
           << "activeForeground=" << rgb(textPrimary) << '\n'
           << "inactiveBackground=" << rgb(background) << '\n'
           << "inactiveBlend=" << rgb(textSecondary) << '\n'
           << "inactiveForeground=" << rgb(textSecondary) << '\n';

    if (!file.commit())
        return false;

    QCoreApplication *application = QCoreApplication::instance();
    if (!application)
        return false;
    application->setProperty("KDE_COLOR_SCHEME_PATH", filePath);

    // Plasma Integration forwards this application property to KWin on both
    // Wayland and X11 whenever an application palette change is observed.
    QEvent paletteEvent(QEvent::ApplicationPaletteChange);
    QCoreApplication::sendEvent(application, &paletteEvent);
    m_lastSignature = signature;
    return true;
}
