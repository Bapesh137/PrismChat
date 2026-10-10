import QtQuick
import QtTest
import "../utils" as L10n
import "../utils/CallControlTranslations.js" as CallControlTranslations

Item {
    width: 320
    height: 200

    FontLoader {
        id: cjkFont
        source: Qt.resolvedUrl("../assets/NotoSansCJK-Regular.ttc")
    }

    TestCase {
        name: "LocalizedResources"

        function test_cjkFontLoads() {
            tryCompare(cjkFont, "status", FontLoader.Ready, 10000)
            verify(cjkFont.name !== "")
        }

        function test_devicesAndSpacesCoverEveryLanguage() {
            var originalLanguage = L10n.I18n.language
            var languages = ["en", "de", "fr", "it", "pl", "uk", "es",
                             "pt", "el", "zh", "ja", "ko", "ar", "hi"]
            var sources = [
                "Это устройство не подтверждено. Отправьте запрос на подтверждение другим доверенным устройствам.",
                "Запрос на подтверждение отправлен",
                "Не удалось отправить запрос",
                "Лобби пространства",
                "Поиск в пространстве",
                "Только по приглашению",
                "Загружаем ещё комнаты…",
                "Недоступно"
            ]
            for (var languageIndex = 0; languageIndex < languages.length; languageIndex++) {
                L10n.I18n.setLanguage(languages[languageIndex])
                for (var sourceIndex = 0; sourceIndex < sources.length; sourceIndex++) {
                    var translation = L10n.I18n.tr(sources[sourceIndex])
                    verify(translation !== "")
                    if (languages[languageIndex] === "uk" && sourceIndex === sources.length - 1)
                        continue
                    verify(translation !== sources[sourceIndex],
                           languages[languageIndex] + ": " + sources[sourceIndex])
                }
            }
            L10n.I18n.setLanguage(originalLanguage)
        }

        function test_readReceiptsCoverEveryLanguage() {
            var originalLanguage = L10n.I18n.language
            var languages = ["en", "de", "fr", "it", "pl", "uk", "es",
                             "pt", "el", "zh", "ja", "ko", "ar", "hi"]
            var sources = [
                "Прочитали",
                "Прочитано",
                "Время прочтения неизвестно"
            ]
            for (var languageIndex = 0; languageIndex < languages.length; languageIndex++) {
                L10n.I18n.setLanguage(languages[languageIndex])
                for (var sourceIndex = 0; sourceIndex < sources.length; sourceIndex++) {
                    var translation = L10n.I18n.tr(sources[sourceIndex])
                    verify(translation !== "")
                    // The first two Ukrainian forms are intentionally spelled
                    // exactly like their Russian source strings.
                    if (languages[languageIndex] === "uk" && sourceIndex < 2)
                        continue
                    verify(translation !== sources[sourceIndex],
                           languages[languageIndex] + ": " + sources[sourceIndex])
                }
            }
            L10n.I18n.setLanguage(originalLanguage)
        }

        function test_callShellCoversEveryLanguage() {
            var sources = [
                "Qt WebEngine не нашёл доступных окон.",
                "Qt WebEngine не нашёл доступных экранов.",
                "WebEngine не предоставил защищённый контекст звонка",
                "В звонке",
                "Восстанавливаем соединение…",
                "Входящий звонок",
                "Выберите экран или окно, которое будет видно участникам звонка.",
                "Демонстрация экрана",
                "Завершение звонка…",
                "Завершить звонок",
                "Закрыть",
                "Зашифрованный звонок",
                "Звонок",
                "Звонок не подключился вовремя. Проверьте микрофон и MatrixRTC / LiveKit на сервере.",
                "Звонок открыт",
                "На весь экран PrismChat",
                "Не удалось загрузить встроенный Element Call: ",
                "Не удалось запустить локальный сервер Element Call",
                "Не удалось подключиться",
                "Не удалось подключиться к звонку",
                "Не удалось подтвердить завершение звонка",
                "Нет связи с бэкендом",
                "Нет соединения с Matrix",
                "Отклонить",
                "Открыть звонок",
                "Открыть управление звонком",
                "Отменить звонок",
                "Переподключение…",
                "Подключение…",
                "Позвонить",
                "Принять",
                "Процесс голосового звонка завершился. Подключитесь заново.",
                "Свернуть звонок",
                "Связь с бэкендом потеряна",
                "Собеседник отклонил звонок",
                "Уменьшить демонстрацию",
                "Экран",
                "Окно",
                "📞 Аудиозвонок · %1 · длился %2",
                "📞 Вызов без ответа · %1"
            ]
            for (var languageIndex = 0;
                    languageIndex < L10n.I18n.supportedLanguages.length;
                    languageIndex++) {
                var language = L10n.I18n.supportedLanguages[languageIndex].code
                if (language === "ru") continue
                for (var sourceIndex = 0; sourceIndex < sources.length; sourceIndex++) {
                    var source = sources[sourceIndex]
                    var translation = L10n.I18n.trFor(language, source)
                    verify(translation !== "", language + ": " + source)
                    verify(translation !== source, language + ": " + source)
                }
            }
        }

        function test_elementCallFallbackControlsCoverExtraLanguages() {
            var languages = CallControlTranslations.fallbackLanguages()
            compare(languages.length, 25)
            for (var languageIndex = 0; languageIndex < languages.length; languageIndex++) {
                var labels = CallControlTranslations.labelsFor(languages[languageIndex])
                var localizedCount = 0
                for (var keyIndex = 0;
                        keyIndex < CallControlTranslations.keys.length;
                        keyIndex++) {
                    var key = CallControlTranslations.keys[keyIndex]
                    verify(labels[key] !== undefined,
                           languages[languageIndex] + ": " + key)
                    verify(labels[key] !== "", languages[languageIndex] + ": " + key)
                    if (labels[key] !== key) localizedCount++
                }
                // A few short labels are spelled identically in related
                // languages (for example Norwegian "Start video"). Ensure the
                // dictionary as a whole is localized instead of rejecting
                // legitimate cognates.
                verify(localizedCount >= 10, languages[languageIndex])
            }
        }
    }
}
