.pragma library

var sources = [
    "Приватность",
    "Отметить прочитанным",
    "Отметить как непрочитанное",
    "Повторить"
]

var translations = {
    "en": ["Privacy", "Mark as read", "Mark as unread", "Retry"],
    "de": ["Datenschutz", "Als gelesen markieren", "Als ungelesen markieren", "Erneut versuchen"],
    "fr": ["Confidentialité", "Marquer comme lu", "Marquer comme non lu", "Réessayer"],
    "it": ["Privacy", "Segna come letto", "Segna come non letto", "Riprova"],
    "pl": ["Prywatność", "Oznacz jako przeczytane", "Oznacz jako nieprzeczytane", "Ponów próbę"],
    "uk": ["Приватність", "Позначити як прочитане", "Позначити як непрочитане", "Повторити"],
    "es": ["Privacidad", "Marcar como leído", "Marcar como no leído", "Reintentar"],
    "pt": ["Privacidade", "Marcar como lido", "Marcar como não lido", "Tentar novamente"],
    "el": ["Απόρρητο", "Επισήμανση ως αναγνωσμένο", "Επισήμανση ως μη αναγνωσμένο", "Δοκιμή ξανά"],
    "zh": ["隐私", "标为已读", "标为未读", "重试"],
    "ja": ["プライバシー", "既読にする", "未読にする", "再試行"],
    "ko": ["개인정보 보호", "읽음으로 표시", "읽지 않음으로 표시", "다시 시도"],
    "ar": ["الخصوصية", "وضع علامة كمقروء", "وضع علامة كغير مقروء", "إعادة المحاولة"],
    "hi": ["गोपनीयता", "पढ़ा हुआ चिह्नित करें", "अपठित चिह्नित करें", "फिर कोशिश करें"]
}

function get(languageCode, sourceText) {
    var languageStrings = translations[languageCode]
    if (languageStrings === undefined)
        return undefined
    if (sourceText === "Пометить как прочитанное") sourceText = "Отметить прочитанным"
    var index = sources.indexOf(sourceText)
    return index < 0 ? undefined : languageStrings[index]
}
