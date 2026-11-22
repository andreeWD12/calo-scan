import SwiftUI
import CaloScanCore

/// Raccolta dati dell'onboarding, calcolo degli obiettivi e salvataggio.
@Observable
@MainActor
final class OnboardingViewModel {

    enum Step: Int, CaseIterable {
        case intro, consent, name, personal, body, activity, goal, diet, allergies, targets, plan

        var title: LocalizedStringResource {
            switch self {
            case .intro: "Benvenuto"
            case .consent: "I tuoi dati"
            case .name: "Come ti chiami?"
            case .personal: "Qualche dato su di te"
            case .body: "Altezza e peso"
            case .activity: "Quanto sei attivo?"
            case .goal: "Qual è il tuo obiettivo?"
            case .diet: "Come mangi di solito?"
            case .allergies: "Allergie e intolleranze"
            case .targets: "Il tuo piano giornaliero"
            case .plan: "Scegli il tuo piano"
            }
        }
    }

    // MARK: Stato

    private(set) var step: Step = .intro
    private(set) var isSaving = false
    var error: APIError?

    // Consensi (mai preselezionati)
    var healthConsent = false
    var aiPhotoConsent = false

    // Dati
    var name = ""
    var birthDate: Date = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    var sex: BiologicalSex?
    var heightCm: Double?
    var weightKg: Double?
    var targetWeightKg: Double?
    var activity: ActivityLevel?
    var goal: NutritionGoal?
    var diet: DietPreference = .omnivore
    var otherDietNote = ""
    var allergens: Set<Allergen> = []
    var otherAllergyNote = ""
    var dietaryNotes = ""
    // Gravidanza (facoltativo): niente deficit e avvisi sugli alimenti da evitare.
    var isPregnant = false
    /// Si chiede a che settimana è (più semplice da sapere); in alternativa la data presunta del parto.
    var pregnancyByWeek = true
    var pregnancyWeek = 12
    var dueDate: Date = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    /// Data salvata nel profilo: da qui la settimana avanza da sola e la dieta si adatta.
    var effectiveDueDate: Date { pregnancyByWeek ? PregnancyInfo.dueDate(week: pregnancyWeek) : dueDate }
    var dueDateRange: ClosedRange<Date> {
        PregnancyInfo.dueDateRange()
    }

    // Personalizzazione obiettivi
    var customCalories: Int?

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    // MARK: Navigazione

    var progress: Double { Double(step.rawValue) / Double(Step.allCases.count - 1) }

    var canContinue: Bool {
        switch step {
        case .intro: true
        case .consent: healthConsent
        case .name: !name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= 50
        case .personal: sex != nil && ageError == nil
        case .body: metrics != nil && targetWeightError == nil
        case .activity: activity != nil
        case .goal: goal != nil
        case .diet: diet != .other || !otherDietNote.trimmingCharacters(in: .whitespaces).isEmpty
        case .allergies: true
        case .targets: customCaloriesError == nil
        case .plan: true
        }
    }

