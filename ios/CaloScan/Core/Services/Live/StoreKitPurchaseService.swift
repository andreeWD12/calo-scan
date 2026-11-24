import Foundation
import StoreKit
import Supabase

/// Acquisti con StoreKit 2. Ogni transazione verificata da StoreKit viene inviata al server (`verify-purchase`),
/// che rilegge lo stato dall'App Store Server API e decide il piano: l'app non si sblocca mai da sola.
/// Ogni acquisto porta `appAccountToken` = ID dell'utente, così l'abbonamento resta legato a questo account.
struct StoreKitPurchaseService: PurchaseService {
    let client: SupabaseClient
    let functions: EdgeFunctionClient

    static let productIDs = ["caloscan.plus.monthly", "caloscan.plus.yearly", "caloscan.pro.monthly", "caloscan.pro.yearly",
                             "caloscan.pro.monthly.pregnancy"]
    static let pregnancyProductID = "caloscan.pro.monthly.pregnancy"

    private struct VerifyBody: Encodable, Sendable { let transactionIds: [String] }
    private struct VerifyResponse: Decodable { let plan: Plan }

    func offers() async throws -> [PlanOffer] {
        let products: [Product]
        do { products = try await Product.products(for: Self.productIDs) }
        catch { throw APIError.offline }
        var offers: [PlanOffer] = []
        for product in products {
            guard let sub = product.subscription else { continue }
            let plan: Plan = product.id.contains(".pro.") ? .pro : .plus
            let yearly = sub.subscriptionPeriod.unit == .year
            let perMonth = yearly ? (product.price / 12).formatted(product.priceFormatStyle) : nil
            var intro: String?, introPrice: String?, introMonths: Int?
            if let offer = sub.introductoryOffer {
                introPrice = offer.displayPrice
                let months = Self.months(offer.period) * max(offer.periodCount, 1)
                introMonths = months
                intro = switch offer.paymentMode {
                case .freeTrial: String(localized: "\(Self.describe(offer.period, count: offer.periodCount)) gratis")
                default: String(localized: "\(offer.displayPrice) per i primi \(Self.describe(offer.period, count: offer.periodCount))")
                }
            }
            offers.append(PlanOffer(id: product.id, plan: plan, period: yearly ? .yearly : .monthly,
                                    displayPrice: product.displayPrice, pricePerMonthText: perMonth, introOffer: intro,
                                    audience: product.id == Self.pregnancyProductID ? .pregnancy : .standard,
                                    introPrice: introPrice, introMonths: introMonths,
                                    isEligibleForIntro: await sub.isEligibleForIntroOffer))
        }
        return offers
    }

    func purchase(offerID: String) async throws -> PurchaseOutcome {
        guard let product = try? await Product.products(for: [offerID]).first else { throw APIError.offline }
        let userID = try await currentUserID()
        let result: Product.PurchaseResult
        do { result = try await product.purchase(options: [.appAccountToken(userID)]) }
        catch { throw APIError.from(error) }
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw APIError.invalidInput(String(localized: "Apple non ha potuto verificare l'acquisto. Non ti è stato addebitato nulla di nuovo: riprova o contatta l'assistenza."))
            }
            try await verifyOnServer([transaction])
            await transaction.finish()
            return .purchased
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: return .cancelled
        }
    }

    /// "Ripristina acquisti": chiede ad Apple di sincronizzare (può chiedere la password) e invia gli abbonamenti attivi.
    func restore() async throws {
        do { try await AppStore.sync() } catch { throw APIError.from(error) }
        try await verifyOnServer(await currentTransactions())
    }

    func syncCurrentEntitlements() async {
        let transactions = await currentTransactions()
        guard !transactions.isEmpty else { return }
        try? await verifyOnServer(transactions)
    }

    /// Rinnovi, acquisti approvati più tardi (Chiedi di acquistare), codici offerta, rimborsi, cambi di piano.
    func transactionUpdates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await update in Transaction.updates {
                    guard case .verified(let transaction) = update else { continue }
                    if (try? await verifyOnServer([transaction])) != nil { await transaction.finish() }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: -

    private func currentTransactions() async -> [Transaction] {
        var list: [Transaction] = []
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement, Self.productIDs.contains(t.productID) { list.append(t) }
        }
        return list
    }

    private func verifyOnServer(_ transactions: [Transaction]) async throws {
        guard !transactions.isEmpty else { return }
        let _: VerifyResponse = try await functions.invoke(.verifyPurchase,
                                                           body: VerifyBody(transactionIds: transactions.map { String($0.id) }))
    }

    private func currentUserID() async throws -> UUID {
        do { return try await client.auth.session.user.id }
        catch { throw APIError.unauthorized }
    }

    private static func months(_ period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .year: 12 * period.value
        case .month: period.value
        default: 0
        }
    }

    private static func describe(_ period: Product.SubscriptionPeriod, count: Int) -> String {
        let n = period.value * max(count, 1)
        return switch period.unit {
        case .day: n == 1 ? String(localized: "1 giorno") : String(localized: "\(n) giorni")
        case .week: n == 1 ? String(localized: "1 settimana") : String(localized: "\(n) settimane")
        case .month: n == 1 ? String(localized: "1 mese") : String(localized: "\(n) mesi")
        case .year: n == 1 ? String(localized: "1 anno") : String(localized: "\(n) anni")
        @unknown default: String(localized: "\(n)")
        }
    }
}
