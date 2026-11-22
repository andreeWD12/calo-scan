import Foundation
import CaloScanCore

/// Implementazione di transizione per i servizi il cui backend viene collegato in una fase successiva.
/// Non finge risultati: ogni chiamata fallisce con un errore esplicito, che l'interfaccia mostra come
/// stato d'errore. Ogni fase sostituisce in `AppServices.live` il servizio corrispondente e, a progetto
/// completo, questo file viene eliminato.
struct NotConnectedService: AuthService, ProfileRepository, MealRepository, FoodSearchService, ScanService,
                            CoachService, WeightRepository, EntitlementService, PurchaseService, AccountService,
                            PushTokenService {

    private func fail() -> APIError { .notConnected }

    func currentState() async -> SessionState { .signedOut }
    func stateChanges() -> AsyncStream<SessionState> { AsyncStream { $0.finish() } }
    func signInWithApple(idToken: String, nonce: String) async throws { throw fail() }
    func signInWithGoogle(idToken: String, accessToken: String) async throws { throw fail() }
    func signIn(email: String, password: String) async throws { throw fail() }
    func signUp(email: String, password: String) async throws -> Bool { throw fail() }
    func sendPasswordReset(email: String) async throws { throw fail() }
    func signOut() async throws { throw fail() }

    func loadProfile() async throws -> UserProfile? { throw fail() }
    func loadTargets() async throws -> DailyTargets? { throw fail() }
    func save(profile: UserProfile, targets: DailyTargets) async throws { throw fail() }

    func dayLog(for day: Date) async throws -> DayLog { throw fail() }
    func dayLogs(from start: Date, to end: Date) async throws -> [DayLog] { throw fail() }
    func save(_ meal: Meal) async throws { throw fail() }
    func delete(mealID: UUID) async throws { throw fail() }

    func search(_ query: String) async throws -> [FoodItem] { throw fail() }
    func lookup(barcode: String) async throws -> FoodItem? { throw fail() }
    func analyze(jpegData: Data) async throws -> ScanResult { throw fail() }

    func dailyInsights() async throws -> [CoachInsight] { throw fail() }
    func history() async throws -> [CoachMessage] { throw fail() }
    func send(_ text: String) async throws -> CoachMessage { throw fail() }

    func entries() async throws -> [WeightEntry] { throw fail() }
    func add(_ entry: WeightEntry) async throws { throw fail() }
    func delete(entryID: UUID) async throws { throw fail() }
    func measurements() async throws -> [BodyMeasurement] { throw fail() }
    func add(_ measurement: BodyMeasurement) async throws { throw fail() }

    func refresh() async throws -> Entitlements { throw fail() }
    func offers() async throws -> [PlanOffer] { throw fail() }
    func purchase(offerID: String) async throws -> PurchaseOutcome { throw fail() }
    func restore() async throws { throw fail() }

    func consents() async throws -> ConsentState { throw fail() }
    func update(consents: ConsentState) async throws { throw fail() }
    func exportData() async throws -> URL { throw fail() }
    func deleteAccount() async throws { throw fail() }

    func register(deviceToken: String, environment: PushEnvironment) async throws { throw fail() }
    func unregister() async throws { throw fail() }
}

extension AppServices {
    /// Servizi di produzione. Fase 2: nessun backend collegato ancora.
    static func live(container: AppContainer) -> AppServices {
        let pending = NotConnectedService()
        return AppServices(auth: pending, profile: pending, meals: pending, foods: pending, scanner: pending,
                           coach: pending, weight: pending, entitlements: pending, purchases: pending,
                           account: pending, push: pending)
    }
}
