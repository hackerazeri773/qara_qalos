import Foundation

/// Eklentinin aldigi son isteklerin degerleri ve HAM metni (tani icin, YALNIZCA BELLEKTE;
/// dosya yazilmaz, kilit ekrani sorununu geri getirmez). Bir yere "<uygulama> tanı" yazip
/// VoiceOver'a okutunca son istekler sesli okunur. Bu dosya iki projede AYNIDIR.
final class RequestHistory {
    static let shared = RequestHistory()

    struct Entry {
        let text: String
        let characters: Bool
        let rawRate: String?
        let rawVolume: String?
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    func add(text: String, characters: Bool, rawRate: String?, rawVolume: String?) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(Entry(text: String(text.prefix(200)), characters: characters,
                             rawRate: rawRate, rawVolume: rawVolume))
        if entries.count > 30 { entries.removeFirst(entries.count - 30) }
    }

    /// Ozel karakterlerin Unicode kodu, rakam rakam: "ə" -> "0 2 5 9".
    private static func codes(_ text: String) -> String {
        var out: [String] = []
        for u in text.unicodeScalars {
            let ascii = u.value < 128 && (CharacterSet.alphanumerics.contains(u) || u == " ")
            if ascii { continue }
            let hex = String(format: "%04X", u.value).map(String.init).joined(separator: " ")
            out.append(hex)
            if out.count >= 8 { break }
        }
        return out.joined(separator: "; ")
    }

    func spokenSummary(appName: String) -> String {
        lock.lock()
        let recent = Array(entries.suffix(6).reversed())
        lock.unlock()
        guard !recent.isEmpty else { return "\(appName) tanı. Hələ istək yoxdur." }
        var parts = ["\(appName) tanı. Son istəklər, yenidən köhnəyə."]
        for (i, e) in recent.enumerated() {
            var line = "İstək \(i + 1)."
            if e.characters { line += " Hərf-hərf." }
            let shown = e.text.trimmingCharacters(in: .whitespacesAndNewlines)
            line += shown.isEmpty ? " Boş mətn." : " Mətn: \(shown)."
            let c = Self.codes(shown)
            if !c.isEmpty { line += " Kodlar: \(c)." }
            if let r = e.rawRate { line += " Sürət \(r.replacingOccurrences(of: "%", with: " faiz"))." }
            parts.append(line)
        }
        return parts.joined(separator: " ")
    }
}
