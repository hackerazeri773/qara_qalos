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
        ],
    ]

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
                // Azerbaycanca seste VoiceOver'in Ingilizce gonderdigi kendi sozleri (button, heading...)
                let t = VoiceOverTerms.localize(segment.text, language: language)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { add(t, characterMode: false) }
                continue
            }
            for c in segment.text where !c.isWhitespace {
                let name = symbolName(c, language: language)
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
