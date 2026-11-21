import Foundation

/// Configurazione pubblica letta da Info.plist (iniettata da Config/Secrets.xcconfig).
/// Contiene solo valori pubblici: nessun segreto deve mai passare da qui.
struct AppConfig: Sendable {
    let supabaseURL: URL
    let supabaseAnonKey: String
    let googleClientID: String?

    enum ConfigError: LocalizedError {
        case missing(String)
        var errorDescription: String? {
            switch self {
            case .missing(let key):
                "Configurazione mancante: \(key). Copia ios/Config/Secrets.example.xcconfig in Secrets.xcconfig."
            }
        }
    }

    static func load(from bundle: Bundle = .main) throws -> AppConfig {
        func value(_ key: String) -> String? {
            guard let v = bundle.object(forInfoDictionaryKey: key) as? String,
                  !v.isEmpty, !v.hasPrefix("YOUR-"), !v.contains("YOUR-PROJECT") else { return nil }
            return v
        }
        guard let urlString = value("SUPABASE_URL"), let url = URL(string: urlString),
              url.scheme == "https" else { throw ConfigError.missing("SUPABASE_URL") }
        guard let anon = value("SUPABASE_ANON_KEY") else { throw ConfigError.missing("SUPABASE_ANON_KEY") }
        return AppConfig(supabaseURL: url, supabaseAnonKey: anon, googleClientID: value("GIDClientID"))
    }
}