    func next() {
        guard canContinue, let following = Step(rawValue: step.rawValue + 1) else { return }
        if following == .targets { customCalories = nil }
        step = following
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    // MARK: Validazione

    var age: Int { BodyMetrics.age(birthDate: birthDate) }

    var birthDateRange: ClosedRange<Date> {
        let cal = Calendar.current
        let oldest = cal.date(byAdding: .year, value: -100, to: .now) ?? .distantPast
        let youngest = cal.date(byAdding: .year, value: -AgePolicy.minimumAccountAge, to: .now) ?? .now
        return oldest...youngest
    }

    var ageError: String? {
        age < AgePolicy.minimumAccountAge
            ? String(localized: "CaloScan è riservata a chi ha almeno \(AgePolicy.minimumAccountAge) anni.") : nil
    }

    var metrics: BodyMetrics? {
        guard let sex, let heightCm, let weightKg else { return nil }
        return try? BodyMetrics(ageYears: age, sex: sex, heightCm: heightCm, weightKg: weightKg)
    }

    var heightError: String? {
        guard let heightCm else { return nil }
        return BodyMetrics.heightRange.contains(heightCm) ? nil : String(localized: "Inserisci un'altezza tra 100 e 250 cm.")
    }

    var weightError: String? {
        guard let weightKg else { return nil }
        return BodyMetrics.weightRange.contains(weightKg) ? nil : String(localized: "Inserisci un peso tra 30 e 350 kg.")
    }

    /// Il peso desiderato non può corrispondere a un BMI sotto 18,5 (sottopeso).
    var targetWeightError: String? {
        guard let targetWeightKg else { return nil }
        guard BodyMetrics.weightRange.contains(targetWeightKg) else {
            return String(localized: "Inserisci un peso tra 30 e 350 kg.")
        }
        if let heightCm, BodyMetrics.heightRange.contains(heightCm) {
            let minHealthy = 18.5 * pow(heightCm / 100, 2)
            if targetWeightKg < minHealthy {
                return String(localized: "Questo peso è sotto l'intervallo considerato salutare per la tua altezza (minimo circa \(Int(minHealthy.rounded())) kg).")
            }
        }
        return nil
    }

    // MARK: Obiettivi

    var computedTargets: DailyTargets? {
        guard let metrics, let activity, let goal else { return nil }
        // In gravidanza mai un deficit: qui il mantenimento (vale anche per Free).
        // L'energia in più della settimana la aggiunge AppState solo con Pro.
        if isPregnant, sex != .male {
            return EnergyCalculator.targets(metrics: metrics, activity: activity, goal: .maintain, diet: diet)
        }
        return EnergyCalculator.targets(metrics: metrics, activity: activity, goal: goal, diet: diet)
    }

    var customCaloriesError: String? {
        guard let customCalories, let metrics else { return nil }
        return EnergyCalculator.isSafeManualTarget(customCalories, metrics: metrics) ? nil
            : String(localized: "Per sicurezza l'obiettivo non può scendere sotto \(Int(EnergyCalculator.calorieFloor(for: metrics.sex))) kcal.")
    }

    /// Obiettivi finali: se l'utente modifica le calorie, i macro vengono ridistribuiti in proporzione.
    var finalTargets: DailyTargets? {
        guard let base = computedTargets else { return nil }
        guard let custom = customCalories, customCaloriesError == nil, custom != base.calorieTarget else { return base }
        let ratio = Double(custom) / Double(base.calorieTarget)
        return DailyTargets(bmr: base.bmr, tdee: base.tdee, calorieTarget: custom,
                            proteinG: Int((Double(base.proteinG) * ratio).rounded()),
                            carbsG: Int((Double(base.carbsG) * ratio).rounded()),
                            fatG: Int((Double(base.fatG) * ratio).rounded()),
                            isAdjustedForSafety: base.isAdjustedForSafety)
    }

    func toggle(_ allergen: Allergen) {
        if allergens.contains(allergen) { allergens.remove(allergen) } else { allergens.insert(allergen) }
    }

    // MARK: Salvataggio

    func buildProfile() -> UserProfile? {
        guard let sex, let heightCm, let weightKg, let activity, let goal else { return nil }
        func clean(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : String(t.prefix(500))
        }
        return UserProfile(
            displayName: name.trimmingCharacters(in: .whitespaces), birthDate: birthDate, sex: sex,
            heightCm: heightCm, weightKg: weightKg, targetWeightKg: targetWeightKg, activity: activity,
            goal: goal, diet: diet, otherDietNote: diet == .other ? clean(otherDietNote) : nil,
            allergens: allergens, otherAllergyNote: allergens.contains(.other) ? clean(otherAllergyNote) : nil,
            dietaryNotes: clean(dietaryNotes),
            pregnancy: isPregnant && sex != .male && PregnancyInfo.isValidDueDate(effectiveDueDate) ? PregnancyInfo(dueDate: effectiveDueDate) : nil)
    }

    /// Salva consensi, profilo, obiettivi e primo peso. Ritorna i dati salvati se tutto è andato a buon fine.
    func save() async -> (UserProfile, DailyTargets)? {
        guard let profile = buildProfile(), let targets = finalTargets else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            try await services.account.update(consents: ConsentState(
                healthDataProcessing: healthConsent, aiImageAnalysis: aiPhotoConsent, productEmails: false))
            try await services.profile.save(profile: profile, targets: targets)
            try await services.weight.add(WeightEntry(date: .now, weightKg: profile.weightKg))
            return (profile, targets)
        } catch {
            self.error = APIError.from(error)
            return nil
        }
    }
}

