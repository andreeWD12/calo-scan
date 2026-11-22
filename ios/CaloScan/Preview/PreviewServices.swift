#if DEBUG
import Foundation
import CaloScanCore

/// Servizi in memoria per SwiftUI Preview, UI test e la modalità anteprima (`-PreviewMode`).
/// Compilati SOLO nelle build Debug: in Release questo file non esiste.
/// I valori nutrizionali d'esempio sono approssimazioni di USDA FoodData Central (SR Legacy).
actor PreviewStore: AuthService, ProfileRepository, MealRepository, FoodSearchService, ScanService,
                    CoachService, WeightRepository, EntitlementService, PurchaseService, AccountService,
                    PushTokenService, ShoppingListService, ReferralService {

    nonisolated let stateStream: AsyncStream<SessionState>
    private nonisolated let continuation: AsyncStream<SessionState>.Continuation

    private let userID = UUID()
    private var state: SessionState
    private var profile: UserProfile?
    private var targets: DailyTargets?
    private var professionalPlan: ProfessionalPlan?
    private var shoppingItems: [ShoppingItem] = []
    private var referral = ReferralStatus(code: "KMRT7QX4", shareURL: URL(string: "https://caloscan.app/i/KMRT7QX4")!,
                                          invitedCount: 1, discountLabel: "30%", canEnterCode: true)
    private var meals: [Meal] = []
    private var weights: [WeightEntry] = []
    private var bodyMeasurements: [BodyMeasurement] = []
    private var messages: [CoachMessage] = []
    private var consentState = ConsentState(healthDataProcessing: false, aiImageAnalysis: false, productEmails: false)
    private var plan: Plan = .free
    private var scansUsed = 0

    init(startOnboarding: Bool) {
        let pair = AsyncStream.makeStream(of: SessionState.self)
        stateStream = pair.stream
        continuation = pair.continuation
        if startOnboarding {
            state = .signedOut
        } else {
            state = .signedIn(userID: userID)
            let p = UserProfile(displayName: "Giulia", birthDate: Calendar.current.date(byAdding: .year, value: -32, to: .now)!,
                                sex: .female, heightCm: 168, weightKg: 66, targetWeightKg: 62, activity: .moderatelyActive,
                                goal: .loseWeight, diet: .mediterranean)
            profile = p
            targets = EnergyCalculator.targets(metrics: try! p.metrics(), activity: p.activity, goal: p.goal, diet: p.diet)
            consentState = ConsentState(healthDataProcessing: true, aiImageAnalysis: true, productEmails: false)
            seedHistory()
        }
    }

    // MARK: Catalogo d'esempio

    static let catalog: [FoodItem] = [
        FoodItem(name: "Pasta di semola, cotta", per100g: Nutrients(kcal: 158, proteinG: 5.8, carbsG: 30.9, fatG: 0.9), source: .usda, defaultServingG: 180),
        FoodItem(name: "Salsa di pomodoro", per100g: Nutrients(kcal: 24, proteinG: 1.2, carbsG: 5.3, fatG: 0.3), source: .usda, defaultServingG: 80),
        FoodItem(name: "Olio extravergine d'oliva", per100g: Nutrients(kcal: 884, proteinG: 0, carbsG: 0, fatG: 100), source: .usda, defaultServingG: 10),
        FoodItem(name: "Petto di pollo, cotto", per100g: Nutrients(kcal: 165, proteinG: 31, carbsG: 0, fatG: 3.6), source: .usda, defaultServingG: 120),
        FoodItem(name: "Riso bianco, cotto", per100g: Nutrients(kcal: 130, proteinG: 2.7, carbsG: 28.2, fatG: 0.3), source: .usda, defaultServingG: 150),
        FoodItem(name: "Mela", per100g: Nutrients(kcal: 52, proteinG: 0.3, carbsG: 13.8, fatG: 0.2), source: .usda, defaultServingG: 180),
        FoodItem(name: "Yogurt greco 0%", per100g: Nutrients(kcal: 59, proteinG: 10.2, carbsG: 3.6, fatG: 0.4), source: .usda, defaultServingG: 170),
        FoodItem(name: "Uovo intero", per100g: Nutrients(kcal: 143, proteinG: 12.6, carbsG: 0.7, fatG: 9.5), source: .usda, defaultServingG: 50),
        FoodItem(name: "Pane integrale", per100g: Nutrients(kcal: 252, proteinG: 12.4, carbsG: 42.7, fatG: 3.5), source: .usda, defaultServingG: 50),
        FoodItem(name: "Banana", per100g: Nutrients(kcal: 89, proteinG: 1.1, carbsG: 22.8, fatG: 0.3), source: .usda, defaultServingG: 120),
        FoodItem(name: "Salmone, cotto", per100g: Nutrients(kcal: 206, proteinG: 22.1, carbsG: 0, fatG: 12.4), source: .usda, defaultServingG: 130),
        FoodItem(name: "Fiocchi d'avena", per100g: Nutrients(kcal: 379, proteinG: 13.2, carbsG: 67.7, fatG: 6.5), source: .usda, defaultServingG: 40),
        FoodItem(name: "Mandorle", per100g: Nutrients(kcal: 579, proteinG: 21.2, carbsG: 21.6, fatG: 49.9), source: .usda, defaultServingG: 25),
    ]

    private func food(_ prefix: String) -> FoodItem { Self.catalog.first { $0.name.hasPrefix(prefix) }! }

    private func seedHistory() {
        let cal = Calendar.current
        for offset in 0..<30 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: .now)) else { continue }
            let at = { (h: Int) in cal.date(bySettingHour: h, minute: 0, second: 0, of: day)! }
            let jitter = Double((offset * 37) % 40) - 20
            meals.append(Meal(type: .breakfast, loggedAt: at(8), items: [
                MealItem(food: food("Yogurt"), grams: 170), MealItem(food: food("Fiocchi"), grams: 40 + jitter / 4)], source: .manual))
            if offset > 0 || cal.component(.hour, from: .now) >= 13 {
                meals.append(Meal(type: .lunch, loggedAt: at(13), items: [
                    MealItem(food: food("Pasta"), grams: 160 + jitter), MealItem(food: food("Salsa"), grams: 80),
                    MealItem(food: food("Olio"), grams: 10)], source: .scan))
            }
            if offset > 0 {
                meals.append(Meal(type: .dinner, loggedAt: at(20), items: [
                    MealItem(food: food(offset % 2 == 0 ? "Salmone" : "Petto"), grams: 130),
                    MealItem(food: food("Riso"), grams: 120 + jitter), MealItem(food: food("Olio"), grams: 8)], source: .manual))
                meals.append(Meal(type: .snack, loggedAt: at(17), items: [MealItem(food: food("Mela"), grams: 180)], source: .manual))
            }
            if offset % 3 == 0 {
                weights.append(WeightEntry(date: at(8), weightKg: 66 - Double(30 - offset) * 0.05))
            }
        }
    }

    // MARK: Auth

    func currentState() async -> SessionState { state }
    nonisolated func stateChanges() -> AsyncStream<SessionState> { stateStream }
    private func set(_ s: SessionState) { state = s; continuation.yield(s) }
    private func signedIn() { set(profile == nil ? .needsOnboarding(userID: userID) : .signedIn(userID: userID)) }
    func signInWithApple(idToken: String, nonce: String) async throws { signedIn() }
    func signInWithGoogle(idToken: String, accessToken: String) async throws { signedIn() }
    func signIn(email: String, password: String) async throws { try await Task.sleep(for: .milliseconds(400)); signedIn() }
    func signUp(email: String, password: String) async throws -> Bool { signedIn(); return false }
    func sendPasswordReset(email: String) async throws { try await Task.sleep(for: .milliseconds(400)) }
    func signOut() async throws { set(.signedOut) }

    // MARK: Profilo

    func loadProfile() async throws -> UserProfile? { profile }
    func loadTargets() async throws -> DailyTargets? { targets }
    func save(profile: UserProfile, targets: DailyTargets) async throws { self.profile = profile; self.targets = targets }
    func loadProfessionalPlan() async throws -> ProfessionalPlan? { professionalPlan }
    func save(professionalPlan: ProfessionalPlan) async throws {
        guard professionalPlan.validate().isEmpty else { throw APIError.invalidInput(String(localized: "Controlla i valori del piano.")) }
        self.professionalPlan = professionalPlan
    }
    func deleteProfessionalPlan() async throws { professionalPlan = nil }

    // MARK: Pasti

    func dayLog(for day: Date) async throws -> DayLog {
        let cal = Calendar.current
        return DayLog(day: cal.startOfDay(for: day), meals: meals.filter { cal.isDate($0.loggedAt, inSameDayAs: day) })
    }

    func dayLogs(from start: Date, to end: Date) async throws -> [DayLog] {
        let cal = Calendar.current
        var result: [DayLog] = []
        var day = cal.startOfDay(for: start)
        while day <= end && day <= .now {
            result.append(try await dayLog(for: day))
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    func save(_ meal: Meal) async throws {
        meals.removeAll { $0.id == meal.id }
        meals.append(meal)
        if meal.source == .scan || meal.source == .description { scansUsed += 1 }
    }

    func delete(mealID: UUID) async throws { meals.removeAll { $0.id == mealID } }

    // MARK: Alimenti e scansione

    func search(_ query: String) async throws -> [FoodItem] {
        try await Task.sleep(for: .milliseconds(250))
        return Self.catalog.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func lookup(barcode: String) async throws -> FoodItem? { nil }

    func analyze(jpegData: Data) async throws -> ScanResult {
        try await Task.sleep(for: .seconds(1.5))
        return ScanResult(id: UUID(), items: [
            ScannedItem(detectedName: "Pasta al pomodoro", matchedFood: food("Pasta"), estimatedGrams: 180, confidenceScore: 0.85),
            ScannedItem(detectedName: "Salsa di pomodoro", matchedFood: food("Salsa"), estimatedGrams: 80, confidenceScore: 0.7,
                        ingredients: ["pomodoro", "basilico"]),
            ScannedItem(detectedName: "Olio d'oliva", matchedFood: food("Olio"), estimatedGrams: 10, confidenceScore: 0.35),
            ScannedItem(detectedName: "Parmigiano grattugiato", matchedFood: nil, estimatedGrams: 10, confidenceScore: 0.45),
        ], questions: ["Quanto olio è stato usato nella preparazione?", "C'è formaggio grattugiato sulla pasta?"],
           overallConfidenceScore: 0.65)
    }

    /// Anteprima: cerca nel catalogo d'esempio le parole della descrizione. Il server reale usa l'AI.
    func analyze(description: String, jpegData: Data?) async throws -> ScanResult {
        try await Task.sleep(for: .seconds(1.2))
        let words = description.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count > 3 }
        let matches = Self.catalog.filter { item in words.contains { item.name.lowercased().contains($0.prefix(4)) } }
        let items = matches.prefix(5).map {
            ScannedItem(detectedName: $0.name, matchedFood: $0, estimatedGrams: $0.defaultServingG ?? 100, confidenceScore: 0.75)
        }
        return ScanResult(id: UUID(), items: Array(items),
                          questions: items.isEmpty ? [] : ["Le quantità sono stimate da porzioni standard: correggile se serve."],
                          overallConfidenceScore: items.isEmpty ? 0 : 0.75)
    }

    // MARK: Coach

    func dailyInsights() async throws -> [CoachInsight] {
        [CoachInsight(id: UUID(), text: "Modalità anteprima: qui compariranno i consigli generati dal coach AI sui tuoi dati.", tone: .info)]
    }

    func history() async throws -> [CoachMessage] { messages }

    func send(_ text: String) async throws -> CoachMessage {
        try await Task.sleep(for: .seconds(1))
        messages.append(CoachMessage(id: UUID(), role: .user, text: text, createdAt: .now))
        let reply = CoachMessage(id: UUID(), role: .assistant,
                                 text: "Modalità anteprima: il coach AI risponderà qui quando il backend sarà collegato (Fase 7).",
                                 createdAt: .now)
        messages.append(reply)
        return reply
    }

    // MARK: Peso

    func entries() async throws -> [WeightEntry] { weights }
    func add(_ entry: WeightEntry) async throws { weights.append(entry) }
    func delete(entryID: UUID) async throws { weights.removeAll { $0.id == entryID } }
    func measurements() async throws -> [BodyMeasurement] { bodyMeasurements }
    func add(_ measurement: BodyMeasurement) async throws { bodyMeasurements.append(measurement) }

    // MARK: Abbonamenti

    func refresh() async throws -> Entitlements {
        let limit = switch plan { case .free: 3; case .plus: 20; case .pro: 100 }
        return Entitlements(plan: plan, scansUsedToday: scansUsed, scansLimitToday: limit,
                            coachMessagesUsedToday: messages.count / 2, coachMessagesLimitToday: plan == .free ? 5 : 30,
                            expiresAt: plan == .free ? nil : Calendar.current.date(byAdding: .month, value: 1, to: .now),
                            willRenew: plan != .free)
    }

    func offers() async throws -> [PlanOffer] {
        [PlanOffer(id: "caloscan.plus.monthly", plan: .plus, period: .monthly, displayPrice: "4,99 €", pricePerMonthText: nil, introOffer: nil),
         PlanOffer(id: "caloscan.plus.yearly", plan: .plus, period: .yearly, displayPrice: "39,99 €", pricePerMonthText: "3,33 €", introOffer: "7 giorni gratis"),
         PlanOffer(id: "caloscan.pro.monthly", plan: .pro, period: .monthly, displayPrice: "9,99 €", pricePerMonthText: nil, introOffer: nil),
         PlanOffer(id: "caloscan.pro.yearly", plan: .pro, period: .yearly, displayPrice: "79,99 €", pricePerMonthText: "6,67 €", introOffer: nil),
         PlanOffer(id: "caloscan.plus.monthly.pregnancy", plan: .plus, period: .monthly, displayPrice: "4,99 €", pricePerMonthText: nil,
                   introOffer: "−30% per i primi 3 mesi", audience: .pregnancy, introPrice: "3,49 €", introMonths: 3)]
    }

    func purchase(offerID: String) async throws -> PurchaseOutcome {
        try await Task.sleep(for: .seconds(1))
        plan = offerID.contains(".pro.") ? .pro : .plus
        return .purchased
    }

    func restore() async throws {}

    // MARK: Account

    func consents() async throws -> ConsentState { consentState }
    func update(consents: ConsentState) async throws { consentState = consents }

    func exportData() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("caloscan-export.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        struct Export: Encodable { let profile: UserProfile?; let meals: [Meal]; let weights: [WeightEntry] }
        try encoder.encode(Export(profile: profile, meals: meals, weights: weights)).write(to: url, options: .completeFileProtection)
        return url
    }

    func register(deviceToken: String, environment: PushEnvironment) async throws {}
    func unregister() async throws {}

    // MARK: Lista della spesa

    func items() async throws -> [ShoppingItem] { shoppingItems }

    func save(_ items: [ShoppingItem]) async throws {
        for item in items {
            if let i = shoppingItems.firstIndex(where: { $0.id == item.id }) { shoppingItems[i] = item }
            else { shoppingItems.append(item) }
        }
    }

    func delete(itemIDs: [UUID]) async throws { shoppingItems.removeAll { itemIDs.contains($0.id) } }

    /// Anteprima: proposte fisse filtrate con le allergie del profilo, come farà il server.
    func suggest(request: String?) async throws -> [ShoppingSuggestion] {
        guard plan != .free else { throw APIError.planRequired(minimum: "Plus") }
        try await Task.sleep(for: .seconds(1.2))
        let allergens = profile?.allergens ?? []
        let all: [(ShoppingSuggestion, Allergen?)] = [
            (ShoppingSuggestion(name: "Petto di pollo", quantity: "600 g", reason: "Proteine magre per 3 cene"), nil),
            (ShoppingSuggestion(name: "Salmone", quantity: "2 filetti", reason: "Omega-3, due volte a settimana"), .fish),
            (ShoppingSuggestion(name: "Yogurt greco 0%", quantity: "4 vasetti", reason: "Colazioni e spuntini proteici"), .milk),
            (ShoppingSuggestion(name: "Lenticchie", quantity: "500 g", reason: "Legumi: fibre e proteine vegetali"), nil),
            (ShoppingSuggestion(name: "Zucchine", quantity: "1 kg", reason: "Verdura per pranzi e cene"), nil),
            (ShoppingSuggestion(name: "Mandorle", quantity: "200 g", reason: "Spuntino, una manciata al giorno"), .treeNuts),
            (ShoppingSuggestion(name: "Pasta integrale", quantity: "500 g", reason: "Carboidrati complessi per i pranzi"), .gluten),
            (ShoppingSuggestion(name: "Mele", quantity: "1 kg", reason: "Frutta per gli spuntini"), nil),
        ]
        let pregnancy = profile?.activePregnancy()
        return all.filter { item in item.1.map { !allergens.contains($0) } ?? true }.map(\.0)
            .filter { s in
                guard let pregnancy else { return true }
                return PregnancyFoodSafety.check(s.name, toxoplasmosisImmune: pregnancy.toxoplasmosisImmune)?.level != .avoid
            }
    }

    // MARK: Stile alimentare

    /// Anteprima: proposte fisse scelte tra gli stili ammessi, con le stesse regole di sicurezza del server.
    func proposeEatingStyles(_ request: EatingStyleRequest) async throws -> [EatingStyleProposal] {
        guard plan != .free else { throw APIError.planRequired(minimum: "Plus") }
        try await Task.sleep(for: .seconds(1.2))
        guard let profile else { return [] }
        let allowed = EatingStyleSafety.allowedStyles(ageYears: profile.ageYears(), bmi: profile.bmi,
                                                      screening: request.screening,
                                                      hasProfessionalPlan: professionalPlan != nil)
        var order: [EatingStyle] = [.mediterranean]
        if request.hunger == .evening || request.mealsPerDay == .two { order.insert(.fasting14, at: 0) }
        if request.trainsRegularly { order.append(.highProtein) }
        order += [.balanced, .fasting12]
        let reasons: [EatingStyle: String] = [
            .fasting14: "Dici di avere poca fame al mattino: una finestra di 10 ore, per esempio dalle 10 alle 20, si adatta alle tue abitudini.",
            .mediterranean: "È lo stile più vario e facile da mantenere nel tempo, e si adatta bene alle tue preferenze.",
            .highProtein: "Ti alleni con regolarità: distribuire le proteine nei pasti aiuta a raggiungere il tuo obiettivo.",
            .balanced: "Un'alimentazione varia con tutti i gruppi di alimenti, semplice da seguire ogni giorno.",
            .fasting12: "Una pausa notturna di 12 ore è il modo più graduale per provare il digiuno intermittente.",
        ]
        var seen = Set<EatingStyle>()
        return order.filter { allowed.contains($0) && seen.insert($0).inserted }.prefix(3).map {
            EatingStyleProposal(style: $0, reason: reasons[$0] ?? "", firstSteps: ["Inizia con 2-3 giorni a settimana", "Bevi acqua durante la giornata"])
        }
    }

    // MARK: Inviti

    /// Anteprima: nessun codice offerta reale. Il premio resta "in attesa" finché un amico non completa i requisiti.
    func referralStatus() async throws -> ReferralStatus {
        var s = referral
        if plan != .free, s.reward == .waiting { s.reward = .notEligible }
        return s
    }

    func applyReferral(code: String) async throws -> ReferralApplyResult {
        guard let c = ReferralCode.normalize(code) else { return .invalidCode }
        guard referral.canEnterCode else { return .alreadyReferred }
        if c == referral.code { return .ownCode }
        referral.canEnterCode = false
        referral.wasReferred = true
        return .applied
    }

    func deleteAccount() async throws {
        profile = nil; targets = nil; meals = []; weights = []; messages = []
        set(.signedOut)
    }
}

extension AppServices {
    /// `-PreviewOnboarding` parte dalla schermata di benvenuto invece che dalla Home.
    static func preview(startOnboarding: Bool = ProcessInfo.processInfo.arguments.contains("-PreviewOnboarding")) -> AppServices {
        let store = PreviewStore(startOnboarding: startOnboarding)
        return AppServices(auth: store, profile: store, meals: store, foods: store, scanner: store, coach: store,
                           weight: store, entitlements: store, purchases: store, account: store, push: store,
                           shopping: store, referrals: store)
    }
}
#endif
