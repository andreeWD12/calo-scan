import Foundation

/// Stili alimentari che l'utente può scegliere insieme al coach (Plus e Pro).
///
/// Catalogo chiuso: il coach AI può solo proporre voci di questo elenco, mai protocolli diversi
/// (niente digiuni oltre 16 ore, 5:2, chetogenica, diete a bassissimo contenuto calorico).
/// Sono indicazioni di benessere, non trattamenti: CaloScan non è un dispositivo medico (MDR).
/// Catalogo e regole identici a `supabase/functions/_shared/eatingStyle.ts`.
public enum EatingStyle: String, Codable, CaseIterable, Sendable {
    case balanced
    case mediterranean
    case highProtein = "high_protein"
    case moderateLowCarb = "moderate_low_carb"
    case vegetarian
    case vegan
    case fasting12 = "fasting_12_12"
    case fasting14 = "fasting_14_10"
    case fasting16 = "fasting_16_8"

    /// Ore della finestra in cui si mangia, per i digiuni intermittenti a finestra (time-restricted eating).
    public var eatingWindowHours: Int? {
        switch self {
        case .fasting12: 12
        case .fasting14: 10
        case .fasting16: 8
        default: nil
        }
    }

    public var isFasting: Bool { eatingWindowHours != nil }

    /// Stili che riducono un gruppo di alimenti o il tempo per mangiare: richiedono più cautela.
    public var isRestrictive: Bool {
        switch self {
        case .moderateLowCarb, .fasting12, .fasting14, .fasting16: true
        default: false
        }
    }
}

/// Risposte alle domande di sicurezza. Tutte obbligatorie: senza risposta lo stile resta bloccato.
public struct EatingStyleScreening: Codable, Equatable, Sendable {
    public var pregnantOrBreastfeeding: Bool
    /// Diabete trattato con insulina o farmaci che possono dare ipoglicemia.
    public var diabetesMedication: Bool
    /// Disturbi alimentari attuali o passati.
    public var eatingDisorderHistory: Bool
    /// Altre condizioni seguite da un medico (es. malattie renali, epatiche, cardiache, farmaci da assumere ai pasti).
    public var medicalSupervision: Bool

    public init(pregnantOrBreastfeeding: Bool = false, diabetesMedication: Bool = false,
                eatingDisorderHistory: Bool = false, medicalSupervision: Bool = false) {
        self.pregnantOrBreastfeeding = pregnantOrBreastfeeding; self.diabetesMedication = diabetesMedication
        self.eatingDisorderHistory = eatingDisorderHistory; self.medicalSupervision = medicalSupervision
    }
}

/// Perché uno stile non è disponibile. L'app spiega il motivo senza giudizi e invita a parlarne col medico.
public enum EatingStyleBlock: String, Codable, Sendable {
    case professionalPlan = "professional_plan"
    case underAge = "under_age"
    case lowBMI = "low_bmi"
    case pregnancy
    case diabetesMedication = "diabetes_medication"
    case eatingDisorder = "eating_disorder"
    case medicalSupervision = "medical_supervision"
}

public enum EatingStyleSafety {
    /// Età minima per i digiuni intermittenti (l'app è dai 16 anni).
    public static let fastingMinimumAge = 18
    public static let minimumBMI = 18.5

    /// Motivi per cui `style` non va proposto. Vuoto = disponibile.
    /// Con un piano del professionista nessuno stile è modificabile qui: vale il piano.
    public static func blocks(for style: EatingStyle, ageYears: Int, bmi: Double,
                              screening: EatingStyleScreening, hasProfessionalPlan: Bool) -> [EatingStyleBlock] {
        if hasProfessionalPlan { return [.professionalPlan] }
        var b: [EatingStyleBlock] = []
        if style.isFasting {
            if ageYears < fastingMinimumAge { b.append(.underAge) }
            if bmi < minimumBMI { b.append(.lowBMI) }
        }
        if style.isRestrictive {
            if screening.pregnantOrBreastfeeding { b.append(.pregnancy) }
            if screening.diabetesMedication { b.append(.diabetesMedication) }
            if screening.eatingDisorderHistory { b.append(.eatingDisorder) }
            if screening.medicalSupervision { b.append(.medicalSupervision) }
        }
        return b
    }

