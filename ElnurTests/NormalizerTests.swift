import XCTest
import ElnurKit

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
}
