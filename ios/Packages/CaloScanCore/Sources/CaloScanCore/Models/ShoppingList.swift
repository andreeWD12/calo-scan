import Foundation

/// Reparti del supermercato usati per raggruppare la lista.
public enum ShoppingCategory: String, Codable, CaseIterable, Sendable {
    case produce, meatFish = "meat_fish", dairyEggs = "dairy_eggs", bakery, pantry, frozen, drinks, other

    private static let keywords: [(ShoppingCategory, [String])] = [
        (.produce, ["mela", "mele", "banan", "pera", "aranc", "limon", "frutt", "verdur", "insalat", "lattuga", "pomodor",
                    "zucchin", "carot", "patat", "cipoll", "aglio", "spinac", "broccol", "peperon", "melanzan", "funghi",
                    "avocado", "fragol", "kiwi", "uva", "rucola", "finocch", "cavol", "sedano", "basilico", "prezzemolo"]),
        (.meatFish, ["pollo", "tacchino", "manzo", "vitello", "maiale", "carne", "salmone", "tonno", "merluzzo", "pesce",
                     "gamber", "prosciutto", "bresaola", "salsicc", "orata", "branzino", "sgombro", "hamburger"]),
        (.dairyEggs, ["latte", "yogurt", "uov", "formagg", "mozzarell", "ricotta", "parmigian", "grana", "burro", "panna",
                      "kefir", "fiocchi di latte", "skyr"]),
        (.bakery, ["pane", "fette biscottate", "cracker", "grissin", "piadin", "focaccia", "brioche", "biscott"]),
        (.frozen, ["surgelat", "congelat", "gelato"]),
        (.drinks, ["acqua", "succo", "caffè", "caffe", "tè ", "tisana", "vino", "birra", "bevanda"]),
        (.pantry, ["pasta", "riso", "farro", "orzo", "quinoa", "avena", "farina", "olio", "aceto", "sale", "zucchero",
                   "legum", "ceci", "lenticch", "fagiol", "piselli", "passata", "pelati", "mandorl", "noci", "nocciol",
                   "miele", "marmellat", "cereali", "muesli", "spezie", "semi"]),
    ]

    /// Reparto suggerito dal nome del prodotto; l'utente può sempre cambiarlo.
    public static func guess(for name: String) -> ShoppingCategory {
        let lower = " " + name.lowercased() + " "
        for (category, words) in keywords where words.contains(where: { lower.contains($0) }) {
            return category
        }
        return .other
    }
}

public enum ShoppingItemSource: String, Codable, Sendable {
    case manual, plan, ai
}

/// Un prodotto della lista della spesa.
public struct ShoppingItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    /// Quantità libera: "500 g", "2 confezioni", "1 kg".
    public var quantity: String?
    public var category: ShoppingCategory
    public var isChecked: Bool
    public var source: ShoppingItemSource
    public var addedAt: Date

    public static let nameMaxLength = 80
    public static let quantityMaxLength = 30
    public static let maxItems = 200

    public init(id: UUID = UUID(), name: String, quantity: String? = nil, category: ShoppingCategory? = nil,
                isChecked: Bool = false, source: ShoppingItemSource = .manual, addedAt: Date = .now) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.category = category ?? ShoppingCategory.guess(for: name)
        self.isChecked = isChecked
        self.source = source
        self.addedAt = addedAt
    }

    /// Ripulisce nome e quantità inseriti dall'utente. Nil se il nome non è utilizzabile.
    public static func sanitized(name: String, quantity: String?) -> (String, String?)? {
        let n = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !n.isEmpty, n.count <= nameMaxLength else { return nil }
        let q = quantity?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let qty = (q?.isEmpty ?? true) ? nil : String(q!.prefix(quantityMaxLength))
        return (n, qty)
    }
}

/// Prodotto proposto dall'AI: l'utente sceglie quali aggiungere.
public struct ShoppingSuggestion: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var quantity: String?
    public var category: ShoppingCategory
    /// Perché viene proposto, es. "Per raggiungere le proteine a cena".
    public var reason: String?

    public init(id: UUID = UUID(), name: String, quantity: String? = nil, category: ShoppingCategory? = nil, reason: String? = nil) {
        self.id = id; self.name = name; self.quantity = quantity
        self.category = category ?? ShoppingCategory.guess(for: name); self.reason = reason
    }

    public func asItem() -> ShoppingItem {
        ShoppingItem(name: name, quantity: quantity, category: category, source: .ai)
    }
}

public enum ShoppingListBuilder {
    /// Prodotti necessari per seguire il piano del professionista per i prossimi `days` giorni,
    /// sommando le grammature dello stesso alimento. Non usa l'AI: è gratuito per tutti.
    public static func items(from plan: ProfessionalPlan, startingAt start: Date = .now, days: Int = 7,
                             calendar: Calendar = .current) -> [ShoppingItem] {
        var totals: [String: (name: String, grams: Double)] = [:]
        var order: [String] = []
        for offset in 0..<max(days, 0) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            for meal in plan.plannedMeals(on: date, calendar: calendar) {
                for food in meal.foods {
                    let key = food.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    if totals[key] == nil { order.append(key) }
                    totals[key, default: (food.name, 0)].grams += food.grams
                }
            }
        }
        return order.compactMap { key in
            guard let entry = totals[key] else { return nil }
            return ShoppingItem(name: entry.name, quantity: formatGrams(entry.grams), source: .plan)
        }
    }

    /// Aggiunge prodotti alla lista senza duplicare quelli già presenti e non ancora presi.
    public static func merge(_ new: [ShoppingItem], into list: [ShoppingItem]) -> [ShoppingItem] {
        var result = list
        for item in new {
            let key = item.name.lowercased()
            if let i = result.firstIndex(where: { $0.name.lowercased() == key && !$0.isChecked }) {
                if result[i].quantity == nil { result[i].quantity = item.quantity }
            } else if result.count < ShoppingItem.maxItems {
                result.append(item)
            }
        }
        return result
    }

    static func formatGrams(_ grams: Double) -> String {
        grams >= 1000
            ? "\((grams / 1000).formatted(.number.precision(.fractionLength(0...1)))) kg"
            : "\(Int(grams.rounded())) g"
    }
}
