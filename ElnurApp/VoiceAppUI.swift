import SwiftUI
import AVFoundation

// Bu dosya ElnurTTS ve ESVoice uygulamalarinda AYNIDIR. Degisiklikleri iki projeye birden yapin.

/// Ekranda gosterilen bir ses.
struct VoiceItem: Identifiable, Hashable {
    let id: String
    let name: String
    /// BCP-47, ornegin "az-AZ"
    let language: String
    /// "male" ya da "female"
    let gender: String
}

/// Uygulamaya ozgu bilgiler (motor, sesler, emegi gecenler).
struct VoiceAppConfig {
    let appName: String
    let voices: [VoiceItem]
    /// Metni secilen sesle uretir. Donus: ornekler ve ornekleme hizi.
    let synthesize: (_ text: String, _ voiceID: String, _ rate: Double) throws -> (samples: [Float], sampleRate: Double)
    /// Arka planda motoru isitir (ilk dinlemede gecikme olmasin).
    var prepare: ((_ voiceID: String) -> Void)? = nil
    /// "Hakkinda" ekranindaki emegi gecenler metninin anahtari (Localizable.strings).
    let creditsKey: String
    /// Istege bagli: ikinci dil icin ses secimi (ElnurTTS: Rusca metinler).
    var secondaryVoice: SecondaryVoiceSetting? = nil
}

/// Ana sesin baska bir dile rastladiginda gectigi ses (ornegin Rusca metinde Svetlana/Dimitry).
struct SecondaryVoiceSetting {
    /// nil = otomatik
    let options: [(value: String?, label: String)]
    let get: () -> String?
    let set: (String?) -> Void
    /// Ayar VoiceOver ses eklentisine ulasabiliyor mu (App Group)?
    let isShared: () -> Bool
}

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

enum SampleSentences {
    /// Ornek cumle sesin KENDI dilindedir (Turkce ses Azerbaycanca metni dogal okuyamaz).
    static func text(for voice: VoiceItem) -> String {
        let n = voice.name
        switch voice.language.prefix(2) {
        case "az":
            return "Salam, mənim adım \(n). Ekrandakı mətnləri, mesajları və bildirişləri sizin üçün oxuyuram. Ümid edirəm ki, səsim xoşunuza gələcək!"
        case "tr":
            return "Merhaba, benim adım \(n). Ekrandaki metinleri, mesajları ve bildirimleri sizin için okuyorum. Umarım sesimi beğenirsiniz!"
        case "ru":
            return "Здравствуйте, меня зовут \(n). Я читаю для вас тексты на экране, сообщения и уведомления. Надеюсь, вам понравится мой голос!"
        default:
            return "Hello, my name is \(n). I read the text on your screen, your messages and notifications. I hope you enjoy my voice!"
        }
    }
}

struct VoiceAppView: View {
    let config: VoiceAppConfig

    @State private var selectedID = ""
    @State private var text = ""
    @State private var rate = 1.0
    @State private var errorText = ""
    @State private var secondaryChoice: String?
    @StateObject private var player = SamplePlayer()

    private var selected: VoiceItem? { config.voices.first { $0.id == selectedID } }

