import SwiftUI
import AVFoundation
import ElnurKit

@main
struct ElnurApp: App {
    init() {
        // Sisteme seslerimizin var oldugunu bildir (VoiceOver listesinde gorunmeleri icin).
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var voices: [ElnurVoiceInfo] = []
    @State private var selectedID = ""
    @State private var text = "Salam! Bu, ElnurTTS səsinin sınağıdır."
    @State private var rate = 1.0
    @State private var pitch = 1.0
    @State private var status = ""
    @State private var busy = false
    @State private var ssmlLog = ""
    @StateObject private var player = SamplePlayer()
    private let systemSynth = AVSpeechSynthesizer()

    var body: some View {
        NavigationStack {
            Form {
                Section("Ses") {
                    Picker("Ses", selection: $selectedID) {
                        ForEach(voices) { voice in
                            Text("\(voice.displayName) (\(voice.language))").tag(voice.id)
                        }
                    }
                    .onChange(of: selectedID) { _, newValue in
                        if let lang = voices.first(where: { $0.id == newValue })?.language {
                            text = Self.sampleText(for: lang)
                        }
                    }
                }
                Section("Metin") {
                    TextField("Okunacak metin", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Deneme ayarları") {
                    VStack(alignment: .leading) {
                        Text("Hız: \(rate, specifier: "%.2f")×")
                        Slider(value: $rate, in: 0.25...5, step: 0.25)
                            .accessibilityLabel("Hız")
                            .accessibilityValue("\(rate, specifier: "%.2f") kat")
                    }
                    VStack(alignment: .leading) {
                        Text("Perde: \(pitch, specifier: "%.2f")×")
                        Slider(value: $pitch, in: 0.5...2, step: 0.1)
                            .accessibilityLabel("Perde")
                            .accessibilityValue("\(pitch, specifier: "%.1f") kat")
                    }
                }
                Section {
                    Button("Uygulama içinde konuş") { speakInApp() }
                        .disabled(busy || selectedID.isEmpty)
                    Button("Sistem sesi olarak konuş") { speakWithSystem() }
                        .disabled(selectedID.isEmpty)
                    Button("Sesleri sisteme yeniden bildir") {
                        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
                        status = "Bildirildi. Sistemin listeyi yenilemesi 30 saniye kadar sürebilir."
                    }
                }
                if !status.isEmpty {
                    Section("Durum") {
                        Text(status).font(.footnote)
                    }
                }
                Section("VoiceOver'da kullanmak") {
                    Text("Ayarlar → Erişilebilirlik → VoiceOver → Konuşma → Ses bölümünden ElnurTTS seslerinden birini seçin. Sesler görünmüyorsa bu uygulamayı bir kez açıp birkaç saniye bekleyin.")
                        .font(.footnote)
                }
                Section("VoiceOver tanı kaydı") {
                    Button("Son SSML isteklerini göster") { ssmlLog = DiagnosticsLog.read() }
                    if !ssmlLog.isEmpty {
                        Text(ssmlLog).font(.caption2).textSelection(.enabled)
                        ShareLink(item: ssmlLog) { Text("Kaydı paylaş") }
                    }
                }
            }
            .navigationTitle("ElnurTTS")
        }
        .task { loadVoices() }
    }

    static func sampleText(for language: String) -> String {
        switch language.prefix(2) {
        case "az": return "Salam! Bu gün hava çox gözəldir, elə deyilmi?"
        case "tr": return "Merhaba! Bu bir deneme cümlesidir."
        case "ru": return "Привет! Сегодня прекрасная погода."
        default: return "Hello! This is a test of the voice."
        }
    }

    private func loadVoices() {
        do {
            let catalog = try ElnurVoiceCatalog.load()
            voices = catalog.voices
            if selectedID.isEmpty { selectedID = catalog.voices.first?.id ?? "" }
        } catch {
            status = error.localizedDescription
        }
    }

    private func speakInApp() {
        busy = true
        status = "Sentezleniyor…"
        let text = self.text, voiceID = selectedID, rate = self.rate, pitch = self.pitch
        Task.detached(priority: .userInitiated) {
            let start = Date()
            do {
                let engine = try ElnurEngine.shared()
                let samples = try engine.synthesize(text: text, voiceID: voiceID, rate: rate, pitch: pitch)
                let elapsed = Date().timeIntervalSince(start)
                let seconds = Double(samples.count) / Double(engine.outputSampleRate)
                await MainActor.run {
                    player.play(samples, sampleRate: Double(engine.outputSampleRate))
                    status = String(format: "%.2f sn ses, %.2f sn'de üretildi.", seconds, elapsed)
                    busy = false
                }
            } catch {
                await MainActor.run {
                    status = "Hata: \(error.localizedDescription)"
                    busy = false
                }
            }
        }
    }

    private func speakWithSystem() {
        guard let voice = AVSpeechSynthesisVoice(identifier: selectedID) else {
            status = "Sistem bu sesi henüz görmüyor. 'Sesleri sisteme yeniden bildir'e basıp biraz bekleyin."
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        systemSynth.speak(utterance)
        status = "Sistem sesi: \(voice.name)"
    }
}

/// Uygulama ici deneme icin basit oynatici.
final class SamplePlayer: ObservableObject {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var format: AVAudioFormat?

    func play(_ samples: [Float], sampleRate: Double) {
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        if self.format != format {
            engine.stop()
            if engine.attachedNodes.contains(node) == false { engine.attach(node) }
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            self.format = format
        }
        if !engine.isRunning { try? engine.start() }
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: [])
        node.play()
    }
}
