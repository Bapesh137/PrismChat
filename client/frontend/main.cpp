#include "clipboard_bridge.h"
#include "frontend_logic.h"
#include "voice/voice_web_profile.h"
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#include "local_socket_bridge.h"
#include "notification_bridge.h"
#include "window_decoration_bridge.h"

#include <QApplication>
#include <QByteArray>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>
#include <QtGlobal>
#include <QtQml>

int main(int argc, char *argv[])
{
    bool remoteWayland = false;
#if defined(Q_OS_LINUX)
    const bool hasWaylandDisplay = !qEnvironmentVariableIsEmpty("WAYLAND_DISPLAY");
    remoteWayland = !qEnvironmentVariableIsEmpty("SSH_CONNECTION")
        && hasWaylandDisplay;
    const bool forceSoftware = qEnvironmentVariableIntValue(
                                   "PRISMCHAT_FORCE_SOFTWARE_RENDERING")
        == 1;
    const bool softwareRendering = remoteWayland || forceSoftware
        || qgetenv("QT_QUICK_BACKEND") == "software"
        || qgetenv("LIBGL_ALWAYS_SOFTWARE") == "1";
    const bool disableWebEngineGpu = softwareRendering
        || qEnvironmentVariableIntValue("PRISMCHAT_DISABLE_WEBENGINE_GPU") == 1;
    // Chromium selects its capturer before QApplication; repair remote Wayland metadata first.
    if (hasWaylandDisplay
        && qEnvironmentVariable("XDG_SESSION_TYPE").compare(
               QStringLiteral("wayland"), Qt::CaseInsensitive)
            != 0) {
        qputenv("XDG_SESSION_TYPE", QByteArrayLiteral("wayland"));
    }
    QByteArray chromiumFlags = qgetenv("QTWEBENGINE_CHROMIUM_FLAGS");
    if (hasWaylandDisplay && chromiumFlags.isEmpty()) {
        chromiumFlags = QByteArrayLiteral(
            "--enable-features=WebRTCPipeWireCapturer");
    }
    // Stop Chromium GPU retries when the session already uses software rendering.
    if (disableWebEngineGpu && !chromiumFlags.contains("--disable-gpu")) {
        if (!chromiumFlags.isEmpty())
            chromiumFlags.append(' ');
        chromiumFlags.append(
            QByteArrayLiteral("--disable-gpu --disable-gpu-compositing"));
    }
    if (!chromiumFlags.isEmpty())
        qputenv("QTWEBENGINE_CHROMIUM_FLAGS", chromiumFlags);

    // Remote Wayland may need software GL; explicit renderer settings win.
    if ((remoteWayland || forceSoftware)
        && qEnvironmentVariableIsEmpty("QT_QUICK_BACKEND")
        && qEnvironmentVariableIsEmpty("QSG_RHI_BACKEND")) {
        qputenv("QSG_RHI_BACKEND", QByteArrayLiteral("opengl"));
        if (qEnvironmentVariableIsEmpty("LIBGL_ALWAYS_SOFTWARE"))
            qputenv("LIBGL_ALWAYS_SOFTWARE", QByteArrayLiteral("1"));
        if (qEnvironmentVariableIsEmpty("GALLIUM_DRIVER"))
            qputenv("GALLIUM_DRIVER", QByteArrayLiteral("llvmpipe"));
    }
    if (qgetenv("QT_QUICK_BACKEND") == "software"
        || qgetenv("LIBGL_ALWAYS_SOFTWARE") == "1") {
        if (qEnvironmentVariableIsEmpty("QT_FFMPEG_DECODING_HW_DEVICE_TYPES"))
            qputenv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", QByteArrayLiteral(","));
        if (qEnvironmentVariableIsEmpty("QT_FFMPEG_ENCODING_HW_DEVICE_TYPES"))
            qputenv("QT_FFMPEG_ENCODING_HW_DEVICE_TYPES", QByteArrayLiteral(","));
        if (qEnvironmentVariableIsEmpty("QT_DISABLE_HW_TEXTURES_CONVERSION"))
            qputenv("QT_DISABLE_HW_TEXTURES_CONVERSION", QByteArrayLiteral("1"));
    }
#endif

    // Authenticated media-proxy URLs must not appear in info logs.
    qputenv("QT_LOGGING_RULES",
            QByteArrayLiteral("qt.multimedia.ffmpeg.mediadataholder.info=false;")
                + qgetenv("QT_LOGGING_RULES"));

    QtWebEngineQuick::initialize();
    QApplication application(argc, argv);
    QApplication::setApplicationName(QStringLiteral("PrismChat"));
    QApplication::setOrganizationName(QStringLiteral("PrismChat"));
    QApplication::setWindowIcon(QIcon(QStringLiteral(":/app/prismchat.png")));
#if defined(Q_OS_LINUX)
    QGuiApplication::setDesktopFileName(QStringLiteral("prismchat"));
#endif

    qmlRegisterType<LocalSocketBridge>("Prism.Ipc", 1, 0, "LocalSocket");
    qmlRegisterSingletonType<FrontendLogic>(
        "Prism.Ipc", 1, 0, "FrontendLogic",
        [](QQmlEngine *, QJSEngine *) -> QObject * {
            return new FrontendLogic;
        });

    qmlRegisterType<VoiceWebProfile>("Prism.Ipc", 1, 0, "VoiceWebProfile");
    QQmlApplicationEngine engine;
    LocalSocketBridge localSocketBridge;
    NotificationBridge notificationBridge;
    ClipboardBridge clipboardBridge;
    WindowDecorationBridge windowDecorationBridge;
    engine.rootContext()->setContextProperty(QStringLiteral("nativeIpcSocket"),
                                             &localSocketBridge);
    engine.rootContext()->setContextProperty(QStringLiteral("systemNotifier"),
                                             &notificationBridge);
    engine.rootContext()->setContextProperty(QStringLiteral("clipboardBridge"),
                                             &clipboardBridge);
    engine.rootContext()->setContextProperty(QStringLiteral("windowDecorationBridge"),
                                             &windowDecorationBridge);
    // Qt 6.11 does not expose the QPA backend through Qt.platform.pluginName.
    engine.rootContext()->setContextProperty(QStringLiteral("prismPlatformName"),
                                             QGuiApplication::platformName());
    engine.rootContext()->setContextProperty(QStringLiteral("prismRemoteWayland"),
                                             remoteWayland);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &application,
        [] { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.load(QUrl(QStringLiteral("qrc:/qml/PrismChatWindow.qml")));

    return application.exec();
}
