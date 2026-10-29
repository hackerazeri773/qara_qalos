import AVFoundation
import os
import ElnurKit

/// VoiceOver ve diger sistem okuyuculari icin ElnurTTS seslerini ureten Audio Unit.
public final class ElnurAudioUnit: AVSpeechSynthesisProviderAudioUnit {

    private static let log = Logger(subsystem: "az.elnurtts", category: "synth")

    private let format: AVAudioFormat
    private var outputBus: AUAudioUnitBus
    private var _outputBusses: AUAudioUnitBusArray!

    private let stream = SampleStream()
    private let workQueue = DispatchQueue(label: "az.elnurtts.synthesis", qos: .userInitiated)

    @objc
    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        let sampleRate = Double((try? ElnurVoiceCatalog.load())?.outputSampleRate ?? 24_000)
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        outputBus = try AUAudioUnitBus(format: format)
        try super.init(componentDescription: componentDescription, options: options)
        _outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    // MARK: - Sesler

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get {
            guard let catalog = try? ElnurVoiceCatalog.load() else { return [] }
            return catalog.voices.map { info in
                let voice = AVSpeechSynthesisProviderVoice(name: info.displayName,
                                                           identifier: info.id,
                                                           primaryLanguages: [info.language],
                                                           supportedLanguages: [info.language])
                voice.gender = info.gender == "male" ? .male : .female
                voice.version = "6.15.5"
                return voice
            }
        }
        set {}
    }

    public override var outputBusses: AUAudioUnitBusArray { _outputBusses }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
    }

    // MARK: - Istekler

    public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
        let token = stream.begin()
        let ssml = speechRequest.ssmlRepresentation
        let request = SpeechRequestText.parse(ssml: ssml)
        let voiceID = speechRequest.voice.identifier
        let rate = VoiceOverMapping.rateMultiplier(for: request)
        let pitch = VoiceOverMapping.pitchMultiplier(for: request)
        let volume = VoiceOverMapping.volumeMultiplier(for: request)
        Self.log.info("SSML rate=\(request.rawRate ?? "-", privacy: .public) pitch=\(request.rawPitch ?? "-", privacy: .public) volume=\(request.rawVolume ?? "-", privacy: .public) -> x\(rate, privacy: .public)")
        DiagnosticsLog.record(ssml: ssml, rate: rate, pitch: pitch, volume: volume)

        // Tani modu: metinde "elnurtts tani" geciyorsa son isteklerin degerlerini seslendir.
        let lowered = request.text.lowercased()
        let isDiagnostic = lowered.contains("elnurtts tanı") || lowered.contains("elnurtts tani")
        let text: String
        if isDiagnostic {
            text = RequestHistory.shared.spokenSummary()
        } else {
            text = request.text
        }

        let stream = self.stream
        workQueue.async {
            var peak: Float = 0
            var limited = 0
            do {
                let engine = try ElnurEngine.shared()
                for sentence in TextSplitter.sentences(text) {
                    guard stream.isCurrent(token) else { return }
                    _ = try engine.synthesize(text: sentence, voiceID: voiceID,
                                              rate: rate, pitch: pitch, volume: volume,
                                              onChunk: { chunk in stream.append(chunk, token: token) },
                                              shouldContinue: { stream.isCurrent(token) })
                    peak = max(peak, engine.lastPeak)
                    limited += engine.lastLimitedSamples
                }
            } catch {
                Self.log.error("Sentez hatasi: \(error.localizedDescription, privacy: .public)")
            }
            if !isDiagnostic {
                RequestHistory.shared.add(rawRate: request.rawRate, rawPitch: request.rawPitch,
                                          rawVolume: request.rawVolume, rate: rate, volume: volume,
                                          peak: peak, limited: limited)
            }
            stream.finish(token: token)
        }
    }

    public override func cancelSpeechRequest() {
        stream.cancel()
    }

    // MARK: - Ses cikisi

    public override var internalRenderBlock: AUInternalRenderBlock {
        let stream = self.stream
        return { actionFlags, _, frameCount, _, outputAudioBufferList, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
            guard let first = buffers.first, let raw = first.mData else { return noErr }
            let frames = raw.assumingMemoryBound(to: Float.self)
            let done = stream.read(into: frames, count: Int(frameCount))
            if buffers.count > 1 {
                for i in 1..<buffers.count {
                    if let other = buffers[i].mData {
                        other.copyMemory(from: raw, byteCount: Int(frameCount) * MemoryLayout<Float>.size)
                    }
                }
            }
            if done {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
            }
            return noErr
        }
    }
}

