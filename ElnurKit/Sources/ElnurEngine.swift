import Foundation
import ElnurTTSEngine

/// ElnurTTS C motorunun Swift sarmalayicisi.
/// Iki motor ornegi tutulur: "std" (24 kHz modeller) ve "min" (16 kHz modeller).
/// Hangi sesin hangisini kullanacagi ElnurVoices.json icindeki "quality" alanindan gelir.
public final class ElnurEngine {
    public let catalog: ElnurVoiceCatalog
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
    private func configDirectory(quality: String) throws -> String {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("ElnurTTSConfig-\(quality)", isDirectory: true)
        try? fm.removeItem(at: base)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        var conf = ""
        if let bundled = ElnurVoiceCatalog.bundle.url(forResource: "ElnurConfig", withExtension: nil) {
            let confURL = bundled.appendingPathComponent("ElnurTTS.conf")
            conf = (try? String(contentsOf: confURL, encoding: .utf8)) ?? ""
            let dicts = bundled.appendingPathComponent("dicts")
            if fm.fileExists(atPath: dicts.path) {
                try? fm.copyItem(at: dicts, to: base.appendingPathComponent("dicts"))
            }
        }
        conf += "\nquality=\(quality)\n"
        try conf.write(to: base.appendingPathComponent("ElnurTTS.conf"), atomically: true, encoding: .utf8)
        return base.path
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
                           onChunk: (([Float]) -> Void)? = nil,
                           shouldContinue: (() -> Bool)? = nil) throws -> [Float] {
        let voice = try self.voice(id: voiceID)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        synth.relative_rate = max(0.1, rate)
        synth.relative_pitch = max(0.1, pitch)
        synth.relative_volume = max(0.0, volume)
        synth.punctuation_mode = ElnurTTS_punctuation_default
        synth.punctuation_list = nil
        synth.capitals_mode = ElnurTTS_capitals_default
        synth.flags = 0

        let utf8 = Array(trimmed.utf8)
        let ok: Bool = voice.name.withCString { profileC in
            synth.voice_profile = profileC
            return utf8.withUnsafeBufferPointer { buf -> Bool in
                buf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: utf8.count) { textC in
                    guard let message = ElnurTTS_new_message(engine, textC, UInt32(utf8.count),
                                                             ElnurTTS_message_text, &synth, userData) else {
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
    private var resampler = LinearResampler()
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

    func receive(_ data: UnsafePointer<Int16>, count: Int) -> Bool {
        var input = [Float](repeating: 0, count: count)
        for i in 0..<count { input[i] = limit(Float(data[i]) / 32768) }
        let converted = (sampleRate == 0 || sampleRate == outputRate)
            ? input
            : resampler.process(input, from: sampleRate, to: outputRate)
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
        return shouldContinue?() ?? true
    }

    func flush() {
        if !pending.isEmpty {
            onChunk?(pending)
            pending.removeAll()
        }
    }
}

/// Basit dogrusal ornekleme hizi donusturucu (16 kHz -> 24 kHz konusma icin yeterli).
struct LinearResampler {
    private var last: Float = 0
    private var position: Double = 0  // bir onceki bloga gore kesirli konum

    mutating func process(_ input: [Float], from inRate: Int, to outRate: Int) -> [Float] {
        if input.isEmpty { return [] }
        let step = Double(inRate) / Double(outRate)
        var output: [Float] = []
        output.reserveCapacity(Int(Double(input.count) / step) + 2)
        // Konum -1 = onceki blogun son ornegi
        var pos = position
        while pos < Double(input.count - 1) {
            let i = Int(floor(pos))
            let frac = Float(pos - Double(i))
            let a = i < 0 ? last : input[i]
            let b = input[i + 1]
            output.append(a + (b - a) * frac)
            pos += step
        }
        position = pos - Double(input.count)
        last = input[input.count - 1]
        return output
    }
}
