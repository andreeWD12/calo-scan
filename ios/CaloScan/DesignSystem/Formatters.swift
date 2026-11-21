import Foundation
import CaloScanCore

/// Formattazione numeri e date nella lingua dell'utente (es. "1.450 kcal" in italiano).
enum Format {
    static func kcal(_ value: Double) -> String {
        "\(Int(value.rounded()).formatted(.number)) kcal"
    }

    static func kcalNumber(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number)
    }

    static func grams(_ value: Double) -> String {
        "\(Int(value.rounded()).formatted(.number)) g"
    }

    static func kg(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) kg"
    }

    static func signedKg(_ value: Double) -> String {
        let s = value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
        return "\(s) kg"
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    static func dayTitle(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return String(localized: "Oggi") }
        if calendar.isDateInYesterday(date) { return String(localized: "Ieri") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

extension MealType {
    var title: String {
        switch self {
        case .breakfast: String(localized: "Colazione")
        case .lunch: String(localized: "Pranzo")
        case .dinner: String(localized: "Cena")
        case .snack: String(localized: "Spuntini")
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "carrot"
        }
    }

    /// Tipo di pasto suggerito in base all'ora corrente.
    static func suggested(for date: Date = .now, calendar: Calendar = .current) -> MealType {
        switch calendar.component(.hour, from: date) {
        case 5..<11: .breakfast
        case 11..<15: .lunch
        case 18..<23: .dinner
        default: .snack
        }
    }
}

extension FoodSource {
    var label: String {
        switch self {
        case .usda: "USDA FoodData Central"
        case .openFoodFacts: "Open Food Facts"
        case .custom: String(localized: "Inserito da te")
        }
    }
}

extension Text {
    /// Testo con link Markdown costruito da una stringa già localizzata e interpolata.
    init(markdown: String) {
        self.init((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
    }
}
