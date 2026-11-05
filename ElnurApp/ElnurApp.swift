import SwiftUI
import AVFoundation
import ElnurKit

/// VoiceOver'in uygulama icinde de kullanicinin normal sesini kullanmasi icin
/// uygulamanin erisilebilirlik dilini telefonun diline esitler. Bu ayar olmadan
/// iOS uygulamayi Ingilizce sayar ve metinleri Ingilizce sesle okur.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.accessibilityLanguage = Locale.preferredLanguages.first ?? "en"
        return true
    }
}

@main
struct ElnurApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Sisteme seslerimizin var oldugunu bildir (VoiceOver listesinde gorunmeleri icin).
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
    }

    var body: some Scene {
        WindowGroup {
            ElnurAppView(config: Self.config, voices: Self.config.voices)
        }
    }

    static let config: VoiceAppConfig = {
        let voices = ((try? ElnurVoiceCatalog.load())?.voices ?? []).map {
            VoiceItem(id: $0.id, name: $0.displayName, language: $0.language, gender: $0.gender)
        }
        return VoiceAppConfig(
            appName: "ElnurTTS",
            voices: voices,
            synthesize: { text, voiceID, rate in
                let engine = try ElnurEngine.shared()
                let samples = try engine.synthesize(text: text, voiceID: voiceID, rate: rate)
                return (samples, Double(engine.outputSampleRate))
            },
            prepare: { _ in _ = try? ElnurEngine.shared() },
            creditsKey: "about.credits.elnurtts")
    }()
}