    public static func allowedStyles(ageYears: Int, bmi: Double, screening: EatingStyleScreening,
                                     hasProfessionalPlan: Bool) -> [EatingStyle] {
        EatingStyle.allCases.filter {
            blocks(for: $0, ageYears: ageYears, bmi: bmi, screening: screening, hasProfessionalPlan: hasProfessionalPlan).isEmpty
        }
    }

    public static func bmi(weightKg: Double, heightCm: Double) -> Double {
        guard heightCm > 0 else { return 0 }
        let m = heightCm / 100
        return weightKg / (m * m)
    }
}

/// Finestra in cui si mangia, per gli stili a digiuno intermittente. Ore locali.
public struct EatingWindow: Codable, Equatable, Sendable {
    /// Minuti dalla mezzanotte in cui inizia la finestra (es. 12:00 = 720).
    public var startMinute: Int
    public var hours: Int

    public init(startMinute: Int, hours: Int) {
        self.startMinute = ((startMinute % 1440) + 1440) % 1440
        self.hours = hours
    }

    public var endMinute: Int { (startMinute + hours * 60) % 1440 }

    /// `true` se all'istante indicato si è dentro la finestra in cui si mangia.
    public func isEating(at date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let offset = ((m - startMinute) % 1440 + 1440) % 1440
        return offset < hours * 60
    }

    /// Prossimo cambio (inizio o fine della finestra) dopo `date`.
    public func nextChange(after date: Date, calendar: Calendar = .current) -> Date {
        let target = isEating(at: date, calendar: calendar) ? endMinute : startMinute
        let day = calendar.startOfDay(for: date)
        let candidate = calendar.date(byAdding: .minute, value: target, to: day) ?? date
        return candidate > date ? candidate : (calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate)
    }
}

/// Stile scelto dall'utente. Salvato nel profilo (dato sanitario, art. 9 GDPR).
public struct EatingStyleChoice: Codable, Equatable, Sendable {
    public var style: EatingStyle
    /// Solo per i digiuni intermittenti.
    public var window: EatingWindow?
    public var chosenAt: Date
    /// Promemoria di inizio/fine finestra: spenti finché l'utente non li attiva.
    public var remindersEnabled: Bool

    public init(style: EatingStyle, window: EatingWindow? = nil, chosenAt: Date = .now, remindersEnabled: Bool = false) {
        self.style = style
        self.window = style.isFasting ? (window.map { EatingWindow(startMinute: $0.startMinute, hours: style.eatingWindowHours!) }
                                         ?? EatingWindow(startMinute: 12 * 60, hours: style.eatingWindowHours!)) : nil
        self.chosenAt = chosenAt
        self.remindersEnabled = remindersEnabled
    }
}

/// Proposta del coach: uno stile del catalogo con la motivazione per l'utente.
public struct EatingStyleProposal: Identifiable, Codable, Equatable, Sendable {
    public var id: EatingStyle { style }
    public var style: EatingStyle
    /// Perché è adatto a questo utente, scritto dal coach (max 300 caratteri, ripulito dal server).
    public var reason: String
    /// Come iniziare in modo graduale.
    public var firstSteps: [String]

    public init(style: EatingStyle, reason: String, firstSteps: [String] = []) {
        self.style = style; self.reason = reason; self.firstSteps = firstSteps
    }
}

/// Preferenze raccolte prima di chiedere le proposte al coach.
public struct EatingStyleRequest: Codable, Equatable, Sendable {
    public enum MealsPerDay: String, Codable, CaseIterable, Sendable { case two, three, fourOrMore = "four_or_more" }
    public enum Hunger: String, Codable, CaseIterable, Sendable { case morning, evening, even }

    public var screening: EatingStyleScreening
    public var mealsPerDay: MealsPerDay
    public var hunger: Hunger
    public var trainsRegularly: Bool
    /// Nota libera, es. "lavoro su turni" (max 300 caratteri).
    public var note: String?

    public init(screening: EatingStyleScreening, mealsPerDay: MealsPerDay = .three, hunger: Hunger = .even,
                trainsRegularly: Bool = false, note: String? = nil) {
        self.screening = screening; self.mealsPerDay = mealsPerDay; self.hunger = hunger
        self.trainsRegularly = trainsRegularly; self.note = note
    }
}
