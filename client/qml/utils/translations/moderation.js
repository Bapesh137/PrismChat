.pragma library

var sources = [
    "Действия администратора",
    "Назначить модератором",
    "Снять роль",
    "Исключить из комнаты",
    "Заблокировать в комнате",
    "Снять блокировку в комнате",
    "Не удалось выполнить действие модерации",
    "Действие модерации выполнено",
    "Управление участниками",
    "Роли задаются уровнем доступа; также можно исключить или заблокировать участника.",
    "Исключить",
    "Бан"
]

var translations = {
    "en": [
        "Admin actions", "Make moderator", "Remove role", "Kick from room",
        "Ban from room", "Unban from room", "Moderation action failed",
        "Moderation action completed", "Member management",
        "Roles use access levels; you can also kick or ban a member.", "Kick", "Ban"
    ],
    "de": [
        "Admin-Aktionen", "Zum Moderator machen", "Rolle entfernen", "Aus Raum entfernen",
        "Im Raum sperren", "Raumsperre aufheben", "Moderationsaktion fehlgeschlagen",
        "Moderationsaktion abgeschlossen", "Mitgliederverwaltung",
        "Rollen verwenden Zugriffsstufen; Mitglieder können auch entfernt oder gesperrt werden.", "Entfernen", "Sperren"
    ],
    "fr": [
        "Actions d’administration", "Nommer modérateur", "Retirer le rôle", "Exclure du salon",
        "Bannir du salon", "Annuler le bannissement", "Échec de l’action de modération",
        "Action de modération effectuée", "Gestion des membres",
        "Les rôles utilisent des niveaux d’accès ; vous pouvez aussi exclure ou bannir un membre.", "Exclure", "Bannir"
    ],
    "it": [
        "Azioni amministratore", "Nomina moderatore", "Rimuovi ruolo", "Espelli dalla stanza",
        "Blocca nella stanza", "Rimuovi blocco dalla stanza", "Azione di moderazione non riuscita",
        "Azione di moderazione completata", "Gestione membri",
        "I ruoli usano livelli di accesso; puoi anche espellere o bloccare un membro.", "Espelli", "Blocca"
    ],
    "pl": [
        "Działania administratora", "Nadaj rolę moderatora", "Usuń rolę", "Wyrzuć z pokoju",
        "Zablokuj w pokoju", "Cofnij blokadę w pokoju", "Działanie moderacyjne nie powiodło się",
        "Działanie moderacyjne wykonane", "Zarządzanie członkami",
        "Role korzystają z poziomów dostępu; członka można też wyrzucić lub zablokować.", "Wyrzuć", "Blokada"
    ],
    "uk": [
        "Дії адміністратора", "Призначити модератором", "Зняти роль", "Виключити з кімнати",
        "Заблокувати в кімнаті", "Зняти блокування в кімнаті", "Не вдалося виконати дію модерації",
        "Дію модерації виконано", "Керування учасниками",
        "Ролі задаються рівнем доступу; учасника також можна виключити або заблокувати.", "Виключити", "Бан"
    ],
    "es": [
        "Acciones de administración", "Hacer moderador", "Quitar función", "Expulsar de la sala",
        "Bloquear en la sala", "Desbloquear en la sala", "La acción de moderación falló",
        "Acción de moderación completada", "Gestión de miembros",
        "Los roles usan niveles de acceso; también puedes expulsar o bloquear a un miembro.", "Expulsar", "Bloquear"
    ],
    "pt": [
        "Ações de administração", "Tornar moderador", "Remover função", "Expulsar da sala",
        "Banir da sala", "Remover banimento", "Falha na ação de moderação",
        "Ação de moderação concluída", "Gerenciamento de membros",
        "As funções usam níveis de acesso; também é possível expulsar ou banir um membro.", "Expulsar", "Banir"
    ],
    "el": [
        "Ενέργειες διαχειριστή", "Ορισμός συντονιστή", "Αφαίρεση ρόλου", "Αποβολή από το δωμάτιο",
        "Αποκλεισμός από το δωμάτιο", "Άρση αποκλεισμού", "Η ενέργεια συντονισμού απέτυχε",
        "Η ενέργεια συντονισμού ολοκληρώθηκε", "Διαχείριση μελών",
        "Οι ρόλοι χρησιμοποιούν επίπεδα πρόσβασης· μπορείτε επίσης να αποβάλετε ή να αποκλείσετε μέλος.", "Αποβολή", "Αποκλεισμός"
    ],
    "zh": [
        "管理员操作", "设为版主", "移除角色", "移出房间",
        "在房间中封禁", "解除房间封禁", "管理操作失败",
        "管理操作已完成", "成员管理",
        "角色由权限级别决定；也可以移出或封禁成员。", "移出", "封禁"
    ],
    "ja": [
        "管理者の操作", "モデレーターにする", "役割を外す", "ルームから退出させる",
        "ルームで禁止", "禁止を解除", "モデレーション操作に失敗しました",
        "モデレーション操作が完了しました", "メンバー管理",
        "役割はアクセスレベルで設定します。メンバーの退出や禁止もできます。", "退出", "禁止"
    ],
    "ko": [
        "관리자 작업", "운영자로 지정", "역할 제거", "방에서 내보내기",
        "방에서 차단", "방 차단 해제", "관리 작업 실패",
        "관리 작업 완료", "멤버 관리",
        "역할은 접근 수준으로 설정하며 멤버를 내보내거나 차단할 수도 있습니다.", "내보내기", "차단"
    ],
    "ar": [
        "إجراءات المشرف", "تعيين مشرف", "إزالة الدور", "طرد من الغرفة",
        "حظر في الغرفة", "إلغاء الحظر من الغرفة", "فشل إجراء الإشراف",
        "اكتمل إجراء الإشراف", "إدارة الأعضاء",
        "تُحدد الأدوار بمستويات الوصول، ويمكن أيضًا طرد العضو أو حظره.", "طرد", "حظر"
    ],
    "hi": [
        "एडमिन कार्रवाइयाँ", "मॉडरेटर बनाएँ", "भूमिका हटाएँ", "कमरे से निकालें",
        "कमरे में प्रतिबंधित करें", "कमरे से प्रतिबंध हटाएँ", "मॉडरेशन कार्रवाई विफल",
        "मॉडरेशन कार्रवाई पूरी हुई", "सदस्य प्रबंधन",
        "भूमिकाएँ एक्सेस स्तर से तय होती हैं; सदस्य को निकाला या प्रतिबंधित भी किया जा सकता है।", "निकालें", "प्रतिबंध"
    ]
}

function get(languageCode, sourceText) {
    var languageStrings = translations[languageCode]
    if (languageStrings === undefined)
        return undefined
    var index = sources.indexOf(sourceText)
    return index < 0 ? undefined : languageStrings[index]
}
