import Foundation

/// VoiceOver'in SSML ile gonderdigi hiz/perde/ses degerlerini motor carpanlarina cevirir.
///
/// Gercek cihaz olcumleri (RHVoiceUkraine projesi): iOS VoiceOver hizi SSML'de
/// yaklasik %10 ... %100 araliginda gonderir (macOS'ta %100 ... %424).
/// Bu yuzden iOS'ta %100 "normal" degil, "en hizli" anlamina gelir.
/// Egri: rotor %0 -> 0.25x, %50 -> 1x, %100 -> 4x (iOS); macOS'ta oran dogrudan kullanilir.
/// Gercek iPhone testinden sonra bu degerler ince ayarlanacak.
public enum VoiceOverMapping {
    public static func rateMultiplier(for request: SpeechRequestText) -> Double {
        // SSML'de hiz yoksa normal hiz.
        guard request.rawRate != nil else { return 1 }
        #if os(iOS)
        let percent = request.rate * 100  // SpeechRequestText "50%" -> 0.5
        // %10 -> 0, %100 -> 1
        let p = min(1, max(0, (percent - 10) / 90))
        // 0 -> 0.25x, 0.5 -> 1x, 1 -> 4x (ustel egri)
        return pow(4, 2 * p - 1)
        #else
        return request.rate
        #endif
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
