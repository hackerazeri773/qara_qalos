import Foundation

/// Motora gidecek bir parca.
public struct SpeechChunk: Equatable {
    public var text: String
    /// true: motorun karakter (harf harf) modu kullanilir.
    public var useCharacterMode: Bool
    public init(text: String, useCharacterMode: Bool) {
        self.text = text
        self.useCharacterMode = useCharacterMode
    }
}

/// VoiceOver isteğini motora gidecek parçalara ayırır.
/// - Harf harf okunacak bölümler (say-as characters) ve tek karakterlik istekler
///   karakter karakter işlenir.
/// - Motorun okuyamadığı semboller için dil başına sembol adları kullanılır.
public enum SpeechPlanner {

    /// Sembol adları. Harfler ve rakamlar burada yok; onları motor kendisi okur.
    public static let symbolNames: [String: [Character: String]] = [
        "az": [
            ",": "vergül", ".": "nöqtə", "?": "sual işarəsi", "!": "nida işarəsi",
            ":": "iki nöqtə", ";": "nöqtəli vergül", "-": "defis", "'": "apostrof",
            "\"": "dırnaq", "(": "mötərizə açılır", ")": "mötərizə bağlanır",
            "[": "kvadrat mötərizə açılır", "]": "kvadrat mötərizə bağlanır",
            "{": "fiqurlu mötərizə açılır", "}": "fiqurlu mötərizə bağlanır",
            "<": "kiçikdir", ">": "böyükdür", "|": "şaquli xətt", "~": "tilda",
            "^": "şapka", "_": "alt xətt", "@": "et", "&": "və işarəsi",
            "=": "bərabərdir", "+": "üstəgəl", "*": "ulduz", "/": "kəsr xətti",
            "\\": "tərs kəsr xətti", "#": "şəbəkə", "%": "faiz", "$": "dollar",
            "€": "avro", "₼": "manat", "₺": "türk lirəsi", "£": "funt sterlinq",
            "₽": "rubl", "°": "dərəcə", "§": "paraqraf", "©": "müəllif hüququ",
            "®": "qeydiyyatlı", "™": "ticarət nişanı", "…": "üç nöqtə", "—": "tire",
            "–": "tire", "«": "dırnaq açılır", "»": "dırnaq bağlanır", "“": "dırnaq açılır",
            "”": "dırnaq bağlanır", "№": "nömrə", "•": "nöqtə işarəsi", "·": "orta nöqtə",
            "×": "vurulsun", "÷": "bölünsün", "±": "üstəgəl çıx", "√": "kök",
            "∞": "sonsuzluq", "≠": "bərabər deyil", "≤": "kiçik və ya bərabər",
            "≥": "böyük və ya bərabər", "→": "sağ ox", "←": "sol ox", "↑": "yuxarı ox",
            "↓": "aşağı ox", "−": "çıx",
            "`": "tərs apostrof", "‘": "tək dırnaq açılır", "’": "tək dırnaq bağlanır", "„": "alt dırnaq",
            "¡": "tərs nida işarəsi", "¿": "tərs sual işarəsi", "‰": "promil", "′": "ştrix", "″": "qoşa ştrix",
            "¢": "sent", "¥": "yen", "¶": "abzas", "†": "xaç", "‡": "qoşa xaç", "¤": "valyuta işarəsi",
            "‹": "tək bucaq dırnaq açılır", "›": "tək bucaq dırnaq bağlanır",
        ],
        "tr": [
            ",": "virgül", ".": "nokta", "?": "soru işareti", "!": "ünlem",
            ":": "iki nokta", ";": "noktalı virgül", "-": "tire", "'": "kesme işareti",
            "\"": "tırnak", "(": "parantez aç", ")": "parantez kapat",
            "[": "köşeli parantez aç", "]": "köşeli parantez kapat",
            "{": "süslü parantez aç", "}": "süslü parantez kapat",
            "<": "küçüktür", ">": "büyüktür", "|": "dikey çizgi", "~": "tilde",
            "^": "şapka", "_": "alt çizgi", "@": "et", "&": "ve işareti",
            "=": "eşittir", "+": "artı", "*": "yıldız", "/": "bölü",
            "\\": "ters bölü", "#": "diyez", "%": "yüzde", "$": "dolar",
            "€": "avro", "₼": "manat", "₺": "Türk lirası", "£": "sterlin",
            "₽": "ruble", "°": "derece", "§": "paragraf", "©": "telif hakkı",
            "®": "tescilli", "™": "ticari marka", "…": "üç nokta", "—": "uzun tire",
            "–": "kısa tire", "«": "tırnak aç", "»": "tırnak kapat", "“": "tırnak aç",
            "”": "tırnak kapat", "№": "numara", "•": "madde işareti", "·": "orta nokta",
            "×": "çarpı", "÷": "bölü", "±": "artı eksi", "√": "karekök",
            "∞": "sonsuz", "≠": "eşit değildir", "≤": "küçük eşittir",
            "≥": "büyük eşittir", "→": "sağ ok", "←": "sol ok", "↑": "yukarı ok",
            "↓": "aşağı ok", "−": "eksi",
            "`": "ters kesme", "‘": "tek tırnak aç", "’": "tek tırnak kapat", "„": "alt tırnak",
            "¡": "ters ünlem", "¿": "ters soru işareti", "‰": "binde", "′": "üssü", "″": "çift üssü",
            "¢": "sent", "¥": "yen", "¶": "paragraf işareti", "†": "haç", "‡": "çift haç", "¤": "para birimi işareti",
            "‹": "tek açılı tırnak aç", "›": "tek açılı tırnak kapat",
        ],
    ]

