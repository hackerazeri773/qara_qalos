import XCTest
import AVFoundation
import ElnurKit

/// iPhone simulatorunde calisan testler.
/// 1) Motor 12 sesin hepsini goruyor mu?
/// 2) Her ses Linux'taki referans motorla ayni uzunlukta/seviyede konusuyor mu? (WAV kaydedilir)
/// 3) Hiz carpani calisiyor mu (Sonic)?
/// 4) Sistem (AVSpeechSynthesizer) eklentimizi goruyor mu?
final class ElnurTests: XCTestCase {

    struct Reference: Decodable {
        let voice: String
        let text: String
        let seconds: Double
        let engineSampleRate: Int
        let rms: Double
    }

    private func references() throws -> [Reference] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reference", withExtension: "json"))
        return try JSONDecoder().decode([Reference].self, from: Data(contentsOf: url))
    }

    private var outputDirectory: URL {
        let path = ProcessInfo.processInfo.environment["ELNUR_OUT"]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("elnur-out").path
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func rms(_ s: [Float]) -> Double {
        guard !s.isEmpty else { return 0 }
        return sqrt(s.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(s.count))
    }

    func test1_EngineSeesAllVoices() throws {
        let engine = try ElnurEngine.shared()
        let names = try engine.engineVoiceNames()
        print("MOTOR SESLERI: \(names)")
        for voice in engine.voices {
            XCTAssertTrue(names.contains(voice.name), "Motor bu sesi gormuyor: \(voice.name)")
        }
    }

    func test2_SynthesizeAllVoices() throws {
        let engine = try ElnurEngine.shared()
        var report: [String] = []
        for (index, ref) in try references().enumerated() {
            let voice = try engine.voice(id: ref.voice)
            let start = Date()
            let samples = try engine.synthesize(text: ref.text, voiceID: ref.voice)
            let elapsed = Date().timeIntervalSince(start)
            let seconds = Double(samples.count) / Double(engine.outputSampleRate)
            let level = Self.rms(samples)
            let line = String(format: "%@ | %.2f sn ses (ref %.2f) | rms %.4f (ref %.4f) | %.2f sn islem",
                              voice.name, seconds, ref.seconds, level, ref.rms, elapsed)
            print("SENTEZ " + line)
            report.append(line)
            XCTAssertEqual(seconds, ref.seconds, accuracy: 0.05, "Sure farkli: \(voice.name)")
            XCTAssertEqual(level, ref.rms, accuracy: ref.rms * 0.15, "Seviye farkli: \(voice.name)")
            try WavWriter.write(samples, sampleRate: engine.outputSampleRate,
                                to: outputDirectory.appendingPathComponent(String(format: "%02d_%@.wav", index + 1, voice.name)))
        }
        try report.joined(separator: "\n").write(to: outputDirectory.appendingPathComponent("rapor.txt"),
                                                 atomically: true, encoding: .utf8)
    }

    func test3_RateChangesDuration() throws {
        let engine = try ElnurEngine.shared()
        let id = "az.elnurtts.gulnar"
        let text = "Salam! Bu gün hava çox gözəldir, elə deyilmi?"
        let normal = try engine.synthesize(text: text, voiceID: id, rate: 1)
        let fast = try engine.synthesize(text: text, voiceID: id, rate: 3)
        let fastest = try engine.synthesize(text: text, voiceID: id, rate: 5)
        print("HIZ normal=\(normal.count) 3x=\(fast.count) 5x=\(fastest.count)")
        XCTAssertLessThan(Double(fast.count), Double(normal.count) * 0.45)
        XCTAssertLessThan(Double(fastest.count), Double(normal.count) * 0.3)
        try WavWriter.write(fast, sampleRate: engine.outputSampleRate, to: outputDirectory.appendingPathComponent("hiz_3x_Gulnar.wav"))
        try WavWriter.write(fastest, sampleRate: engine.outputSampleRate, to: outputDirectory.appendingPathComponent("hiz_5x_Gulnar.wav"))
    }

    func test4_SystemSeesExtension() throws {
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        let ids = Set(try ElnurVoiceCatalog.load().voices.map(\.id))
        var found: [AVSpeechSynthesisVoice] = []
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            found = AVSpeechSynthesisVoice.speechVoices().filter { ids.contains($0.identifier) }
            if !found.isEmpty { break }
            RunLoop.current.run(until: Date().addingTimeInterval(2))
        }
        print("SISTEM SESLERI: \(found.map { "\($0.name) [\($0.language)]" })")
        if found.isEmpty {
            throw XCTSkip("Simulator eklenti seslerini listelemedi (simulatorde beklenen bir durum olabilir).")
        }
    }
}

enum WavWriter {
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
