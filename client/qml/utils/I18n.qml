pragma Singleton

import QtQuick
import "translations/en.js" as En
import "translations/de.js" as De
import "translations/fr.js" as Fr
import "translations/it.js" as It
import "translations/pl.js" as Pl
import "translations/uk.js" as Uk
import "translations/es.js" as Es
import "translations/pt.js" as Pt
import "translations/el.js" as El
import "translations/zh.js" as Zh
import "translations/ja.js" as Ja
import "translations/ko.js" as Ko
import "translations/ar.js" as Ar
import "translations/hi.js" as Hi
import "translations/extra.js" as Extra
import "translations/enhancements.js" as Enhancements
import "translations/system.js" as SystemMessages
import "translations/attachments.js" as AttachmentTranslations
import "translations/ui.js" as UiTranslations
import "translations/storage.js" as StorageTranslations
import "translations/create_room.js" as CreateRoomTranslations
import "translations/notifications.js" as NotificationTranslations
import "translations/stickers.js" as StickerTranslations
import "translations/devices.js" as DeviceTranslations
import "translations/assistant_additions.js" as AssistantAdditions
import "translations/navigation_additions.js" as NavigationAdditions
import "translations/motion_intro.js" as MotionIntroTranslations
import "translations/privacy_encryption.js" as PrivacyEncryptionTranslations
import "translations/encryption_recovery.js" as EncryptionRecoveryTranslations
import "translations/moderation.js" as ModerationTranslations
import "translations/spaces.js" as SpaceTranslations
import "translations/reactions.js" as ReactionTranslations
import "translations/typing.js" as TypingTranslations
import "translations/generated.js" as GeneratedTranslations