    private static let schwaPattern = try! NSRegularExpression(
        pattern: #"^\s*(?:(büyük|buyuk|böyük|capital)\s+)?(?:schwa|\(null\))\s*$"#, options: [.caseInsensitive])

    /// "schwa" / "Büyük schwa" -> ə / Ə harfi (motorun karakter moduyla). VoiceOver'in Turkcesinde
    /// "ə" icin fonetik kelime olmadigindan harf tusunda bir de "Büyük (null)" gonderiliyor.
    static func schwaKey(_ text: String) -> [SpeechChunk]? {
        let ns = text as NSString
        guard let m = schwaPattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let capital = m.range(at: 1).location != NSNotFound
        var chunks: [SpeechChunk] = []
        if capital { chunks.append(SpeechChunk(text: "Böyük", useCharacterMode: false)) }
        chunks.append(SpeechChunk(text: capital ? "Ə" : "ə", useCharacterMode: true))
        return chunks
    }

    // VoiceOver (tr) buyuk "Ə" harfini taniyamiyor ve metnin icinde " schwa " olarak yaziyor:
    // "Əlavə" -> " schwa lavə", "ƏLAVƏ" -> " schwa LAV schwa ". Kucuk "ə" oldugu gibi geliyor.
    // VoiceOver "schwa"yi kendi ekledigi bosluklarla yazar: metnin basinda " schwa ", ortada
    // "  schwa " (asil bosluk + eklenen bosluk). Metindeki gercek "schwa" kelimesi (tek bosluk) korunur.
    private static let schwaBeforeWord = try! NSRegularExpression(
        pattern: #"(^ |  )schwa (?=\p{L})"#, options: [.caseInsensitive])
    private static let schwaAfterWord = try! NSRegularExpression(
        pattern: #"(?<=\p{L}) schwa(?=  | ?$)"#, options: [.caseInsensitive])

    static func restoreCapitalSchwa(_ text: String, language: String) -> String {
        guard language.hasPrefix("az"), text.range(of: "schwa", options: .caseInsensitive) != nil else { return text }
        var t = schwaBeforeWord.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                                         withTemplate: "$1Ə")
        t = schwaAfterWord.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length),
                                                    withTemplate: "Ə")
        return t
    }

