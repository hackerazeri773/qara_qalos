import Foundation

/// Metni motora vermeden önce hazırlar. Android ESVoice (TextNormalizer.kt) ve Windows
/// (tts_server.py -> normalize_text) ile BİREBİR aynı kurallar; hepsi birlikte güncellenmeli.
///  - emoji ve semboller (CLDR adlarıyla) okunur; emojinin önüne ve arkasına virgül duraklaması
///    Tablo: Voices/emoji_<dil>.txt  (her satır "emoji<TAB>ad")
///  - görünmez yön/biçim işaretleri silinir, NFKC (süslü Unicode harfler düz harfe)
///  - "…" ve ".." -> "."   uzun/orta tire -> virgül
///  - telefon numaraları gruplara ayrılıp sözcüklerle okunur ("+994 50 123 45 67")
///  - saat 14:30 -> "14 30";  sayı + ek: "2-ci" -> "ikinci", "20si" -> "iyirmisi", tr "4'e" -> "dörde"
///  - + & @ # * = % dilin kendi kelimesiyle yazılır
public enum TextNormalizer {

    /// Hangi adımların uygulanacağı. ElnurTTS sayıları, yüzdeyi ve renkli emojileri kendisi
    /// doğru okuduğu için orada yalnızca okumadığı semboller (para birimi, matematik vb.) çevrilir.
    public struct Options: Sendable {
        /// true: yalnızca renkli olmayan semboller (₼ $ © × → ...) tablodan okunur, emojiler motora kalır.
        public var symbolsOnly: Bool
        public var numbers: Bool
        public var percent: Bool
        public var dropUnreadable: Bool
        /// Tabloda olmayan < > | ^ § № • gibi işaretleri de adıyla okut.
        public var nameExtraSymbols: Bool

        public static let full = Options(symbolsOnly: false, numbers: true, percent: true,
                                         dropUnreadable: true, nameExtraSymbols: false)
        public static let elnurTTS = Options(symbolsOnly: true, numbers: false, percent: false,
                                             dropUnreadable: false, nameExtraSymbols: true)
    }

    private static let extraSymbols: Set<Character> = ["<", ">", "|", "^", "§", "№", "•", "‰", "¶", "†"]
    private static let extraNames: [String: [Character: String]] = [
        "az": ["‰": "promil", "¶": "abzas", "†": "xaç"],
        "tr": ["‰": "binde", "¶": "paragraf işareti", "†": "haç"],
    ]

    private static let symbolWords: [String: [Character: String]] = [
        "az": ["+": "plus", "&": "və", "@": "et", "#": "diyez", "*": "ulduz", "=": "bərabərdir", "%": "faiz"],
        "tr": ["+": "artı", "&": "ve", "@": "et", "#": "diyez", "*": "yıldız", "=": "eşittir", "%": "yüzde"],
    ]

    private struct NumWords {
        let units: [String]
        let tens: [String]
        let hundred, thousand, million, billion: String
    }

