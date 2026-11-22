import Foundation

@Observable
@MainActor
final class PaywallViewModel {
    private(set) var offers: Loadable<[PlanOffer]> = .idle
    private(set) var purchasingID: String?
    private(set) var isRestoring = false
    var period: PlanOffer.Period = .yearly
    var selectedPlan: Plan = .plus
    var error: APIError?
    var pendingMessage: String?

    private let purchases: any PurchaseService

    init(purchases: any PurchaseService) {
        self.purchases = purchases
    }

    func load() async {
        offers = .loading
        do {
            let list = try await purchases.offers()
            offers = list.isEmpty ? .empty : .loaded(list)
        } catch {
            offers = .failed(APIError.from(error))
        }
    }

    func offer(for plan: Plan) -> PlanOffer? {
        offers.value?.first { $0.plan == plan && $0.period == period && $0.audience == .standard }
    }

    /// Offerta gravidanza, solo se Apple la concede a questo Apple ID. Altrimenti resta il paywall normale.
    var pregnancyOffer: PlanOffer? {
        offers.value?.first { $0.audience == .pregnancy && $0.isEligibleForIntro && $0.introPrice != nil }
    }

    var selectedOffer: PlanOffer? { offer(for: selectedPlan) }

    /// Ritorna `true` quando l'acquisto è completato e verificato dal server.
    func purchaseSelected() async -> Bool {
        guard let offer = selectedOffer else { return false }
        return await purchase(offer)
    }

    func purchase(_ offer: PlanOffer) async -> Bool {
        guard purchasingID == nil else { return false }
        purchasingID = offer.id
        defer { purchasingID = nil }
        do {
            switch try await purchases.purchase(offerID: offer.id) {
            case .purchased: return true
            case .pending:
                pendingMessage = String(localized: "Acquisto in attesa di approvazione (ad esempio da In famiglia). Lo attiveremo appena confermato.")
                return false
            case .cancelled: return false
            }
        } catch {
            self.error = APIError.from(error)
            return false
        }
    }

    func restore() async -> Bool {
        isRestoring = true
        defer { isRestoring = false }
        do { try await purchases.restore(); return true }
        catch { self.error = APIError.from(error); return false }
    }
}

extension Plan {
    /// Funzionalità mostrate nel paywall. I limiti numerici reali sono definiti sul server (`plan_limits`).
    var features: [LocalizedStringKey] {
        switch self {
        case .free:
            ["Diario alimentare e inserimento manuale", "Calcolo del fabbisogno calorico", "Lista della spesa manuale",
             "Statistiche settimanali di base", "Scansioni AI limitate ogni giorno"]
        case .plus:
            ["Più scansioni AI ogni giorno", "Analisi dettagliata dei macronutrienti",
             "Statistiche settimanali e mensili complete", "Consigli nutrizionali personalizzati",
             "Analisi delle abitudini alimentari", "Lista della spesa suggerita dall'AI",
             "Stile alimentare scelto con il coach, anche digiuno intermittente",
             "Dieta per la gravidanza: fabbisogno per trimestre e avvisi sugli alimenti"]
        case .pro:
            ["Tutto di Plus", "Scansioni AI con limiti molto più alti", "AI Nutrition Coach avanzato",
             "Piano dei pasti settimanale e idee ricette", "Lista della spesa AI senza limiti settimanali",
             "Report mensili avanzati"]
        }
    }
}
