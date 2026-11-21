import Foundation

/// Valori nutrizionali. Tutte le grandezze sono in kcal o grammi.
public struct Nutrients: Codable, Equatable, Hashable, Sendable {
    public var kcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double

    public init(kcal: Double, proteinG: Double, carbsG: Double, fatG: Double) {
        self.kcal = kcal; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
    }

    public static let zero = Nutrients(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0)

    /// Scala valori "per 100 g" sulla quantità indicata.
    public func scaled(per100gTo grams: Double) -> Nutrients {
        let f = max(grams, 0) / 100
        return Nutrients(kcal: kcal * f, proteinG: proteinG * f, carbsG: carbsG * f, fatG: fatG * f)
    }

    public static func + (l: Nutrients, r: Nutrients) -> Nutrients {
        Nutrients(kcal: l.kcal + r.kcal, proteinG: l.proteinG + r.proteinG,
                  carbsG: l.carbsG + r.carbsG, fatG: l.fatG + r.fatG)
    }
}

public extension Sequence where Element == Nutrients {
    var total: Nutrients { reduce(.zero, +) }
}

public enum MealType: String, Codable, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack
}
