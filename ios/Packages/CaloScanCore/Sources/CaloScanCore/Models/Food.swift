import Foundation

/// Origine dei valori nutrizionali. L'app mostra sempre la fonte all'utente.
public enum FoodSource: String, Codable, Sendable {
    case usda, openFoodFacts = "open_food_facts", custom
}

/// Alimento con valori per 100 g provenienti da un database attendibile (o creato dall'utente).
public struct FoodItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var brand: String?
    public var per100g: Nutrients
    public var source: FoodSource
    public var defaultServingG: Double?

    public init(id: UUID = UUID(), name: String, brand: String? = nil, per100g: Nutrients,
                source: FoodSource, defaultServingG: Double? = nil) {
        self.id = id; self.name = name; self.brand = brand; self.per100g = per100g
        self.source = source; self.defaultServingG = defaultServingG
    }
}

public struct MealItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var food: FoodItem
    public var grams: Double

    public static let gramsRange = 1.0...3000.0

    public init(id: UUID = UUID(), food: FoodItem, grams: Double) {
        self.id = id; self.food = food
        self.grams = min(max(grams, Self.gramsRange.lowerBound), Self.gramsRange.upperBound)
    }

    public var nutrients: Nutrients { food.per100g.scaled(per100gTo: grams) }
}

/// `description`: alimenti riconosciuti dall'AI a partire da una descrizione scritta dall'utente.
/// `plan`: pasto registrato dal piano del professionista.
public enum MealSource: String, Codable, Sendable { case scan, description, manual, plan }

public struct Meal: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var type: MealType
    public var loggedAt: Date
    public var items: [MealItem]
    public var source: MealSource
    public var scanID: UUID?
    /// Sgarro (pasto fuori dal piano o dalle abitudini). Conta nelle calorie del giorno
    /// come ogni altro pasto; le statistiche lo mostrano anche a parte.
    public var isCheatMeal: Bool

    public init(id: UUID = UUID(), type: MealType, loggedAt: Date, items: [MealItem],
                source: MealSource, scanID: UUID? = nil, isCheatMeal: Bool = false) {
        self.id = id; self.type = type; self.loggedAt = loggedAt; self.items = items
        self.source = source; self.scanID = scanID; self.isCheatMeal = isCheatMeal
    }

    private enum CodingKeys: String, CodingKey { case id, type, loggedAt, items, source, scanID, isCheatMeal }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        type = try c.decode(MealType.self, forKey: .type)
        loggedAt = try c.decode(Date.self, forKey: .loggedAt)
        items = try c.decode([MealItem].self, forKey: .items)
        source = try c.decode(MealSource.self, forKey: .source)
        scanID = try c.decodeIfPresent(UUID.self, forKey: .scanID)
        isCheatMeal = try c.decodeIfPresent(Bool.self, forKey: .isCheatMeal) ?? false
    }

    public var totals: Nutrients { items.map(\.nutrients).total }
}

/// Tutti i pasti di un giorno di calendario.
public struct DayLog: Codable, Hashable, Sendable {
    public let day: Date           // inizio del giorno nel fuso dell'utente
    public var meals: [Meal]

    public init(day: Date, meals: [Meal]) { self.day = day; self.meals = meals }

    public var totals: Nutrients { meals.map(\.totals).total }
    public func meals(of type: MealType) -> [Meal] { meals.filter { $0.type == type } }
    public func totals(of type: MealType) -> Nutrients { meals(of: type).map(\.totals).total }
    public var isEmpty: Bool { meals.allSatisfy(\.items.isEmpty) }
}

/// Affidabilità di una stima dell'AI, derivata dal punteggio 0…1 restituito dal server.
public enum Confidence: String, Codable, Sendable {
    case low, medium, high
    public init(score: Double) {
        switch score {
        case ..<0.5: self = .low
        case ..<0.8: self = .medium
        default: self = .high
        }
    }
}

/// Un alimento riconosciuto in una foto. `matchedFood` è nil se nessun database ha dato un riscontro affidabile.
public struct ScannedItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var detectedName: String
    public var matchedFood: FoodItem?
    public var estimatedGrams: Double
    public var confidenceScore: Double
    public var ingredients: [String]

    public init(id: UUID = UUID(), detectedName: String, matchedFood: FoodItem?, estimatedGrams: Double,
                confidenceScore: Double, ingredients: [String] = []) {
        self.id = id; self.detectedName = detectedName; self.matchedFood = matchedFood
        self.estimatedGrams = estimatedGrams; self.confidenceScore = confidenceScore; self.ingredients = ingredients
    }

    public var confidence: Confidence { Confidence(score: confidenceScore) }
    public var needsReview: Bool { matchedFood == nil || confidence == .low }
}

public struct ScanResult: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var items: [ScannedItem]
    /// Domande di chiarimento generate dall'analisi (es. "Quanto olio è stato usato?").
    public var questions: [String]
    public var overallConfidenceScore: Double

    public init(id: UUID, items: [ScannedItem], questions: [String], overallConfidenceScore: Double) {
        self.id = id; self.items = items; self.questions = questions
        self.overallConfidenceScore = overallConfidenceScore
    }
}
