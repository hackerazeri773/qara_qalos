# VoiceOver tarzinda SSML test durumlari uretir -> Swift dizisi
import json, sys
from xml.sax.saxutils import escape
def ch(c, cap=None):
    inner = '<say-as interpret-as="characters">%s</say-as>' % escape(c)
    return '<speak>%s%s</speak>' % ((cap + ' ') if cap else '', inner)
def sp(t): return '<speak>%s</speak>' % escape(t)
def tel(t): return '<say-as interpret-as="telephone">%s</say-as>' % escape(t)
cases = {"az": [], "tr": []}
letters = {"az": "a b c ç d e ə f g ğ h x ı i j k q l m n o ö p r s ş t u ü v y z w", "tr": "a b c ç d e f g ğ h ı i j k l m n o ö p r s ş t u ü v y z q w x"}
cap = {"az": "Böyük", "tr": "Büyük"}
for lang in cases:
    C = cases[lang]
    for l in letters[lang].split(): C.append(("harf " + l, ch(l)))
    for l in ["ə", "ç", "ğ", "ı", "ö", "ş", "ü", "i"] if lang == "az" else ["ç", "ğ", "ı", "ö", "ş", "ü", "i"]:
        C.append(("büyük harf " + l.upper() if l != "i" else "büyük harf İ", ch(l.upper() if l != "i" else "İ", cap[lang])))
    C.append(("büyük I (noktasız)", ch("I", cap[lang])))
    for p in list(",.?!:;-()\"'@#%&*+=/\\<>_|~^[]{}") + ["$", "€", "₼", "₺", "£", "°", "§", "©", "®", "…", "—", "«", "»", "№", "•"]:
        C.append(("karakter " + p, ch(p)))
    for d in "0123456789": C.append(("rakam " + d, ch(d)))
    for e in ["😀", "😂", "❤️", "👍", "👋🏽", "🙏", "🔥", "🎉", "🇦🇿", "🇹🇷"]:
        C.append(("emoji tek " + e, sp(e)))
    if lang == "az":
        words = ["Salam 👋 necəsən? 😊", "Əlinizə sağlıq! ❤️", "Şəhərə gəldik, çox gözəl idi.", "Ölkəmiz, üzüm, ğ hərfi, ıslaq", "İstanbul və Bakı",
                 "WhatsApp, YouTube, Google, iPhone", "e-poçt: test@mail.az", "https://www.google.com", "Привет, как дела?", "Hello, how are you?",
                 "BMT, AZN, USB, VoiceOver", "1-ci, 2-ci, 3-cü sinif", "25 AZN, 25 ₼, $100, €50", "Faiz: 50%, temperatur −5 °C",
                 "Tarix: 05.11.2026, saat 14:30", "Telefon: +994 50 123 45 67"]
    else:
        words = ["Merhaba 👋 nasılsın? 😊", "Ellerinize sağlık! ❤️", "Şehre geldik, çok güzeldi.", "Ülkemiz, üzüm, ğ harfi, ıslak", "İstanbul ve Iğdır",
                 "WhatsApp, YouTube, Google, iPhone", "e-posta: test@mail.com.tr", "https://www.google.com", "Привет, как дела?", "Hello, how are you?",
                 "TBMM, TL, USB, VoiceOver", "1., 2. ve 3. sınıf", "25 TL, 25 ₺, $100, €50", "Yüzde: %50, sıcaklık −5 °C",
                 "Tarih: 05.11.2026, saat 14:30", "Telefon: +90 532 123 45 67"]
    for w in words: C.append(("metin " + w, sp(w)))
    C.append(("telephone 2026", "<speak>Yıl " + tel("2026") + "</speak>"))
    C.append(("ondalık bölünmüş 0,365", "<speak>Değer 0," + tel("365") + ".</speak>"))
    C.append(("telefon numarası", "<speak>" + tel("050 123 45 67") + "</speak>"))
    C.append(("say-as date", '<speak><say-as interpret-as="date">05.11.2026</say-as></speak>'))
    C.append(("break", '<speak>Bir<break time="300ms"/>iki</speak>'))
out = ["// Bu dosya scripts/gen_cases.py ile uretildi. VoiceOver tarzinda SSML test durumlari.", "enum TextCoverageCases {", "    static let cases: [String: [(String, String)]] = ["]
for lang, C in cases.items():
    out.append('        "%s": [' % lang)
    for name, ssml in C:
        out.append("            (%s, %s)," % (json.dumps(name, ensure_ascii=False), json.dumps(ssml, ensure_ascii=False)))
    out.append("        ],")
out += ["    ]", "}"]
open(sys.argv[1], "w").write("\n".join(out) + "\n")
print({k: len(v) for k, v in cases.items()})
