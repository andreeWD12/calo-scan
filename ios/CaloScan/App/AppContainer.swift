import Foundation
import Supabase

/// Client di infrastruttura condivisi dai servizi live. Creato una sola volta all'avvio.
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
