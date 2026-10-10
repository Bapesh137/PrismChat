import QtQml

QtObject {
    readonly property var themeData: ({
        "id": "cga_glitch",
        "name": "CGA Palette 1",

        "accent": "#FF55FF",       // Главный цвет совпадает с фактическим CGA-акцентом
        "icons": "#55FFFF",        // Циановые иконки контрастируют с маджентовыми кнопками
        "accentText": "#000000",    

        "background": "#000000",    // Абсолютная пустота
        "surface": "#555555",       // Грязный серый (CGA-интенсивный черный)
        "elevated": "#FF55FF",      // Маджента для выделенных элементов

        "textPrimary": "#FFFFFF",   // Белый текст
        "textSecondary": "#55FFFF", // Циан для второстепенного текста

        "divider": "#FFFFFF"        // Белые ломаные границы
    })
}