    /// Sesler dile gore; cihazin dili en ustte.
    private var groups: [(language: String, voices: [VoiceItem])] {
        let device = String((Locale.preferredLanguages.first ?? "en").prefix(2))
        var original: [String] = []
        for v in config.voices where !original.contains(v.language) { original.append(v.language) }
        let order = original.filter { $0.hasPrefix(device) } + original.filter { !$0.hasPrefix(device) }
        return order.map { lang in (lang, config.voices.filter { $0.language == lang }) }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                Section {
                    Text(L("app.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                ForEach(groups, id: \.language) { group in
                    Section {
                        ForEach(group.voices) { voice in
                            voiceRow(voice)
                        }
                    } header: {
                        Text(Self.languageName(group.language))
                    }
                }

                if let setting = config.secondaryVoice {
                    secondaryVoiceSection(setting)
                }
                tryItSection.id("try")
                voiceOverSection.id("vo")

                Section {
                    NavigationLink {
                        AboutView(config: config)
                    } label: {
                        Label(L("about.title"), systemImage: "info.circle")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(config.appName)
            .onAppear {
                // Yalnizca otomatik ekran goruntusu icin: "-demoScroll vo" gibi baslatma argumani.
                if let target = UserDefaults.standard.string(forKey: "demoScroll") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { proxy.scrollTo(target, anchor: .top) }
                }
            }
            }
        }
        .onAppear(perform: start)
    }

    // MARK: - Bolumler

    private func voiceRow(_ voice: VoiceItem) -> some View {
        let isSelected = voice.id == selectedID
        let isPlaying = player.isPlaying && player.playingVoiceID == voice.id
        return Button {
            select(voice)
            play(SampleSentences.text(for: voice), voiceID: voice.id)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: voice.gender == "male" ? "person.fill" : "person")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.name).font(.body).foregroundStyle(.primary)
                    Text(L(voice.gender == "male" ? "gender.male" : "gender.female"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if player.isLoading && player.playingVoiceID == voice.id {
                    ProgressView().accessibilityHidden(true)
                } else {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : (isSelected ? "checkmark" : "play.circle"))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(voice.name), \(L(voice.gender == "male" ? "gender.male" : "gender.female"))")
        .accessibilityHint(L("voice.hint"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func secondaryVoiceSection(_ setting: SecondaryVoiceSetting) -> some View {
        Section {
            Picker(L("secondary.title"), selection: Binding(
                get: { secondaryChoice ?? setting.get() ?? "" },
                set: { value in
                    secondaryChoice = value
                    setting.set(value.isEmpty ? nil : value)
                })) {
                ForEach(setting.options.indices, id: \.self) { i in
                    Text(setting.options[i].label).tag(setting.options[i].value ?? "")
                }
            }
        } header: {
            Text(L("secondary.title"))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("secondary.footer"))
                if !setting.isShared() {
                    Text(L("secondary.unavailable")).foregroundStyle(.orange)
                }
            }
        }
    }

    private var tryItSection: some View {
        Section {
            TextField(L("try.placeholder"), text: $text, axis: .vertical)
                .lineLimit(3...8)
                .accessibilityLabel(L("try.placeholder"))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("speed.label"))
                    Spacer()
                    Text(Self.speedText(rate)).monospacedDigit().foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
                Slider(value: $rate, in: 0.5...3, step: 0.25)
                    .accessibilityLabel(L("speed.label"))
                    .accessibilityValue(Self.speedText(rate))
            }

            Button {
                if player.isPlaying || player.isLoading {
                    player.stop()
                } else if let v = selected {
                    play(text, voiceID: v.id)
                }
            } label: {
                HStack {
                    Spacer()
                    Label(player.isPlaying || player.isLoading ? L("button.stop") : L("button.play"),
                          systemImage: player.isPlaying || player.isLoading ? "stop.fill" : "play.fill")
                        .font(.headline)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .disabled(selected == nil || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !player.isPlaying))

            if !errorText.isEmpty {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text(L("try.title"))
        } footer: {
            if let v = selected {
                Text(String(format: L("try.footer"), v.name))
            }
        }
    }

    private var voiceOverSection: some View {
        Section {
            step(1, L("vo.step1"))
            step(2, String(format: L("vo.step2"), config.appName))
            step(3, L("vo.step3"))
            step(4, L("vo.step4"))
        } header: {
            Text(L("vo.title"))
        } footer: {
            Text(L("vo.footer"))
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)
            Text(text).font(.subheadline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(n). \(text)")
    }

    // MARK: - Islemler

    private func start() {
        // Sesleri sisteme bildir (VoiceOver listesinde gorunsunler).
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        if selectedID.isEmpty {
            let first = groups.first?.voices.first
            if let first { select(first) }
        }
        if let prepare = config.prepare, !selectedID.isEmpty {
            let id = selectedID
            DispatchQueue.global(qos: .utility).async { prepare(id) }
        }
    }

    private func select(_ voice: VoiceItem) {
        let previousSample = selected.map(SampleSentences.text(for:))
        selectedID = voice.id
        // Kullanici kendi metnini yazmadiysa ornek cumleyi yeni sesin diline cevir.
        if text.isEmpty || text == previousSample {
            text = SampleSentences.text(for: voice)
        }
    }

    private func play(_ text: String, voiceID: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        errorText = ""
        let rate = self.rate
        let synthesize = config.synthesize
        player.load(voiceID: voiceID) {
            try synthesize(t, voiceID, rate)
        } onError: { message in
            errorText = String(format: L("error.play"), message)
        }
    }

    // MARK: - Yardimcilar

    static func languageName(_ code: String) -> String {
        let lang = String(code.prefix(2))
        let key = "lang." + lang
        let own = L(key)
        if own != key { return own }
        let name = Locale.current.localizedString(forLanguageCode: lang) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    static func speedText(_ rate: Double) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return (f.string(from: NSNumber(value: rate)) ?? "\(rate)") + "×"
    }
}

struct AboutView: View {
    let config: VoiceAppConfig

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    var body: some View {
        List {
            Section {
                LabeledContent(L("about.version"), value: version)
                LabeledContent(L("about.voices"), value: "\(config.voices.count)")
            }
            Section {
                Label {
                    Text(L("about.offline"))
                } icon: {
                    Image(systemName: "lock.shield").foregroundStyle(.tint)
                }
            }
            Section(L("about.credits.title")) {
                Text(L(config.creditsKey)).font(.subheadline)
            }
        }
        .navigationTitle(L("about.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Uygulama ici dinleme: sentez arka planda, calma AVAudioEngine ile.
final class SamplePlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var playingVoiceID: String?

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var generation = 0

    func load(voiceID: String,
              synthesize: @escaping () throws -> (samples: [Float], sampleRate: Double),
              onError: @escaping (String) -> Void) {
        stop()
        generation += 1
        let token = generation
        isLoading = true
        playingVoiceID = voiceID
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try synthesize()
                DispatchQueue.main.async {
                    guard token == self.generation else { return }
                    self.isLoading = false
                    self.play(result.samples, sampleRate: result.sampleRate, token: token)
                }
            } catch {
                DispatchQueue.main.async {
                    guard token == self.generation else { return }
                    self.isLoading = false
                    self.playingVoiceID = nil
                    onError(error.localizedDescription)
                }
            }
        }
    }

    func stop() {
        generation += 1
        node.stop()
        isPlaying = false
        isLoading = false
        playingVoiceID = nil
    }

    private func play(_ samples: [Float], sampleRate: Double, token: Int) {
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else {
            playingVoiceID = nil
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }

        // VoiceOver ile birlikte calisirken ses kisilmesin/karismasin.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        if self.format != format {
            engine.stop()
            if !engine.attachedNodes.contains(node) { engine.attach(node) }
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            self.format = format
        }
        if !engine.isRunning { try? engine.start() }
        node.stop()
        isPlaying = true
        node.scheduleBuffer(buffer, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.isPlaying = false
                self.playingVoiceID = nil
            }
        }
        node.play()
    }
}
