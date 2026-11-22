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
    /// Pasti con alimenti e grammature, copiati dall'utente dal piano. Vuoto se non inseriti.
    public var mealPlan: [PlannedDay]

    public static let calorieRange = 800...6000
    public static let macroRange = 0...1000
    public static let notesMaxLength = 1000
    public static let nameMaxLength = 80
    /// Tolleranza tra le kcal dei macronutrienti indicati e l'obiettivo calorico (arrotondamenti del piano).
    public static let macroTolerance = 0.15
    public static let maxFoodsPerMeal = 30

    public init(professional: HealthProfessional, professionalName: String? = nil, calorieTarget: Int,
                proteinG: Int? = nil, carbsG: Int? = nil, fatG: Int? = nil, notes: String? = nil,
                startDate: Date, reviewDate: Date? = nil, confirmedAt: Date, mealPlan: [PlannedDay] = []) {
        self.professional = professional; self.professionalName = professionalName
        self.calorieTarget = calorieTarget; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
        self.notes = notes; self.startDate = startDate; self.reviewDate = reviewDate; self.confirmedAt = confirmedAt
        self.mealPlan = mealPlan
    }

    private enum CodingKeys: String, CodingKey {
        case professional, professionalName, calorieTarget, proteinG, carbsG, fatG, notes, startDate, reviewDate
        case confirmedAt, mealPlan
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        professional = try c.decode(HealthProfessional.self, forKey: .professional)
        professionalName = try c.decodeIfPresent(String.self, forKey: .professionalName)
        calorieTarget = try c.decode(Int.self, forKey: .calorieTarget)
        proteinG = try c.decodeIfPresent(Int.self, forKey: .proteinG)
        carbsG = try c.decodeIfPresent(Int.self, forKey: .carbsG)
        fatG = try c.decodeIfPresent(Int.self, forKey: .fatG)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        startDate = try c.decode(Date.self, forKey: .startDate)
        reviewDate = try c.decodeIfPresent(Date.self, forKey: .reviewDate)
        confirmedAt = try c.decode(Date.self, forKey: .confirmedAt)
        mealPlan = try c.decodeIfPresent([PlannedDay].self, forKey: .mealPlan) ?? []
    }

    public enum Issue: String, Equatable, Sendable {
        case caloriesOutOfRange, macroOutOfRange, macrosDoNotMatchCalories, notesTooLong, nameTooLong, reviewBeforeStart
        case mealPlanInvalid
    }

    /// Pasti previsti per una data: il giorno della settimana corrispondente, altrimenti quello valido ogni giorno.
    public func plannedMeals(on date: Date, calendar: Calendar = .current) -> [PlannedMeal] {
        let weekday = calendar.component(.weekday, from: date)
        let day = mealPlan.first { $0.weekday == weekday } ?? mealPlan.first { $0.weekday == nil }
        return day?.meals.filter { !$0.foods.isEmpty } ?? []
    }

    public func plannedMeal(_ type: MealType, on date: Date, calendar: Calendar = .current) -> PlannedMeal? {
        plannedMeals(on: date, calendar: calendar).first { $0.type == type }
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
        if !Self.isValid(mealPlan: mealPlan) { issues.append(.mealPlanInvalid) }
        return issues
    }

    static func isValid(mealPlan: [PlannedDay]) -> Bool {
        guard mealPlan.count <= 8 else { return false }
        let weekdays = mealPlan.map(\.weekday)
        guard Set(weekdays).count == weekdays.count,
              weekdays.allSatisfy({ $0.map { (1...7).contains($0) } ?? true }) else { return false }
        for day in mealPlan {
            let types = day.meals.map(\.type)
            guard Set(types).count == types.count else { return false }
            for meal in day.meals {
                guard meal.foods.count <= maxFoodsPerMeal else { return false }
                for food in meal.foods {
                    let name = food.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, name.count <= nameMaxLength, MealItem.gramsRange.contains(food.grams) else { return false }
                }
            }
        }
        return true
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

/// Un alimento del piano con la sua grammatura. `food` è la corrispondenza nel database
/// (USDA / Open Food Facts) scelta dall'utente: senza, l'alimento resta nel piano ma non ha valori nutrizionali.
public struct PlannedFood: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var grams: Double
    public var food: FoodItem?

    public init(id: UUID = UUID(), name: String, grams: Double, food: FoodItem? = nil) {
        self.id = id; self.name = name; self.grams = grams; self.food = food
    }

    public var nutrients: Nutrients? { food?.per100g.scaled(per100gTo: grams) }
}

public struct PlannedMeal: Identifiable, Codable, Hashable, Sendable {
    public var id: MealType { type }
    public var type: MealType
    public var foods: [PlannedFood]

    public init(type: MealType, foods: [PlannedFood] = []) { self.type = type; self.foods = foods }

    /// Totale dei soli alimenti con valori nutrizionali.
    public var totals: Nutrients { foods.compactMap(\.nutrients).total }
    public var unmatchedCount: Int { foods.filter { $0.food == nil }.count }

    /// Voci del diario per registrare il pasto: solo gli alimenti con valori nutrizionali.
    public func mealItems() -> [MealItem] {
        foods.compactMap { planned in planned.food.map { MealItem(food: $0, grams: planned.grams) } }
    }
}

/// Pasti di un giorno del piano. `weekday` segue `Calendar` (1 = domenica … 7 = sabato);
/// nil = valido per tutti i giorni.
public struct PlannedDay: Identifiable, Codable, Hashable, Sendable {
    public var id: Int { weekday ?? 0 }
    public var weekday: Int?
    public var meals: [PlannedMeal]

    public init(weekday: Int?, meals: [PlannedMeal] = MealType.allCases.map { PlannedMeal(type: $0) }) {
        self.weekday = weekday; self.meals = meals
    }

    public var totals: Nutrients { meals.map(\.totals).total }
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
