import Foundation

/// Traguardi da festeggiare dopo un pasto o un peso registrato. Solo comportamenti sani e costanza:
/// mai festeggiare un giorno sotto l'obiettivo calorico o un calo di peso oltre l'obiettivo.
public enum Milestone: Equatable, Hashable, Sendable {
    /// Calorie del giorno tra il 90% e il 110% dell'obiettivo, con la cena registrata.
    case dayOnTarget
    /// Proteine del giorno raggiunte.
    case proteinReached
    /// Colazione, pranzo e cena registrati.
    case allMainMeals
    /// Giorni consecutivi con almeno un pasto (solo le soglie in `streakSteps`).
    case streak(Int)
    /// Primo pasto registrato dopo almeno 3 giorni di pausa.
    case welcomeBack
    /// Primo pasto della giornata: un consiglio sulle abitudini, a rotazione.
    case habitTip(Int)
    /// Metà strada verso il peso obiettivo.
    case weightHalfway
    /// Peso obiettivo raggiunto.
    case weightGoalReached

    public static let streakSteps = [3, 7, 14, 30, 60, 100, 200, 365]
    public static let habitTipCount = 10

    /// Festa a schermo pieno con coriandoli; gli altri sono pop-up brevi.
    public var isCelebration: Bool {
        switch self {
        case .dayOnTarget, .weightHalfway, .weightGoalReached, .streak: true
        default: false
        }
    }

    /// Una sola volta al giorno (`daily`) o una sola volta in assoluto (gli altri).
    public var isDaily: Bool {
        switch self {
        case .dayOnTarget, .proteinReached, .allMainMeals, .welcomeBack, .habitTip: true
        case .streak, .weightHalfway, .weightGoalReached: false
        }
    }

    /// Chiave per ricordare che è già stato mostrato.
    public var key: String {
        switch self {
        case .dayOnTarget: "dayOnTarget"
        case .proteinReached: "proteinReached"
        case .allMainMeals: "allMainMeals"
        case .streak(let n): "streak.\(n)"
        case .welcomeBack: "welcomeBack"
        case .habitTip: "habitTip"
        case .weightHalfway: "weightHalfway"
        case .weightGoalReached: "weightGoalReached"
        }
    }
}

public enum Milestones {
    /// Dopo un pasto salvato. `logs`: giorni recenti (fino a 60), oggi compreso, in qualsiasi ordine.
    /// In ordine di importanza: la vista mostra il primo non ancora visto.
    public static func afterMeal(logs: [DayLog], targets: DailyTargets?, goal: NutritionGoal?,
                                 now: Date = .now, calendar: Calendar = .current) -> [Milestone] {
        let todayStart = calendar.startOfDay(for: now)
        let today = logs.first { calendar.isDate($0.day, inSameDayAs: todayStart) } ?? DayLog(day: todayStart, meals: [])
        guard !today.isEmpty else { return [] }
        var out: [Milestone] = []

        let streak = streakLength(logs: logs, today: todayStart, calendar: calendar)
        if Milestone.streakSteps.contains(streak) { out.append(.streak(streak)) }

        let totals = today.totals
        if let t = targets, t.calorieTarget > 0, goal != .trackOnly, !today.meals(of: .dinner).isEmpty {
            let ratio = totals.kcal / Double(t.calorieTarget)
            if (0.9...1.1).contains(ratio) { out.append(.dayOnTarget) }
        }
        if let t = targets, t.proteinG > 0, totals.proteinG >= Double(t.proteinG) { out.append(.proteinReached) }
        if [MealType.breakfast, .lunch, .dinner].allSatisfy({ !today.meals(of: $0).isEmpty }) { out.append(.allMainMeals) }

        let loggedMeals = today.meals.filter { !$0.items.isEmpty }
        if loggedMeals.count == 1 {
            // Primo pasto di oggi: bentornato dopo una pausa, altrimenti un consiglio sulle abitudini.
            let previous = logs.filter { !$0.isEmpty && calendar.startOfDay(for: $0.day) < todayStart }.map(\.day).max()
            if let previous, let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: previous), to: todayStart).day, gap >= 4 {
                out.append(.welcomeBack)
            } else {
                let day = calendar.ordinality(of: .day, in: .era, for: todayStart) ?? 0
                out.append(.habitTip(day % Milestone.habitTipCount))
            }
        }
        return out
    }

    /// Dopo un peso registrato. `entries` compreso il nuovo; `goal` = peso obiettivo del profilo.
    /// Niente traguardi di peso in gravidanza (lo decide chi chiama).
    public static func afterWeight(entries: [WeightEntry], goal: Double?) -> [Milestone] {
        let sorted = entries.sorted { $0.date < $1.date }
        guard let goal, sorted.count >= 2, let start = sorted.first?.weightKg, abs(goal - start) >= 0.5 else { return [] }
        let latest = sorted[sorted.count - 1].weightKg, previous = sorted[sorted.count - 2].weightKg
        let progress = { (w: Double) in (w - start) / (goal - start) }
        if progress(latest) >= 1, progress(previous) < 1 { return [.weightGoalReached] }
        if progress(latest) >= 0.5, progress(previous) < 0.5 { return [.weightHalfway] }
        return []
    }

    /// Giorni consecutivi con almeno un alimento, fino a oggi compreso.
    static func streakLength(logs: [DayLog], today: Date, calendar: Calendar) -> Int {
        let logged = Set(logs.filter { !$0.isEmpty }.map { calendar.startOfDay(for: $0.day) })
        var day = today, count = 0
        while logged.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