    static func unicodeLetterName(_ text: String) -> String? {
        var key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard key.contains(" letter ") else { return nil }
        for prefix in ["büyük ", "böyük "] where key.hasPrefix(prefix) { key.removeFirst(prefix.count) }
        return UnicodeLetterNames.table[key]
    }

    static func isEmoji(_ c: Character) -> Bool {
        c.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value >= 0x1F000 }
    }

    public static func symbolName(_ c: Character, language: String) -> String? {
        symbolNames[String(language.prefix(2))]?[c]
    }

    /// - Parameters:
    ///   - language: sesin dili (ör. "az-AZ").
    ///   - engineCharacterMode: motorun kendi karakter modu var mı (ElnurTTS: evet).
    ///   - engineSilentSymbols: motorun karakter modunda da okuyamadığı semboller.
    public static func plan(_ request: SpeechRequestText, language: String,
                            engineCharacterMode: Bool,
                            engineSilentSymbols: Set<Character> = []) -> [SpeechChunk] {
        var segments = request.segments.isEmpty
            ? [SpeechSegment(text: request.text, isCharacters: false)]
            : request.segments
        // Azerbaycanca sesler sisteme "tr-AZ" olarak tanitildigi icin VoiceOver Turkcede olmayan
        // "ə" harfini klavyede Ingilizce Unicode adiyla ("schwa") gonderiyor. Harfin kendisi okunur.
        if language.hasPrefix("az"), let schwa = schwaKey(request.text) {
            return schwa
        }
        // VoiceOver'in tanimadigi harfler Ingilizce Unicode adiyla geliyor ("cyrillic small letter be"):
        // harfin kendisi okunur (Kiril harfini motorun Rusca sesi okur).
        if let letter = unicodeLetterName(request.text) {
            return [SpeechChunk(text: letter, useCharacterMode: true)]
        }
        // Tek karakterlik istek (ör. yazarken harf yankısı) da harf harf okunur.
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 1, !segments.contains(where: \.isCharacters) {
            segments = [SpeechSegment(text: trimmed, isCharacters: true)]
        }

        var chunks: [SpeechChunk] = []
        func add(_ text: String, characterMode: Bool) {
            if !characterMode, let last = chunks.last, !last.useCharacterMode {
                chunks[chunks.count - 1].text += " " + text
            } else {
                chunks.append(SpeechChunk(text: text, useCharacterMode: characterMode))
            }
        }

        for segment in segments {
            if !segment.isCharacters {
                // Azerbaycanca seste VoiceOver'in Turkce noktalama/sembol adlari Azerbaycanca okunur;
                // kelime icindeki buyuk "Ə" yerine yazdigi "schwa" yeniden harfe cevrilir.
                let t = VoiceOverPunctuation.localize(restoreCapitalSchwa(segment.text, language: language),
                                                      language: language)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { add(t, characterMode: false) }
                continue
            }
            for c in segment.text where !c.isWhitespace {
                let name = symbolName(c, language: language)
                // Tabloda yoksa: harf/rakam/emoji olmayan semboller icin CLDR adi (Android'deki
                // emoji_<dil>.txt; ~1500 sembol, para birimi, matematik isareti).
                if name == nil, !c.isLetter, !c.isNumber, !isEmoji(c),
                   let cldr = TextNormalizer.emojiName(c, language: language) {
                    add(cldr, characterMode: false)
                    continue
                }
                if let name, !engineCharacterMode || engineSilentSymbols.contains(c) {
                    add(name, characterMode: false)
                } else if engineCharacterMode {
                    chunks.append(SpeechChunk(text: String(c), useCharacterMode: true))
                } else {
                    // Harf/rakam: motor tek basina gelen harfi adiyla okur.
                    add(String(c), characterMode: false)
                }
            }
        }
        return chunks
    }
}
