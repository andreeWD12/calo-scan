import Foundation
import Supabase

/// Token APNs salvato sul server (funzione SQL `register_push_token`): serve solo per le notifiche che partono
/// dal server, come "il tuo premio è pronto". I promemoria restano notifiche locali.
struct SupabasePushTokenService: PushTokenService {
    let client: SupabaseClient
    private static let lastTokenKey = "push.lastToken"

    private struct RegisterParams: Encodable, Sendable { let p_token: String; let p_environment: String }
    private struct UnregisterParams: Encodable, Sendable { let p_token: String }

    func register(deviceToken: String, environment: PushEnvironment) async throws {
        // Senza sessione (prima dell'accesso) non si registra: lo si rifà dopo l'accesso.
        guard (try? await client.auth.session) != nil else { return }
        do {
            try await client.rpc("register_push_token",
                                 params: RegisterParams(p_token: deviceToken, p_environment: environment.rawValue)).execute()
            UserDefaults.standard.set(deviceToken, forKey: Self.lastTokenKey)
        } catch {
            throw APIError.from(error)
        }
    }

    /// All'uscita dall'account: questo iPhone non riceve più notifiche per l'account.
    func unregister() async throws {
        guard let token = UserDefaults.standard.string(forKey: Self.lastTokenKey) else { return }
        do {
            try await client.rpc("unregister_push_token", params: UnregisterParams(p_token: token)).execute()
            UserDefaults.standard.removeObject(forKey: Self.lastTokenKey)
        } catch {
            throw APIError.from(error)
        }
    }
}
