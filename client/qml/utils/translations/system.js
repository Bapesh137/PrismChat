.pragma library

var templates = {
    "ru": {
        "invite": "{actor} пригласил(а) {target}",
        "join": "{target} вошёл(ла) в комнату",
        "leave": "{target} покинул(а) комнату",
        "invite_rejected": "Приглашение для {target} было отклонено или отменено",
        "kick": "{actor} исключил(а) {target}",
        "ban": "{actor} заблокировал(а) {target}",
        "knock": "{target} запросил(а) доступ к комнате"
    },
    "en": {
        "invite": "{actor} invited {target}",
        "join": "{target} joined the room",
        "leave": "{target} left the room",
        "invite_rejected": "The invitation for {target} was declined or withdrawn",
        "kick": "{actor} removed {target} from the room",
        "ban": "{actor} banned {target}",
        "knock": "{target} requested access to the room"
    },
    "de": {
        "invite": "{actor} hat {target} eingeladen",
        "join": "{target} ist dem Raum beigetreten",
        "leave": "{target} hat den Raum verlassen",
        "invite_rejected": "Die Einladung für {target} wurde abgelehnt oder zurückgezogen",
        "kick": "{actor} hat {target} aus dem Raum entfernt",
        "ban": "{actor} hat {target} gesperrt",
        "knock": "{target} hat Zugang zum Raum angefragt"
    },
    "fr": {
        "invite": "{actor} a invité {target}",
        "join": "{target} a rejoint le salon",
        "leave": "{target} a quitté le salon",
        "invite_rejected": "L’invitation de {target} a été refusée ou annulée",
        "kick": "{actor} a exclu {target} du salon",
        "ban": "{actor} a banni {target}",
        "knock": "{target} a demandé l’accès au salon"
    },
    "it": {
        "invite": "{actor} ha invitato {target}",
        "join": "{target} è entrato nella stanza",
        "leave": "{target} ha lasciato la stanza",
        "invite_rejected": "L’invito per {target} è stato rifiutato o annullato",
        "kick": "{actor} ha rimosso {target} dalla stanza",
        "ban": "{actor} ha bloccato {target}",
        "knock": "{target} ha richiesto l’accesso alla stanza"
    },
    "pl": {
        "invite": "{actor} zaprosił(a) {target}",
        "join": "{target} dołączył(a) do pokoju",
        "leave": "{target} opuścił(a) pokój",
        "invite_rejected": "Zaproszenie dla {target} zostało odrzucone lub wycofane",
        "kick": "{actor} usunął(-ęła) {target} z pokoju",
        "ban": "{actor} zablokował(a) {target}",
        "knock": "{target} poprosił(a) o dostęp do pokoju"
    },
    "uk": {
        "invite": "{actor} запросив(-ла) {target}",
        "join": "{target} приєднався(-лася) до кімнати",
        "leave": "{target} залишив(-ла) кімнату",
        "invite_rejected": "Запрошення для {target} було відхилено або скасовано",
        "kick": "{actor} видалив(-ла) {target} з кімнати",
        "ban": "{actor} заблокував(-ла) {target}",
        "knock": "{target} запросив(-ла) доступ до кімнати"
    },
    "es": {
        "invite": "{actor} invitó a {target}",
        "join": "{target} se unió a la sala",
        "leave": "{target} salió de la sala",
        "invite_rejected": "La invitación para {target} fue rechazada o retirada",
        "kick": "{actor} expulsó a {target} de la sala",
        "ban": "{actor} bloqueó a {target}",
        "knock": "{target} solicitó acceso a la sala"
    },
    "pt": {
        "invite": "{actor} convidou {target}",
        "join": "{target} entrou na sala",
        "leave": "{target} saiu da sala",
        "invite_rejected": "O convite para {target} foi recusado ou cancelado",
        "kick": "{actor} removeu {target} da sala",
        "ban": "{actor} bloqueou {target}",
        "knock": "{target} solicitou acesso à sala"
    },
    "el": {
        "invite": "Ο χρήστης {actor} προσκάλεσε τον χρήστη {target}",
        "join": "Ο χρήστης {target} μπήκε στο δωμάτιο",
        "leave": "Ο χρήστης {target} έφυγε από το δωμάτιο",
        "invite_rejected": "Η πρόσκληση για τον χρήστη {target} απορρίφθηκε ή ανακλήθηκε",
        "kick": "Ο χρήστης {actor} αφαίρεσε τον χρήστη {target} από το δωμάτιο",
        "ban": "Ο χρήστης {actor} απέκλεισε τον χρήστη {target}",
        "knock": "Ο χρήστης {target} ζήτησε πρόσβαση στο δωμάτιο"
    },
    "zh": {
        "invite": "{actor} 邀请了 {target}",
        "join": "{target} 加入了房间",
        "leave": "{target} 离开了房间",
        "invite_rejected": "对 {target} 的邀请已被拒绝或撤回",
        "kick": "{actor} 将 {target} 移出了房间",
        "ban": "{actor} 封禁了 {target}",
        "knock": "{target} 请求加入房间"
    },
    "ja": {
        "invite": "{actor} が {target} を招待しました",
        "join": "{target} がルームに参加しました",
        "leave": "{target} がルームから退出しました",
        "invite_rejected": "{target} への招待が拒否または取り消されました",
        "kick": "{actor} が {target} をルームから削除しました",
        "ban": "{actor} が {target} を禁止しました",
        "knock": "{target} がルームへの参加をリクエストしました"
    },
    "ko": {
        "invite": "{actor} 님이 {target} 님을 초대했습니다",
        "join": "{target} 님이 방에 참여했습니다",
        "leave": "{target} 님이 방을 나갔습니다",
        "invite_rejected": "{target} 님의 초대가 거절되었거나 취소되었습니다",
        "kick": "{actor} 님이 {target} 님을 방에서 내보냈습니다",
        "ban": "{actor} 님이 {target} 님을 차단했습니다",
        "knock": "{target} 님이 방 참여를 요청했습니다"
    },
    "ar": {
        "invite": "دعا {actor} ‏{target}",
        "join": "انضم {target} إلى الغرفة",
        "leave": "غادر {target} الغرفة",
        "invite_rejected": "رُفضت دعوة {target} أو أُلغيت",
        "kick": "أزال {actor} ‏{target} من الغرفة",
        "ban": "حظر {actor} ‏{target}",
        "knock": "طلب {target} الانضمام إلى الغرفة"
    },
    "hi": {
        "invite": "{actor} ने {target} को आमंत्रित किया",
        "join": "{target} रूम में शामिल हुए",
        "leave": "{target} ने रूम छोड़ दिया",
        "invite_rejected": "{target} का आमंत्रण अस्वीकार या वापस ले लिया गया",
        "kick": "{actor} ने {target} को रूम से निकाल दिया",
        "ban": "{actor} ने {target} को प्रतिबंधित किया",
        "knock": "{target} ने रूम में शामिल होने का अनुरोध किया"
    }
}

function format(languageCode, kind, actor, target, fallback) {
    var languageTemplates = templates[languageCode] || templates.en
    var template = languageTemplates[kind] || templates.en[kind]
    if (template === undefined)
        return fallback

    return template.split("{actor}").join(actor || "")
                   .split("{target}").join(target || "")
}