// MARK: - Testi delle opzioni

extension ActivityLevel {
    var title: LocalizedStringKey {
        switch self {
        case .sedentary: "Sedentario"
        case .lightlyActive: "Poco attivo"
        case .moderatelyActive: "Moderatamente attivo"
        case .veryActive: "Molto attivo"
        case .extremelyActive: "Estremamente attivo"
        }
    }
    var subtitle: LocalizedStringKey {
        switch self {
        case .sedentary: "Lavoro alla scrivania, poco movimento"
        case .lightlyActive: "Camminate o sport leggero 1–3 volte a settimana"
        case .moderatelyActive: "Allenamento 3–5 volte a settimana"
        case .veryActive: "Allenamento intenso 6–7 volte a settimana"
        case .extremelyActive: "Lavoro fisico pesante o doppi allenamenti"
        }
    }
    var symbol: String {
        switch self {
        case .sedentary: "chair.lounge"
        case .lightlyActive: "figure.walk"
        case .moderatelyActive: "figure.run"
        case .veryActive: "figure.strengthtraining.traditional"
        case .extremelyActive: "flame"
        }
    }
}

extension NutritionGoal {
    var title: LocalizedStringKey {
        switch self {
        case .loseWeight: "Perdere peso"
        case .maintain: "Mantenere il peso"
        case .gainMuscle: "Aumentare la massa muscolare"
        case .improveQuality: "Migliorare l'alimentazione"
        case .trackOnly: "Monitorare le calorie"
        }
    }
    var symbol: String {
        switch self {
        case .loseWeight: "arrow.down.right"
        case .maintain: "equal"
        case .gainMuscle: "dumbbell"
        case .improveQuality: "leaf"
        case .trackOnly: "list.bullet.clipboard"
        }
    }
}

extension DietPreference {
    var title: LocalizedStringKey {
        switch self {
        case .omnivore: "Onnivora"
        case .vegetarian: "Vegetariana"
        case .vegan: "Vegana"
        case .mediterranean: "Mediterranea"
        case .lowCarb: "Low carb"
        case .other: "Altro"
        }
    }
}

extension Allergen {
    var title: LocalizedStringKey {
        switch self {
        case .gluten: "Glutine"
        case .milk: "Latte (allergia)"
        case .lactose: "Lattosio (intolleranza)"
        case .eggs: "Uova"
        case .fish: "Pesce"
        case .shellfish: "Crostacei"
        case .molluscs: "Molluschi"
        case .peanuts: "Arachidi"
        case .treeNuts: "Frutta a guscio"
        case .soy: "Soia"
        case .celery: "Sedano"
        case .mustard: "Senape"
        case .sesame: "Sesamo"
        case .sulphites: "Solfiti"
        case .lupin: "Lupini"
        case .other: "Altro"
        }
    }
}

extension BiologicalSex {
    var title: LocalizedStringKey {
        switch self {
        case .male: "Maschile"
        case .female: "Femminile"
        case .unspecified: "Preferisco non indicarlo"
        }
    }
}
