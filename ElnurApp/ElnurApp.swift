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
            VoiceAppView(config: Self.config)
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
            creditsKey: "about.credits.elnurtts",
            secondaryVoice: SecondaryVoiceSetting(
                options: [(value: String?, label: String)]([(value: nil, label: L("secondary.auto"))])
                    + voices.filter { $0.language.hasPrefix("ru") }.map { v -> (value: String?, label: String) in
                        (value: v.name, label: "\(v.name), \(L(v.gender == "male" ? "gender.male" : "gender.female"))")
                    },
                get: { ElnurSettings.russianPartner },
                set: { ElnurSettings.russianPartner = $0 },
                isShared: { ElnurSettings.isShared }))
    }()
}
