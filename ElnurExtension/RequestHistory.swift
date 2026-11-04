import Foundation
import UIKit

/// Eklentinin aldigi son isteklerin degerleri ve HAM metni (tani icin, YALNIZCA BELLEKTE;
/// dosya yazilmaz, kilit ekrani sorununu geri getirmez). Bir yere "<uygulama> tanı" yazip
/// VoiceOver'a okutunca son istekler sesli okunur. Bu dosya iki projede AYNIDIR.
final class RequestHistory {
    static let shared = RequestHistory()

    struct Entry {
        let time: Date
        let ssml: String
        let text: String
        let characters: Bool
        let rawRate: String?
        let rawVolume: String?
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    func add(ssml: String, text: String, characters: Bool, rawRate: String?, rawVolume: String?) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(Entry(time: Date(), ssml: String(ssml.prefix(600)), text: String(text.prefix(200)), characters: characters,
                             rawRate: rawRate, rawVolume: rawVolume))
        if entries.count > 60 { entries.removeFirst(entries.count - 60) }
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

    /// Kaydin tamamini panoya kopyalar (kullanici bu sohbete yapistirir).
    /// Donus: kopyalanan istek sayisi; pano yazmaya izin vermezse nil.
    func copyToPasteboard(appName: String) -> Int? {
        lock.lock()
        let all = entries
        lock.unlock()
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        var lines = ["\(appName) tanı kaydı, \(all.count) istək (köhnədən yeniyə)"]
        for (i, e) in all.enumerated() {
            let codes = e.text.unicodeScalars.map { String(format: "%04X", $0.value) }.prefix(40).joined(separator: " ")
            lines.append("#\(i + 1) \(f.string(from: e.time))\(e.characters ? " [hərf-hərf]" : "")")
            lines.append("  mətn: \(e.text)")
            lines.append("  kod: \(codes)")
            lines.append("  ssml: \(e.ssml.replacingOccurrences(of: "\n", with: " "))")
        }
        let text = lines.joined(separator: "\n")
        var before = 0
        var after = 0
        let work = {
            let pb = UIPasteboard.general
            before = pb.changeCount
            pb.string = text
            after = pb.changeCount
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
        return after != before ? all.count : nil
    }
}
