import Foundation

/// Azerbaycanca sesler sisteme "tr-AZ" olarak tanitildigi icin VoiceOver noktalama ve sembol
/// adlarini TURKCE gonderir ("virgül", "soru işareti", "sol parantez"...). Bu adlar Azerbaycanca
/// karsiliklariyla okunur. Ogeler (düğme, başlık), ipuclari ve emoji adlari bilerek Turkce kalir.
/// Kurallar (gercek VoiceOver kayitlarina gore):
///  - Yalnizca Azerbaycanca seslerde uygulanir.
///  - Yalnizca BUTUN kelime eslesir ("noktalı" icindeki "nokta"ya dokunulmaz); uzun adlar once.
///  - `inline`: yalnizca noktalama adi olabilen ifadeler; cumle icinde de degisir
///    (Noktalama: Tumu ayarinda VoiceOver bunlari cumlenin icine yazar).
///  - `standalone`: Turkcede gunluk kelime de olabilenler (yıldız, derece, eksi...); yalnizca
///    VoiceOver onu TEK BASINA gonderdiginde (klavye tusu, harf harf okuma) degisir.
/// Bu dosya ElnurTTS ve ESVoice projelerinde AYNIDIR.
public enum VoiceOverPunctuation {

    static let inline: [String: String] = [
        "virgül": "vergül",
        "nokta": "nöqtə",
        "iki nokta": "iki nöqtə",
        "noktalı virgül": "nöqtəli vergül",
        "üç nokta": "üç nöqtə",
        "soru işareti": "sual işarəsi",
        "ünlem işareti": "nida işarəsi",
        "kesme işareti": "apostrof",
        "tırnak işareti": "dırnaq",
        "kısa çizgi": "defis",
        "uzun çizgi": "tire",
        "orta çizgi": "tire",
        "eğik çizgi": "kəsr xətti",
        "ters eğik çizgi": "tərs kəsr xətti",
        "alt çizgi": "alt xətt",
        "dikey çizgi": "şaquli xətt",
        "sol parantez": "mötərizə açılır",
        "sağ parantez": "mötərizə bağlanır",
        "sol köşeli parantez": "kvadrat mötərizə açılır",
        "sağ köşeli parantez": "kvadrat mötərizə bağlanır",
        "sol küme parantezi": "fiqurlu mötərizə açılır",
        "sağ küme parantezi": "fiqurlu mötərizə bağlanır",
        "sağ ok": "sağ ox",
        "sol ok": "sol ox",
        "yukarı ok": "yuxarı ox",
        "aşağı ok": "aşağı ox",
        "et işareti": "et",
        "ampersand": "və işarəsi",
        "diyez": "şəbəkə",
        "türk lirası işareti": "türk lirəsi",
        "dolar işareti": "dollar",
        "euro işareti": "avro",
        "avro işareti": "avro",
        "sterlin işareti": "funt sterlinq",
        "paragraf işareti": "paraqraf",
        "derece işareti": "dərəcə",
        "yüzde işareti": "faiz",
        "madde işareti": "nöqtə işarəsi",
        "küçüktür işareti": "kiçikdir",
        "büyüktür işareti": "böyükdür",
        "eşittir işareti": "bərabərdir",
        "artı işareti": "üstəgəl",
        "yıldız işareti": "ulduz",
    ]

    static let standalone: [String: String] = [
        "artı": "üstəgəl",
        "eksi": "çıx",
        "eşittir": "bərabərdir",
        "yıldız": "ulduz",
        "yüzde": "faiz",
        "derece": "dərəcə",
        "tilde": "tilda",
        "şapka": "şapka",
        "küçüktür": "kiçikdir",
        "büyüktür": "böyükdür",
        "boşluk": "boşluq",
        "yeni satır": "yeni sətir",
        "sekme": "tab",
    ]

    private static let inlinePattern: NSRegularExpression = {
        let keys = inline.keys.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
        return try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])(?:" + keys.joined(separator: "|") + ")(?![\\p{L}\\p{N}])",
                                        options: [.caseInsensitive])
    }()

    /// Turkce kucuk harfe cevirme (I -> ı, İ -> i).
    private static func lowerTR(_ s: String) -> String {
        s.lowercased(with: Locale(identifier: "tr"))
    }

    public static func localize(_ text: String, language: String) -> String {
        guard language.hasPrefix("az") else { return text }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = lowerTR(trimmed)
        if let whole = standalone[key] ?? inline[key] {
            return whole
        }
        let ns = text as NSString
        let matches = inlinePattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return text }
        var out = ""
        var last = 0
        for m in matches {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let found = lowerTR(ns.substring(with: m.range))
            out += inline[found] ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}
