import Foundation
import AVFoundation
import ElnurTTSEngine

/// ElnurTTS C motorunun Swift sarmalayicisi.
/// Iki motor ornegi tutulur: "std" (24 kHz modeller) ve "min" (16 kHz modeller).
/// Hangi sesin hangisini kullanacagi ElnurVoices.json icindeki "quality" alanindan gelir.
public final class ElnurEngine {
    public let catalog: ElnurVoiceCatalog

    /// Motorun karakter modunda da ses vermeyen semboller (olcumle bulundu);
    /// bunlar icin SpeechPlanner'in sembol adlari kullanilir.
    public static let characterModeSilentSymbols: Set<Character> = ["@", "&", "=", "<", ">", "|", "~", "^", "$", "`", "‘", "’", "„", "¡", "¿", "‰", "′", "″", "¢", "¥", "¶", "†", "‡", "¤", "‹", "›"]
    public var outputSampleRate: Int { catalog.outputSampleRate }

    private let dataPath: String
    private var engines: [String: ElnurTTS_tts_engine] = [:]
    private let lock = NSLock()

    /// Son sentezin tani bilgileri (tepe degeri, sinirlayiciya takilan ornek sayisi).
    public private(set) var lastPeak: Float = 0
    public private(set) var lastLimitedSamples = 0
    public private(set) var lastEngineSampleRate = 0

    private static let sharedLock = NSLock()
    private static var sharedInstance: ElnurEngine?

    public static func shared() throws -> ElnurEngine {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        if let sharedInstance { return sharedInstance }
        let engine = try ElnurEngine()
        sharedInstance = engine
        return engine
    }

    public init() throws {
        catalog = try ElnurVoiceCatalog.load()
        TextNormalizer.emojiTableURL = { lang in
            ElnurVoiceCatalog.bundle.url(forResource: "emoji_\(lang)", withExtension: "txt", subdirectory: "Emoji")
        }
        guard let data = ElnurVoiceCatalog.bundle.url(forResource: "ElnurData", withExtension: nil) else {
            throw ElnurError.missingResource("ElnurData")
        }
        dataPath = data.path
    }

    deinit {
        for engine in engines.values { ElnurTTS_delete_tts_engine(engine) }
    }

    public var voices: [ElnurVoiceInfo] { catalog.voices }

    public func voice(id: String) throws -> ElnurVoiceInfo {
        guard let voice = catalog.voice(id: id) else { throw ElnurError.unknownVoice(id) }
        return voice
    }

