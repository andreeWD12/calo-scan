import Foundation

/// Sesso biologico usato SOLO per le stime metaboliche. `.unspecified` è sempre ammesso.
public enum BiologicalSex: String, Codable, CaseIterable, Sendable {
    case male, female, unspecified
}

public enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary, lightlyActive = "lightly_active", moderatelyActive = "moderately_active"
    case veryActive = "very_active", extremelyActive = "extremely_active"

    /// Fattori PAL standard usati con Mifflin-St Jeor.
    public var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .lightlyActive: 1.375
        case .moderatelyActive: 1.55
        case .veryActive: 1.725
        case .extremelyActive: 1.9
        }
    }
}

public enum NutritionGoal: String, Codable, CaseIterable, Sendable {
    case loseWeight = "lose_weight", maintain, gainMuscle = "gain_muscle"
    case improveQuality = "improve_quality", trackOnly = "track_only"
}

public enum DietPreference: String, Codable, CaseIterable, Sendable {
    case omnivore, vegetarian, vegan, mediterranean, lowCarb = "low_carb", other
}

public enum Allergen: String, Codable, CaseIterable, Sendable {
    // I 14 allergeni del Reg. UE 1169/2011 (allegato II), più intolleranza al lattosio e voce libera.
    case gluten, milk, lactose, eggs, fish, shellfish, molluscs, peanuts, treeNuts = "tree_nuts", soy
    case celery, mustard, sesame, sulphites, lupin, other
}

/// Dati fisici necessari ai calcoli. Validati alla costruzione.
public struct BodyMetrics: Codable, Equatable, Sendable {
    public let ageYears: Int
    public let sex: BiologicalSex
    public let heightCm: Double
    public let weightKg: Double

    public static let ageRange = 13...100
    public static let heightRange = 100.0...250.0
    public static let weightRange = 30.0...350.0

    public init(ageYears: Int, sex: BiologicalSex, heightCm: Double, weightKg: Double) throws {
        guard Self.ageRange.contains(ageYears) else { throw ValidationError.outOfRange(field: "age") }
        guard Self.heightRange.contains(heightCm) else { throw ValidationError.outOfRange(field: "height") }
        guard Self.weightRange.contains(weightKg) else { throw ValidationError.outOfRange(field: "weight") }
        self.ageYears = ageYears
        self.sex = sex
        self.heightCm = heightCm
        self.weightKg = weightKg
    }

    /// Età compiuta a una certa data.
    public static func age(birthDate: Date, on date: Date = .now, calendar: Calendar = .init(identifier: .gregorian)) -> Int {
        calendar.dateComponents([.year], from: birthDate, to: date).year ?? 0
    }
}

public enum ValidationError: Error, Equatable, Sendable {
    case outOfRange(field: String)
}

/// Profilo nutrizionale dell'utente (dati inseriti nell'onboarding, modificabili dal Profilo).
public struct UserProfile: Codable, Equatable, Sendable {
    public var displayName: String
    public var birthDate: Date
    public var sex: BiologicalSex
    public var heightCm: Double
    public var weightKg: Double
    public var targetWeightKg: Double?
    public var activity: ActivityLevel
    public var goal: NutritionGoal
    public var diet: DietPreference
    public var otherDietNote: String?
    public var allergens: Set<Allergen>
    public var otherAllergyNote: String?
    /// Note libere su esigenze alimentari. Trattate come dato sanitario (art. 9 GDPR).
    public var dietaryNotes: String?
    /// Stile alimentare scelto con il coach (Plus e Pro). Nil se non scelto.
    public var eatingStyle: EatingStyleChoice?

    public init(
        displayName: String, birthDate: Date, sex: BiologicalSex, heightCm: Double, weightKg: Double,
        targetWeightKg: Double?, activity: ActivityLevel, goal: NutritionGoal, diet: DietPreference,
        otherDietNote: String? = nil, allergens: Set<Allergen> = [], otherAllergyNote: String? = nil,
        dietaryNotes: String? = nil, eatingStyle: EatingStyleChoice? = nil
    ) {
        self.displayName = displayName; self.birthDate = birthDate; self.sex = sex
        self.heightCm = heightCm; self.weightKg = weightKg; self.targetWeightKg = targetWeightKg
        self.activity = activity; self.goal = goal; self.diet = diet; self.otherDietNote = otherDietNote
        self.allergens = allergens; self.otherAllergyNote = otherAllergyNote; self.dietaryNotes = dietaryNotes
        self.eatingStyle = eatingStyle
    }

    public var bmi: Double { EatingStyleSafety.bmi(weightKg: weightKg, heightCm: heightCm) }

    public func ageYears(on date: Date = .now) -> Int { BodyMetrics.age(birthDate: birthDate, on: date) }

    public func metrics(on date: Date = .now) throws -> BodyMetrics {
        try BodyMetrics(ageYears: ageYears(on: date), sex: sex, heightCm: heightCm, weightKg: weightKg)
    }
}

/// Politiche d'età. 16 anni è la soglia più alta tra gli Stati UE per il consenso digitale
/// (art. 8 GDPR): adottarla vale in tutta l'Unione.
public enum AgePolicy {
    public static let minimumAccountAge = 16
}
