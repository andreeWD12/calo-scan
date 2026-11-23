import Foundation

public struct WeightEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var date: Date
    public var weightKg: Double

    public init(id: UUID = UUID(), date: Date, weightKg: Double) {
        self.id = id; self.date = date; self.weightKg = weightKg
    }
}

/// Misure corporee opzionali, tutte in centimetri.
public struct BodyMeasurement: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var date: Date
    public var waistCm: Double?
    public var hipsCm: Double?
    public var chestCm: Double?
    public var armCm: Double?
    public var thighCm: Double?

    public init(id: UUID = UUID(), date: Date, waistCm: Double? = nil, hipsCm: Double? = nil,
                chestCm: Double? = nil, armCm: Double? = nil, thighCm: Double? = nil) {
        self.id = id; self.date = date; self.waistCm = waistCm; self.hipsCm = hipsCm
        self.chestCm = chestCm; self.armCm = armCm; self.thighCm = thighCm
    }

    public var isEmpty: Bool { [waistCm, hipsCm, chestCm, armCm, thighCm].allSatisfy { $0 == nil } }

    /// Le singole misure, con i limiti di validità (gli stessi del database).
    public enum Kind: String, CaseIterable, Sendable {
        case waist, hips, chest, arm, thigh

        public var range: ClosedRange<Double> {
            switch self {
            case .waist, .hips, .chest: 30...250
            case .arm: 10...100
            case .thigh: 20...150
            }
        }

        public var keyPath: WritableKeyPath<BodyMeasurement, Double?> {
            switch self {
            case .waist: \.waistCm
            case .hips: \.hipsCm
            case .chest: \.chestCm
            case .arm: \.armCm
            case .thigh: \.thighCm
            }
        }
    }

    public func value(_ kind: Kind) -> Double? { self[keyPath: kind.keyPath] }

    /// Misure compilate ma fuori dai limiti.
    public var invalidKinds: [Kind] {
        Kind.allCases.filter { kind in value(kind).map { !kind.range.contains($0) } ?? false }
    }

    /// Variazione di ogni misura tra la prima rilevazione che la contiene e l'ultima (cm, negativo = diminuita).
    /// `history` può essere in qualsiasi ordine.
    public static func changes(in history: [BodyMeasurement]) -> [Kind: Double] {
        let sorted = history.sorted { $0.date < $1.date }
        var result: [Kind: Double] = [:]
        for kind in Kind.allCases {
            let values = sorted.compactMap { $0.value(kind) }
            if values.count >= 2, let first = values.first, let last = values.last {
                result[kind] = ((last - first) * 10).rounded() / 10
            }
        }
        return result
    }
}

public struct WeightProgress: Equatable, Sendable {
    public let start: Double
    public let current: Double
    public let goal: Double?

    /// Negativo = peso perso.
    public var change: Double { current - start }

    /// Avanzamento 0…1 verso il peso obiettivo, nil se l'obiettivo non è impostato o coincide con l'inizio.
    public var fractionToGoal: Double? {
        guard let goal, goal != start else { return nil }
        return min(max((current - start) / (goal - start), 0), 1)
    }

    public init?(entries: [WeightEntry], goal: Double?) {
        let sorted = entries.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        start = first.weightKg; current = last.weightKg; self.goal = goal
    }
}
