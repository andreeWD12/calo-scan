import Foundation
import CaloScanCore

// Contratti tra ViewModel e dati. I ViewModel dipendono solo da questi protocolli:
// le implementazioni Supabase vengono collegate fase per fase (vedi `AppServices.live`).

enum SessionState: Equatable, Sendable {
    case unknown          // in verifica all'avvio
    case signedOut
    case needsOnboarding(userID: UUID)
    case signedIn(userID: UUID)
}

// MARK: - Autenticazione

protocol AuthService: Sendable {
    func currentState() async -> SessionState
    func stateChanges() -> AsyncStream<SessionState>
    func signInWithApple(idToken: String, nonce: String) async throws
    func signInWithGoogle(idToken: String, accessToken: String) async throws
    func signIn(email: String, password: String) async throws
    /// Ritorna `true` se serve la conferma via email prima del primo accesso.
    func signUp(email: String, password: String) async throws -> Bool
    func sendPasswordReset(email: String) async throws
    func signOut() async throws
}

// MARK: - Profilo

protocol ProfileRepository: Sendable {
    func loadProfile() async throws -> UserProfile?
    func loadTargets() async throws -> DailyTargets?
    /// Salva profilo e obiettivi. Il server rivalida gli obiettivi con le soglie di sicurezza.
    func save(profile: UserProfile, targets: DailyTargets) async throws
}

// MARK: - Diario e alimenti

protocol MealRepository: Sendable {
    func dayLog(for day: Date) async throws -> DayLog
    func dayLogs(from start: Date, to end: Date) async throws -> [DayLog]
    func save(_ meal: Meal) async throws
    func delete(mealID: UUID) async throws
}

protocol FoodSearchService: Sendable {
    func search(_ query: String) async throws -> [FoodItem]
    func lookup(barcode: String) async throws -> FoodItem?
}

protocol ScanService: Sendable {
    /// Invia la foto (già ridimensionata e senza metadati) all'analisi server-side.
    func analyze(jpegData: Data) async throws -> ScanResult
}

// MARK: - Coach

struct CoachInsight: Identifiable, Codable, Hashable, Sendable {
    enum Tone: String, Codable, Sendable { case positive, suggestion, info }
    let id: UUID
    let text: String
    let tone: Tone
}

struct CoachMessage: Identifiable, Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    let id: UUID
    let role: Role
    let text: String
    let createdAt: Date
}

protocol CoachService: Sendable {
    func dailyInsights() async throws -> [CoachInsight]
    func history() async throws -> [CoachMessage]
    func send(_ text: String) async throws -> CoachMessage
}

// MARK: - Progressi

protocol WeightRepository: Sendable {
    func entries() async throws -> [WeightEntry]
    func add(_ entry: WeightEntry) async throws
    func delete(entryID: UUID) async throws
    func measurements() async throws -> [BodyMeasurement]
    func add(_ measurement: BodyMeasurement) async throws
}

// MARK: - Abbonamenti

enum Plan: String, Codable, Comparable, Sendable, CaseIterable {
    case free, plus, pro
    private var rank: Int { switch self { case .free: 0; case .plus: 1; case .pro: 2 } }
    static func < (l: Plan, r: Plan) -> Bool { l.rank < r.rank }

    var displayName: String {
        switch self { case .free: "Free"; case .plus: "Plus"; case .pro: "Pro" }
    }
}

/// Stato dei permessi letto dal server. L'interfaccia lo usa solo per mostrare o nascondere;
/// i controlli reali avvengono nelle Edge Functions.
struct Entitlements: Codable, Equatable, Sendable {
    let plan: Plan
    let scansUsedToday: Int
    let scansLimitToday: Int
    let coachMessagesUsedToday: Int
    let coachMessagesLimitToday: Int
    let expiresAt: Date?
    let willRenew: Bool

    static let free = Entitlements(plan: .free, scansUsedToday: 0, scansLimitToday: 3,
                                   coachMessagesUsedToday: 0, coachMessagesLimitToday: 5,
                                   expiresAt: nil, willRenew: false)

    var scansRemaining: Int { max(scansLimitToday - scansUsedToday, 0) }
}

protocol EntitlementService: Sendable {
    func refresh() async throws -> Entitlements
}

/// Prodotto in vendita, costruito dai dati di StoreKit (prezzi localizzati da Apple, mai scritti nel codice).
struct PlanOffer: Identifiable, Hashable, Sendable {
    enum Period: String, Sendable { case monthly, yearly }
    let id: String               // product ID App Store
    let plan: Plan
    let period: Period
    let displayPrice: String
    let pricePerMonthText: String?
    let introOffer: String?
}

enum PurchaseOutcome: Sendable { case purchased, pending, cancelled }

protocol PurchaseService: Sendable {
    func offers() async throws -> [PlanOffer]
    func purchase(offerID: String) async throws -> PurchaseOutcome
    func restore() async throws
}

// MARK: - Account e privacy

struct ConsentState: Codable, Equatable, Sendable {
    var healthDataProcessing: Bool      // art. 9(2)(a) GDPR, obbligatorio per usare l'app
    var aiImageAnalysis: Bool           // invio foto al fornitore AI
    var productEmails: Bool             // facoltativo
}

protocol AccountService: Sendable {
    func consents() async throws -> ConsentState
    func update(consents: ConsentState) async throws
    /// Esporta tutti i dati dell'utente (art. 20 GDPR) e ritorna un file JSON locale.
    func exportData() async throws -> URL
    /// Cancella definitivamente account, dati e immagini (art. 17 GDPR, App Store 5.1.1(v)).
    func deleteAccount() async throws
}

// MARK: - Contenitore

/// Tutti i servizi dell'app, iniettati nei ViewModel.
struct AppServices: Sendable {
    let auth: any AuthService
    let profile: any ProfileRepository
    let meals: any MealRepository
    let foods: any FoodSearchService
    let scanner: any ScanService
    let coach: any CoachService
    let weight: any WeightRepository
    let entitlements: any EntitlementService
    let purchases: any PurchaseService
    let account: any AccountService
    let push: any PushTokenService
}