QtObject {
    id: root

    property string language: detectSystemLanguage()
    readonly property bool isRtl: ["ar", "he", "fa", "ur"].indexOf(language) !== -1
    // English stays first; the rest use a locale-independent order.
    readonly property var supportedLanguages: [
        { code: "en", name: "English" },
        { code: "af", name: "Afrikaans" },
        { code: "ar", name: "العربية" },
        { code: "eu", name: "Euskara" },
        { code: "bn", name: "বাংলা" },
        { code: "bs", name: "Bosanski" },
        { code: "bg", name: "Български" },
        { code: "ca", name: "Català" },
        { code: "zh", name: "中文" },
        { code: "hr", name: "Hrvatski" },
        { code: "cs", name: "Čeština" },
        { code: "da", name: "Dansk" },
        { code: "nl", name: "Nederlands" },
        { code: "et", name: "Eesti" },
        { code: "fil", name: "Filipino" },
        { code: "fi", name: "Suomi" },
        { code: "fr", name: "Français" },
        { code: "gl", name: "Galego" },
        { code: "de", name: "Deutsch" },
        { code: "el", name: "Ελληνικά" },
        { code: "he", name: "עברית" },
        { code: "hi", name: "हिन्दी" },
        { code: "hu", name: "Magyar" },
        { code: "is", name: "Íslenska" },
        { code: "id", name: "Bahasa Indonesia" },
        { code: "it", name: "Italiano" },
        { code: "ja", name: "日本語" },
        { code: "ko", name: "한국어" },
        { code: "lv", name: "Latviešu" },
        { code: "lt", name: "Lietuvių" },
        { code: "ms", name: "Bahasa Melayu" },
        { code: "nb", name: "Norsk bokmål" },
        { code: "fa", name: "فارسی" },
        { code: "pl", name: "Polski" },
        { code: "pt", name: "Português" },
        { code: "ro", name: "Română" },
        { code: "ru", name: "Русский" },
        { code: "sr", name: "Srpski" },
        { code: "sk", name: "Slovenčina" },
        { code: "sl", name: "Slovenščina" },
        { code: "es", name: "Español" },
        { code: "sw", name: "Kiswahili" },
        { code: "sv", name: "Svenska" },
        { code: "ta", name: "தமிழ்" },
        { code: "te", name: "తెలుగు" },
        { code: "th", name: "ไทย" },
        { code: "tr", name: "Türkçe" },
        { code: "uk", name: "Українська" },
        { code: "ur", name: "اردو" },
        { code: "vi", name: "Tiếng Việt" }
    ]

    function normalizeLanguage(code) {
        var normalized = String(code || "").toLowerCase().replace(/_/g, "-")
        var base = normalized.split("-")[0]
        if (base === "ua")
            base = "uk"
        else if (base === "no")
            base = "nb"
        else if (base === "iw")
            base = "he"
        else if (base === "in")
            base = "id"
        else if (base === "tl")
            base = "fil"
        var supported = []
        for (var index = 0; index < supportedLanguages.length; index++)
            supported.push(supportedLanguages[index].code)
        return supported.indexOf(base) !== -1 ? base : "en"
    }

    function detectSystemLanguage() {
        return normalizeLanguage(Qt.locale().name)
    }

    function initialize(savedLanguage) {
        return setLanguage(savedLanguage && savedLanguage !== ""
                           ? savedLanguage : detectSystemLanguage())
    }

    function setLanguage(code) {
        var normalized = normalizeLanguage(code)
        if (language !== normalized)
            language = normalized
        return normalized
    }

    function dictionaryFor(code) {
        switch (code) {
        case "de": return De.strings
        case "fr": return Fr.strings
        case "it": return It.strings
        case "pl": return Pl.strings
        case "uk": return Uk.strings
        case "es": return Es.strings
        case "pt": return Pt.strings
        case "el": return El.strings
        case "zh": return Zh.strings
        case "ja": return Ja.strings
        case "ko": return Ko.strings
        case "ar": return Ar.strings
        case "hi": return Hi.strings
        case "en": return En.strings
        default: return null
        }
    }

    function lookupTranslation(code, source) {
        if (code === "ru")
            return source
        var dictionary = dictionaryFor(code)
        if (dictionary && dictionary[source] !== undefined)
            return dictionary[source]
        var uiTranslation = UiTranslations.get(code, source)
        if (uiTranslation !== undefined)
            return uiTranslation
        var storageTranslation = StorageTranslations.get(code, source)
        if (storageTranslation !== undefined)
            return storageTranslation
        var createRoomTranslation = CreateRoomTranslations.get(code, source)
        if (createRoomTranslation !== undefined)
            return createRoomTranslation
        var stickerTranslation = StickerTranslations.get(code, source)
        if (stickerTranslation !== undefined)
            return stickerTranslation
        var deviceTranslation = DeviceTranslations.get(code, source)
        if (deviceTranslation !== undefined)
            return deviceTranslation
        var assistantTranslation = AssistantAdditions.get(code, source)
        if (assistantTranslation !== undefined)
            return assistantTranslation
        var motionIntroTranslation = MotionIntroTranslations.get(code, source)
        if (motionIntroTranslation !== undefined)
            return motionIntroTranslation
        var navigationTranslation = NavigationAdditions.get(code, source)
        if (navigationTranslation !== undefined)
            return navigationTranslation
        var privacyEncryptionTranslation = PrivacyEncryptionTranslations.get(code, source)
        if (privacyEncryptionTranslation !== undefined)
            return privacyEncryptionTranslation
        var encryptionRecoveryTranslation = EncryptionRecoveryTranslations.get(code, source)
        if (encryptionRecoveryTranslation !== undefined)
            return encryptionRecoveryTranslation
        var moderationTranslation = ModerationTranslations.get(code, source)
        if (moderationTranslation !== undefined)
            return moderationTranslation
        var reactionTranslation = ReactionTranslations.get(code, source)
        if (reactionTranslation !== undefined)
            return reactionTranslation
        var typingTranslation = TypingTranslations.get(code, source)
        if (typingTranslation !== undefined)
            return typingTranslation
        var spaceTranslation = SpaceTranslations.get(code, source)
        if (spaceTranslation !== undefined)
            return spaceTranslation
        var notificationTranslation = NotificationTranslations.get(code, source)
        if (notificationTranslation !== undefined)
            return notificationTranslation
        var attachmentTranslation = AttachmentTranslations.get(code, source)
        if (attachmentTranslation !== undefined)
            return attachmentTranslation
        var enhancementTranslation = Enhancements.get(code, source)
        if (enhancementTranslation !== undefined)
            return enhancementTranslation
        var extraTranslation = Extra.get(code, source)
        if (extraTranslation !== undefined)
            return extraTranslation
        return GeneratedTranslations.get(code, source)
    }

    function trFor(code, source) {
        var selectedLanguage = normalizeLanguage(code)
        if (selectedLanguage === "ru")
            return source
        var translated = lookupTranslation(selectedLanguage, source)
        if (translated !== undefined)
            return translated
        // Missing translations fall back through English.
        var english = lookupTranslation("en", source)
        return english !== undefined ? english : source
    }

    function tr(source) {
        return trFor(language, source)
    }

    function localizedSystemMessage(kind, body, sender) {
        var text = String(body || "")
        var actor = String(sender || "")
        var target = text
        var marker = ""
        var splitIndex = -1

        if (kind === "invite") {
            marker = " пригласил(а) "
            splitIndex = text.indexOf(marker)
            if (splitIndex >= 0) {
                actor = text.substring(0, splitIndex)
                target = text.substring(splitIndex + marker.length)
            }
        } else if (kind === "kick") {
            marker = " исключил(а) "
            splitIndex = text.indexOf(marker)
            if (splitIndex >= 0) {
                actor = text.substring(0, splitIndex)
                target = text.substring(splitIndex + marker.length)
            }
        } else if (kind === "ban") {
            marker = " заблокировал(а) "
            splitIndex = text.indexOf(marker)
            if (splitIndex >= 0) {
                actor = text.substring(0, splitIndex)
                target = text.substring(splitIndex + marker.length)
            }
        } else if (kind === "join") {
            marker = " вошёл(ла) в комнату"
            splitIndex = text.lastIndexOf(marker)
            if (splitIndex >= 0 && splitIndex === text.length - marker.length)
                target = text.substring(0, splitIndex)
        } else if (kind === "leave") {
            marker = " покинул(а) комнату"
            splitIndex = text.lastIndexOf(marker)
            if (splitIndex >= 0 && splitIndex === text.length - marker.length)
                target = text.substring(0, splitIndex)
        } else if (kind === "invite_rejected") {
            var prefix = "Приглашение для "
            var suffix = " было отклонено или отменено"
            if (text.indexOf(prefix) === 0 && text.lastIndexOf(suffix) === text.length - suffix.length)
                target = text.substring(prefix.length, text.length - suffix.length)
        } else if (kind === "knock") {
            marker = " запросил(а) доступ к комнате"
            splitIndex = text.lastIndexOf(marker)
            if (splitIndex >= 0 && splitIndex === text.length - marker.length)
                target = text.substring(0, splitIndex)
        } else {
            return text
        }

        var generated = GeneratedTranslations.formatSystem(language, kind, actor.trim(), target.trim())
        if (generated !== undefined)
            return generated
        return SystemMessages.format(language, kind, actor.trim(), target.trim(), text)
    }

    function localizedMessagePreview(source) {
        var text = String(source || "")
        var base = text.replace(/\.(ogg|opus|wav|m4a|mp3|webm)$/i, "")
        var normalized = base.toLocaleLowerCase()
        var voiceLabels = [
            "Голосовое сообщение",
            En.strings["Голосовое сообщение"], De.strings["Голосовое сообщение"],
            Fr.strings["Голосовое сообщение"], It.strings["Голосовое сообщение"],
            Pl.strings["Голосовое сообщение"], Uk.strings["Голосовое сообщение"],
            Es.strings["Голосовое сообщение"], Pt.strings["Голосовое сообщение"],
            El.strings["Голосовое сообщение"], Zh.strings["Голосовое сообщение"],
            Ja.strings["Голосовое сообщение"], Ko.strings["Голосовое сообщение"],
            Ar.strings["Голосовое сообщение"], Hi.strings["Голосовое сообщение"]
        ]
        for (var languageIndexValue = 0; languageIndexValue < supportedLanguages.length; languageIndexValue++) {
            var generatedLabel = GeneratedTranslations.get(supportedLanguages[languageIndexValue].code, "Голосовое сообщение")
            if (generatedLabel !== undefined)
                voiceLabels.push(generatedLabel)
        }
        for (var index = 0; index < voiceLabels.length; index++) {
            if (String(voiceLabels[index] || "").toLocaleLowerCase() === normalized)
                return tr("Голосовое сообщение")
        }
        return text
    }
    function languageIndex(code) {
        var normalized = normalizeLanguage(code)
        for (var index = 0; index < supportedLanguages.length; index++) {
            if (supportedLanguages[index].code === normalized)
                return index
        }
        return 0
    }
}
