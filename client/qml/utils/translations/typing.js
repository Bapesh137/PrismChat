.pragma library

var translations = {
    "en": ["Typing indicator", "Let room members know when you are typing a message. You can override this for individual rooms in “Edit room”.", "Send typing indicator", "Do not send typing indicator", "%1 is typing…", "%1 and %2 are typing…", "%1, %2 and %3 more are typing…"],
    "de": ["Tippanzeige", "Teile Raummitgliedern mit, wenn du eine Nachricht schreibst. Dies kann unter „Raum bearbeiten“ für einzelne Räume geändert werden.", "Tippanzeige senden", "Tippanzeige nicht senden", "%1 tippt…", "%1 und %2 tippen…", "%1, %2 und %3 weitere tippen…"],
    "fr": ["Indicateur de saisie", "Indiquez aux membres du salon quand vous écrivez un message. Ce réglage peut être modifié par salon dans « Modifier le salon ».", "Envoyer l’indicateur de saisie", "Ne pas envoyer l’indicateur de saisie", "%1 écrit…", "%1 et %2 écrivent…", "%1, %2 et %3 autres écrivent…"],
    "it": ["Indicatore di digitazione", "Comunica ai membri della stanza quando stai scrivendo un messaggio. Puoi modificarlo per singole stanze in «Modifica stanza».", "Invia indicatore di digitazione", "Non inviare indicatore di digitazione", "%1 sta scrivendo…", "%1 e %2 stanno scrivendo…", "%1, %2 e altri %3 stanno scrivendo…"],
    "pl": ["Wskaźnik pisania", "Informuj członków pokoju, gdy piszesz wiadomość. Dla poszczególnych pokoi ustawienie można zmienić w „Edytuj pokój”.", "Wysyłaj wskaźnik pisania", "Nie wysyłaj wskaźnika pisania", "%1 pisze…", "%1 i %2 piszą…", "%1, %2 i jeszcze %3 piszą…"],
    "uk": ["Індикатор набору тексту", "Повідомляти учасникам кімнати, коли ви набираєте повідомлення. Для окремих кімнат налаштування можна змінити в «Редагувати кімнату».", "Надсилати індикатор набору", "Не надсилати індикатор набору", "%1 друкує…", "%1 і %2 друкують…", "%1, %2 і ще %3 друкують…"],
    "es": ["Indicador de escritura", "Avisa a los miembros de la sala cuando estás escribiendo un mensaje. Puedes cambiarlo por sala en «Editar sala».", "Enviar indicador de escritura", "No enviar indicador de escritura", "%1 está escribiendo…", "%1 y %2 están escribiendo…", "%1, %2 y %3 más están escribiendo…"],
    "pt": ["Indicador de digitação", "Avise os membros da sala quando estiver escrevendo uma mensagem. Você pode alterar isso por sala em «Editar sala».", "Enviar indicador de digitação", "Não enviar indicador de digitação", "%1 está digitando…", "%1 e %2 estão digitando…", "%1, %2 e mais %3 estão digitando…"],
    "el": ["Ένδειξη πληκτρολόγησης", "Ενημερώστε τα μέλη του δωματίου όταν πληκτρολογείτε μήνυμα. Μπορείτε να το αλλάξετε ανά δωμάτιο στην «Επεξεργασία δωματίου».", "Αποστολή ένδειξης πληκτρολόγησης", "Να μην αποστέλλεται ένδειξη πληκτρολόγησης", "Ο/Η %1 πληκτρολογεί…", "Οι %1 και %2 πληκτρολογούν…", "Οι %1, %2 και %3 ακόμη πληκτρολογούν…"],
    "zh": ["正在输入指示", "输入消息时通知房间成员。可在“编辑房间”中为单个房间更改此设置。", "发送正在输入指示", "不发送正在输入指示", "%1 正在输入…", "%1 和 %2 正在输入…", "%1、%2 及另外 %3 人正在输入…"],
    "ja": ["入力中インジケーター", "メッセージの入力中であることをルームのメンバーに知らせます。ルームごとに「ルームを編集」で変更できます。", "入力中を送信", "入力中を送信しない", "%1 が入力中…", "%1 と %2 が入力中…", "%1、%2、ほか %3 人が入力中…"],
    "ko": ["입력 중 표시", "메시지를 입력할 때 방 구성원에게 알립니다. 방별 설정은 ‘방 편집’에서 변경할 수 있습니다.", "입력 중 표시 보내기", "입력 중 표시 보내지 않기", "%1 님이 입력 중…", "%1 님과 %2 님이 입력 중…", "%1 님, %2 님 외 %3명이 입력 중…"],
    "ar": ["مؤشر الكتابة", "أبلغ أعضاء الغرفة عندما تكتب رسالة. يمكنك تغيير ذلك لكل غرفة من «تعديل الغرفة».", "إرسال مؤشر الكتابة", "عدم إرسال مؤشر الكتابة", "%1 يكتب…", "%1 و%2 يكتبان…", "%1 و%2 و%3 آخرون يكتبون…"],
    "hi": ["टाइपिंग संकेतक", "संदेश लिखते समय कमरे के सदस्यों को बताएँ। हर कमरे के लिए इसे “कमरा संपादित करें” में बदला जा सकता है।", "टाइपिंग संकेतक भेजें", "टाइपिंग संकेतक न भेजें", "%1 लिख रहे हैं…", "%1 और %2 लिख रहे हैं…", "%1, %2 और %3 अन्य लिख रहे हैं…"]
}

var sources = [
    "Индикатор набора текста",
    "Сообщать участникам комнаты, когда вы набираете сообщение. Для отдельных комнат настройку можно изменить в «Редактировать комнату».",
    "Отправлять индикатор набора текста",
    "Не отправлять индикатор набора текста",
    "%1 печатает…",
    "%1 и %2 печатают…",
    "%1, %2 и ещё %3 печатают…"
]

function get(languageCode, sourceText) {
    var values = translations[languageCode]
    if (values === undefined)
        return undefined
    var index = sources.indexOf(sourceText)
    return index < 0 ? undefined : values[index]
}
