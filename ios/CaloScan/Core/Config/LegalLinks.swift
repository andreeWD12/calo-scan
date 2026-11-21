import Foundation

/// URL pubblici di informativa privacy, termini e supporto (obbligatori per App Store e GDPR).
/// Configurati in Secrets.xcconfig → Info.plist, così si cambiano senza toccare il codice.
enum LegalLinks {
    static var privacyPolicy: URL { url("PRIVACY_POLICY_URL") }
    static var terms: URL { url("TERMS_URL") }
    static var support: URL { url("SUPPORT_URL") }
    /// Contratto di licenza standard Apple, usato se non si fornisce un EULA personalizzato.
    static let appleEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private static func url(_ key: String) -> URL {
        if let s = Bundle.main.object(forInfoDictionaryKey: key) as? String, let u = URL(string: s), u.scheme == "https" {
            return u
        }
        // Valore mancante in configurazione: rimanda alla pagina di supporto di Apple invece di un link rotto.
        return URL(string: "https://www.apple.com/legal/privacy/")!
    }
}
