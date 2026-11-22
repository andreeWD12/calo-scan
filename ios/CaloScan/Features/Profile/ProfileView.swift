import SwiftUI
import CaloScanCore

enum ProfileRoute: Hashable { case editProfile, editTargets, professionalPlan, subscription, settings, privacy, coach, shopping, referral }

/// Profilo personale: dati, obiettivi, piano, impostazioni.
struct ProfileView: View {
    @Environment(AppState.self) private var app
    @State private var path: [ProfileRoute] = []
    @State private var showGuide = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let profile = app.profile {
                    Section {
                        HStack(spacing: DS.Spacing.m) {
                            Text(String(profile.displayName.prefix(1)).uppercased())
                                .font(DS.Font.title)
                                .foregroundStyle(DS.Palette.onBrand)
                                .frame(width: 56, height: 56)
                                .background(DS.Palette.brand, in: .circle)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName).font(DS.Font.headline)
                                Text("\(profile.ageYears()) anni · \(Int(profile.heightCm)) cm · \(Format.kg(profile.weightKg))")
                                    .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                            }
                            Spacer()
                            if app.entitlements.plan != .free { PlanBadge(plan: app.entitlements.plan) }
                        }
                        NavigationLink("Modifica dati personali", value: ProfileRoute.editProfile)
                    }
                }
                if let targets = app.targets {
                    Section {
                        if let plan = app.professionalPlan {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(plan.professional.targetLabel).font(DS.Font.callout.weight(.semibold))
                                    if let review = plan.reviewDate {
                                        Text("Prossimo controllo: \(review.formatted(date: .long, time: .omitted))")
                                            .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: "stethoscope").foregroundStyle(DS.Palette.brand)
                            }
                        }
                        LabeledContent("Calorie", value: Format.kcal(Double(targets.calorieTarget)))
                        LabeledContent("Proteine", value: "\(targets.proteinG) g")
                        LabeledContent("Carboidrati", value: "\(targets.carbsG) g")
                        LabeledContent("Grassi", value: "\(targets.fatG) g")
                        NavigationLink(value: ProfileRoute.professionalPlan) {
                            Label(app.professionalPlan == nil ? "Aggiungi il piano del medico o dietista" : "Modifica il piano del professionista",
                                  systemImage: "stethoscope")
                        }
                        if app.professionalPlan == nil {
                            NavigationLink("Modifica obiettivi", value: ProfileRoute.editTargets)
                        }
                    } header: {
                        Text("Obiettivi giornalieri")
                    } footer: {
                        if app.professionalPlan == nil {
                            Text("Hai calorie o una dieta indicate da un professionista? Aggiungile: il diario userà quei valori.")
                        }
                    }
                }
                Section {
                    NavigationLink(value: ProfileRoute.coach) { Label("AI Nutrition Coach", systemImage: "sparkles") }
                    NavigationLink(value: ProfileRoute.shopping) { Label("Lista della spesa", systemImage: "cart") }
                    NavigationLink(value: ProfileRoute.subscription) { Label("Abbonamento", systemImage: "crown") }
                    NavigationLink(value: ProfileRoute.referral) { Label("Invita un amico", systemImage: "person.2") }
                    NavigationLink(value: ProfileRoute.settings) { Label("Impostazioni", systemImage: "gearshape") }
                    NavigationLink(value: ProfileRoute.privacy) { Label("Privacy e account", systemImage: "hand.raised") }
                }
                Section {
                    Button { showGuide = true } label: { Label("Guida all'app", systemImage: "book.pages") }
                    Link(destination: LegalLinks.support) { Label("Assistenza", systemImage: "questionmark.circle") }
                } footer: {
                    Text("CaloScan fornisce stime a scopo informativo e non è un dispositivo medico.")
                }
            }
            .navigationTitle("Profilo")
            .fullScreenCover(isPresented: $showGuide) {
                AppGuideView { showGuide = false }
            }
            .onChange(of: app.router.pending, initial: true) { _, link in
                if link == .professionalPlan { path = [.professionalPlan]; app.router.pending = nil }
            }
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .editProfile: EditProfileView()
                case .editTargets: EditTargetsView()
                case .professionalPlan: ProfessionalPlanView()
                case .subscription: ManageSubscriptionView()
                case .settings: SettingsView()
                case .privacy: PrivacyAccountView()
                case .coach: CoachView(services: app.services)
                case .shopping: ShoppingListView(services: app.services)
                case .referral: ReferralView(services: app.services)
                }
            }
        }
    }
}