    /// Motorun kendi gordugu sesler (tani amacli).
    public func engineVoiceNames() throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let engine = try engine(quality: "std")
        let count = Int(ElnurTTS_get_number_of_voices(engine))
        guard let list = ElnurTTS_get_voices(engine) else { return [] }
        return (0..<count).compactMap { list[$0].name.map { String(cString: $0) } }
    }

    // MARK: - Motor ornekleri

    /// Kalite ayari yalnizca yapilandirma dosyasiyla verilebildigi icin her kalite
    /// icin ayri bir yapilandirma klasoru olusturulur.
    /// Her kalite icin hazir ayar klasoru UYGULAMA PAKETININ ICINDE durur (ElnurConfig/std, /min).
    /// Eklenti hicbir dosya YAZMAZ: telefon yeniden baslatildiginda, kilit ilk kez acilana kadar
    /// yazilan dosyalar korumali oldugundan okunamaz/yazilamaz ve VoiceOver kilit ekraninda
    /// sessiz kaliyordu. Paket icindeki dosyalar her zaman okunabilir.
    private func configDirectory(quality: String) throws -> String {
        guard let url = ElnurVoiceCatalog.bundle.url(forResource: "ElnurConfig", withExtension: nil)?
            .appendingPathComponent(quality == "min" ? "min" : "std", isDirectory: true),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("ElnurTTS.conf").path) else {
            throw ElnurError.missingResource("ElnurConfig/\(quality)")
        }
        return url.path
    }


    private func engine(quality: String) throws -> ElnurTTS_tts_engine {
        if let existing = engines[quality] { return existing }
        let configPath = try configDirectory(quality: quality)

        var params = ElnurTTS_init_params()
        params.callbacks.set_sample_rate = { rate, userData in
            guard let userData else { return 1 }
            Unmanaged<SynthesisSink>.fromOpaque(userData).takeUnretainedValue().sampleRate = Int(rate)
            return 1
        }
        params.callbacks.play_speech = { samples, count, userData in
            guard let userData, let samples else { return 1 }
            let sink = Unmanaged<SynthesisSink>.fromOpaque(userData).takeUnretainedValue()
            return sink.receive(samples, count: Int(count)) ? 1 : 0
        }
        params.options = 0

        let created: ElnurTTS_tts_engine? = dataPath.withCString { dataC in
            configPath.withCString { configC in
                params.data_path = dataC
                params.config_path = configC
                params.resource_paths = nil
                return ElnurTTS_new_tts_engine(&params)
            }
        }
        guard let created else { throw ElnurError.engineInit("data=\(dataPath)") }
        engines[quality] = created
        return created
    }

    /// Android surumuyle ayni ses profili: ana ses + otomatik dil gecisi acik olan DIGER dillerin
    /// varsayilan sesleri ("Gulnar+Dimitry+Jenny"). RHVoice her harfi profilde onu taniyan ILK
    /// sese verir: Latin harfler ana seste kalir, Kiril harfli bolumleri Rusca ses okur.
    func voiceProfile(for voice: ElnurVoiceInfo) -> String {
        let mainLang = String(voice.language.prefix(2))
        var names = [voice.name]
        var seen: Set<String> = [mainLang]
        for v in catalog.voices {
            let lang = String(v.language.prefix(2))
            guard !seen.contains(lang) else { continue }
            seen.insert(lang)
            let setting = ElnurSettings.language(lang)
            guard setting.detect else { continue }
            // Ana ses 24 kHz ("std") motorda calisiyorsa 16 kHz'lik sesler (Elnur, Faruk) profile
            // girmemeli: 24 kHz modelleri bozuk, cizirti cikariyor. Yerine ayni dilin ayni
            // cinsiyetteki 24 kHz sesi gecer (Elnur -> Babek).
            let usable: (ElnurVoiceInfo) -> Bool = { voice.quality == "min" || $0.quality != "min" }
            let chosen = catalog.voices.first {
                ($0.name == setting.voice || $0.displayName == setting.voice) && $0.language.hasPrefix(lang) && usable($0)
            }
            let preferredGender = catalog.voices.first {
                ($0.name == setting.voice || $0.displayName == setting.voice) && $0.language.hasPrefix(lang)
            }?.gender ?? voice.gender
            let fallback = catalog.voices.first { $0.language.hasPrefix(lang) && usable($0) && $0.gender == preferredGender }
                ?? catalog.voices.first { $0.language.hasPrefix(lang) && usable($0) }
            guard let partner = chosen ?? fallback else { continue }
            names.append(partner.name)
        }
        return names.joined(separator: "+")
    }

    /// Modeli onceden yukler (ilk konusmadaki gecikmeyi azaltir).
    public func preload(voiceID: String) {
        _ = try? synthesize(text: ".", voiceID: voiceID)
    }

    // MARK: - Sentez

    /// Metni sese cevirir. Donus: outputSampleRate hizinda, -1...1 araliginda Float ornekler.
    /// - Parameters:
    ///   - rate: hiz carpani (1 = normal, motorun siniri 5).
    ///   - pitch: perde carpani (1 = normal).
    ///   - volume: ses seviyesi carpani (1 = normal).
    ///   - shouldContinue: false donerse sentez yarida kesilir.
    public func synthesize(text: String, voiceID: String,
                           rate: Double = 1, pitch: Double = 1, volume: Double = 1,
                           characters: Bool = false,
                           onChunk: (([Float]) -> Void)? = nil,
                           shouldContinue: (() -> Bool)? = nil) throws -> [Float] {
        let voice = try self.voice(id: voiceID)
        // Motorun okumadigi semboller (₼ $ € × → & @ = < > ...) Android ile ayni adlarla yazilir.
        let normalize = !characters && (voice.language.hasPrefix("az") || voice.language.hasPrefix("tr"))
        let prepared = normalize ? TextNormalizer.normalize(text, language: voice.language, options: .elnurTTS) : text
        let trimmed = prepared.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        lock.lock()
        defer { lock.unlock() }
        let engine = try engine(quality: voice.quality)

        let sink = SynthesisSink(outputRate: outputSampleRate, onChunk: onChunk, shouldContinue: shouldContinue)
        let userData = Unmanaged.passUnretained(sink).toOpaque()

        var synth = ElnurTTS_synth_params()
        synth.absolute_rate = 0
        synth.absolute_pitch = 0
        synth.absolute_volume = 0
        // Dilin kendi ayarlari (Android: language.X.volume / rate) VoiceOver degerlerinin ustune eklenir.
        let langSetting = ElnurSettings.language(String(voice.language.prefix(2)))
        synth.relative_rate = max(0.1, rate * langSetting.rateMultiplier)
        synth.relative_pitch = max(0.1, pitch)
        synth.relative_volume = max(0.0, volume * langSetting.volumeMultiplier)
        synth.punctuation_mode = ElnurTTS_punctuation_default
        synth.punctuation_list = nil
        synth.capitals_mode = ElnurTTS_capitals_default
        synth.flags = 0

        let utf8 = Array(trimmed.utf8)
        let profile = voiceProfile(for: voice)
        let messageType = characters ? ElnurTTS_message_characters : ElnurTTS_message_text
        let ok: Bool = profile.withCString { profileC in
            synth.voice_profile = profileC
            return utf8.withUnsafeBufferPointer { buf -> Bool in
                buf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: utf8.count) { textC in
                    guard let message = ElnurTTS_new_message(engine, textC, UInt32(utf8.count),
                                                             messageType, &synth, userData) else {
                        return false
                    }
                    defer { ElnurTTS_delete_message(message) }
                    _ = ElnurTTS_speak(message)
                    return true
                }
            }
        }
        withExtendedLifetime(sink) {}
        if !ok { throw ElnurError.synthesisFailed("mesaj olusturulamadi") }
        sink.flush()
        lastPeak = sink.peak
        lastLimitedSamples = sink.limitedSamples
        lastEngineSampleRate = sink.sampleRate
        return sink.samples
    }
}