    private static let numWords: [String: NumWords] = [
        "az": NumWords(
            units: ["sıfır", "bir", "iki", "üç", "dörd", "beş", "altı", "yeddi", "səkkiz", "doqquz"],
            tens: ["", "on", "iyirmi", "otuz", "qırx", "əlli", "altmış", "yetmiş", "səksən", "doxsan"],
            hundred: "yüz", thousand: "min", million: "milyon", billion: "milyard"),
        "tr": NumWords(
            units: ["sıfır", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"],
            tens: ["", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"],
            hundred: "yüz", thousand: "bin", million: "milyon", billion: "milyar"),
    ]

    // Android ile aynı ICU desenleri
    private static let W = #"\p{L}\p{N}_"#
    private static let D = #"\p{Nd}"#
    private static let S = #"[\s ]"#

    private static func re(_ p: String, _ o: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: o)
    }

    private static let invisible = re(#"[­​‌‎‏‪-‮⁠-⁤⁦-⁯﻿]"#)
    private static let variation = re(#"[︎️]"#)
    private static let dots = re(#"\.{2,}"#)
    private static let dash = re("\(S)*[\\u2012\\u2013\\u2014\\u2015]\(S)*")
    private static let phonePattern = re("(?<![\(W)+])(\\+?\\(?\(D){1,4}\\)?(?:[ \\-]\\(?\(D){2,4}\\)?){2,6})(?![\(W)])")
    private static let isoDate = re(#"^\p{Nd}{4}-\p{Nd}{2}-\p{Nd}{2}$"#)
    private static let groupSplit = re(#"[ \-()+]+"#)
    private static let time = re("(?<![\(W):])(\(D){1,2}):(\(D){2})(?![\(D):])")
    private static let numSuffixPattern = re("(?<![\(W).,])(\(D){1,12})[-'\\u2019]?(\\p{L}+)")
    private static let ordinalPattern = re(#"^(?:n?c[ıiuü]|[ıiuü]nc[ıiuü])"#, [.caseInsensitive])
    private static let vowels = Set("aıoueiəöüAIOUEİƏÖÜ")
    private static let pctAfter = re("(\(D)+(?:[.,]\(D)+)?)\(S)*%")
    private static let pctBefore = re("%\(S)*(\(D)+(?:[.,]\(D)+)?)")
    private static let repeatedSym = re(#"([+*#=~_])\1+"#)
    private static let spaces = re(#"[ \t ]{2,}"#)
    private static let spaceBeforePunct = re("\(S)+([,.;:!?])")
    private static let multiComma = re(",(?:\(S)*,)+")
    private static let commaBeforePunct = re(",\(S)*([.;:!?])")
    private static let weakBeforeStrong = re("[,;:]\(S)*([.!?])")
    private static let strongThenComma = re("([.!?;:])\(S)*,")
    private static let leadingWeak = re(#"^[\s ,;:]+"#)
    private static let trailingWeak = re(#"[\s ,;:]+$"#)

    // MARK: - Emoji tablosu

    private final class EmojiTable {
        let map: [String: String]
        let first: Set<UInt32>
        let maxLen: Int
        init(map: [String: String], first: Set<UInt32>, maxLen: Int) {
            self.map = map; self.first = first; self.maxLen = maxLen
        }
    }

    private static let lock = NSLock()
    private static var emojiTables: [String: EmojiTable] = [:]
    /// Tablo dosyasının yeri (ESVoiceCore/ElnurKit kendi paketini verir).
    public static var emojiTableURL: (String) -> URL? = { _ in nil }

    private static func emojiTable(_ lang: String) -> EmojiTable {
        lock.lock()
        defer { lock.unlock() }
        if let t = emojiTables[lang] { return t }
        var map: [String: String] = [:]
        var first = Set<UInt32>()
        var maxLen = 1
        if let url = emojiTableURL(lang), let data = try? Data(contentsOf: url) {
            let content = String(decoding: data, as: UTF8.self)
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let tab = line.firstIndex(of: "\t"), tab > line.startIndex else { continue }
                let key = String(line[..<tab])
                var name = String(line[line.index(after: tab)...])
                while name.hasSuffix("\r") { name.removeLast() }
                if name.isEmpty { continue }
                map[key] = name
                if let f = key.unicodeScalars.first { first.insert(f.value) }
                maxLen = max(maxLen, key.unicodeScalars.count)
            }
        }
        let table = EmojiTable(map: map, first: first, maxLen: maxLen)
        emojiTables[lang] = table
        return table
    }

    // MARK: - Ana işlem

    public static func language(_ code: String) -> String {
        let l = String(code.prefix(2)).lowercased()
        return symbolWords[l] != nil ? l : "tr"
    }

    public static func normalize(_ text: String, language code: String, options: Options = .full) -> String {
        let lang = language(code)
        let words = symbolWords[lang]!
        var t = sub(invisible, text, "")
        if !options.symbolsOnly { t = sub(variation, t, "") }
        t = replaceEmoji(t, lang: lang, symbolsOnly: options.symbolsOnly)
        if !options.symbolsOnly { t = t.precomposedStringWithCompatibilityMapping }
        t = t.replacingOccurrences(of: "…", with: ".")
        t = sub(dots, t, ".")
        t = sub(dash, t, ", ")
        if options.numbers {
            t = replace(phonePattern, t) { g in phone(g[1], words: words, lang: lang) }
            t = replace(time, t) { g in g[1] + " " + g[2] }
            t = replace(numSuffixPattern, t) { g in numSuffix(g, lang: lang) }
        }
        if options.percent {
            if lang == "tr" {
                t = replace(pctAfter, t) { g in "yüzde " + g[1] }
                t = replace(pctBefore, t) { g in "yüzde " + g[1] }
            } else {
                t = replace(pctAfter, t) { g in g[1] + " " + words["%"]! }
                t = replace(pctBefore, t) { g in g[1] + " " + words["%"]! }
            }
        }
        t = sub(repeatedSym, t, " ")
        for sym in (options.percent ? "+&@#*=%" : "+&@#*=") {
            t = t.replacingOccurrences(of: String(sym), with: " " + words[sym]! + " ")
        }
        t = t.replacingOccurrences(of: "~", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        if !options.symbolsOnly { t = t.replacingOccurrences(of: "\u{200D}", with: "") }
        if options.nameExtraSymbols {
            var out = ""
            for c in t {
                if extraSymbols.contains(c),
                   let name = extraNames[lang]?[c] ?? SpeechPlanner.symbolName(c, language: lang) {
                    out += " \(name) "
                } else {
                    out.append(c)
                }
            }
            t = out
        }
        if options.dropUnreadable { t = dropUnreadable(t) }
        t = sub(spaces, t, " ")
        t = sub(spaceBeforePunct, t, "$1")
        t = sub(multiComma, t, ",")
        t = sub(commaBeforePunct, t, "$1")
        t = sub(weakBeforeStrong, t, "$1")
        t = sub(strongThenComma, t, "$1")
        t = sub(leadingWeak, t, "")
        t = sub(trailingWeak, t, "")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tek bir karakterin (harf harf okumada) emoji/sembol tablosundaki adı.
    public static func emojiName(_ c: Character, language code: String) -> String? {
        let key = String(String.UnicodeScalarView(c.unicodeScalars.filter { $0.value != 0xFE0F && $0.value != 0xFE0E }))
        return emojiTable(language(code)).map[key]
    }

    // MARK: - Emoji

    private static func isPictographic(_ cps: ArraySlice<Unicode.Scalar>) -> Bool {
        cps.contains { s in
            let cp = s.value
            return cp >= 0x1F000 || (0x2600...0x27BF).contains(cp) || (0x2B00...0x2BFF).contains(cp)
                || cp == 0x200D || cp == 0x20E3
        }
    }

    private static func replaceEmoji(_ t: String, lang: String, symbolsOnly: Bool) -> String {
        let table = emojiTable(lang)
        if table.map.isEmpty { return t }
        let cps = Array(t.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        let n = cps.count
        while i < n {
            let cp = cps[i]
            if table.first.contains(cp.value) {
                var matched = false
                var k = min(table.maxLen, n - i)
                while k > 0 {
                    let slice = cps[i..<(i + k)]
                    if let name = table.map[String(String.UnicodeScalarView(slice))],
                       !(symbolsOnly && isPictographic(slice)) {
                        let piece = isPictographic(slice) ? ", \(name), " : " \(name) "
                        out.append(contentsOf: piece.unicodeScalars)
                        i += k
                        matched = true
                        break
                    }
                    k -= 1
                }
                if !matched {
                    out.append(cp)
                    i += 1
                }
                continue
            }
            // yetim ten rengi / birleştirici: atla
            if !symbolsOnly, (0x1F3FB...0x1F3FF).contains(cp.value) || cp.value == 0x200D || cp.value == 0x20E3 {
                i += 1
                continue
            }
            out.append(cp)
            i += 1
        }
        return String(out)
    }

    // MARK: - Sayılar

    public static func numberWords(_ n0: Int64, language code: String) -> [String] {
        let w = numWords[language(code)]!
        if n0 == 0 { return [w.units[0]] }
        func under1000(_ x: Int) -> [String] {
            var r: [String] = []
            let h = x / 100, rest = x % 100
            if h > 0 {
                if h == 1 { r.append(w.hundred) } else { r.append(w.units[h]); r.append(w.hundred) }
            }
            let tt = rest / 10, u = rest % 10
            if tt > 0 { r.append(w.tens[tt]) }
            if u > 0 { r.append(w.units[u]) }
            return r
        }
        var words: [String] = []
        var n = n0
        for (scale, name) in [(Int64(1_000_000_000), w.billion), (1_000_000, w.million), (1000, w.thousand)] {
            let q = Int(n / scale)
            n %= scale
            if q > 0 {
                if q == 1 && scale == 1000 { words.append(name) } else { words += under1000(q); words.append(name) }
            }
        }
        words += under1000(Int(n))
        return words
    }

    private static func soften(_ word: String, lang: String) -> String {
        lang == "tr" && word == "dört" ? String(word.dropLast()) + "d" : word
    }

    private static func ordinal(_ word: String, lang: String) -> String {
        let last = word.last(where: { vowels.contains($0) })?.lowercased().first ?? "i"
        let h: String
        switch last {
        case "a", "ı": h = "ı"
        case "o", "u": h = "u"
        case "ö", "ü": h = "ü"
        default: h = "i"
        }
        if let l = word.last, vowels.contains(l) { return word + "nc" + h }
        return soften(word, lang: lang) + h + "nc" + h
    }

    private static func numSuffix(_ g: [String], lang: String) -> String {
        let digits = g[1], suffix = g[2]
        if !suffix.contains(where: { vowels.contains($0) }) { return g[0] }   // 5km, 15m gibi birimler
        guard let value = Int64(digits) else { return g[0] }
        var words = numberWords(value, language: lang)
        let ns = suffix as NSString
        if let m = ordinalPattern.firstMatch(in: suffix, range: NSRange(location: 0, length: ns.length)) {
            words[words.count - 1] = ordinal(words.last!, lang: lang)
            return words.joined(separator: " ") + ns.substring(from: m.range.location + m.range.length)
        }
        if let f = suffix.first, vowels.contains(f) { words[words.count - 1] = soften(words.last!, lang: lang) }
        words[words.count - 1] = words.last! + suffix
        return words.joined(separator: " ")
    }

    private static func groupWords(_ g: String, lang: String) -> String {
        let rest = String(g.drop(while: { $0 == "0" }))
        let zeros = g.count - rest.count
        var w = Array(repeating: numWords[lang]!.units[0], count: zeros)
        if !rest.isEmpty, let v = Int64(rest) { w += numberWords(v, language: lang) }
        return w.joined(separator: " ")
    }

    private static func phone(_ s: String, words: [Character: String], lang: String) -> String {
        let digits = s.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        let ns = s as NSString
        var groups: [String] = []
        var last = 0
        for m in groupSplit.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            groups.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        groups.append(ns.substring(from: last))
        groups = groups.filter { !$0.isEmpty }
        let isDate = isoDate.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) != nil
        if digits.count < 7 || isDate || groups.isEmpty { return s }
        // 1 200 000 gibi binlik gruplu sayı: ilk grup 1-3 hane, diğerleri tam 3 hane, başında + ( 0 yok
        if !s.hasPrefix("+") && !s.hasPrefix("(") && !s.hasPrefix("0")
            && (1...3).contains(groups[0].count) && groups.dropFirst().allSatisfy({ $0.count == 3 }) {
            return s
        }
        var out = groups.map { groupWords($0, lang: lang) }.joined(separator: " ")
        if s.hasPrefix("+") { out = words["+"]! + " " + out }
        return " \(out) "
    }

    // MARK: - Yardımcılar

    /// Tabloda olmayan ve okunamayan semboller (So), vekil/özel kullanım/atanmamış karakterler
    private static func dropUnreadable(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            switch u.properties.generalCategory {
            case .otherSymbol, .surrogate, .privateUse, .unassigned: continue
            default: out.append(u)
            }
        }
        return String(out)
    }

    private static func sub(_ r: NSRegularExpression, _ s: String, _ template: String) -> String {
        r.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length),
                                   withTemplate: template)
    }

    private static func replace(_ r: NSRegularExpression, _ s: String, _ f: ([String]) -> String) -> String {
        let ns = s as NSString
        let matches = r.matches(in: s, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return s }
        var out = ""
        var last = 0
        for m in matches {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            var groups: [String] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            out += f(groups)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}
