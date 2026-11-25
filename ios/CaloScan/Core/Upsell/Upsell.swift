import Foundation
import Observation

/// Momenti in cui l'app può suggerire un piano superiore. Ogni invito è legato a qualcosa
/// che l'utente sta facendo in quel momento, mai a un timer o all'apertura dell'app.
enum UpsellKind: String, Codable, CaseIterable, Sendable {
    /// Rimane una sola scansione AI oggi, o sono finite.
    case scansRunningLow
    /// Rimane un solo messaggio al coach oggi, o sono finiti.
    case coachRunningLow
    /// L'utente registra con costanza (10 pasti salvati): momento positivo per mostrare le statistiche complete.
    case engagedUser
}

struct UpsellPrompt: Identifiable, Equatable, Sendable {
    let kind: UpsellKind
    let target: Plan
    let title: String
    let message: String
    let symbol: String
    var id: UpsellKind { kind }
}

/// Regole di frequenza. Pensate per non essere invasive e per rispettare il divieto UE di
/// pratiche commerciali aggressive (direttiva 2005/29/CE) e di dark pattern (DSA art. 25):
/// niente urgenza finta, niente conti alla rovescia, chiusura sempre visibile, nessun blocco dell'uso.
struct UpsellPolicy: Codable, Equatable, Sendable {
    /// Primo avvio dell'app su questo dispositivo.
    var firstLaunch: Date
    var lastShown: [UpsellKind: Date] = [:]
    var dismissals: [UpsellKind: Int] = [:]
    var history: [Date] = []
    var mealsSaved = 0

    static let quietPeriod: TimeInterval = 2 * 86_400          // nessun invito nei primi 2 giorni…
    static let cooldownPerKind: TimeInterval = 7 * 86_400      // …lo stesso invito al massimo 1 volta a settimana
    static let maxPerWeek = 2
    static let maxDismissals = 3                                // dopo 3 chiusure quel tipo non compare più
    static let engagedMealThreshold = 10

    init(firstLaunch: Date) { self.firstLaunch = firstLaunch }

    func canShow(_ kind: UpsellKind, plan: Plan, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard plan < .pro else { return false }
        if kind == .engagedUser && plan != .free { return false }
        if (dismissals[kind] ?? 0) >= Self.maxDismissals { return false }
        // Le scansioni in esaurimento sono un'informazione utile: niente periodo di quiete.
        if kind != .scansRunningLow && now.timeIntervalSince(firstLaunch) < Self.quietPeriod { return false }
        if let last = lastShown[kind], now.timeIntervalSince(last) < Self.cooldownPerKind { return false }
        if history.contains(where: { calendar.isDate($0, inSameDayAs: now) }) { return false }
        let lastWeek = history.filter { now.timeIntervalSince($0) < 7 * 86_400 }
        return lastWeek.count < Self.maxPerWeek
    }

    mutating func recordShown(_ kind: UpsellKind, now: Date = .now) {
        lastShown[kind] = now
        history = history.filter { now.timeIntervalSince($0) < 7 * 86_400 } + [now]
    }

    mutating func recordDismissal(_ kind: UpsellKind) {
        dismissals[kind, default: 0] += 1
    }
}

/// Decide se e quale invito mostrare. Lo stato resta solo sul dispositivo (UserDefaults):
/// nessun tracciamento, nessun dato inviato al server.
@Observable
@MainActor
final class UpsellCenter {
    private(set) var current: UpsellPrompt?
    private(set) var policy: UpsellPolicy
    private let defaults: UserDefaults
    private static let key = "upsellPolicy.v1"
    private var hideTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(UpsellPolicy.self, from: data) {
            policy = saved
        } else {
            policy = UpsellPolicy(firstLaunch: .now)
        }
    }

    /// Dopo il salvataggio di un pasto: scansioni in esaurimento o utente costante.
    func mealSaved(entitlements e: Entitlements, usedAIScan: Bool) {
        policy.mealsSaved += 1
        persist()
        if usedAIScan && e.scansRemaining <= 1 {
            offer(.scansRunningLow, plan: e.plan, remaining: e.scansRemaining)
        } else if policy.mealsSaved >= UpsellPolicy.engagedMealThreshold {
            offer(.engagedUser, plan: e.plan, remaining: nil)
        }
    }

    /// Dopo un messaggio al coach.
    func coachMessageSent(entitlements e: Entitlements) {
        let remaining = max(e.coachMessagesLimitToday - e.coachMessagesUsedToday, 0)
        if remaining <= 1 { offer(.coachRunningLow, plan: e.plan, remaining: remaining) }
    }

    /// Chiusura con la X: conta per le regole di frequenza.
    func dismiss() {
        guard let kind = current?.kind else { return }
        policy.recordDismissal(kind)
        persist()
        current = nil
    }

    /// L'utente ha aperto i piani: l'invito ha fatto il suo lavoro.
    func accepted() { current = nil }

    private func offer(_ kind: UpsellKind, plan: Plan, remaining: Int?) {
        guard current == nil, policy.canShow(kind, plan: plan),
              let prompt = Self.prompt(for: kind, plan: plan, remaining: remaining) else { return }
        policy.recordShown(kind)
        persist()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            // Compare dopo il popup di conferma, così non si sovrappongono.
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.current = prompt
            // Sparisce da solo: la scomparsa automatica non conta come chiusura.
            try? await Task.sleep(for: .seconds(9))
            guard !Task.isCancelled, self?.current?.kind == kind else { return }
            self?.current = nil
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(policy) { defaults.set(data, forKey: Self.key) }
    }

    static func prompt(for kind: UpsellKind, plan: Plan, remaining: Int?) -> UpsellPrompt? {
        let target: Plan = plan == .free ? .plus : .pro
        switch kind {
        case .scansRunningLow:
            let title = remaining == 0
                ? String(localized: "Scansioni di oggi finite")
                : String(localized: "Ti resta 1 scansione AI oggi")
            let message = target == .plus
                ? String(localized: "Si rinnovano domani. Con Plus hai 20 scansioni al giorno.")
                : String(localized: "Si rinnovano domani. Con Pro hai 100 scansioni al giorno.")
            return UpsellPrompt(kind: kind, target: target, title: title, message: message, symbol: "camera.viewfinder")
        case .coachRunningLow:
            let title = remaining == 0
                ? String(localized: "Messaggi al coach finiti per oggi")
                : String(localized: "Ultimo messaggio al coach per oggi")
            let message = target == .plus
                ? String(localized: "Con Plus hai 30 messaggi al giorno e consigli personalizzati.")
                : String(localized: "Con Pro hai 150 messaggi al giorno, piani pasto e ricette.")
            return UpsellPrompt(kind: kind, target: target, title: title, message: message, symbol: "sparkles")
        case .engagedUser:
            guard plan == .free else { return nil }
            return UpsellPrompt(kind: kind, target: .plus,
                                title: String(localized: "Stai registrando con costanza"),
                                message: String(localized: "Con Plus vedi le statistiche mensili e l'analisi delle tue abitudini."),
                                symbol: "chart.bar.xaxis")
        }
    }
}

extension Plan: Identifiable {
    var id: String { rawValue }
}