/// Motorun geri cagirmalarindan gelen ornekleri toplar ve gerekirse hiz donusturur.
final class SynthesisSink {
    var sampleRate: Int = 0
    private let outputRate: Int
    private let onChunk: (([Float]) -> Void)?
    private let shouldContinue: (() -> Bool)?
    private(set) var samples: [Float] = []
    private var resampler: HighQualityResampler?
    private var pending: [Float] = []
    private(set) var peak: Float = 0
    private(set) var limitedSamples = 0

    /// Yumusak sinirlayici: 0.9'un ustundeki tepe degerlerini sert kirpmak yerine
    /// yumusakca 1'e yaklastirir.
    @inline(__always)
    private func limit(_ x: Float) -> Float {
        let a = abs(x)
        if a > peak { peak = a }
        guard a > 0.9 else { return x }
        limitedSamples += 1
        let y = 0.9 + 0.1 * tanh((a - 0.9) / 0.1)
        return x < 0 ? -y : y
    }

    init(outputRate: Int, onChunk: (([Float]) -> Void)?, shouldContinue: (() -> Bool)?) {
        self.outputRate = outputRate
        self.onChunk = onChunk
        self.shouldContinue = shouldContinue
    }

    private func convert(_ input: [Float], final: Bool) -> [Float] {
        guard sampleRate > 0, sampleRate != outputRate else { return input }
        if resampler == nil {
            resampler = HighQualityResampler(from: Double(sampleRate), to: Double(outputRate))
        }
        return resampler?.process(input, final: final) ?? input
    }

    private func emit(_ converted: [Float]) {
        if onChunk != nil {
            pending.append(contentsOf: converted)
            // Kucuk parcalari biriktirip ~50 ms'lik bloklar halinde gonder.
            if pending.count >= outputRate / 20 {
                onChunk?(pending)
                pending.removeAll(keepingCapacity: true)
            }
        } else {
            samples.append(contentsOf: converted)
        }
    }

    func receive(_ data: UnsafePointer<Int16>, count: Int) -> Bool {
        var input = [Float](repeating: 0, count: count)
        for i in 0..<count { input[i] = limit(Float(data[i]) / 32768) }
        emit(convert(input, final: false))
        return shouldContinue?() ?? true
    }

    func flush() {
        if resampler != nil {
            emit(convert([], final: true))
        }
        if !pending.isEmpty {
            onChunk?(pending)
            pending.removeAll()
        }
    }
}

/// Apple'in en yuksek kaliteli ornekleme hizi donusturucusu (AVAudioConverter,
/// "mastering" algoritmasi). Parca parca gelen sesi durumunu koruyarak cevirir.
final class HighQualityResampler {
    private let converter: AVAudioConverter
    private let inFormat: AVAudioFormat
    private let outFormat: AVAudioFormat
    private let ratio: Double
    private var finished = false

    init?(from inRate: Double, to outRate: Double) {
        guard let i = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inRate, channels: 1, interleaved: false),
              let o = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: outRate, channels: 1, interleaved: false),
              let c = AVAudioConverter(from: i, to: o) else { return nil }
        c.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
        c.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        inFormat = i
        outFormat = o
        converter = c
        ratio = outRate / inRate
    }

    func process(_ input: [Float], final: Bool) -> [Float] {
        if finished { return [] }
        var inputBuffer: AVAudioPCMBuffer?
        if !input.isEmpty, let b = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(input.count)) {
            b.frameLength = AVAudioFrameCount(input.count)
            input.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: input.count) }
            inputBuffer = b
        }
        var supplied = false
        var output: [Float] = []
        let capacity = AVAudioFrameCount(Double(max(input.count, 256)) * ratio) + 1024
        while true {
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { break }
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, outStatus in
                if !supplied, let inputBuffer {
                    supplied = true
                    outStatus.pointee = .haveData
                    return inputBuffer
                }
                outStatus.pointee = final ? .endOfStream : .noDataNow
                return nil
            }
            if out.frameLength > 0 {
                output.append(contentsOf: UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
            }
            switch status {
            case .haveData:
                continue
            case .endOfStream:
                finished = true
                return output
            default:
                return output
            }
        }
        return output
    }
}
