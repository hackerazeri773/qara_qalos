import Foundation

/// ElnurVoices.json icindeki tek bir ses.
public struct ElnurVoiceInfo: Codable, Identifiable, Hashable {
    /// Sistemde kullanilan kimlik, ornegin "az.elnurtts.gulnar".
    public let id: String
    /// Motorun tanidigi ad (voice.info icindeki "name").
    public let name: String
    /// Ekranda gorunen ad.
    public let displayName: String
    /// BCP-47 dil kodu, ornegin "az-AZ".
    public let language: String
    public let gender: String
    /// "std" = 24 kHz model, "min" = 16 kHz model.
    public let quality: String
}

public struct ElnurVoiceCatalog: Codable {
    /// Eklentinin sisteme verdigi ses formati (16 kHz modeller bu hiza cevrilir).
    public let outputSampleRate: Int
    public let voices: [ElnurVoiceInfo]

    /// ElnurKit.framework paketi (veriler burada).
    public static var bundle: Bundle { Bundle(for: ElnurBundleToken.self) }

    public static func load() throws -> ElnurVoiceCatalog {
        guard let url = bundle.url(forResource: "ElnurVoices", withExtension: "json") else {
            throw ElnurError.missingResource("ElnurVoices.json")
        }
        return try JSONDecoder().decode(ElnurVoiceCatalog.self, from: Data(contentsOf: url))
    }

    public func voice(id: String) -> ElnurVoiceInfo? {
        voices.first { $0.id == id }
    }
}

final class ElnurBundleToken {}

public enum ElnurError: LocalizedError {
    case missingResource(String)
    case engineInit(String)
    case unknownVoice(String)
    case synthesisFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingResource(let name): return "Kaynak bulunamadi: \(name)"
        case .engineInit(let message): return "ElnurTTS baslatilamadi: \(message)"
        case .unknownVoice(let id): return "Bilinmeyen ses: \(id)"
        case .synthesisFailed(let message): return "Sentez hatasi: \(message)"
        }
    }
}
