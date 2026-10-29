import SwiftUI
import AVFoundation
import ElnurKit

/// VoiceOver'in uygulama icinde de kullanicinin normal sesini kullanmasi icin
/// uygulamanin erisilebilirlik dilini telefonun diline esitler. Bu ayar olmadan
/// iOS uygulamayi Ingilizce sayar ve metinleri Ingilizce sesle okur.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.accessibilityLanguage = Locale.preferredLanguages.first ?? "tr-TR"
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
    @StateObject private var probe = SystemVoiceProbe()
    @StateObject private var capture = CaptureExporter()

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
                Section("Karşılaştırma dosyaları") {
                    Button("Seçili ses için karşılaştırma dosyalarını oluştur") {
                        capture.run(voiceID: selectedID)
                    }
                    .disabled(capture.busy || selectedID.isEmpty)
                    if !capture.status.isEmpty {
                        Text(capture.status).font(.caption)
                    }
                    if !capture.files.isEmpty {
                        ShareLink(items: capture.files) { Text("Dosyaları paylaş") }
                    }
                    Text("Dosyalar ayrıca Windows'taki Apple Devices uygulamasında, iPhone → Dosyalar → ElnurTTS altında görünür.")
                        .font(.footnote)
                }
                Section("Sistem tanısı") {
                    Button("Sistemin gördüğü ElnurTTS seslerini listele") { probe.listVoices() }
                    Button("Sistem sesiyle dosyaya yazma testi") { probe.writeTest(voiceID: selectedID, text: text) }
                    if !probe.report.isEmpty {
                        Text(probe.report).font(.caption).textSelection(.enabled)
                        ShareLink(item: probe.report) { Text("Tanı raporunu paylaş") }
                    }
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
        status = probe.speak(voiceID: selectedID, text: text)
    }
}

