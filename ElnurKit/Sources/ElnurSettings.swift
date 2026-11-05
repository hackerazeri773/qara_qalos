import Foundation

/// Uygulama ile VoiceOver ses eklentisi arasinda paylasilan ayarlar (App Group).
/// Ucretsiz Apple hesabiyla kurulumda App Group calismayabilir; o zaman `isShared` false olur
/// ve eklenti varsayilanlari kullanir. Telefon yeniden baslatilip kilit ilk kez acilana kadar
/// da paylasilan ayarlar okunamaz; o arada da varsayilanlar kullanilir.
public enum ElnurSettings {
    public static let groupID = "group.az.elnurtts.shared"
    static let russianPartnerKey = "russianPartnerVoice"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    /// Uygulama ile eklenti gercekten ayni ayarlari goruyor mu?
    public static var isShared: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    /// Azerbaycanca/Turkce seslerin Rusca (Kiril) metinde gecis yaptigi ses: "Svetlana", "Dimitry"
    /// ya da nil (otomatik: ana sesle ayni cinsiyet).
    public static var russianPartner: String? {
        get { defaults?.string(forKey: russianPartnerKey) }
        set {
            if let newValue { defaults?.set(newValue, forKey: russianPartnerKey) }
            else { defaults?.removeObject(forKey: russianPartnerKey) }
        }
    }
}
