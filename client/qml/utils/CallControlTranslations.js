.pragma library

// Element Call 0.26 ships complete locale files for the languages below.
// PrismChat offers additional interface languages, so keep the primary call
// controls localized for those languages as well. The keys are Element Call's
// English labels and are deliberately limited to interactive call controls.
var officialLanguages = [
    "bg", "cs", "da", "de", "el", "en", "es", "et", "fa", "fi", "fr",
    "id", "it", "ja", "lv", "nl", "pl", "ro", "ru", "sk", "sv", "tr",
    "uk", "vi", "zh"
]

var keys = [
    "Mute microphone", "Unmute microphone", "Start video", "Stop video",
    "Share screen", "Sharing screen", "End call", "Raise hand",
    "Pick reaction", "Show more", "Settings", "Participants", "Switch camera"
]

var values = {
    "af": ["Demp mikrofoon", "Ontdemp mikrofoon", "Begin video", "Stop video", "Deel skerm", "Skerm word gedeel", "Beëindig oproep", "Steek hand op", "Kies reaksie", "Wys meer", "Instellings", "Deelnemers", "Wissel kamera"],
    "ar": ["كتم الميكروفون", "إلغاء كتم الميكروفون", "تشغيل الفيديو", "إيقاف الفيديو", "مشاركة الشاشة", "تتم مشاركة الشاشة", "إنهاء المكالمة", "رفع اليد", "اختيار تفاعل", "إظهار المزيد", "الإعدادات", "المشاركون", "تبديل الكاميرا"],
    "eu": ["Mikrofonoa isilarazi", "Mikrofonoaren soinua aktibatu", "Bideoa hasi", "Bideoa gelditu", "Pantaila partekatu", "Pantaila partekatzen", "Deia amaitu", "Eskua altxatu", "Erreakzioa aukeratu", "Erakutsi gehiago", "Ezarpenak", "Parte-hartzaileak", "Aldatu kamera"],
    "bn": ["মাইক্রোফোন নিঃশব্দ করুন", "মাইক্রোফোনের শব্দ চালু করুন", "ভিডিও চালু করুন", "ভিডিও বন্ধ করুন", "স্ক্রিন শেয়ার করুন", "স্ক্রিন শেয়ার হচ্ছে", "কল শেষ করুন", "হাত তুলুন", "প্রতিক্রিয়া বেছে নিন", "আরও দেখুন", "সেটিংস", "অংশগ্রহণকারীরা", "ক্যামেরা বদলান"],
    "bs": ["Isključi mikrofon", "Uključi mikrofon", "Pokreni video", "Zaustavi video", "Dijeli ekran", "Ekran se dijeli", "Završi poziv", "Podigni ruku", "Odaberi reakciju", "Prikaži više", "Postavke", "Učesnici", "Promijeni kameru"],
    "ca": ["Silencia el micròfon", "Activa el micròfon", "Inicia el vídeo", "Atura el vídeo", "Comparteix la pantalla", "S'està compartint la pantalla", "Finalitza la trucada", "Aixeca la mà", "Tria una reacció", "Mostra'n més", "Configuració", "Participants", "Canvia de càmera"],
    "hr": ["Isključi mikrofon", "Uključi mikrofon", "Pokreni video", "Zaustavi video", "Dijeli zaslon", "Zaslon se dijeli", "Završi poziv", "Podigni ruku", "Odaberi reakciju", "Prikaži više", "Postavke", "Sudionici", "Promijeni kameru"],
    "fil": ["I-mute ang mikropono", "I-unmute ang mikropono", "Simulan ang video", "Ihinto ang video", "Ibahagi ang screen", "Ibinabahagi ang screen", "Tapusin ang tawag", "Itaas ang kamay", "Pumili ng reaction", "Magpakita pa", "Mga setting", "Mga kalahok", "Lumipat ng camera"],
    "gl": ["Silenciar o micrófono", "Activar o micrófono", "Iniciar o vídeo", "Deter o vídeo", "Compartir a pantalla", "Compartindo a pantalla", "Rematar a chamada", "Erguer a man", "Escoller unha reacción", "Amosar máis", "Axustes", "Participantes", "Cambiar de cámara"],
    "he": ["השתקת המיקרופון", "ביטול השתקת המיקרופון", "הפעלת וידאו", "עצירת וידאו", "שיתוף המסך", "המסך משותף", "סיום השיחה", "הרמת יד", "בחירת תגובה", "הצגת עוד", "הגדרות", "משתתפים", "החלפת מצלמה"],
    "hi": ["माइक्रोफ़ोन म्यूट करें", "माइक्रोफ़ोन अनम्यूट करें", "वीडियो शुरू करें", "वीडियो बंद करें", "स्क्रीन साझा करें", "स्क्रीन साझा हो रही है", "कॉल समाप्त करें", "हाथ उठाएँ", "प्रतिक्रिया चुनें", "और दिखाएँ", "सेटिंग्स", "प्रतिभागी", "कैमरा बदलें"],
    "hu": ["Mikrofon némítása", "Mikrofon némításának feloldása", "Videó indítása", "Videó leállítása", "Képernyő megosztása", "Képernyő megosztva", "Hívás befejezése", "Kéz felemelése", "Reakció kiválasztása", "Több megjelenítése", "Beállítások", "Résztvevők", "Kamera váltása"],
    "is": ["Slökkva á hljóðnema", "Kveikja á hljóðnema", "Hefja myndskeið", "Stöðva myndskeið", "Deila skjá", "Skjár í deilingu", "Ljúka símtali", "Rétta upp hönd", "Velja viðbragð", "Sýna meira", "Stillingar", "Þátttakendur", "Skipta um myndavél"],
    "ko": ["마이크 음소거", "마이크 음소거 해제", "비디오 시작", "비디오 중지", "화면 공유", "화면 공유 중", "통화 종료", "손들기", "반응 선택", "더 보기", "설정", "참가자", "카메라 전환"],
    "lt": ["Nutildyti mikrofoną", "Įjungti mikrofoną", "Pradėti vaizdą", "Sustabdyti vaizdą", "Bendrinti ekraną", "Ekranas bendrinamas", "Baigti skambutį", "Pakelti ranką", "Pasirinkti reakciją", "Rodyti daugiau", "Nustatymai", "Dalyviai", "Perjungti kamerą"],
    "ms": ["Redam mikrofon", "Nyahredam mikrofon", "Mulakan video", "Hentikan video", "Kongsi skrin", "Skrin sedang dikongsi", "Tamatkan panggilan", "Angkat tangan", "Pilih reaksi", "Tunjukkan lagi", "Tetapan", "Peserta", "Tukar kamera"],
    "nb": ["Demp mikrofon", "Opphev demping av mikrofon", "Start video", "Stopp video", "Del skjerm", "Skjermen deles", "Avslutt samtale", "Rekk opp hånden", "Velg reaksjon", "Vis mer", "Innstillinger", "Deltakere", "Bytt kamera"],
    "pt": ["Silenciar microfone", "Ativar som do microfone", "Iniciar vídeo", "Parar vídeo", "Partilhar ecrã", "A partilhar o ecrã", "Terminar chamada", "Levantar a mão", "Escolher reação", "Mostrar mais", "Definições", "Participantes", "Mudar câmara"],
    "sr": ["Искључи микрофон", "Укључи микрофон", "Покрени видео", "Заустави видео", "Дели екран", "Екран се дели", "Заврши позив", "Подигни руку", "Изабери реакцију", "Прикажи више", "Подешавања", "Учесници", "Промени камеру"],
    "sl": ["Izklopi mikrofon", "Vklopi mikrofon", "Začni video", "Ustavi video", "Deli zaslon", "Zaslon je v skupni rabi", "Končaj klic", "Dvigni roko", "Izberi odziv", "Prikaži več", "Nastavitve", "Udeleženci", "Preklopi kamero"],
    "sw": ["Nyamazisha maikrofoni", "Washa maikrofoni", "Anzisha video", "Simamisha video", "Shiriki skrini", "Skrini inashirikiwa", "Maliza simu", "Inua mkono", "Chagua mwitikio", "Onyesha zaidi", "Mipangilio", "Washiriki", "Badili kamera"],
    "ta": ["ஒலிவாங்கியை முடக்கு", "ஒலிவாங்கியை இயக்கு", "காணொளியைத் தொடங்கு", "காணொளியை நிறுத்து", "திரையைப் பகிர்", "திரை பகிரப்படுகிறது", "அழைப்பை முடி", "கையை உயர்த்து", "எதிர்வினையைத் தேர்ந்தெடு", "மேலும் காட்டு", "அமைப்புகள்", "பங்கேற்பாளர்கள்", "கேமராவை மாற்று"],
    "te": ["మైక్రోఫోన్‌ను మ్యూట్ చేయండి", "మైక్రోఫోన్ మ్యూట్ తీసివేయండి", "వీడియోను ప్రారంభించండి", "వీడియోను ఆపండి", "స్క్రీన్‌ను షేర్ చేయండి", "స్క్రీన్ షేర్ అవుతోంది", "కాల్ ముగించండి", "చేయి ఎత్తండి", "ప్రతిస్పందనను ఎంచుకోండి", "మరిన్ని చూపించండి", "సెట్టింగ్‌లు", "పాల్గొనేవారు", "కెమెరాను మార్చండి"],
    "th": ["ปิดเสียงไมโครโฟน", "เปิดเสียงไมโครโฟน", "เริ่มวิดีโอ", "หยุดวิดีโอ", "แชร์หน้าจอ", "กำลังแชร์หน้าจอ", "วางสาย", "ยกมือ", "เลือกรีแอ็กชัน", "แสดงเพิ่มเติม", "การตั้งค่า", "ผู้เข้าร่วม", "สลับกล้อง"],
    "ur": ["مائیکروفون خاموش کریں", "مائیکروفون کی آواز بحال کریں", "ویڈیو شروع کریں", "ویڈیو بند کریں", "اسکرین شیئر کریں", "اسکرین شیئر ہو رہی ہے", "کال ختم کریں", "ہاتھ اٹھائیں", "ردِعمل منتخب کریں", "مزید دکھائیں", "ترتیبات", "شرکاء", "کیمرا تبدیل کریں"]
}

function normalize(code) {
    var value = String(code || "").toLowerCase().replace(/_/g, "-")
    return value.split("-")[0]
}

function labelsFor(code) {
    var language = normalize(code)
    if (officialLanguages.indexOf(language) !== -1 || values[language] === undefined)
        return ({})
    var labels = ({})
    for (var index = 0; index < keys.length; index++)
        labels[keys[index]] = values[language][index]
    return labels
}

function fallbackLanguages() {
    return Object.keys(values)
}