/// Sistem (AVSpeechSynthesizer) uzerinden eklentimizi deneyen ve ne oldugunu raporlayan yardimci.
final class SystemVoiceProbe: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var report = ""
    private let synth = AVSpeechSynthesizer()
    private let writer = AVSpeechSynthesizer()
    private var started = false

    override init() {
        super.init()
        synth.delegate = self
    }

    private func log(_ line: String) {
        DispatchQueue.main.async {
            let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            self.report += "[\(time)] \(line)\n"
        }
    }

    /// iOS ucuncu taraf seslere kendi on ekini ekleyebiliyor; bu yuzden kimligin
    /// bir parcasina ya da ses adina gore aranir.
    static func systemVoice(for voiceID: String) -> AVSpeechSynthesisVoice? {
        if let exact = AVSpeechSynthesisVoice(identifier: voiceID) { return exact }
        let all = AVSpeechSynthesisVoice.speechVoices()
        if let partial = all.first(where: { $0.identifier.contains(voiceID) }) { return partial }
        let info = (try? ElnurVoiceCatalog.load())?.voice(id: voiceID)
        return all.first(where: { $0.name == info?.displayName && $0.language == info?.language })
    }

    static func isOurs(_ v: AVSpeechSynthesisVoice) -> Bool {
        let names = Set(((try? ElnurVoiceCatalog.load())?.voices ?? []).map(\.displayName))
        return v.identifier.lowercased().contains("elnurtts") || names.contains(v.name)
    }

    func listVoices() {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let ours = all.filter { Self.isOurs($0) }
        log("Sistemde toplam \(all.count) ses var, ElnurTTS: \(ours.count)")
        for v in ours {
            log("  \(v.name) | \(v.language) | \(v.identifier)")
        }
        let langs = Set(all.map(\.language)).sorted()
        log("Sistem dilleri: \(langs.joined(separator: ", "))")
    }

    /// Donus: ekranda gosterilecek durum metni.
    func speak(voiceID: String, text: String) -> String {
        guard let voice = Self.systemVoice(for: voiceID) else {
            log("speak: sistem '\(voiceID)' sesini bulamadi")
            return "Sistem bu sesi bulamadı. 'Sesleri sisteme yeniden bildir'e basıp 30 sn bekleyin."
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        started = false
        log("speak: \(voice.name) [\(voice.language)] \(voice.identifier) istendi")
        synth.stopSpeaking(at: .immediate)
        synth.speak(utterance)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            if !self.started { self.log("speak: 5 sn icinde konusma BASLAMADI") }
        }
        return "Sistem sesi istendi: \(voice.name). Sonuç 'Sistem tanısı' bölümünde."
    }

    /// Eklentinin ses uretip uretmedigini, hoparlore gondermeden olcer.
    func writeTest(voiceID: String, text: String) {
        guard let voice = Self.systemVoice(for: voiceID) else {
            log("write: sistem '\(voiceID)' sesini bulamadi")
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        var frames = 0
        var buffers = 0
        var rate = 0.0
        let start = Date()
        log("write: \(voice.name) basladi")
        writer.write(utterance) { [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 {
                let secs = rate > 0 ? Double(frames) / rate : 0
                self?.log(String(format: "write: bitti, %d parca, %d ornek (%.2f sn ses), %.2f sn surdu", buffers, frames, secs, Date().timeIntervalSince(start)))
                return
            }
            buffers += 1
            frames += Int(pcm.frameLength)
            rate = pcm.format.sampleRate
            if buffers == 1 {
                self?.log("write: bicim \(pcm.format)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            if buffers == 0 { self?.log("write: 8 sn icinde hic ses gelmedi") }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        started = true
        log("speak: konusma basladi")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        log("speak: konusma bitti")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        log("speak: konusma iptal edildi")
    }
}

/// Telefondaki motorun ve sistem (VoiceOver) yolunun urettigi sesi WAV olarak kaydeder.
/// Bu dosyalar simulator ciktisiyla ornek ornek karsilastirilir.
final class CaptureExporter: ObservableObject {
    @Published var status = ""
    @Published var files: [URL] = []
    @Published var busy = false
    private let synth = AVSpeechSynthesizer()

    /// Testlerdeki (reference.json) cumlelerin aynisi.
    static func referenceText(for language: String) -> String {
        switch language.prefix(2) {
        case "az": return "Salam! Bu gün hava çox gözəldir, elə deyilmi? Saat 14:30-da 3 nəfər gəldi."
        case "tr": return "Merhaba! Ayarlar, Erişilebilirlik, VoiceOver. Fiyatı 25,5 TL idi."
        case "ru": return "Привет! Сегодня прекрасная погода, не правда ли?"
        default: return "Hello! This is a test of the voice."
        }
    }

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func set(_ text: String) {
        DispatchQueue.main.async { self.status = text }
    }

    func run(voiceID: String) {
        guard let info = (try? ElnurVoiceCatalog.load())?.voice(id: voiceID) else { return }
        busy = true
        files = []
        let text = Self.referenceText(for: info.language)
        let motorURL = documents.appendingPathComponent("karsilastirma_\(info.name)_motor.wav")
        let systemURL = documents.appendingPathComponent("karsilastirma_\(info.name)_sistem.wav")
        set("1/2: motor çıktısı üretiliyor…")

        DispatchQueue.global(qos: .userInitiated).async {
            var made: [URL] = []
            do {
                let engine = try ElnurEngine.shared()
                let samples = try engine.synthesize(text: text, voiceID: voiceID)
                try WavFile.write(samples, sampleRate: engine.outputSampleRate, to: motorURL)
                made.append(motorURL)
            } catch {
                self.set("Motor hatası: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                self.files = made
                self.status = "2/2: sistem (VoiceOver) yolu deneniyor…"
                self.captureSystem(voiceID: voiceID, text: text, to: systemURL, made: made)
            }
        }
    }

    private func captureSystem(voiceID: String, text: String, to url: URL, made: [URL]) {
        guard let voice = SystemVoiceProbe.systemVoice(for: voiceID) else {
            finish(made, note: "Sistem yolu: ses bulunamadı (yalnızca motor dosyası kaydedildi).")
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        var collected: [Float] = []
        var rate = 0
        var done = false
        synth.write(utterance) { [weak self] buffer in
            guard let self, let pcm = buffer as? AVAudioPCMBuffer, !done else { return }
            if pcm.frameLength == 0 {
                done = true
                do {
                    try WavFile.write(collected, sampleRate: rate > 0 ? rate : 48_000, to: url)
                    self.finish(made + [url], note: "Hazır: \(made.count + 1) dosya (sistem \(rate) Hz).")
                } catch {
                    self.finish(made, note: "Sistem dosyası yazılamadı: \(error.localizedDescription)")
                }
                return
            }
            rate = Int(pcm.format.sampleRate)
            let n = Int(pcm.frameLength)
            if let f = pcm.floatChannelData {
                collected.append(contentsOf: UnsafeBufferPointer(start: f[0], count: n))
            } else if let i = pcm.int16ChannelData {
                collected.append(contentsOf: UnsafeBufferPointer(start: i[0], count: n).map { Float($0) / 32768 })
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            if !done {
                done = true
                self?.finish(made, note: "Sistem yolu 20 sn içinde bitmedi (yalnızca motor dosyası kaydedildi).")
            }
        }
    }

    private func finish(_ urls: [URL], note: String) {
        DispatchQueue.main.async {
            self.files = urls
            self.status = note
            self.busy = false
        }
    }
}

enum WavFile {
    static func write(_ samples: [Float], sampleRate: Int, to url: URL) throws {
        var data = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(byteCount)
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * 32767)
            withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
        }
        try data.write(to: url)
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
