import Foundation

/// Consigli del giorno del coach, calcolati sul telefono con regole fisse: niente AI, gratuiti per tutti i piani.
/// Tono sempre incoraggiante e mai colpevolizzante; non suggeriscono mai di mangiare meno dell'obiettivo.
public struct DailyTip: Equatable, Sendable {
    public enum Tone: String, Sendable { case positive, suggestion, info }
    public let text: String
    public let tone: Tone
}

public enum DailyTips {
    public static let maxTips = 3

    /// - Parameters:
    ///   - today: pasti di oggi.
    ///   - recent: giorni precedenti (fino a 7), oggi escluso.
    ///   - targets: obiettivi effettivi (piano del professionista, gravidanza o calcolati).
    public static func make(today: DayLog, recent: [DayLog], targets: DailyTargets?, diet: DietPreference?,
                            allergens: Set<Allergen>, now: Date = .now, calendar: Calendar = .current) -> [DailyTip] {
        var tips: [DailyTip] = []
        let hour = calendar.component(.hour, from: now)
        let totals = today.totals

        if today.isEmpty {
            tips.append(DailyTip(text: hour < 11
                ? String(localized: "Inizia registrando la colazione: con la ricerca o il codice a barre bastano pochi secondi.")
                : String(localized: "Non hai ancora registrato pasti oggi. Puoi aggiungerli quando vuoi, anche a fine giornata."),
                tone: .info))
        } else if let t = targets, t.calorieTarget > 0 {
            let target = Double(t.calorieTarget)
            let remaining = target - totals.kcal
            if totals.kcal > target * 1.1 {
                tips.append(DailyTip(text: String(localized: "Oggi sei sopra l'obiettivo di circa \(rounded(-remaining)) kcal. Nessun problema: conta l'andamento della settimana, non il singolo giorno."), tone: .info))
            } else if remaining > 150 {
                tips.append(DailyTip(text: String(localized: "Oggi hai ancora circa \(rounded(remaining)) kcal a disposizione."), tone: .info))
            } else {
                tips.append(DailyTip(text: String(localized: "Sei in linea con l'obiettivo di oggi."), tone: .positive))
            }

            let protein = Double(t.proteinG)
            if protein > 0 {
                if hour >= 15, totals.proteinG < protein * 0.6 {
                    let ideas = proteinIdeas(diet: diet, allergens: allergens)
                    let text = ideas.isEmpty
                        ? String(localized: "Ti mancano circa \(rounded(protein - totals.proteinG)) g di proteine: nel prossimo pasto puoi includerne una fonte.")
                        : String(localized: "Ti mancano circa \(rounded(protein - totals.proteinG)) g di proteine: nel prossimo pasto puoi includere \(ideas).")
                    tips.append(DailyTip(text: text, tone: .suggestion))
                } else if totals.proteinG >= protein * 0.9 {
                    tips.append(DailyTip(text: String(localized: "Proteine di oggi quasi raggiunte: ben fatto."), tone: .positive))
                }
            }
        }

        let logged = recent.filter { !$0.isEmpty }
        if logged.count >= 5 {
            tips.append(DailyTip(text: String(localized: "Hai registrato i pasti in \(logged.count) degli ultimi 7 giorni: ottima costanza!"), tone: .positive))
        }
        if let t = targets, t.calorieTarget > 0, logged.count >= 4 {
            let average = logged.map(\.totals.kcal).reduce(0, +) / Double(logged.count)
            if abs(average - Double(t.calorieTarget)) <= Double(t.calorieTarget) * 0.1 {
                tips.append(DailyTip(text: String(localized: "Negli ultimi giorni la media è di \(rounded(average)) kcal, in linea con l'obiettivo."), tone: .positive))
            }
        }
        return Array(tips.prefix(maxTips))
    }

    /// Fino a tre fonti di proteine compatibili con alimentazione e allergeni, es. "legumi, uova o pesce".
    static func proteinIdeas(diet: DietPreference?, allergens: Set<Allergen>) -> String {
        let vegan = diet == .vegan, vegetarian = vegan || diet == .vegetarian
        let all: [(String, Bool)] = [
            (String(localized: "legumi"), true),
            (String(localized: "uova"), !vegan && !allergens.contains(.eggs)),
            (String(localized: "pesce"), !vegetarian && !allergens.contains(.fish)),
            (String(localized: "carne bianca"), !vegetarian),
            (String(localized: "yogurt greco"), !vegan && allergens.isDisjoint(with: [.milk, .lactose])),
            (String(localized: "tofu"), !allergens.contains(.soy)),
        ]
        let names = all.filter(\.1).map(\.0).prefix(3)
        guard let last = names.last else { return "" }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + String(localized: " o ") + last
    }

    private static func rounded(_ v: Double) -> Int { Int((v / 10).rounded() * 10) }
}
