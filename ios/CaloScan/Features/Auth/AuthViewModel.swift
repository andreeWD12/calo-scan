import Foundation
import AuthenticationServices
import CryptoKit

/// Logica di registrazione, accesso e recupero password.
@Observable
@MainActor
final class AuthViewModel {
    var email = ""
    var password = ""
    var passwordConfirmation = ""
    var acceptedTerms = false
    var confirmedMinimumAge = false

    private(set) var isLoading = false
    private(set) var error: APIError?
    private(set) var infoMessage: String?

    private let auth: any AuthService
    /// Nonce in chiaro della richiesta Apple in corso (Apple riceve solo l'hash SHA-256).
    private var currentNonce: String?

    init(auth: any AuthService) {
        self.auth = auth
    }

    // MARK: Validazione

    var emailError: String? {
        guard !email.isEmpty else { return nil }
        return Self.isValidEmail(email) ? nil : String(localized: "Inserisci un indirizzo email valido.")
    }

    var passwordError: String? {
        guard !password.isEmpty else { return nil }
        return Self.passwordIssues(password).first
    }

    var confirmationError: String? {
        guard !passwordConfirmation.isEmpty else { return nil }
        return password == passwordConfirmation ? nil : String(localized: "Le password non coincidono.")
    }

    var canSignIn: Bool { Self.isValidEmail(email) && !password.isEmpty }

    var canSignUp: Bool {
        Self.isValidEmail(email) && Self.passwordIssues(password).isEmpty
            && password == passwordConfirmation && acceptedTerms && confirmedMinimumAge
    }

    static func isValidEmail(_ s: String) -> Bool {
        s.wholeMatch(of: /[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/) != nil
    }

    /// Regole allineate a `supabase/config.toml` (min 8, maiuscole, minuscole, cifre).
    static func passwordIssues(_ p: String) -> [String] {
        var issues: [String] = []
        if p.count < 8 { issues.append(String(localized: "Almeno 8 caratteri.")) }
        if p.rangeOfCharacter(from: .uppercaseLetters) == nil { issues.append(String(localized: "Almeno una lettera maiuscola.")) }
        if p.rangeOfCharacter(from: .lowercaseLetters) == nil { issues.append(String(localized: "Almeno una lettera minuscola.")) }
        if p.rangeOfCharacter(from: .decimalDigits) == nil { issues.append(String(localized: "Almeno una cifra.")) }
        return issues
    }

    // MARK: Azioni

    func signIn() async {
        await run { try await self.auth.signIn(email: self.trimmedEmail, password: self.password) }
    }

    func signUp() async {
        await run {
            let needsConfirmation = try await self.auth.signUp(email: self.trimmedEmail, password: self.password)
            if needsConfirmation {
                self.infoMessage = String(localized: "Ti abbiamo inviato un'email di conferma. Apri il link per attivare l'account.")
            }
        }
    }

    func sendPasswordReset() async {
        await run {
            try await self.auth.sendPasswordReset(email: self.trimmedEmail)
            // Messaggio identico che l'email esista o no, per non rivelare quali account sono registrati.
            self.infoMessage = String(localized: "Se esiste un account con questa email, riceverai un link per reimpostare la password.")
        }
    }

    // MARK: Sign in with Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            self.error = .unknown
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                self.error = .unknown
                return
            }
            await run { try await self.auth.signInWithApple(idToken: token, nonce: nonce) }
        }
    }

    // MARK: Google

    func signInWithGoogle() async {
        await run {
            let tokens = try await GoogleSignInCoordinator.signIn()
            try await self.auth.signInWithGoogle(idToken: tokens.idToken, accessToken: tokens.accessToken)
        }
    }

    func dismissError() { error = nil }

    // MARK: Supporto

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        infoMessage = nil
        defer { isLoading = false }
        do { try await operation() }
        catch GoogleSignInCoordinator.Failure.cancelled { }
        catch { self.error = APIError.from(error) }
    }

    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