/// Modifica dei dati personali; gli obiettivi vengono ricalcolati con le stesse formule dell'onboarding.
struct EditProfileView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: UserProfile?
    @State private var height: Double?
    @State private var weight: Double?
    @State private var targetWeight: Double?
    @State private var isSaving = false
    @State private var error: APIError?

    var body: some View {
        Form {
            if let binding = Binding($draft) {
                Section("Dati personali") {
                    TextField("Nome", text: binding.displayName)
                    DatePicker("Data di nascita", selection: binding.birthDate, displayedComponents: .date)
                    Picker("Sesso biologico", selection: binding.sex) {
                        ForEach(BiologicalSex.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Section("Corpo") {
                    NumericField(label: "Altezza", value: $height, unit: "cm", fractionDigits: 0)
                    NumericField(label: "Peso attuale", value: $weight, unit: "kg")
                    NumericField(label: "Peso desiderato", value: $targetWeight, unit: "kg")
                }
                Section("Stile di vita e obiettivi") {
                    Picker("Attività", selection: binding.activity) {
                        ForEach(ActivityLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Obiettivo", selection: binding.goal) {
                        ForEach(NutritionGoal.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Alimentazione", selection: binding.diet) {
                        ForEach(DietPreference.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    ForEach(Allergen.allCases, id: \.self) { allergen in
                        Toggle(isOn: Binding(
                            get: { draft?.allergens.contains(allergen) ?? false },
                            set: { on in
                                if on { draft?.allergens.insert(allergen) } else { draft?.allergens.remove(allergen) }
                            })) { Text(allergen.title) }
                    }
                } header: { Text("Allergie e intolleranze") }
                Section {
                    Text("Salvando, gli obiettivi giornalieri verranno ricalcolati in base ai nuovi dati.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                }
            }
        }
        .navigationTitle("Dati personali")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") { Task { await save() } }.disabled(isSaving || validated == nil)
            }
        }
        .onAppear {
            guard draft == nil, let p = app.profile else { return }
            draft = p; height = p.heightCm; weight = p.weightKg; targetWeight = p.targetWeightKg
        }
        .alert("Salvataggio non riuscito",
               isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
               presenting: error) { _ in Button("OK", role: .cancel) {} } message: { Text($0.localizedDescription) }
    }

    private var validated: (UserProfile, DailyTargets)? {
        guard var p = draft, let height, let weight else { return nil }
        p.heightCm = height; p.weightKg = weight; p.targetWeightKg = targetWeight
        p.displayName = p.displayName.trimmingCharacters(in: .whitespaces)
        guard !p.displayName.isEmpty, p.ageYears() >= AgePolicy.minimumAccountAge,
              let metrics = try? p.metrics() else { return nil }
        return (p, EnergyCalculator.targets(metrics: metrics, activity: p.activity, goal: p.goal, diet: p.diet))
    }

    private func save() async {
        guard let result = validated else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await app.services.profile.save(profile: result.0, targets: result.1)
            app.updateProfile(result.0, targets: result.1)
            app.toasts.success(String(localized: "Profilo aggiornato"), subtitle: String(localized: "Obiettivi ricalcolati"))
            dismiss()
        } catch {
            self.error = APIError.from(error)
        }
    }
}

/// Modifica manuale degli obiettivi, con le soglie minime di sicurezza.
struct EditTargetsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var calories = 2000
    @State private var proteinShare = 0.25
    @State private var fatShare = 0.30
    @State private var isSaving = false
    @State private var error: APIError?

    private var metrics: BodyMetrics? { try? app.profile?.metrics() }
    private var floor: Int { Int(EnergyCalculator.calorieFloor(for: app.profile?.sex ?? .unspecified)) }
    private var carbShare: Double { max(1 - proteinShare - fatShare, 0) }

    private var targets: DailyTargets? {
        guard let base = app.computedTargets else { return nil }
        let kcal = Double(calories)
        return DailyTargets(bmr: base.bmr, tdee: base.tdee, calorieTarget: calories,
                            proteinG: Int((kcal * proteinShare / 4).rounded()),
                            carbsG: Int((kcal * carbShare / 4).rounded()),
                            fatG: Int((kcal * fatShare / 9).rounded()),
                            isAdjustedForSafety: false)
    }

    var body: some View {
        Form {
            if app.professionalPlan != nil {
                Section {
                    Label("Stai seguendo il piano indicato dal tuo professionista: il diario usa quei valori. Qui modifichi gli obiettivi calcolati dall'app, che tornano in uso se rimuovi il piano.",
                          systemImage: "stethoscope")
                        .font(DS.Font.callout)
                }
            }
            Section {
                Stepper(value: $calories, in: floor...6000, step: 50) {
                    LabeledContent("Calorie", value: Format.kcal(Double(calories)))
                }
            } footer: {
                if let t = app.computedTargets {
                    Text("Stima calcolata: \(Format.kcal(Double(t.tdee))) di fabbisogno. Per sicurezza l'obiettivo non può scendere sotto \(Format.kcal(Double(floor))).")
                }
            }
            Section("Ripartizione dei macronutrienti") {
                shareSlider("Proteine", value: $proteinShare, range: 0.10...0.35, tint: DS.Palette.protein)
                shareSlider("Grassi", value: $fatShare, range: 0.20...0.40, tint: DS.Palette.fat)
                LabeledContent("Carboidrati", value: Format.percent(carbShare))
                if let t = targets {
                    MacroInline(protein: Double(t.proteinG), carbs: Double(t.carbsG), fat: Double(t.fatG))
                }
            }
            Section {
                Button("Ripristina i valori calcolati") { resetToComputed() }
            }
        }
        .navigationTitle("Obiettivi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") { Task { await save() } }.disabled(isSaving || targets == nil)
            }
        }
        .onAppear(perform: loadCurrent)
        .alert("Salvataggio non riuscito",
               isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
               presenting: error) { _ in Button("OK", role: .cancel) {} } message: { Text($0.localizedDescription) }
    }

    private func shareSlider(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, tint: Color) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: Format.percent(value.wrappedValue))
            Slider(value: value, in: range, step: 0.01).tint(tint)
        }
    }

    private func loadCurrent() {
        guard let t = app.computedTargets, t.calorieTarget > 0 else { return }
        calories = max(t.calorieTarget, floor)
        let kcal = Double(t.calorieTarget)
        proteinShare = min(max(Double(t.proteinG) * 4 / kcal, 0.10), 0.35)
        fatShare = min(max(Double(t.fatG) * 9 / kcal, 0.20), 0.40)
    }

    private func resetToComputed() {
        guard let p = app.profile, let metrics else { return }
        let t = EnergyCalculator.targets(metrics: metrics, activity: p.activity, goal: p.goal, diet: p.diet)
        calories = t.calorieTarget
        let kcal = Double(t.calorieTarget)
        proteinShare = min(max(Double(t.proteinG) * 4 / kcal, 0.10), 0.35)
        fatShare = min(max(Double(t.fatG) * 9 / kcal, 0.20), 0.40)
    }

    private func save() async {
        guard let profile = app.profile, let targets else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await app.services.profile.save(profile: profile, targets: targets)
            app.updateProfile(profile, targets: targets)
            app.toasts.success(String(localized: "Obiettivi aggiornati"))
            dismiss()
        } catch {
            self.error = APIError.from(error)
        }
    }
}
