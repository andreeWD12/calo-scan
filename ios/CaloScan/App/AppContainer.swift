import SwiftUI
import Supabase

/// Container delle dipendenze. Creato una sola volta all'avvio e passato nell'Environment.
/// Le fasi successive aggiungono qui i servizi concreti (auth, pasti, scanner, abbonamenti…).
@MainActor
final class AppContainer {
    let config: AppConfig
    let supabase: SupabaseClient
    let functions: EdgeFunctionClient

    init(config: AppConfig) {
        self.config = config
        // supabase-swift salva la sessione nel Keychain su iOS e rinnova il token in automatico.
        self.supabase = SupabaseClient(supabaseURL: config.supabaseURL, supabaseKey: config.supabaseAnonKey)
        self.functions = EdgeFunctionClient(client: supabase)
    }
}

private struct AppContainerKey: EnvironmentKey {
    static let defaultValue: AppContainer? = nil
}

extension EnvironmentValues {
    var container: AppContainer? {
        get { self[AppContainerKey.self] }
        set { self[AppContainerKey.self] = newValue }
    }
}
