import Foundation

/// SSML'nin bir parcasi: duz metin ya da harf harf okunacak bolum
/// (VoiceOver harf harf gezinirken <say-as interpret-as="characters"> gonderir).
public struct SpeechSegment: Equatable {
    public var text: String
    public var isCharacters: Bool
    public init(text: String, isCharacters: Bool) {
        self.text = text
        self.isCharacters = isCharacters
    }
}

/// VoiceOver'in gonderdigi SSML'den duz metin ve hiz/perde bilgisini cikarir.
public struct SpeechRequestText {
    public var text: String
    /// Metnin parcalari (harf harf okunacak bolumler ayri isaretli).
    public var segments: [SpeechSegment] = []
    /// Konusma hizi carpani (1.0 normal, 2.0 iki kat hizli).
    public var rate: Double = 1.0
    /// Perde carpani (1.0 normal).
    public var pitch: Double = 1.0
    /// Ses seviyesi carpani (1.0 normal).
    public var volume: Double = 1.0
    /// SSML'deki ham prosody degerleri (tani icin).
    public var rawRate: String?
    public var rawPitch: String?
    public var rawVolume: String?

    public static func parse(ssml: String) -> SpeechRequestText {
        let handler = SSMLHandler()
        if let data = ssml.data(using: .utf8) {
            let parser = XMLParser(data: data)
            parser.delegate = handler
            if parser.parse() {
                var result = SpeechRequestText(text: handler.text)
                result.segments = handler.segments
                if let r = handler.rate { result.rate = r }
                if let p = handler.pitch { result.pitch = p }
                if let v = handler.volume { result.volume = v }
                result.rawRate = handler.rawRate
                result.rawPitch = handler.rawPitch
                result.rawVolume = handler.rawVolume
                return result
            }
        }
        // SSML degilse veya bozuksa: etiketleri silip duz metin olarak kullan.
        let stripped = ssml.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
        var result = SpeechRequestText(text: stripped)
        result.segments = [SpeechSegment(text: stripped, isCharacters: false)]
        return result
    }

    /// "150%", "+20%", "fast", "1.5" gibi degerleri carpana cevirir.
    static func multiplier(_ raw: String, named: [String: Double]) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let n = named[value] { return n }
        // "-3.0dB", "+6dB" -> dogrusal carpan (iOS VoiceOver ses seviyesini boyle gonderir)
        if value.hasSuffix("db"), let db = Double(value.dropLast(2)) {
            return pow(10, db / 20)
        }
        if value.hasSuffix("%"), let number = Double(value.dropLast()) {
            if value.hasPrefix("+") || value.hasPrefix("-") { return max(0.1, 1.0 + number / 100.0) }
            return max(0.1, number / 100.0)
        }
        if let number = Double(value), number > 0 { return number }
        return nil
    }

    private final class SSMLHandler: NSObject, XMLParserDelegate {
        var text = ""
        var segments: [SpeechSegment] = []
        private var characterDepth = 0
        private var sayAsStack: [Bool] = []

        private func appendSegment(_ string: String, characters: Bool) {
            if let last = segments.last, last.isCharacters == characters {
                segments[segments.count - 1].text += string
            } else {
                segments.append(SpeechSegment(text: string, isCharacters: characters))
            }
        }
        var rate: Double?
        var pitch: Double?
        var volume: Double?
        var rawRate: String?
        var rawPitch: String?
        var rawVolume: String?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String] = [:]) {
            switch elementName.lowercased() {
            case "prosody":
                if let r = attributes["rate"] { rawRate = r }
                if let p = attributes["pitch"] { rawPitch = p }
                if let v = attributes["volume"] { rawVolume = v }
                if let v = attributes["volume"], let m = SpeechRequestText.multiplier(v, named: [
                    "silent": 0, "x-soft": 0.4, "soft": 0.7, "medium": 1.0, "default": 1.0, "loud": 1.3, "x-loud": 1.6]) {
                    volume = m
                }
                if let r = attributes["rate"], let m = SpeechRequestText.multiplier(r, named: [
                    "x-slow": 0.5, "slow": 0.75, "medium": 1.0, "default": 1.0, "fast": 1.5, "x-fast": 2.0]) {
                    rate = m
                }
                if let p = attributes["pitch"], let m = SpeechRequestText.multiplier(p, named: [
                    "x-low": 0.8, "low": 0.9, "medium": 1.0, "default": 1.0, "high": 1.1, "x-high": 1.2]) {
                    pitch = m
                }
            case "say-as":
                let kind = (attributes["interpret-as"] ?? "").lowercased()
                let spell = ["characters", "spell-out", "letters", "verbatim"].contains(kind)
                sayAsStack.append(spell)
                if spell { characterDepth += 1 }
            case "break", "p", "s":
                if !text.isEmpty && !text.hasSuffix(" ") {
                    text += " "
                    appendSegment(" ", characters: false)
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            if elementName.lowercased() == "say-as", let spell = sayAsStack.popLast(), spell {
                characterDepth = max(0, characterDepth - 1)
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
            appendSegment(string, characters: characterDepth > 0)
        }
    }
}

/// Uzun metni cumlelere boler; boylece ilk cumle hemen seslendirilir.
public enum TextSplitter {
    private static let terminators: Set<Character> = [".", "!", "?", "…", "\n", ";"]

    public static func sentences(_ text: String, maxLength: Int = 220) -> [String] {
        let chars = Array(text)
        var result: [String] = []
        var current = ""

        func push() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append(trimmed) }
            current = ""
        }

        for (i, ch) in chars.enumerated() {
            current.append(ch)
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            let atBoundary = next == nil || next!.isWhitespace
            if terminators.contains(ch) && atBoundary {
                push()
            } else if current.count >= maxLength && (ch == "," || ch == " ") {
                push()
            }
        }
        push()
        return result
    }
}
