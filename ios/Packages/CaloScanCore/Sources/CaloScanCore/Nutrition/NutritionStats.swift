import Foundation

/// Riepilogo di un periodo (settimana, mese). Considera solo i giorni con almeno un pasto registrato,
/// così i giorni non registrati non abbassano la media.
public struct PeriodStats: Equatable, Sendable {
    public let loggedDays: Int
    public let total: Nutrients
    public let average: Nutrients
    public let daysOnTarget: Int
    public let daysOver: Int
    public let daysUnder: Int

    /// Quota di giorni registrati entro la tolleranza dell'obiettivo (0…1).
    public var consistency: Double { loggedDays == 0 ? 0 : Double(daysOnTarget) / Double(loggedDays) }
}

public enum NutritionStats {
    /// - Parameter tolerance: scarto ammesso rispetto all'obiettivo (default ±10%).
    public static func summarize(_ days: [DayLog], calorieTarget: Int, tolerance: Double = 0.10) -> PeriodStats {
        let logged = days.filter { !$0.isEmpty }
        let total = logged.map(\.totals).total
        let n = Double(max(logged.count, 1))
        let average = Nutrients(kcal: total.kcal / n, proteinG: total.proteinG / n,
                                carbsG: total.carbsG / n, fatG: total.fatG / n)
        let target = Double(calorieTarget)
        var on = 0, over = 0, under = 0
        for day in logged {
            let kcal = day.totals.kcal
            if kcal > target * (1 + tolerance) { over += 1 }
            else if kcal < target * (1 - tolerance) { under += 1 }
            else { on += 1 }
        }
        return PeriodStats(loggedDays: logged.count, total: total, average: average,
                           daysOnTarget: on, daysOver: over, daysUnder: under)
    }

    /// Avanzamento verso l'obiettivo calorico del giorno, 0…∞ (oltre 1 = superato).
    public static func progress(consumed: Double, target: Int) -> Double {
        target <= 0 ? 0 : max(consumed, 0) / Double(target)
    }
}
