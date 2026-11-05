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

    public static let minPitch = 0.5
    public static let maxPitch = 2.0

    /// VoiceOver perdeyi goreli yuzde olarak gonderir (pitch="-10%" -> 0.9). Perde motorun
    /// kendi perde ayariyla uygulanir (RHVoice: relative_pitch; ESVoice: modelin pitch_add girisi);
    /// sesi bozmaz (olculdu: f0 0.7x/1.4x, surtunmeli seslerde degisiklik yok).
    public static func pitchMultiplier(for request: SpeechRequestText) -> Double {
        guard request.rawPitch != nil else { return 1 }
        return min(maxPitch, max(minPitch, request.pitch))
    }

    /// Ses seviyesi hicbir zaman 1'in ustune cikarilmaz; yukseltmeyi VoiceOver yapar.
    /// Motorun kendi seviyesini asmak kirpilmaya (cizirtiya) yol acar.
    public static func volumeMultiplier(for request: SpeechRequestText) -> Double {
        min(1, max(0.05, request.volume))
    }
}
