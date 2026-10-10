pragma Singleton
import QtQuick

QtObject {
    id: root

    readonly property var builtinPacks: [
        {
            id: "prism-classic",
            display_name_source: "Prism — классика",
            icon: "◆",
            icon_kind: "classic",
            builtin: true,
            images: [
                { builtin_id: "heart", body_source: "Сердце", symbol: "♥", color: "#ff5a7d" },
                { builtin_id: "star", body_source: "Звезда", symbol: "★", color: "#ffc94a" },
                { builtin_id: "check", body_source: "Готово", symbol: "✓", color: "#42d982" },
                { builtin_id: "alert", body_source: "Внимание", symbol: "!", color: "#ff8a4c" },
                { builtin_id: "smile", body_source: "Улыбка", symbol: "☺", color: "#ffd84d" },
                { builtin_id: "party", body_source: "Праздник", symbol: "✦", color: "#b788ff" },
                { builtin_id: "thumbs_up", body_source: "Класс", symbol: "👍", color: "#ffd084" },
                { builtin_id: "thumbs_down", body_source: "Не нравится", symbol: "👎", color: "#ffd084" },
                { builtin_id: "fire", body_source: "Огонь", symbol: "🔥", color: "#ff824d" },
                { builtin_id: "rocket", body_source: "Поехали", symbol: "🚀", color: "#70c8ff" },
                { builtin_id: "laugh", body_source: "Смешно", symbol: "😂", color: "#ffd84d" },
                { builtin_id: "sad", body_source: "Грустно", symbol: "☹", color: "#71b9ff" },
                { builtin_id: "wow", body_source: "Вау", symbol: "○", color: "#ffd84d" },
                { builtin_id: "wave", body_source: "Привет", symbol: "👋", color: "#ffd084" },
                { builtin_id: "clap", body_source: "Аплодисменты", symbol: "👏", color: "#ffd084" },
                { builtin_id: "coffee", body_source: "Кофе", symbol: "☕", color: "#c68b59" },
                { builtin_id: "idea", body_source: "Идея", symbol: "💡", color: "#ffe05a" }
            ]
        },
        {
            id: "prism-reactions",
            display_name_source: "Prism — реакции",
            icon: "☺",
            icon_kind: "reactions",
            builtin: true,
            images: [
                { builtin_id: "love", body_source: "Влюблён", symbol: "😍", color: "#ff6b91" },
                { builtin_id: "cool", body_source: "Круто", symbol: "😎", color: "#ffd84d" },
                { builtin_id: "angry", body_source: "Злюсь", symbol: "😡", color: "#ff6565" },
                { builtin_id: "cry", body_source: "Плачу", symbol: "😭", color: "#79c7ff" },
                { builtin_id: "sleepy", body_source: "Спать", symbol: "😴", color: "#b79cff" },
                { builtin_id: "thinking", body_source: "Думаю", symbol: "🤔", color: "#ffd084" },
                { builtin_id: "question", body_source: "Вопрос", symbol: "?", color: "#78bfff" },
                { builtin_id: "lightning", body_source: "Молния", symbol: "⚡", color: "#ffe15a" },
                { builtin_id: "sparkle", body_source: "Блеск", symbol: "✨", color: "#ffd95d" },
                { builtin_id: "gift", body_source: "Подарок", symbol: "🎁", color: "#ff6e88" },
                { builtin_id: "music", body_source: "Музыка", symbol: "♪", color: "#b889ff" }
            ]
        },
        {
            id: "prism-animated",
            display_name_source: "Prism — анимация",
            icon: "✦",
            icon_kind: "animated",
            builtin: true,
            images: [
                { builtin_id: "heart_pulse", body_source: "Сердце бьётся", symbol: "♥", color: "#ff5a7d", animated: true },
                { builtin_id: "star_bounce", body_source: "Прыгающая звезда", symbol: "★", color: "#ffc94a", animated: true },
                { builtin_id: "smile_blink", body_source: "Подмигивание", symbol: "☺", color: "#ffd84d", animated: true },
                { builtin_id: "party_wiggle", body_source: "Танцующая вечеринка", symbol: "✦", color: "#b788ff", animated: true },
                { builtin_id: "rocket_launch", body_source: "Запуск ракеты", symbol: "🚀", color: "#70c8ff", animated: true },
                { builtin_id: "fire_flicker", body_source: "Живой огонь", symbol: "🔥", color: "#ff824d", animated: true },
                { builtin_id: "wave_wiggle", body_source: "Машу рукой", symbol: "👋", color: "#ffd084", animated: true },
                { builtin_id: "wow_pulse", body_source: "Большое вау", symbol: "○", color: "#ffd84d", animated: true }
            ]
        },
        {
            id: "prism-signs",
            display_name_source: "Prism — знаки",
            icon: "☀",
            icon_kind: "signs",
            builtin: true,
            images: [
                { builtin_id: "stop", body_source: "Стоп", symbol: "⛔", color: "#ff6464" },
                { builtin_id: "yes", body_source: "Да", symbol: "✓", color: "#42d982" },
                { builtin_id: "no", body_source: "Нет", symbol: "✕", color: "#ff6464" },
                { builtin_id: "sun", body_source: "Солнце", symbol: "☀", color: "#ffd84d" },
                { builtin_id: "moon", body_source: "Луна", symbol: "☾", color: "#a8b8ff" },
                { builtin_id: "crown", body_source: "Корона", symbol: "♛", color: "#ffd35c" },
                { builtin_id: "trophy", body_source: "Победа", symbol: "🏆", color: "#ffc94a" },
                { builtin_id: "pizza", body_source: "Пицца", symbol: "🍕", color: "#ff9b58" },
                { builtin_id: "cloud", body_source: "Облачно", symbol: "☁", color: "#b6c5d4" },
                { builtin_id: "rain", body_source: "Дождь", symbol: "☂", color: "#70c8ff" },
                { builtin_id: "bell", body_source: "Звонок", symbol: "🔔", color: "#ffd35c" },
                { builtin_id: "camera", body_source: "Фото", symbol: "▣", color: "#9ab7ce" }
            ]
        }
    ]

    function packById(packId) {
        var id = String(packId || "")
        for (var index = 0; index < builtinPacks.length; index++) {
            if (builtinPacks[index].id === id)
                return builtinPacks[index]
        }
        return null
    }

    function packForBuiltinId(stickerId) {
        var id = String(stickerId || "")
        for (var packIndex = 0; packIndex < builtinPacks.length; packIndex++) {
            var images = builtinPacks[packIndex].images || []
            for (var imageIndex = 0; imageIndex < images.length; imageIndex++) {
                if (String(images[imageIndex].builtin_id || "") === id)
                    return builtinPacks[packIndex]
            }
        }
        return null
    }

    function packForBody(body) {
        var value = String(body || "")
        for (var packIndex = 0; packIndex < builtinPacks.length; packIndex++) {
            var images = builtinPacks[packIndex].images || []
            for (var imageIndex = 0; imageIndex < images.length; imageIndex++) {
                if (String(images[imageIndex].body_source || "") === value)
                    return builtinPacks[packIndex]
            }
        }
        return null
    }
}
