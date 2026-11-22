import Foundation

/// Modalità gravidanza. Gratuita per tutti: è una funzione di sicurezza alimentare, non un piano dietetico.
///
/// Fonti: Ministero della Salute e ISS (alimentazione e sicurezza alimentare in gravidanza),
/// EFSA (valori di riferimento per energia 2013 e proteine 2012; caffeina 2015).
/// CaloScan non sostituisce ginecologo, ostetrica o dietista: le indicazioni sono informative.
/// Regole identiche a `supabase/functions/_shared/pregnancy.ts`.
public struct PregnancyInfo: Codable, Equatable, Sendable {
    /// Data presunta del parto.
    public var dueDate: Date
    /// Immunità alla toxoplasmosi (dal test del primo trimestre). Nil = non lo so.
    public var toxoplasmosisImmune: Bool?

    public init(dueDate: Date, toxoplasmosisImmune: Bool? = nil) {
        self.dueDate = dueDate; self.toxoplasmosisImmune = toxoplasmosisImmune
    }

    /// La data presunta del parto deve cadere tra oggi e 42 settimane da oggi.
    public static func isValidDueDate(_ date: Date, today: Date = .now, calendar: Calendar = .current) -> Bool {
        let days = daysUntil(date, from: today, calendar: calendar)
        return days >= 0 && days <= 294
    }

    static func daysUntil(_ date: Date, from: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// Settimane compiute di gravidanza (1…42), contate dalla data presunta del parto (= 40 settimane).
    public func week(on date: Date = .now, calendar: Calendar = .current) -> Int {
        let days = Self.daysUntil(dueDate, from: date, calendar: calendar)
        let elapsed = 280 - days
        return min(max(Int((Double(elapsed) / 7).rounded(.down)), 1), 42)
    }

    public func trimester(on date: Date = .now, calendar: Calendar = .current) -> Int {
        let w = week(on: date, calendar: calendar)
        return w <= 13 ? 1 : (w <= 27 ? 2 : 3)
    }

    /// La modalità resta attiva fino a 2 settimane dopo la data presunta, poi l'app chiede di aggiornarla.
    public func isActive(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        Self.daysUntil(dueDate, from: date, calendar: calendar) >= -14
    }
}

public enum PregnancyNutrition {
    /// Energia aggiuntiva al giorno per trimestre (EFSA 2013).
    public static func extraKcal(trimester: Int) -> Int { [70, 260, 500][min(max(trimester, 1), 3) - 1] }
    /// Proteine aggiuntive al giorno per trimestre (EFSA 2012).
    public static func extraProteinG(trimester: Int) -> Int { [1, 9, 28][min(max(trimester, 1), 3) - 1] }

    /// Obiettivi in gravidanza: mai in deficit. Mantenimento + energia e proteine aggiuntive del trimestre;
    /// grassi al 30% delle kcal, carboidrati il resto. Identico a `pregnancyTargets` (TS).
    public static func targets(metrics m: BodyMetrics, activity: ActivityLevel, diet: DietPreference,
                               trimester: Int) -> DailyTargets {
        let base = EnergyCalculator.targets(metrics: m, activity: activity, goal: .maintain, diet: diet)
        let kcal = Double(base.calorieTarget + extraKcal(trimester: trimester))
        let protein = Double(base.proteinG + extraProteinG(trimester: trimester))
        let fat = max(kcal * 0.30 / 9, m.weightKg * 0.6)
        let carbs = max((kcal - protein * 4 - fat * 9) / 4, 0)
        return DailyTargets(bmr: base.bmr, tdee: base.tdee, calorieTarget: Int(kcal.rounded()),
                            proteinG: Int(protein.rounded()), carbsG: Int(carbs.rounded()), fatG: Int(fat.rounded()),
                            isAdjustedForSafety: false)
    }
}

/// Esito del controllo di un alimento in gravidanza.
public struct PregnancyFoodFlag: Equatable, Sendable {
    public enum Level: String, Codable, Sendable { case avoid, limit }
    public enum Risk: String, Codable, Sendable {
        case toxoplasmosis, listeria, salmonella, mercury, alcohol, caffeine, vitaminA = "vitamin_a", glycyrrhizin
    }
    public let level: Level
    public let risk: Risk
}

/// Riconoscimento per parole chiave del nome dell'alimento. Non può essere completo:
/// l'interfaccia lo dice sempre ("controlla anche l'etichetta e chiedi al ginecologo").
public enum PregnancyFoodSafety {
    struct Rule {
        let level: PregnancyFoodFlag.Level
        let risk: PregnancyFoodFlag.Risk
        let words: [String]
        var unless: [String] = []
        /// Regola che si allenta se l'utente è immune alla toxoplasmosi.
        var toxoplasmosisOnly = false
    }

