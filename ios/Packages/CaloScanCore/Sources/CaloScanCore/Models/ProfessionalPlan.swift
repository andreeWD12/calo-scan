import Foundation

/// Chi ha indicato il piano alimentare all'utente.
public enum HealthProfessional: String, Codable, CaseIterable, Sendable {
    case doctor, dietitian, nutritionist
}

/// Calorie e, se presenti, macronutrienti indicati da un medico o da un altro professionista sanitario.
///
/// L'app non genera né modifica questi valori: li registra come li inserisce l'utente e li usa
/// come riferimento nel diario. Per questo restano possibili valori sotto le soglie che l'app
/// applica ai propri calcoli, fino al minimo assoluto `calorieRange.lowerBound`.
/// Dati sanitari ai sensi dell'art. 9 GDPR.
///
/// Validazione identica a `validateProfessionalPlan` in `supabase/functions/_shared/nutrition.ts`.
public struct ProfessionalPlan: Codable, Equatable, Sendable {
    public var professional: HealthProfessional
    public var professionalName: String?
    public var calorieTarget: Int
    public var proteinG: Int?
    public var carbsG: Int?
    public var fatG: Int?
    /// Indicazioni del piano scritte dall'utente (es. "mediterranea, 5 pasti, pochi zuccheri semplici").
    public var notes: String?
    public var startDate: Date
    public var reviewDate: Date?
    /// Momento in cui l'utente ha confermato che i valori provengono da un professionista.
    public var confirmedAt: Date

    public static let calorieRange = 800...6000
    public static let macroRange = 0...1000
    public static let notesMaxLength = 1000
    public static let nameMaxLength = 80
    /// Tolleranza tra le kcal dei macronutrienti indicati e l'obiettivo calorico (arrotondamenti del piano).
    public static let macroTolerance = 0.15

    public init(professional: HealthProfessional, professionalName: String? = nil, calorieTarget: Int,
                proteinG: Int? = nil, carbsG: Int? = nil, fatG: Int? = nil, notes: String? = nil,
                startDate: Date, reviewDate: Date? = nil, confirmedAt: Date) {
        self.professional = professional; self.professionalName = professionalName
        self.calorieTarget = calorieTarget; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
        self.notes = notes; self.startDate = startDate; self.reviewDate = reviewDate; self.confirmedAt = confirmedAt
    }

    public enum Issue: String, Equatable, Sendable {
        case caloriesOutOfRange, macroOutOfRange, macrosDoNotMatchCalories, notesTooLong, nameTooLong, reviewBeforeStart
    }

    public var hasMacros: Bool { proteinG != nil || carbsG != nil || fatG != nil }

    public func validate() -> [Issue] {
        var issues: [Issue] = []
        if !Self.calorieRange.contains(calorieTarget) { issues.append(.caloriesOutOfRange) }
        let macros = [proteinG, carbsG, fatG].compactMap { $0 }
        if macros.contains(where: { !Self.macroRange.contains($0) }) { issues.append(.macroOutOfRange) }
        if let p = proteinG, let c = carbsG, let f = fatG, calorieTarget > 0 {
            let fromMacros = Double(p * 4 + c * 4 + f * 9)
            if abs(fromMacros - Double(calorieTarget)) / Double(calorieTarget) > Self.macroTolerance {
                issues.append(.macrosDoNotMatchCalories)
            }
        }
        if (notes?.count ?? 0) > Self.notesMaxLength { issues.append(.notesTooLong) }
        if (professionalName?.count ?? 0) > Self.nameMaxLength { issues.append(.nameTooLong) }
        if let reviewDate, reviewDate < startDate { issues.append(.reviewBeforeStart) }
        return issues
    }

    /// `true` se le calorie sono sotto la soglia che l'app usa per i propri calcoli: l'interfaccia
    /// chiede una conferma esplicita e ricorda di seguire il piano sotto controllo medico.
    public func isBelowAppFloor(for sex: BiologicalSex) -> Bool {
        Double(calorieTarget) < EnergyCalculator.calorieFloor(for: sex)
    }

    /// Obiettivi giornalieri effettivi. I macronutrienti non indicati dal professionista mantengono
    /// le proporzioni degli obiettivi calcolati (`fallback`); i carboidrati coprono le kcal restanti.
    public func dailyTargets(fallback: DailyTargets?) -> DailyTargets {
        let kcal = Double(calorieTarget)
        let baseKcal = Double(max(fallback?.calorieTarget ?? 0, 1))
        let proteinShare = fallback.map { Double($0.proteinG) * 4 / baseKcal } ?? 0.25
        let fatShare = fallback.map { Double($0.fatG) * 9 / baseKcal } ?? 0.30
        let p = proteinG ?? Int((kcal * proteinShare / 4).rounded())
        let f = fatG ?? Int((kcal * fatShare / 9).rounded())
        let c = carbsG ?? max(Int(((kcal - Double(p) * 4 - Double(f) * 9) / 4).rounded()), 0)
        return DailyTargets(bmr: fallback?.bmr ?? 0, tdee: fallback?.tdee ?? 0, calorieTarget: calorieTarget,
                            proteinG: p, carbsG: c, fatG: f, isAdjustedForSafety: false)
    }
}

/// Descrizione testuale di un pasto, usata quando la foto non basta.
/// Regole identiche a `sanitizeFoodDescription` in `supabase/functions/_shared/nutrition.ts`.
public enum FoodDescription {
    public static let minLength = 3
    public static let maxLength = 500

    /// Rimuove caratteri di controllo e spazi superflui. Ritorna nil se il testo non è utilizzabile.
    public static func sanitize(_ text: String) -> String? {
        let cleaned = text.unicodeScalars
            .map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard cleaned.count >= minLength, cleaned.count <= maxLength,
              cleaned.contains(where: \.isLetter) else { return nil }
        return cleaned
    }
}
