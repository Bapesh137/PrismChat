#pragma once

#include <QDateTime>
#include <QHash>
#include <QJSValue>
#include <QJSValueIterator>
#include <QList>
#include <QSet>
#include <QStringList>
#include <QVariant>
#include <QtQml/QJSEngine>
#include <QtQml/QQmlEngine>
#include <QTimer>

#include <algorithm>
#include <cmath>
#include <functional>
#include <utility>

namespace FrontendLogicSupport {

using Values = QList<QJSValue>;

inline QJSEngine *engineFor(const QJSValue &root)
{
    if (QObject *object = root.toQObject()) {
        if (QJSEngine *engine = qjsEngine(object))
            return engine;
        return qmlEngine(object);
    }
    return nullptr;
}

inline QJSValue undefined()
{
    return QJSValue(QJSValue::UndefinedValue);
}

inline QJSValue nullValue()
{
    return QJSValue(QJSValue::NullValue);
}

inline int length(const QJSValue &value)
{
    if (!value.isObject())
        return 0;
    const QJSValue arrayLength = value.property(QStringLiteral("length"));
    if (arrayLength.isNumber())
        return qMax(0, arrayLength.toInt());
    const QJSValue count = value.property(QStringLiteral("count"));
    return count.isNumber() ? qMax(0, count.toInt()) : 0;
}

inline QJSValue argument(const QJSValue &arguments, int index)
{
    return arguments.isObject() ? arguments.property(index) : undefined();
}

inline QString string(const QJSValue &value, const QString &fallback = {})
{
    if (value.isUndefined() || value.isNull())
        return fallback;
    return value.toString();
}

inline double number(const QJSValue &value, double fallback = 0.0)
{
    if (value.isUndefined() || value.isNull())
        return fallback;
    const double result = value.toNumber();
    return std::isfinite(result) ? result : fallback;
}

inline bool boolean(const QJSValue &value, bool fallback = false)
{
    if (value.isUndefined() || value.isNull())
        return fallback;
    return value.toBool();
}

inline QJSValue call(const QJSValue &object,
                     const QString &method,
                     const Values &arguments = {})
{
    const QJSValue callable = object.property(method);
    if (!callable.isCallable())
        return undefined();
    return callable.callWithInstance(object, arguments);
}

inline QJSValue callRoot(const QJSValue &root,
                         const QString &method,
                         const Values &arguments = {})
{
    return call(root, method, arguments);
}

inline void set(QJSValue object, const QString &name, const QJSValue &value)
{
    object.setProperty(name, value);
}

inline QJSValue object(QJSEngine *engine)
{
    return engine ? engine->newObject() : undefined();
}

inline QJSValue array(QJSEngine *engine, int size = 0)
{
    return engine ? engine->newArray(qMax(0, size)) : undefined();
}

inline QJSValue fromVariant(QJSEngine *engine, const QVariant &value)
{
    return engine ? engine->toScriptValue(value) : undefined();
}

inline QJSValue cloneObject(QJSEngine *engine, const QJSValue &source)
{
    QJSValue result = object(engine);
    if (!source.isObject())
        return result;
    QJSValueIterator iterator(source);
    while (iterator.hasNext()) {
        iterator.next();
        result.setProperty(iterator.name(), iterator.value());
    }
    return result;
}

inline QJSValue cloneArray(QJSEngine *engine, const QJSValue &source)
{
    const int count = length(source);
    QJSValue result = array(engine, count);
    for (int index = 0; index < count; ++index)
        result.setProperty(index, source.property(index));
    return result;
}

inline QJSValue arrayFromValues(QJSEngine *engine, const Values &values)
{
    QJSValue result = array(engine, values.size());
    for (int index = 0; index < values.size(); ++index)
        result.setProperty(index, values.at(index));
    return result;
}

inline Values values(const QJSValue &source)
{
    Values result;
    const int count = length(source);
    result.reserve(count);
    for (int index = 0; index < count; ++index)
        result.append(source.property(index));
    return result;
}

inline QStringList objectKeys(const QJSValue &source)
{
    QStringList result;
    if (!source.isObject())
        return result;
    QJSValueIterator iterator(source);
    while (iterator.hasNext()) {
        iterator.next();
        result.append(iterator.name());
    }
    return result;
}

inline QJSValue mergeObjects(QJSEngine *engine,
                             const QJSValue &source,
                             const QList<QPair<QString, QJSValue>> &changes)
{
    QJSValue result = cloneObject(engine, source);
    for (const auto &change : changes)
        result.setProperty(change.first, change.second);
    return result;
}

inline QJSValue objectFromProperties(
    QJSEngine *engine,
    const QList<QPair<QString, QJSValue>> &properties)
{
    QJSValue result = object(engine);
    for (const auto &property : properties)
        result.setProperty(property.first, property.second);
    return result;
}

inline qint64 nowMs()
{
    return QDateTime::currentMSecsSinceEpoch();
}

inline QString translated(const QJSValue &root, const QString &text)
{
    const QJSValue service = root.property(QStringLiteral("i18nService"));
    const QJSValue translated = call(service, QStringLiteral("tr"), {QJSValue(text)});
    return translated.isString() ? translated.toString() : text;
}

inline QString localizedError(const QJSValue &root,
                              const QString &error,
                              const QString &fallback)
{
    const QJSValue service = root.property(QStringLiteral("i18nService"));
    const QString language = string(service.property(QStringLiteral("language")));
    const QString fallbackText = translated(root, fallback);
    if (error.isEmpty())
        return fallbackText;
    if (language == QStringLiteral("ru"))
        return error;

    const QString direct = translated(root, error);
    if (direct != error)
        return direct;

    // Dynamic backend errors may contain room IDs, server details or SDK text
    // and therefore cannot be matched by a static translation key. Never leak
    // the Russian backend text into another locale: use a localized fallback.
    if (fallbackText != fallback)
        return fallbackText;
    return translated(root, QStringLiteral("Не удалось выполнить действие"));
}

inline QJSValue modelGet(const QJSValue &model, int index)
{
    return call(model, QStringLiteral("get"), {QJSValue(index)});
}

inline int modelCount(const QJSValue &model)
{
    return qMax(0, model.property(QStringLiteral("count")).toInt());
}

inline void modelSetProperty(QJSValue model,
                             int index,
                             const QString &name,
                             const QJSValue &value)
{
    call(model, QStringLiteral("setProperty"), {QJSValue(index), QJSValue(name), value});
}

inline void modelClear(QJSValue model)
{
    call(model, QStringLiteral("clear"));
}

inline void modelAppend(QJSValue model, const QJSValue &value)
{
    call(model, QStringLiteral("append"), {value});
}

inline QJSValue error(QJSEngine *engine, const QString &operation)
{
    if (!engine)
        return undefined();
    engine->throwError(QStringLiteral("Unknown native frontend operation: ") + operation);
    return undefined();
}

inline void callLater(const QJSValue &root, const QString &method)
{
    if (QObject *context = root.toQObject()) {
        QTimer::singleShot(0, context, [root, method] {
            callRoot(root, method);
        });
    }
}

inline void callLater(const QJSValue &root,
                      const QString &method,
                      const Values &arguments)
{
    if (QObject *context = root.toQObject()) {
        QTimer::singleShot(0, context, [root, method, arguments] {
            callRoot(root, method, arguments);
        });
    }
}

} // namespace FrontendLogicSupport
