.pragma library

var sources = ["Быстрые реакции", "Изменить набор", "Выберите реакцию сверху, затем новый эмодзи", "Заменить"]
var translations = {
    en: ["Quick reactions", "Edit set", "Choose a reaction above, then a new emoji", "Replace"],
    de: ["Schnellreaktionen", "Auswahl ändern", "Wähle oben eine Reaktion und dann ein neues Emoji", "Ersetzen"],
    fr: ["Réactions rapides", "Modifier la sélection", "Choisissez une réaction ci-dessus, puis un nouvel emoji", "Remplacer"],
    it: ["Reazioni rapide", "Modifica selezione", "Scegli una reazione sopra, poi una nuova emoji", "Sostituisci"],
    pl: ["Szybkie reakcje", "Edytuj zestaw", "Wybierz reakcję powyżej, a następnie nowe emoji", "Zastąp"],
    uk: ["Швидкі реакції", "Змінити набір", "Виберіть реакцію вгорі, а потім новий емодзі", "Замінити"],
    es: ["Reacciones rápidas", "Editar selección", "Elige una reacción arriba y luego un nuevo emoji", "Reemplazar"],
    pt: ["Reações rápidas", "Editar seleção", "Escolha uma reação acima e depois um novo emoji", "Substituir"],
    el: ["Γρήγορες αντιδράσεις", "Αλλαγή επιλογής", "Επίλεξε μια αντίδραση παραπάνω και μετά ένα νέο emoji", "Αντικατάσταση"],
    zh: ["快捷回应", "编辑组合", "先选择上方的回应，再选择新的表情", "替换"],
    ja: ["クイックリアクション", "セットを編集", "上のリアクションを選んでから、新しい絵文字を選択", "置き換え"],
    ko: ["빠른 반응", "목록 편집", "위에서 반응을 고른 다음 새 이모지를 선택하세요", "바꾸기"],
    ar: ["التفاعلات السريعة", "تعديل المجموعة", "اختر تفاعلاً أعلاه ثم رمزاً تعبيرياً جديداً", "استبدال"],
    hi: ["त्वरित प्रतिक्रियाएँ", "समूह बदलें", "ऊपर कोई प्रतिक्रिया चुनें, फिर नया इमोजी चुनें", "बदलें"]
}

function get(languageCode, sourceText) {
    var values = translations[languageCode]
    var index = sources.indexOf(sourceText)
    return values && index >= 0 ? values[index] : undefined
}
