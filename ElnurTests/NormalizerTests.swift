import XCTest
@testable import ElnurKit

/// Android TextNormalizer.kt ile ayni sonuclari vermeli.
final class NormalizerTests: XCTestCase {
    func test0_AndroidRules() throws {
        _ = try ElnurEngine.shared()   // emoji tablosu yolu
        let az: [(String, String)] = [
            ("2-ci", "ikinci"),
            ("20si", "iyirmisi"),
            ("5-ci mərtəbə", "beşinci mərtəbə"),
            ("Telefon: +994 50 123 45 67", "Telefon: plus doqquz yüz doxsan dörd əlli yüz iyirmi üç qırx beş altmış yeddi"),
            ("50%", "50 faiz"),
            ("saat 14:30", "saat 14 30"),
            ("Salam 😀", "Salam, gülən üz"),
            ("25 ₼", "25 Azərbaycan Manatı"),
            ("a & b", "a və b"),
            ("Bakı — paytaxt", "Bakı, paytaxt"),
            ("Hə...", "Hə."),
        ]
        let tr: [(String, String)] = [
            ("4'e", "dörde"),
            ("%50", "yüzde 50"),
            ("3. kat", "3. kat"),
        ]
        var failures: [String] = []
        for (lang, cases) in [("az-AZ", az), ("tr-TR", tr)] {
            for (input, expected) in cases {
                let got = TextNormalizer.normalize(input, language: lang)
                print("NORMALIZE [\(lang)] \(input) => \(got)")
                if got != expected { failures.append("\(input) => \(got) (beklenen: \(expected))") }
            }
        }
        for s in ["25 AZN, 25 ₼, $100, €50", "Qiymət 2+2=4, a<b, x×y", "№5, § 3, • maddə", "Salam 👋 necəsən? 😊"] {
            print("NORMALIZE [elnur] \(s) => \(TextNormalizer.normalize(s, language: "az", options: .elnurTTS))")
        }
        for f in failures { print("NORMALIZE HATA: \(f)") }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func test0e_CharacterSymbolsAz() throws {
        _ = try ElnurEngine.shared()   // emoji/sembol tablosu yolu
        func spoken(_ c: String) -> String {
            let r = SpeechRequestText.parse(ssml: "<speak><say-as interpret-as=\"characters\">\(c)</say-as></speak>")
            return SpeechPlanner.plan(r, language: "az-AZ", engineCharacterMode: true,
                                      engineSilentSymbols: ElnurEngine.characterModeSilentSymbols).map(\.text).joined(separator: " ")
        }
        XCTAssertEqual(spoken("⇒"), "sağa doğru ikili ox")   // CLDR tablosundan
        XCTAssertEqual(spoken("‰"), "promil")                 // elle eklenen
        XCTAssertEqual(spoken("ə"), "ə")                      // harf: motor okur
        print("SEMBOL ⇒ \(spoken("⇒")) | ‰ \(spoken("‰")) | ¤ \(spoken("¤"))")
    }

    func test0f_SchwaKey() {
        func plan(_ t: String, _ lang: String) -> [String] {
            SpeechPlanner.plan(SpeechRequestText.parse(ssml: "<speak><lang xml:lang=\"tr\">\(t)</lang></speak>"),
                               language: lang, engineCharacterMode: true).map { ($0.useCharacterMode ? "K:" : "") + $0.text }
        }
        XCTAssertEqual(plan(" schwa ", "az-AZ").last?.hasSuffix("ə"), true)
        XCTAssertEqual(plan("Büyük schwa", "az-AZ").last?.hasSuffix("Ə"), true)
        XCTAssertEqual(plan("schwa", "tr-TR"), ["schwa"])
    }

    func test0g_TurkishPunctuationNamesAz() {
        let az = "az-AZ"
        XCTAssertEqual(VoiceOverPunctuation.localize("virgül", language: az), "vergül")
        XCTAssertEqual(VoiceOverPunctuation.localize("soru işareti", language: az), "sual işarəsi")
        XCTAssertEqual(VoiceOverPunctuation.localize("Salam virgül  mənim adım Feride nokta", language: az),
                       "Salam vergül  mənim adım Feride nöqtə")
        XCTAssertEqual(VoiceOverPunctuation.localize("1 nokta  Ayarlar sağ ok  Erişilebilirlik", language: az),
                       "1 nöqtə  Ayarlar sağ ox  Erişilebilirlik")
        XCTAssertEqual(VoiceOverPunctuation.localize("noktalı virgül", language: az), "nöqtəli vergül")
        XCTAssertEqual(VoiceOverPunctuation.localize("Rotor Dilleri kesme işareti ne", language: az), "Rotor Dilleri apostrof ne")
        XCTAssertEqual(VoiceOverPunctuation.localize("yıldız", language: az), "ulduz")             // tek basina
        XCTAssertEqual(VoiceOverPunctuation.localize("Yıldız Hanım geldi", language: az), "Yıldız Hanım geldi") // cumle ici: dokunma
        XCTAssertEqual(VoiceOverPunctuation.localize("noktalı yazı", language: az), "noktalı yazı")
        XCTAssertEqual(VoiceOverPunctuation.localize("virgül", language: "tr-TR"), "virgül")
    }

    func test0h_UnicodeLetterNamesAndPitch() {
        func plan(_ t: String) -> [String] {
            SpeechPlanner.plan(SpeechRequestText.parse(ssml: "<speak><lang xml:lang=\"tr\">\(t)</lang></speak>"),
                               language: "az-AZ", engineCharacterMode: true).map { ($0.useCharacterMode ? "K:" : "") + $0.text }
        }
        XCTAssertEqual(plan("cyrillic small letter be"), ["K:б"])
        XCTAssertEqual(plan(" Cyrillic capital letter zhe "), ["K:Ж"])
        XCTAssertEqual(plan("greek small letter alpha"), ["K:α"])
        XCTAssertEqual(plan("Bir cyrillic small letter be yazdı").count, 1)
        let p = SpeechRequestText.parse(ssml: "<speak><prosody pitch=\"-10.000004%\" rate=\"190%\">salam</prosody></speak>")
        XCTAssertEqual(VoiceOverMapping.pitchMultiplier(for: p), 0.9, accuracy: 0.001)
        let q = SpeechRequestText.parse(ssml: "<speak><prosody rate=\"190%\">salam</prosody></speak>")
        XCTAssertEqual(VoiceOverMapping.pitchMultiplier(for: q), 1.0)
    }

    func test0i_AndroidStyleProfile() throws {
        let engine = try ElnurEngine.shared()
        let gulnar = try engine.voice(id: "az.elnurtts.gulnar")
        let auto = engine.voiceProfile(for: gulnar)
        print("PROFIL varsayilan: \(auto)")
        XCTAssertTrue(auto.hasPrefix("Gulnar+"))
        XCTAssertTrue(auto.contains("Svetlana"))
        var ru = ElnurSettings.language("ru"); ru.voice = "Dimitry"; ElnurSettings.setLanguage("ru", ru)
        let chosen = engine.voiceProfile(for: gulnar)
        print("PROFIL Dimitry secili: \(chosen)")
        XCTAssertTrue(chosen.contains("Dimitry") && !chosen.contains("Svetlana"))
        ElnurSettings.setLanguage("ru", .default)
    }

    /// Dimitry + Elnur profili: Latin bolumleri Elnur kendi 16 kHz modeliyle okur, cizirti olmamali.
    func test0j_MixedSampleRateProfileIsClean() throws {
        let engine = try ElnurEngine.shared()
        var az = ElnurSettings.language("az"); az.voice = "Elnur"; ElnurSettings.setLanguage("az", az)
        defer { ElnurSettings.setLanguage("az", .default) }
        let dimitry = try engine.voice(id: "az.elnurtts.dimitry")
        let profile = engine.voiceProfile(for: dimitry)
        print("PROFIL dimitry: \(profile)")
        XCTAssertTrue(profile.contains("Elnur"))
        for id in ["az.elnurtts.dimitry", "az.elnurtts.elnur", "az.elnurtts.faruk"] {
            let x = try engine.synthesize(text: "Salam, Elnur danışır. Привет, это тест. Ayarlar ElnurTTS, səs.", voiceID: id)
            var jumps = 0
            for i in 1..<x.count where abs(x[i] - x[i - 1]) > 0.3 { jumps += 1 }
            print("KARISIK \(id): \(x.count) ornek, \(jumps) sicrama")
            XCTAssertGreaterThan(x.count, 48_000)
            XCTAssertLessThan(Double(jumps) / Double(x.count), 0.001, id)
        }
    }

    func test0k_CapitalSchwaInText() {
        func plan(_ t: String) -> String {
            SpeechPlanner.plan(SpeechRequestText.parse(ssml: "<speak><lang xml:lang=\"tr\">\(t)</lang></speak>"),
                               language: "az-AZ", engineCharacterMode: true).map(\.text).joined(separator: "|")
        }
        XCTAssertEqual(plan(" schwa lavə"), "Əlavə")
        XCTAssertEqual(plan("Ayarlar sağ ok  schwa lçatımlılıq"), "Ayarlar sağ ox  Əlçatımlılıq")
        XCTAssertEqual(plan(" schwa LAV schwa "), "ƏLAVƏ")
        XCTAssertEqual(plan("əlavə"), "əlavə")
        XCTAssertEqual(plan("Bu schwa lavə gəldi"), "Bu Əlavə gəldi")
        XCTAssertEqual(plan("Bu  schwa lavə"), "Bu  Əlavə")
        XCTAssertEqual(plan("schwalavə"), "Əlavə")
        XCTAssertEqual(SpeechPlanner.restoreCapitalSchwa(" schwa lavə", language: "tr-TR"), " schwa lavə")
    }
}
