import Foundation
import Supabase

/// Autenticazione con Supabase Auth: Apple, Google, email e password.
/// La sessione è salvata da supabase-swift nel Keychain e rinnovata in automatico.
/// Dopo l'accesso si controlla se esiste il profilo: se manca, si apre l'onboarding.
struct SupabaseAuthService: AuthService {
    let client: SupabaseClient

    /// Link delle email (conferma registrazione, recupero password). Deve essere tra i Redirect URL
    /// di Supabase › Authentication › URL Configuration ed è registrato come schema in Info.plist.
    static let callbackURL = URL(string: "caloscan://auth-callback")!

    func currentState() async -> SessionState {
        // `session` rinnova il token se è scaduto; senza sessione valida l'utente è disconnesso.
        guard let session = try? await client.auth.session else { return .signedOut }
        return await state(for: session.user.id)
    }

    func stateChanges() -> AsyncStream<SessionState> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, session) in client.auth.authStateChanges {
                    switch event {
                    case .signedIn:
                        if let session { continuation.yield(await state(for: session.user.id)) }
                    case .signedOut, .userDeleted:
                        continuation.yield(.signedOut)
                    default:
                        // initialSession è già gestita da currentState(); token rinnovati e
                        // modifiche all'utente non cambiano la schermata.
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        try await perform {
            try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
        }
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        try await perform {
            try await client.auth.signInWithIdToken(credentials: .init(provider: .google, idToken: idToken, accessToken: accessToken))
        }
    }

    func signIn(email: String, password: String) async throws {
        try await perform { try await client.auth.signIn(email: email, password: password) }
    }

    func signUp(email: String, password: String) async throws -> Bool {
        try await perform {
            let response = try await client.auth.signUp(email: email, password: password, redirectTo: Self.callbackURL)
            // Senza sessione serve la conferma via email (impostazione "Confirm email" di Supabase).
            return response.session == nil
        }
    }

    func sendPasswordReset(email: String) async throws {
        try await perform { try await client.auth.resetPasswordForEmail(email, redirectTo: Self.callbackURL) }
    }

    func updatePassword(_ password: String) async throws {
        try await perform { _ = try await client.auth.update(user: UserAttributes(password: password)) }
    }

    func signOut() async throws {
        try await perform { try await client.auth.signOut() }
        // Il profilo locale in cache non deve sopravvivere all'uscita.
        UserDefaults.standard.removeObject(forKey: Self.onboardedKey)
    }

    func handle(url: URL) async -> AuthCallback {
        guard url.scheme == Self.callbackURL.scheme, url.host == Self.callbackURL.host else { return .notHandled }
        do {
            _ = try await client.auth.session(from: url)
            // Il link di recupero password porta "type=recovery" nell'URL (query o frammento).
            return url.absoluteString.contains("type=recovery") ? .passwordRecovery : .signedIn
        } catch {
            Log.auth.error("Link di accesso non valido o scaduto")
            return .failed
        }
    }

    // MARK: Onboarding completato?

    /// Ultimo utente di cui sappiamo che ha completato l'onboarding: serve solo offline,
    /// per non riproporre l'onboarding a chi l'ha già fatto. Non contiene dati personali.
    private static let onboardedKey = "auth.onboardedUserID"

    static func markOnboarded(userID: UUID) {
        UserDefaults.standard.set(userID.uuidString, forKey: onboardedKey)
    }

    private struct ProfileRow: Decodable { let userId: UUID
        enum CodingKeys: String, CodingKey { case userId = "user_id" } }

    private func state(for userID: UUID) async -> SessionState {
        do {
            let rows: [ProfileRow] = try await client.from("profiles")
                .select("user_id")
                .eq("user_id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value
            if rows.isEmpty { return .needsOnboarding(userID: userID) }
            Self.markOnboarded(userID: userID)
            return .signedIn(userID: userID)
        } catch {
            Log.auth.error("Verifica del profilo non riuscita, uso lo stato salvato")
            let cached = UserDefaults.standard.string(forKey: Self.onboardedKey)
            return cached == userID.uuidString ? .signedIn(userID: userID) : .needsOnboarding(userID: userID)
        }
    }

    private func perform<T>(_ work: () async throws -> T) async throws -> T {
        do { return try await work() }
        catch let error as AuthError { throw Self.map(error) }
        catch { throw APIError.from(error) }
    }

    /// Messaggi chiari per gli errori più comuni, senza rivelare se un'email è registrata.
    private static func map(_ error: AuthError) -> APIError {
        switch error.errorCode {
        case .invalidCredentials:
            .invalidInput(String(localized: "Email o password non corrette."))
        case .emailNotConfirmed:
            .invalidInput(String(localized: "Conferma prima la tua email: apri il link che ti abbiamo inviato."))
        case .weakPassword:
            .invalidInput(String(localized: "La password è troppo debole: usa almeno 8 caratteri con maiuscole, minuscole e cifre."))
        case .overEmailSendRateLimit, .overRequestRateLimit:
            .invalidInput(String(localized: "Troppi tentativi. Aspetta qualche minuto e riprova."))
        case .userAlreadyExists, .emailExists:
            .invalidInput(String(localized: "Non è stato possibile creare l'account. Se sei già registrato, accedi o recupera la password."))
        case .samePassword:
            .invalidInput(String(localized: "La nuova password deve essere diversa da quella attuale."))
        default:
            .unknown
        }
    }
}
