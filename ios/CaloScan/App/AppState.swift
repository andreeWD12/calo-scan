import SwiftUI
import CaloScanCore

/// Stato globale condiviso tra le schermate: sessione, profilo, obiettivi, permessi del piano.
@Observable
@MainActor
final class AppState {
    let services: AppServices
    let toasts = ToastCenter()
    let upsell = UpsellCenter()
    let router = DeepLinkRouter.shared

    private(set) var session: SessionState = .unknown
    private(set) var profile: UserProfile?
    /// Obiettivi calcolati dall'app (o modificati a mano dall'utente).
    private(set) var computedTargets: DailyTargets?
    /// Piano indicato da un medico o dietista: se presente, prevale sugli obiettivi calcolati.
    private(set) var professionalPlan: ProfessionalPlan?
    /// Obiettivi effettivi usati da Home, Diario, Progressi e Coach.
    /// Ordine: piano del professionista › gravidanza (mai in deficit, EFSA per trimestre) › obiettivi calcolati.
    var targets: DailyTargets? {
        if let professionalPlan { return professionalPlan.dailyTargets(fallback: computedTargets) }
        if let profile, let pregnancy = profile.activePregnancy(), let metrics = try? profile.metrics() {
            return PregnancyNutrition.targets(metrics: metrics, activity: profile.activity, diet: profile.diet,
                                              trimester: pregnancy.trimester())
        }
        return computedTargets
    }

    /// Gravidanza attiva: abilita gli avvisi sugli alimenti in tutta l'app.
    var pregnancy: PregnancyInfo? { profile?.activePregnancy() }
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
            profile = nil; computedTargets = nil; professionalPlan = nil; entitlements = .free
            return
        }
        await reloadProfile()
        await refreshEntitlements()
    }

    func reloadProfile() async {
        do {
            profile = try await services.profile.loadProfile()
            computedTargets = try await services.profile.loadTargets()
            professionalPlan = try await services.profile.loadProfessionalPlan()
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
        self.computedTargets = targets
        if case .needsOnboarding(let id) = session { session = .signedIn(userID: id) }
    }

    func updateProfile(_ profile: UserProfile, targets: DailyTargets) {
        self.profile = profile
        self.computedTargets = targets
    }

    func setProfessionalPlan(_ plan: ProfessionalPlan?) {
        professionalPlan = plan
        diaryRevision += 1
    }

    /// Pasto salvato: aggiorna il diario e mostra la conferma.
    func mealSaved(_ type: MealType, source: MealSource = .manual) {
        diaryDidChange()
        let subtitle: String? = switch source {
        case .scan: String(localized: "Valori stimati dalla foto")
        case .description: String(localized: "Valori stimati dalla descrizione")
        case .plan: String(localized: "Come da piano")
        case .manual: nil
        }
        let symbol = switch source {
        case .scan: "camera.viewfinder"
        case .description: "text.bubble"
        case .plan: "list.clipboard"
        case .manual: "checkmark.circle.fill"
        }
        toasts.success(String(localized: "Aggiunto a \(type.title)"), subtitle: subtitle, symbol: symbol)
        let usedAI = source == .scan || source == .description
        Task {
            await refreshEntitlements()
            upsell.mealSaved(entitlements: entitlements, usedAIScan: usedAI)
        }
    }

    /// Dopo ogni messaggio al coach: aggiorna i limiti e valuta l'invito all'upgrade.
    func coachMessageSent() {
        Task {
            await refreshEntitlements()
            upsell.coachMessageSent(entitlements: entitlements)
        }
    }

    func diaryDidChange() {
        diaryRevision += 1
    }
}
