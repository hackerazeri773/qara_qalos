import Foundation

/// iOS'ta Azerbaycanca arayuz olmadigi icin VoiceOver, Azerbaycanca bir ses secildiginde kendi
/// sozlerini ("button", "heading", "double tap to activate"...) Ingilizce gonderir. Bu tablo
/// yalnizca Azerbaycanca seslerde, ve yalnizca BUTUN bir parca olarak gelen ifadeleri
/// (virgul/nokta ile ayrilmis) cevirir; metnin icindeki ayni kelimelere dokunmaz.
/// Bu dosya ElnurTTS ve ESVoice projelerinde AYNIDIR.
public enum VoiceOverTerms {

    static let az: [String: String] = [
        // Ogeler / roller
        "button": "düymə",
        "back button": "geri düyməsi",
        "pop up button": "açılan düymə",
        "popup button": "açılan düymə",
        "switch button": "keçirici",
        "toggle": "keçirici",
        "heading": "başlıq",
        "header": "başlıq",
        "link": "keçid",
        "visited link": "baxılmış keçid",
        "image": "şəkil",
        "text field": "mətn sahəsi",
        "secure text field": "gizli mətn sahəsi",
        "search field": "axtarış sahəsi",
        "text view": "mətn sahəsi",
        "adjustable": "tənzimlənən",
        "tab": "vərəq",
        "tab bar": "vərəq paneli",
        "menu": "menyu",
        "menu item": "menyu elementi",
        "alert": "xəbərdarlıq",
        "table": "cədvəl",
        "list": "siyahı",
        "landmark": "orientir",
        "web content": "veb məzmun",
        "slider": "sürüşdürücü",
        "picker item": "seçim elementi",
        "progress": "irəliləyiş",
        "app": "tətbiq",
        "folder": "qovluq",
        "window": "pəncərə",
        "summary element": "xülasə",
        "keyboard key": "klaviatura düyməsi",
        "status bar": "status sətri",
        "toolbar": "alətlər paneli",
        "container": "konteyner",
        "article": "məqalə",
        "frame": "çərçivə",
        "math": "riyazi ifadə",

        // Vəziyyətlər
        "selected": "seçilib",
        "not selected": "seçilməyib",
        "dimmed": "deaktiv",
        "is editing": "redaktə olunur",
        "collapsed": "yığılıb",
        "expanded": "açılıb",
        "required": "məcburi",
        "actions available": "əməliyyatlar var",
        "new": "yeni",
        "busy": "məşğul",
        "screen locked": "ekran kilidləndi",
        "unlocked": "kilid açıldı",
        "empty": "boş",
        "no title": "başlıqsız",

        // İpucları
        "double tap to activate": "aktivləşdirmək üçün iki dəfə toxunun",
        "double tap to open": "açmaq üçün iki dəfə toxunun",
        "double tap to edit": "redaktə etmək üçün iki dəfə toxunun",
        "double tap to select": "seçmək üçün iki dəfə toxunun",
        "double tap to toggle setting": "ayarı dəyişmək üçün iki dəfə toxunun",
        "double tap to expand": "açmaq üçün iki dəfə toxunun",
        "double tap to collapse": "yığmaq üçün iki dəfə toxunun",
        "double tap to play": "oxutmaq üçün iki dəfə toxunun",
        "double tap to dismiss": "bağlamaq üçün iki dəfə toxunun",
        "double tap and hold to edit": "redaktə etmək üçün iki dəfə toxunub saxlayın",
        "swipe up or down with one finger to adjust the value": "dəyəri dəyişmək üçün bir barmaqla yuxarı və ya aşağı sürüşdürün",
        "swipe up or down to select a custom action, then double tap to activate": "əməliyyat seçmək üçün yuxarı və ya aşağı sürüşdürün, sonra aktivləşdirmək üçün iki dəfə toxunun",
        "swipe up or down to select a custom action": "əməliyyat seçmək üçün yuxarı və ya aşağı sürüşdürün",
        "then double tap to activate": "sonra aktivləşdirmək üçün iki dəfə toxunun",

        // Rotor
        "characters": "hərflər",
        "words": "sözlər",
        "lines": "sətirlər",
        "headings": "başlıqlar",
        "links": "keçidlər",
        "containers": "konteynerlər",
        "landmarks": "orientirlər",
        "form controls": "forma elementləri",
        "speaking rate": "nitq sürəti",
        "speech rate": "nitq sürəti",
        "volume": "səs səviyyəsi",
        "languages": "dillər",
        "actions": "əməliyyatlar",
        "vertical navigation": "şaquli naviqasiya",
        "punctuation": "durğu işarələri",
        "hints": "ipucları",
        "images": "şəkillər",
        "tables": "cədvəllər",
        "lists": "siyahılar",
        "buttons": "düymələr",
        "text fields": "mətn sahələri",
        "typing mode": "yazma rejimi",
        "edit": "redaktə",
        "default": "standart",
    ]

    /// Yalnizca bir anahtar/kecirici degeri olarak gelen "on/off" (baska kelimeyle karismasin diye
    /// ayni istekte "switch button" ya da "toggle" varsa cevrilir).
    static let azSwitchValues: [String: String] = ["on": "açıq", "off": "bağlı"]

    private static let ofPattern = try! NSRegularExpression(pattern: #"^(page )?(\d+) of (\d+)$"#, options: [.caseInsensitive])
    private static let separators = CharacterSet(charactersIn: ",;.!?:\n")

    /// Azerbaycanca olmayan dillerde metni oldugu gibi dondurur.
    public static func localize(_ text: String, language: String) -> String {
        guard language.hasPrefix("az") else { return text }
        let lower = text.lowercased()
        let hasSwitch = lower.contains("switch button") || lower.contains("toggle")

        var result = ""
        var piece = ""
        func flush() {
            guard !piece.isEmpty else { return }
            let lead = String(piece.prefix(while: { $0.isWhitespace }))
            let trail = String(piece.reversed().prefix(while: { $0.isWhitespace }).reversed())
            let core = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = core.lowercased()
            var replaced: String?
            if let t = az[key] {
                replaced = t
            } else if hasSwitch, let t = azSwitchValues[key] {
                replaced = t
            } else if let m = ofPattern.firstMatch(in: core, range: NSRange(location: 0, length: (core as NSString).length)) {
                let ns = core as NSString
                let page = m.range(at: 1).location != NSNotFound
                let n = ns.substring(with: m.range(at: 2)), total = ns.substring(with: m.range(at: 3))
                replaced = (page ? "səhifə \(n)" : n) + ", cəmi \(total)"
            }
            result += replaced.map { lead + $0 + trail } ?? piece
            piece = ""
        }
        for ch in text {
            if ch.unicodeScalars.allSatisfy({ separators.contains($0) }) {
                flush()
                result.append(ch)
            } else {
                piece.append(ch)
            }
        }
        flush()
        return result
    }
}
