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
        stream.configure(sampleRate: format.sampleRate)
        _outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        // Motoru hemen arka planda isit (Ukraynaca RHVoice gibi): eklenti yeniden baslatildiginda
        // ilk okumanin gecikmesi kisalir.
        workQueue.async { _ = try? ElnurEngine.shared().warmUp() }
    }

    // MARK: - Sesler

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get {
            guard let catalog = try? ElnurVoiceCatalog.load() else { return [] }
            return catalog.voices.map { info in
                let voice = AVSpeechSynthesisProviderVoice(name: info.displayName,
                                                           identifier: info.id,
                                                           primaryLanguages: [Self.systemLanguage(info.language)],
                                                           supportedLanguages: [Self.systemLanguage(info.language)])
                voice.gender = info.gender == "male" ? .male : .female
                voice.version = "6.15.5"
                return voice
            }
        }
        set {}
    }

    /// iOS'ta Azerbaycanca arayuz yok: "az-AZ" sesleri listede "null" gorunuyor ve VoiceOver
    /// kendi sozlerini (dugme, baslik...) Ingilizce okuyordu. Azerbaycanca sesler sisteme
    /// "tr-AZ" (Turkce, Azerbaycan) olarak tanitilir: VoiceOver sozlerini Turkce okur ve bu dil
    /// "Turkce (Turkiye)"den ayri oldugu icin rotorda ayri secilebilir. Motor yine sesin
    /// gercek dilini (az) kullanir; sayi/emoji/sozluk kurallari degismez.
    static func systemLanguage(_ language: String) -> String {
        language.hasPrefix("az") ? "tr-AZ" : language
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

        let stream = self.stream
        workQueue.async {
            do {
                let engine = try ElnurEngine.shared()
                let language = (try? engine.voice(id: voiceID).language) ?? "az-AZ"
                let chunks: [SpeechChunk] = SpeechPlanner.plan(request, language: language, engineCharacterMode: true,
                                         engineSilentSymbols: ElnurEngine.characterModeSilentSymbols)
                for chunk in chunks {
                    let pieces = chunk.useCharacterMode ? [chunk.text] : TextSplitter.sentences(chunk.text)
                    for piece in pieces {
                        guard stream.isCurrent(token) else { return }
                        _ = try engine.synthesize(text: piece, voiceID: voiceID,
                                                  rate: rate, pitch: pitch, volume: volume,
                                                  characters: chunk.useCharacterMode,
                                                  onChunk: { c in stream.append(c, token: token) },
                                                  shouldContinue: { stream.isCurrent(token) })
                    }
                }
            } catch {
                Self.log.error("Sentez hatasi: \(error.localizedDescription, privacy: .public)")
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
            // Her blokta durumu acikca bildir (iOS 27 daha kati): surüyor / bitti.
            actionFlags.pointee = done ? .offlineUnitRenderAction_Complete : .offlineUnitRenderAction_Render
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
    /// Bu istekte motordan gercek ses geldi mi? Gelmeden once ses cikisi BEKLETILMEZ.
    private var gotAudio = false
    /// Her istegin basina konan sessizlik ve ilk sesin yumusak girisi (ornek sayisi).
    private var leadSamples = 0
    private var fadeSamples = 0

    /// iOS 27: uzun bir bekleyisten sonra ilk okumada (eklenti yeniden baslarken) cikis
    /// bekletilince ses patliyor ve basi kesiliyordu. Ses yolu acilirken kaybolan kisim
    /// bu sessizlik olur; yumusak giris de baslangictaki "tik"i onler.
    func configure(sampleRate: Double) {
        condition.lock()
        defer { condition.unlock() }
        leadSamples = Int(sampleRate * 0.1)
        fadeSamples = Int(sampleRate * 0.005)
    }

    func begin() -> Int {
        condition.lock()
        defer { condition.unlock() }
        generation += 1
        samples.removeAll(keepingCapacity: true)
        // Tam sessizlik yerine duyulmayacak kadar kisik (-60 dB) dolgu: iOS bastaki tam sessizligi
        // kirpiyor gibi; kirpilinca hoparlor uyanirken konusmanin basi ("s") kayboluyordu.
        for _ in 0..<leadSamples { samples.append(Float.random(in: -0.001...0.001)) }
        readIndex = 0
        finished = false
        gotAudio = false
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
        if !gotAudio && !newSamples.isEmpty {
            gotAudio = true
            var faded = newSamples
            let n = min(fadeSamples, faded.count)
            for i in 0..<n { faded[i] *= Float(i) / Float(max(1, n)) }
            samples.append(contentsOf: faded)
        } else {
            samples.append(contentsOf: newSamples)
        }
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

        // Istenen blogun tamami hazir olana kadar bekle. Yarim blogu sessizlikle
        // doldurmak konusmanin icine kisa bosluklar sokar ("takilarak konusma").
        // Ama motordan henuz hic ses gelmediyse (soguk baslangic) bekleme: hemen sessizlik ver.
        // iOS 27 bekletilen ses cikisini kesiyor (patlama + kesik baslangic).
        if gotAudio {
            let deadline = Date().addingTimeInterval(1.0)
            while samples.count - readIndex < count && !finished {
                if !condition.wait(until: deadline) { break }
            }
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
