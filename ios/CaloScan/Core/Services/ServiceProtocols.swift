import Foundation
import CaloScanCore

// Contratti tra ViewModel e dati. Le implementazioni Supabase arrivano nelle fasi 3–8;
// i ViewModel dipendono solo da questi protocolli, così sono testabili con implementazioni in memoria.

enum SessionState: Equatable, Sendable {
    case unknown          // in verifica all'avvio
    case signedOut
    case needsOnboarding(userID: UUID)
    case signedIn(userID: UUID)
}

protocol AuthService: Sendable {
    func currentState() async -> SessionState
    func stateChanges() -> AsyncStream<SessionState>
    func signInWithApple(idToken: String, nonce: String) async throws
    func signInWithGoogle(idToken: String, accessToken: String) async throws
    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String) async throws
    func sendPasswordReset(email: String) async throws
    func signOut() async throws
}

enum Plan: String, Codable, Comparable, Sendable {
    case free, plus, pro
    private var rank: Int { switch self { case .free: 0; case .plus: 1; case .pro: 2 } }
    static func < (l: Plan, r: Plan) -> Bool { l.rank < r.rank }
}

/// Stato dei permessi letto dal server. L'interfaccia lo usa solo per mostrare/nascondere;
/// i controlli reali avvengono nelle Edge Functions.
struct Entitlements: Codable, Equatable, Sendable {
    let plan: Plan
    let scansUsedToday: Int
    let scansLimitToday: Int
    let coachMessagesUsedToday: Int
    let coachMessagesLimitToday: Int
    let expiresAt: Date?
}

protocol EntitlementService: Sendable {
    func refresh() async throws -> Entitlements
}
