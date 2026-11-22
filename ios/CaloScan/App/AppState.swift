import SwiftUI
import CaloScanCore

/// Stato globale condiviso tra le schermate: sessione, profilo, obiettivi, permessi del piano.
@Observable
@MainActor
final class AppState {
    let services: AppServices
    let toasts = ToastCenter()
    let router = DeepLinkRouter.shared

    private(set) var session: SessionState = .unknown
    private(set) var profile: UserProfile?
    private(set) var targets: DailyTargets?
    private(set) var entitlements: Entitlements = .free
    /// Incrementato quando il diario cambia, così Home e Diario ricaricano i dati.
    private(set) var diaryRevision = 0

    private var sessionTask: Task<Void, Never>?

    init(services: AppServices) {
        self.services = services
    }

    /// Avvia l'ascolto della sessione. Chiamato una volta all'avvio dell'app.
    func start() async {
        await apply(await services.auth.currentState())
        sessionTask?.cancel()
        sessionTask = Task { [weak self, services] in
            for await state in services.auth.stateChanges() {
                await self?.apply(state)
            }
        }
    }

    private func apply(_ state: SessionState) async {
        session = state
        guard case .signedIn = state else {
            profile = nil; targets = nil; entitlements = .free
            return
        }
        await reloadProfile()
        await refreshEntitlements()
    }

    func reloadProfile() async {
        do {
            profile = try await services.profile.loadProfile()
            targets = try await services.profile.loadTargets()
        } catch {
            Log.app.error("Caricamento profilo fallito: \(String(describing: error), privacy: .public)")
        }
    }

    func refreshEntitlements() async {
        do { entitlements = try await services.entitlements.refresh() }
        catch { Log.purchases.error("Aggiornamento piano fallito") }
    }

    /// Chiamato al termine dell'onboarding, dopo il salvataggio sul server.
    func completeOnboarding(profile: UserProfile, targets: DailyTargets) {
        self.profile = profile
        self.targets = targets
        if case .needsOnboarding(let id) = session { session = .signedIn(userID: id) }
    }

    func updateProfile(_ profile: UserProfile, targets: DailyTargets) {
        self.profile = profile
        self.targets = targets
    }

    /// Pasto salvato: aggiorna il diario e mostra la conferma.
    func mealSaved(_ type: MealType, fromScan: Bool = false) {
        diaryDidChange()
        toasts.success(String(localized: "Aggiunto a \(type.title)"),
                       subtitle: fromScan ? String(localized: "Valori stimati dalla foto") : nil,
                       symbol: fromScan ? "camera.viewfinder" : "checkmark.circle.fill")
    }

    func diaryDidChange() {
        diaryRevision += 1
        Task { await refreshEntitlements() }
    }
}
