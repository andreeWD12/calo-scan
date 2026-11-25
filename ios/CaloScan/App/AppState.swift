import SwiftUI
import UserNotifications
import CaloScanCore

/// Stato globale condiviso tra le schermate: sessione, profilo, obiettivi, permessi del piano.
@Observable
@MainActor
final class AppState {
    let services: AppServices
    let toasts = ToastCenter()
    let upsell = UpsellCenter()
    /// Feste per i traguardi e pop-up di incoraggiamento e sulle abitudini.
    let celebrations = CelebrationCenter()
    let router = DeepLinkRouter.shared

    private(set) var session: SessionState = .unknown
    private(set) var profile: UserProfile?
    /// Obiettivi calcolati dall'app (o modificati a mano dall'utente).
    private(set) var computedTargets: DailyTargets?
    /// Piano indicato da un medico o dietista: se presente, prevale sugli obiettivi calcolati.
    private(set) var professionalPlan: ProfessionalPlan?
    /// Obiettivi effettivi usati da Home, Diario, Progressi e Coach.
    /// Ordine: piano del professionista › gravidanza › obiettivi calcolati.
    /// Gravidanza: con Pro fabbisogno EFSA per settimana/trimestre; con Free almeno il mantenimento.
    /// Il "mai in deficit" vale per tutti i piani: è una tutela di sicurezza, non una funzione a pagamento.
    var targets: DailyTargets? {
        if let professionalPlan { return professionalPlan.dailyTargets(fallback: computedTargets) }
        if let profile, let pregnancy = profile.activePregnancy(), let metrics = try? profile.metrics() {
            if hasPregnancyPlan {
                return PregnancyNutrition.targets(metrics: metrics, activity: profile.activity, diet: profile.diet,
                                                  trimester: pregnancy.trimester())
            }
            let maintenance = EnergyCalculator.targets(metrics: metrics, activity: profile.activity, goal: .maintain, diet: profile.diet)
            if let computedTargets, computedTargets.calorieTarget >= maintenance.calorieTarget { return computedTargets }
            return maintenance
        }
        return computedTargets
    }

    /// Gravidanza attiva (tutti i piani): niente deficit, niente digiuni o stili restrittivi.
    var pregnancy: PregnancyInfo? { profile?.activePregnancy() }
    /// Dieta per la gravidanza completa (solo Pro): fabbisogno per settimana, avvisi automatici sugli alimenti.
    var hasPregnancyPlan: Bool { entitlements.plan == .pro }
    /// Stile alimentare scelto con il coach, digiuni compresi (solo Pro).
    var hasEatingStyles: Bool { entitlements.plan == .pro }
    private(set) var entitlements: Entitlements = .free
    /// Incrementato quando il diario cambia, così Home e Diario ricaricano i dati.
    private(set) var diaryRevision = 0

    private var sessionTask: Task<Void, Never>?
    private var purchasesTask: Task<Void, Never>?
    /// Aperto dal link di recupero password: mostra la schermata per scegliere la nuova password.
    var showsNewPassword = false

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
        // Rinnovi, rimborsi, acquisti approvati più tardi: StoreKit li segnala anche ad app chiusa, all'avvio successivo.
        purchasesTask?.cancel()
        purchasesTask = Task { [weak self, services] in
            for await _ in services.purchases.transactionUpdates() {
                await self?.refreshEntitlements()
            }
        }
    }

    private func apply(_ state: SessionState) async {
        session = state
        if state == .signedOut { await MealPhotoStore.shared.removeAll() }
        guard case .signedIn = state else {
            profile = nil; computedTargets = nil; professionalPlan = nil; entitlements = .free
            return
        }
        await reloadProfile()
        await refreshEntitlements()
        // Token push: all'avvio non c'era ancora la sessione, ora il server può collegarlo all'account.
        if await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
        // Abbonamenti già attivi su questo Apple ID (altro dispositivo, reinstallazione): il server li verifica con Apple.
        await services.purchases.syncCurrentEntitlements()
        await refreshEntitlements()
    }

    /// Link esterni: accesso/recupero password (caloscan://auth-callback) o deep link interni.
    func open(_ url: URL) async {
        switch await services.auth.handle(url: url) {
        case .passwordRecovery:
            showsNewPassword = true
        case .signedIn:
            toasts.success(String(localized: "Email confermata"), symbol: "checkmark.seal.fill")
        case .failed:
            toasts.show(Toast(style: .warning, title: String(localized: "Link non valido o scaduto"),
                              subtitle: String(localized: "Richiedine uno nuovo dalla schermata di accesso.")))
        case .notHandled:
            if let link = DeepLink(url: url) { router.open(link) }
        }
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
        Task { await checkMealMilestones() }
    }

    /// Traguardi dopo un pasto: obiettivo del giorno, proteine, giornata completa, giorni di fila, abitudini.
    private func checkMealMilestones() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let from = calendar.date(byAdding: .day, value: -60, to: today),
              let logs = try? await services.meals.dayLogs(from: from, to: today) else { return }
        celebrations.offer(Milestones.afterMeal(logs: logs, targets: targets, goal: profile?.goal, calendar: calendar))
    }

    /// Traguardi di peso (metà strada, obiettivo raggiunto). Mai in gravidanza.
    func weightSaved(entries: [WeightEntry]) {
        guard pregnancy == nil else { return }
        celebrations.offer(Milestones.afterWeight(entries: entries, goal: profile?.targetWeightKg))
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
