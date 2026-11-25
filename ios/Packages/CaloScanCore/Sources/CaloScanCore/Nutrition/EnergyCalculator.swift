import Foundation

/// Obiettivi giornalieri calcolati. `isAdjustedForSafety` indica che un limite minimo è intervenuto.
public struct DailyTargets: Codable, Equatable, Sendable {
    public let bmr: Int
    public let tdee: Int
    public let calorieTarget: Int
    public let proteinG: Int
    public let carbsG: Int
    public let fatG: Int
    public let isAdjustedForSafety: Bool

    public init(bmr: Int, tdee: Int, calorieTarget: Int, proteinG: Int, carbsG: Int, fatG: Int,
                isAdjustedForSafety: Bool) {
        self.bmr = bmr; self.tdee = tdee; self.calorieTarget = calorieTarget
        self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
        self.isAdjustedForSafety = isAdjustedForSafety
    }
}

/// Calcoli energetici. Algoritmo identico a `supabase/functions/_shared/nutrition.ts`:
/// qualsiasi modifica va fatta in entrambi i file insieme ai test.
public enum EnergyCalculator {

    /// Mifflin-St Jeor (1990). Con sesso non specificato si usa la media delle due formule (−78).
    public static func bmr(_ m: BodyMetrics) -> Double {
        let base = 10 * m.weightKg + 6.25 * m.heightCm - 5 * Double(m.ageYears)
        switch m.sex {
        case .male: return base + 5
        case .female: return base - 161
        case .unspecified: return base - 78
        }
    }

    public static func tdee(_ m: BodyMetrics, activity: ActivityLevel) -> Double {
        bmr(m) * activity.multiplier
    }

    /// Soglia minima assoluta di kcal giornaliere che l'app non proporrà mai.
    public static func calorieFloor(for sex: BiologicalSex) -> Double {
        switch sex {
        case .male: 1500
        case .female: 1200
        case .unspecified: 1350
        }
    }

    public static func targets(
        metrics m: BodyMetrics,
        activity: ActivityLevel,
        goal: NutritionGoal,
        diet: DietPreference = .omnivore
    ) -> DailyTargets {
        let bmrValue = bmr(m)
        let tdeeValue = bmrValue * activity.multiplier

        // Deficit/surplus moderati; i minori non ricevono obiettivi di deficit.
        var effectiveGoal = goal
        if m.ageYears < 18 && goal == .loseWeight { effectiveGoal = .maintain }

        var target: Double
        switch effectiveGoal {
        case .loseWeight: target = tdeeValue - min(tdeeValue * 0.15, 500)
        case .gainMuscle: target = tdeeValue + min(tdeeValue * 0.10, 300)
        case .maintain, .improveQuality, .trackOnly: target = tdeeValue
        }

        let floor = max(bmrValue, calorieFloor(for: m.sex))
        var adjusted = effectiveGoal != goal
        if target < floor { target = floor; adjusted = true }

        // Proteine (g/kg), limitate a 2,2 g/kg e al 35% delle kcal.
        let proteinPerKg: Double
        switch effectiveGoal {
        case .loseWeight: proteinPerKg = 1.8
        case .gainMuscle: proteinPerKg = 2.0
        default: proteinPerKg = 1.6
        }
        let protein = min(m.weightKg * min(proteinPerKg, 2.2), target * 0.35 / 4)

        // Grassi: 30% (35% low carb), minimo 0,6 g/kg.
        let fatShare = diet == .lowCarb ? 0.35 : 0.30
        let fat = max(target * fatShare / 9, m.weightKg * 0.6)

        let carbs = max((target - protein * 4 - fat * 9) / 4, 0)

        return DailyTargets(
            bmr: Int(bmrValue.rounded()),
            tdee: Int(tdeeValue.rounded()),
            calorieTarget: Int(target.rounded()),
            proteinG: Int(protein.rounded()),
            carbsG: Int(carbs.rounded()),
            fatG: Int(fat.rounded()),
            isAdjustedForSafety: adjusted
        )
    }

    /// Valida un obiettivo calorico inserito manualmente dall'utente.
    public static func isSafeManualTarget(_ kcal: Int, metrics m: BodyMetrics) -> Bool {
        Double(kcal) >= calorieFloor(for: m.sex) && kcal <= 6000
    }
}
