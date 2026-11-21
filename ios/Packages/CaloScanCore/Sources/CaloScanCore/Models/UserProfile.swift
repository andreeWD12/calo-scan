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
    case gluten, lactose, treeNuts = "tree_nuts", peanuts, eggs, fish, shellfish, soy, sesame, other
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
