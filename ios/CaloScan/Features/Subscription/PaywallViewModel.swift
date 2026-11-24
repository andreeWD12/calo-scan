import Foundation
import SwiftUI

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
            ["Diario alimentare e inserimento manuale", "Ricerca alimenti e codici a barre",
             "Calcolo del fabbisogno calorico", "Statistiche del giorno e della settimana",
             "Peso dell'ultimo mese", "Lista della spesa manuale", "Consigli del giorno del coach",
             "Esportazione ed eliminazione dei dati, sempre incluse"]
        case .plus:
            ["Scanner AI: 4 scansioni al giorno, una per pasto", "Analisi dettagliata dei macronutrienti",
             "Distribuzione delle calorie tra i pasti", "Statistiche mensili complete",
             "Misure corporee e storico completo del peso", "Piano del medico o dietista nel diario",
             "Chat con il coach AI: 30 messaggi al giorno", "Lista della spesa suggerita dall'AI"]
        case .pro:
            ["Tutto di Plus", "Scanner AI: 15 scansioni al giorno", "Chat con il coach AI: 150 messaggi al giorno",
             "Stile alimentare scelto con il coach, anche digiuno intermittente",
             "Dieta per la gravidanza che si adatta alla tua settimana",
             "Idee per pasti e ricette chiedendo al coach"]
        }
    }
}
