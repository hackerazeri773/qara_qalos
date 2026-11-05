import Foundation

/// ElnurTTS Android surumundeki dil ayarlari (SettingsFragment): her dil icin
/// varsayilan ses, otomatik dil gecisi, ses yuksekligi (dB) ve konusma hizi (%).
/// Uygulama ile VoiceOver ses eklentisi arasinda App Group ile paylasilir. Ucretsiz Apple
/// hesabiyla kurulumda App Group calismaz (`isShared` false): ayarlar o zaman yalnizca
/// uygulama icinde gecerlidir, eklenti varsayilanlari kullanir. Telefon yeniden baslatilip
/// kilit ilk kez acilana kadar da paylasilan ayarlar okunamaz (varsayilanlar kullanilir).
public enum ElnurSettings {
    public static let groupID = "group.az.elnurtts.shared"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    /// Uygulama ile eklenti gercekten ayni ayarlari goruyor mu?
    public static var isShared: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    public struct Language: Equatable {
        /// Varsayilan ses (motor adi, ornegin "Dimitry"); nil = dilin ilk sesi.
        public var voice: String?
        /// Otomatik dil gecisi (Android: language.X.detect, varsayilan acik).
        public var detect: Bool
        /// Ses yuksekligi, dB (Android: -12...+12).
        public var volumeDB: Double
        /// Konusma hizi, yuzde (Android: 50...300).
        public var ratePercent: Double

        public static let `default` = Language(voice: nil, detect: true, volumeDB: 0, ratePercent: 100)

        public var volumeMultiplier: Double { pow(10, volumeDB / 20) }
        public var rateMultiplier: Double { ratePercent / 100 }
    }

    public static let volumeRange: ClosedRange<Double> = -12...12
    public static let rateRange: ClosedRange<Double> = 50...300

    /// `code`: dilin iki harfli kodu ("az", "tr", "ru", "en").
    public static func language(_ code: String) -> Language {
        guard let d = defaults else { return .default }
        let p = "language.\(code)."
        var l = Language.default
        l.voice = d.string(forKey: p + "voice")
        if d.object(forKey: p + "detect") != nil { l.detect = d.bool(forKey: p + "detect") }
        if d.object(forKey: p + "volume") != nil {
            l.volumeDB = min(volumeRange.upperBound, max(volumeRange.lowerBound, d.double(forKey: p + "volume")))
        }
        if d.object(forKey: p + "rate") != nil {
            l.ratePercent = min(rateRange.upperBound, max(rateRange.lowerBound, d.double(forKey: p + "rate")))
        }
        return l
    }

    public static func setLanguage(_ code: String, _ l: Language) {
        guard let d = defaults else { return }
        let p = "language.\(code)."
        if let v = l.voice { d.set(v, forKey: p + "voice") } else { d.removeObject(forKey: p + "voice") }
        d.set(l.detect, forKey: p + "detect")
        d.set(l.volumeDB, forKey: p + "volume")
        d.set(l.ratePercent, forKey: p + "rate")
    }
}
