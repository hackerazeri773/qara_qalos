import XCTest
import ElnurKit

/// Her test durumunu eklentinin kod yolundan gecirir (SSML -> metin -> cumleler -> motor)
/// ve sonucu raporlar: sure, sesli kisim, sessiz kalan durumlar.
final class TextCoverageTests: XCTestCase {

    private var outputDirectory: URL {
        let path = ProcessInfo.processInfo.environment["ELNUR_OUT"]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("out").path
        let url = URL(fileURLWithPath: path).appendingPathComponent("metin")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 10 ms'lik pencerelerde enerjisi esigi asan toplam sure (saniye).
    private static func voicedSeconds(_ s: [Float], rate: Int) -> Double {
        let w = rate / 100
        guard w > 0, s.count >= w else { return 0 }
        var voiced = 0
        var i = 0
        while i + w <= s.count {
            var e: Float = 0
            for j in i..<(i + w) { e += s[j] * s[j] }
            if sqrt(e / Float(w)) > 0.02 { voiced += 1 }
            i += w
        }
        return Double(voiced) / 100
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
    }

    func test5_TextCoverage() throws {
        let engine = try ElnurEngine.shared()
        let voices = ["az": "az.elnurtts.gulnar", "tr": "az.elnurtts.ahmet"]
        var lines = ["dil\tno\tdurum\tsure_sn\tsesli_sn\tad\tmetin\tfonem"]
        var silent: [String] = []
        for lang in TextCoverageCases.cases.keys.sorted() {
            guard let voiceID = voices[lang], let cases = TextCoverageCases.cases[lang] else { continue }
            for (index, item) in cases.enumerated() {
                let (name, ssml) = item
                let request = SpeechRequestText.parse(ssml: ssml)
                var samples: [Float] = []
                let chunks = SpeechPlanner.plan(request, language: lang, engineCharacterMode: true,
                                                engineSilentSymbols: ElnurEngine.characterModeSilentSymbols)
                for chunk in chunks {
                    let pieces = chunk.useCharacterMode ? [chunk.text] : TextSplitter.sentences(chunk.text)
                    for piece in pieces {
                        samples += try engine.synthesize(text: piece, voiceID: voiceID, characters: chunk.useCharacterMode)
                    }
                }
                let rate = engine.outputSampleRate
                let seconds = Double(samples.count) / Double(rate)
                let voiced = Self.voicedSeconds(samples, rate: rate)
                let status = voiced < 0.08 ? "SESSIZ" : "ok"
                if status != "ok" { silent.append("\(lang) \(name)") }
                let phonemes = chunks.map { ($0.useCharacterMode ? "[K]" : "") + $0.text }.joined(separator: " / ")
                lines.append([lang, String(format: "%03d", index), status, String(format: "%.2f", seconds),
                              String(format: "%.2f", voiced), Self.clean(name), Self.clean(request.text),
                              Self.clean(phonemes)].joined(separator: "\t"))
                let file = outputDirectory.appendingPathComponent(String(format: "%@_%03d.wav", lang, index))
                try TextCoverageWav.write(samples, sampleRate: rate, to: file)
            }
        }
        try lines.joined(separator: "\n").write(to: outputDirectory.appendingPathComponent("metin_raporu.tsv"),
                                                atomically: true, encoding: .utf8)
        print("METIN TESTI: \(lines.count - 1) durum, sessiz: \(silent.count)")
        for s in silent { print("METIN SESSIZ: \(s)") }
    }
}

enum TextCoverageWav {
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