/// Arka plandaki sentez ile ses cikisi arasinda guvenli ornek kuyrugu.
final class SampleStream {
    private let condition = NSCondition()
    private var samples: [Float] = []
    private var readIndex = 0
    private var finished = true
    private var generation = 0

    func begin() -> Int {
        condition.lock()
        defer { condition.unlock() }
        generation += 1
        samples.removeAll(keepingCapacity: true)
        readIndex = 0
        finished = false
        condition.broadcast()
        return generation
    }

    func cancel() {
        condition.lock()
        defer { condition.unlock() }
        generation += 1
        samples.removeAll()
        readIndex = 0
        finished = true
        condition.broadcast()
    }

    func isCurrent(_ token: Int) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return token == generation
    }

    func append(_ newSamples: [Float], token: Int) {
        condition.lock()
        defer { condition.unlock() }
        guard token == generation else { return }
        samples.append(contentsOf: newSamples)
        condition.broadcast()
    }

    func finish(token: Int) {
        condition.lock()
        defer { condition.unlock() }
        guard token == generation else { return }
        finished = true
        condition.broadcast()
    }

    /// `count` kadar ornek yazar (eksikse sessizlikle doldurur). Donus: istek bitti mi?
    func read(into destination: UnsafeMutablePointer<Float>, count: Int) -> Bool {
        condition.lock()
        defer { condition.unlock() }

        let deadline = Date().addingTimeInterval(3.0)
        while readIndex >= samples.count && !finished {
            if !condition.wait(until: deadline) { break }
        }

        let available = samples.count - readIndex
        let n = max(0, min(available, count))
        if n > 0 {
            samples.withUnsafeBufferPointer { src in
                destination.update(from: src.baseAddress! + readIndex, count: n)
            }
            readIndex += n
        }
        if n < count {
            (destination + n).update(repeating: 0, count: count - n)
        }
        if readIndex > 200_000 {
            samples.removeFirst(readIndex)
            readIndex = 0
        }
        return finished && readIndex >= samples.count
    }
}

/// Eklentinin aldigi son isteklerin degerleri (tani icin, yalnizca bellekte).
final class RequestHistory {
    static let shared = RequestHistory()

    struct Entry {
        let rawRate: String?
        let rawPitch: String?
        let rawVolume: String?
        let rate: Double
        let volume: Double
        let peak: Float
        let limited: Int
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    func add(rawRate: String?, rawPitch: String?, rawVolume: String?,
             rate: Double, volume: Double, peak: Float, limited: Int) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(Entry(rawRate: rawRate, rawPitch: rawPitch, rawVolume: rawVolume,
                             rate: rate, volume: volume, peak: peak, limited: limited))
        if entries.count > 20 { entries.removeFirst(entries.count - 20) }
    }

    /// Sayilari motorun rahat okuyacagi bicimde yazar: "42.5%" -> "42 virgül 5 yüzde".
    private static func speakable(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "yok" }
        var t = raw
        t = t.replacingOccurrences(of: "%", with: " yüzde")
        t = t.replacingOccurrences(of: "dB", with: " desibel")
        t = t.replacingOccurrences(of: "+", with: "artı ")
        t = t.replacingOccurrences(of: "-", with: "eksi ")
        t = t.replacingOccurrences(of: ".", with: " virgül ")
        return t
    }

    private static func number(_ x: Double) -> String {
        String(format: "%.2f", x).replacingOccurrences(of: ".", with: " virgül ")
    }

    func spokenSummary() -> String {
        lock.lock()
        let recent = entries.suffix(3)
        let total = entries.count
        let limitedTotal = entries.reduce(0) { $0 + $1.limited }
        lock.unlock()
        guard !recent.isEmpty else { return "ElnurTTS tanı. Henüz kayıtlı istek yok." }
        var parts = ["ElnurTTS tanı. Son \(total) istekte sınırlayıcıya takılan örnek sayısı \(limitedTotal)."]
        for (i, e) in recent.reversed().enumerated() {
            parts.append("İstek \(i + 1). Hız \(Self.speakable(e.rawRate)). Ses \(Self.speakable(e.rawVolume)). Perde \(Self.speakable(e.rawPitch)). Motor hızı \(Self.number(e.rate)). Motor sesi \(Self.number(e.volume)). Tepe \(Self.number(Double(e.peak))). Sınırlanan \(e.limited).")
        }
        return parts.joined(separator: " ")
    }
}