    static let rules: [Rule] = [
        Rule(level: .avoid, risk: .alcohol,
             words: ["vino", "birra", "spritz", "prosecco", "spumante", "champagne", "liquor", "grappa", "amaro ",
                     "limoncello", "cocktail", "aperitivo alcolico", " rum", " vodka", " whisky", " gin ", "sangria", "alcol"],
             unless: ["analcolic", "senza alcol", "aceto", "0,0", "0.0", "lievito"]),
        Rule(level: .avoid, risk: .toxoplasmosis,
             words: ["carne cruda", "al sangue", "carpaccio di manzo", "carpaccio di carne", "tartare di manzo", "tartare di carne",
                     "battuta di", "salsiccia cruda"]),
        Rule(level: .avoid, risk: .toxoplasmosis,
             words: ["prosciutto crudo", "crudo di parma", "san daniele", "salame", "salami", "speck", "coppa", "bresaola",
                     "lardo", "culatello", "pancetta", "nduja", "'nduja", "soppressata", "finocchiona", "guanciale"],
             unless: ["cotto", "cotta", "cioccolat", "gelato", "carbonara", "amatriciana", "gricia", "rosolat", "croccant"], toxoplasmosisOnly: true),
        Rule(level: .avoid, risk: .listeria,
             words: ["sushi", "sashimi", "pesce crudo", "crudo di pesce", "carpaccio di pesce", "carpaccio di salmone",
                     "carpaccio di tonno", "tartare di salmone", "tartare di tonno", "tartare di pesce", "ostric", "cozze crude",
                     "ricci di mare", "ceviche", "alici marinate", "acciughe marinate", "poke"],
             unless: ["cotto", "cotta", "cotti", "vegetarian", "vegan"]),
        Rule(level: .avoid, risk: .listeria,
             words: ["salmone affumicato", "pesce affumicato", "pesce spada affumicato", "tonno affumicato", "trota affumicata"]),
        Rule(level: .avoid, risk: .salmonella,
             words: ["uovo crudo", "uova crude", "tiramis", "zabaion", "maionese fatta in casa", "maionese casalinga",
                     "mousse", "crema al mascarpone", "uovo alla coque", "uova alla coque"],
             unless: ["senza uova", "pastorizzat"]),
        Rule(level: .avoid, risk: .listeria,
             words: ["latte crudo", "a latte crudo", "brie", "camembert", "gorgonzola", "roquefort", "taleggio", "erborinat",
                     "crosta fiorita", "formaggio fresco non pastorizzato"],
             unless: ["pastorizzat", "cotto", "cotta", "al forno"]),
        Rule(level: .avoid, risk: .vitaminA, words: ["fegato", "paté", "patè", "pate ", "foie gras"]),
        Rule(level: .avoid, risk: .mercury, words: ["pesce spada", "squalo", "verdesca", "palombo", "smeriglio", "marlin", "luccio"]),
        Rule(level: .avoid, risk: .listeria, words: ["germogli"], unless: ["cotti", "saltati"]),
        Rule(level: .avoid, risk: .caffeine, words: ["energy drink", "red bull", "monster energy", "bevanda energetica"]),
        Rule(level: .limit, risk: .mercury, words: ["tonno"]),
        Rule(level: .limit, risk: .caffeine,
             words: ["caffè", "caffe ", "espresso", "cappuccino", "macchiato", "tè ", "te verde", "tè verde", "tè nero", " cola"],
             unless: ["decaffeinat", "deteinat", "orzo", "ginseng senza"]),
        Rule(level: .limit, risk: .glycyrrhizin, words: ["liquirizia"]),
    ]

    /// Il primo rischio trovato nel nome, oppure nil.
    public static func check(_ name: String, toxoplasmosisImmune: Bool? = nil) -> PregnancyFoodFlag? {
        let text = " " + name.lowercased().replacingOccurrences(of: "’", with: "'") + " "
        for rule in rules {
            guard rule.words.contains(where: { text.contains($0) }),
                  !rule.unless.contains(where: { text.contains($0) }) else { continue }
            if rule.toxoplasmosisOnly && toxoplasmosisImmune == true {
                // Immune alla toxoplasmosi: resta il rischio listeria dei salumi crudi, quindi "con moderazione".
                return PregnancyFoodFlag(level: .limit, risk: .listeria)
            }
            return PregnancyFoodFlag(level: rule.level, risk: rule.risk)
        }
        return nil
    }
}
