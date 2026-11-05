import SwiftUI
import AVFoundation
import ElnurKit

/// ElnurTTS ana ekrani: Android surumundeki gibi her dil icin ayri bolum —
/// varsayilan ses (acilir menu), ornegi dinle, otomatik dil gecisi, ses yuksekligi, hiz.
struct ElnurAppView: View {
    let config: VoiceAppConfig
    /// Motor adi -> ses
    let voices: [VoiceItem]

    @State private var settings: [String: ElnurSettings.Language] = [:]
    @State private var text = ""
    @State private var tryVoiceID = ""
    @State private var errorText = ""
    @StateObject private var player = SamplePlayer()

    private var languages: [String] {
        let device = String((Locale.preferredLanguages.first ?? "en").prefix(2))
        var order: [String] = []
        for v in voices {
            let l = String(v.language.prefix(2))
            if !order.contains(l) { order.append(l) }
        }
        return order.filter { $0 == device } + order.filter { $0 != device }
    }

    private func voices(of lang: String) -> [VoiceItem] {
        voices.filter { $0.language.hasPrefix(lang) }
    }

    /// Dilin secili (varsayilan) sesi.
    private func selectedVoice(_ lang: String) -> VoiceItem? {
        let list = voices(of: lang)
        let name = settings[lang]?.voice
        return list.first { $0.name == name } ?? list.first
    }

    private func binding(_ lang: String) -> Binding<ElnurSettings.Language> {
        Binding(
            get: { settings[lang] ?? .default },
            set: { value in
                settings[lang] = value
                ElnurSettings.setLanguage(lang, value)
            })
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        Text(L("app.subtitle.elnur"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                        if !ElnurSettings.isShared {
                            Label(L("settings.unavailable"), systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }

                    ForEach(languages, id: \.self) { lang in
                        languageSection(lang)
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
                    start()
                    if let target = UserDefaults.standard.string(forKey: "demoScroll") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { proxy.scrollTo(target, anchor: .top) }
                    }
                }
            }
        }
    }

    // MARK: - Dil bolumu

    private func languageSection(_ lang: String) -> some View {
        let list = voices(of: lang)
        let current = selectedVoice(lang)
        let b = binding(lang)
        return Section {
            Picker(L("lang.voice"), selection: Binding(
                get: { current?.name ?? "" },
                set: { name in
                    var s = b.wrappedValue
                    s.voice = name
                    b.wrappedValue = s
                    if let v = list.first(where: { $0.name == name }) { tryVoiceID = v.id }
                })) {
                ForEach(list) { v in
                    Text("\(v.name), \(L(v.gender == "male" ? "gender.male" : "gender.female"))").tag(v.name)
                }
            }
            .pickerStyle(.menu)

            if let v = current {
                Button {
                    play(SampleSentences.text(for: v), voiceID: v.id)
                } label: {
                    Label(isPlaying(v.id) ? L("button.stop") : L("lang.sample"),
                          systemImage: isPlaying(v.id) ? "stop.fill" : "play.circle")
                }
            }

            if voices.count > list.count {
                Toggle(isOn: Binding(get: { b.wrappedValue.detect },
                                     set: { var s = b.wrappedValue; s.detect = $0; b.wrappedValue = s })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("lang.detect.title"))
                        Text(L("lang.detect.desc")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            sliderRow(title: L("lang.volume"),
                      value: Binding(get: { b.wrappedValue.volumeDB },
                                     set: { var s = b.wrappedValue; s.volumeDB = $0.rounded(); b.wrappedValue = s }),
                      range: ElnurSettings.volumeRange, step: 1,
                      text: Self.dbText(b.wrappedValue.volumeDB))

            sliderRow(title: L("lang.rate"),
                      value: Binding(get: { b.wrappedValue.ratePercent },
                                     set: { var s = b.wrappedValue; s.ratePercent = ($0 / 5).rounded() * 5; b.wrappedValue = s }),
                      range: ElnurSettings.rateRange, step: 5,
                      text: "\(Int(b.wrappedValue.ratePercent))%")
        } header: {
            Text(VoiceAppView.languageName(lang))
        } footer: {
            Text(L("lang.footer"))
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           step: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(text).monospacedDigit().foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(text)
        }
    }

    // MARK: - Deneme

    private var tryItSection: some View {
        Section {
            Picker(L("try.voice"), selection: $tryVoiceID) {
                ForEach(voices) { v in
                    Text("\(v.name) — \(VoiceAppView.languageName(v.language))").tag(v.id)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: tryVoiceID) { old, new in
                // Kullanici kendi metnini yazmadiysa ornek cumleyi yeni sesin diline cevir.
                let oldSample = voices.first { $0.id == old }.map(SampleSentences.text(for:))
                if let v = voices.first(where: { $0.id == new }), text.isEmpty || text == oldSample {
                    text = SampleSentences.text(for: v)
                }
            }

            TextField(L("try.placeholder"), text: $text, axis: .vertical)
                .lineLimit(3...8)
                .accessibilityLabel(L("try.placeholder"))

            Button {
                if player.isPlaying || player.isLoading {
                    player.stop()
                } else {
                    play(text, voiceID: tryVoiceID)
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
            .disabled(tryVoiceID.isEmpty)

            if !errorText.isEmpty {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text(L("try.title"))
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

    private func isPlaying(_ id: String) -> Bool {
        (player.isPlaying || player.isLoading) && player.playingVoiceID == id
    }

    private func start() {
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        var s: [String: ElnurSettings.Language] = [:]
        for l in languages { s[l] = ElnurSettings.language(l) }
        settings = s
        if tryVoiceID.isEmpty, let first = languages.first, let v = selectedVoice(first) {
            tryVoiceID = v.id
            text = SampleSentences.text(for: v)
        }
        if let prepare = config.prepare {
            let id = tryVoiceID
            DispatchQueue.global(qos: .utility).async { prepare(id) }
        }
    }

    private func play(_ text: String, voiceID: String) {
        if isPlaying(voiceID) {
            player.stop()
            return
        }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        errorText = ""
        let synthesize = config.synthesize
        player.load(voiceID: voiceID) {
            try synthesize(t, voiceID, 1)
        } onError: { message in
            errorText = String(format: L("error.play"), message)
        }
    }

    static func dbText(_ db: Double) -> String {
        let v = Int(db.rounded())
        return (v > 0 ? "+" : "") + "\(v) dB"
    }
}
