import Foundation

/// VoiceOver'in SSML ile gonderdigi hiz/perde/ses degerlerini motor carpanlarina cevirir.
///
/// Gercek iPhone olcumleri (RHVoiceUkraine, Ekim 2026 surumu): iOS VoiceOver hizi
/// prosody rate="N%" olarak gonderir; %100 = normal hiz. Rotor varsayilan hizdayken
/// hiz hic gonderilmez. Bu yuzden yuzde dogrudan carpana cevrilir (%90 -> 0.9x).
/// (Onceki surumdeki "%10-100 = 0.25x-4x" egrisi eski bir belgeye dayaniyordu ve
/// %45 civarinda asiri hizlanmaya yol aciyordu.)
public enum VoiceOverMapping {
    public static let minRate = 0.5
    public static let maxRate = 5.0

    public static func rateMultiplier(for request: SpeechRequestText) -> Double {
        // SSML'de hiz yoksa normal hiz.
        guard request.rawRate != nil else { return 1 }
        // SpeechRequestText: "90%" -> 0.9, "+10%" -> 1.1, "fast" -> 1.5
        return min(maxRate, max(minRate, request.rate))
    }

    /// VoiceOver'in perde degeri motora uygulanmaz: HTS/MAGE vokoderinde perde
    /// degisikligi surtunmeli seslerde ("s", "ş") bozulmaya yol aciyor.
    /// (RHVoiceUkraine projesi de ayni karari vermis.)
    public static func pitchMultiplier(for request: SpeechRequestText) -> Double {
        1.0
    }

    /// Ses seviyesi hicbir zaman 1'in ustune cikarilmaz; yukseltmeyi VoiceOver yapar.
    /// Motorun kendi seviyesini asmak kirpilmaya (cizirtiya) yol acar.
    public static func volumeMultiplier(for request: SpeechRequestText) -> Double {
        min(1, max(0.05, request.volume))
    }
}
