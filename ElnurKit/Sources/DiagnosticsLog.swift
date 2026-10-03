import Foundation

/// VoiceOver'in gonderdigi son SSML isteklerini kaydeder.
/// Gercek iPhone testinde hiz/perde/ses esleme egrisini ayarlamak icin kullanilir.
/// Not: Eklenti ile uygulama arasinda paylasim icin App Group gerekir (ucretli Apple
/// gelistirici hesabi). O olmadan kayit yalnizca eklentinin kendi alaninda kalir.
public enum DiagnosticsLog {
    public static let appGroup = "group.az.elnurtts.shared"

    private static var fileURL: URL? {
        let fm = FileManager.default
        let base = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        return base?.appendingPathComponent("ssml_log.txt")
    }

    public static func record(ssml: String, rate: Double, pitch: Double, volume: Double) {
        guard let url = fileURL else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) x\(String(format: "%.2f", rate)) p\(String(format: "%.2f", pitch)) v\(String(format: "%.2f", volume)) | \(ssml.replacingOccurrences(of: "\n", with: " "))\n"
        var existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        existing += line
        // Son ~200 satiri tut
        let lines = existing.split(separator: "\n", omittingEmptySubsequences: true)
        let trimmed = lines.suffix(200).joined(separator: "\n") + "\n"
        try? trimmed.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func read() -> String {
        guard let url = fileURL else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
