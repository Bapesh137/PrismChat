#include "notification_bridge.h"

#include <QApplication>
#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QIcon>
#include <QTimer>

int main(int argc, char *argv[])
{
    QApplication application(argc, argv);
    QApplication::setApplicationName(QStringLiteral("PrismChat"));
    QApplication::setOrganizationName(QStringLiteral("PrismChat"));
    QApplication::setWindowIcon(QIcon(QStringLiteral(":/app/prismchat.png")));
#if defined(Q_OS_LINUX)
    QGuiApplication::setDesktopFileName(QStringLiteral("prismchat"));
#endif
    QApplication::setQuitOnLastWindowClosed(false);

    QCommandLineParser parser;
    parser.addHelpOption();
    const QCommandLineOption titleOption(
        QStringLiteral("title"), QStringLiteral("Notification title"), QStringLiteral("title"));
    const QCommandLineOption messageOption(
        QStringLiteral("message"), QStringLiteral("Notification message"), QStringLiteral("message"));
    parser.addOption(titleOption);
    parser.addOption(messageOption);
    parser.process(application);

    const QString title = parser.value(titleOption).trimmed();
    const QString message = parser.value(messageOption).trimmed();
    if (message.isEmpty())
        return 2;

    NotificationBridge notifier;
    if (!notifier.available())
        return 3;

    QTimer::singleShot(250, &application, [&notifier, title, message] {
        notifier.showNotification(title, message, QString());
    });
    QTimer::singleShot(10000, &application, &QCoreApplication::quit);
    return application.exec();
}
