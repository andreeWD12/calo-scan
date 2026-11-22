import SwiftUI
import CaloScanCore

/// Onboarding a passi: consenso → dati personali → fisici → stile di vita → obiettivi → piano → guida all'app.
struct OnboardingFlowView: View {
    @Environment(AppState.self) private var app
    @State private var model: OnboardingViewModel
    @State private var savedResult: (UserProfile, DailyTargets)?
    @State private var showingGuide = false

    init(services: AppServices) {
        _model = State(initialValue: OnboardingViewModel(services: services))
    }

    var body: some View {
        VStack(spacing: 0) {
            if showingGuide {
                AppGuideView(onFinish: complete)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
            header
            if model.step == .plan {
                PlanChoiceView(services: app.services, onContinueFree: finish, onPurchased: finish)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.l) {
                        Text(model.step.title).font(DS.Font.title)
                            .accessibilityAddTraits(.isHeader)
                        stepContent
                    }
                    .padding(DS.Spacing.screen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(model.step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
                }
                .scrollDismissesKeyboard(.interactively)
                footer
            }
            }
        }
        .background(DS.Palette.background.ignoresSafeArea())
        .animation(DS.Motion.standard, value: model.step)
        .animation(DS.Motion.standard, value: showingGuide)
        .alert("Salvataggio non riuscito",
               isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } }),
               presenting: model.error) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0.localizedDescription) }
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.s) {
            Button { model.back() } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
            }
            .opacity(model.step == .intro ? 0 : 1)
            .disabled(model.step == .intro || model.isSaving)
            .accessibilityLabel(Text("Indietro"))
            ProgressView(value: model.progress)
                .tint(DS.Palette.brand)
                .accessibilityLabel(Text("Avanzamento"))
            Spacer().frame(width: 44)
        }
        .padding(.horizontal, DS.Spacing.xs)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .intro: IntroStep()
        case .consent: ConsentStep(model: model)
        case .name: NameStep(model: model)
        case .personal: PersonalStep(model: model)
        case .body: BodyStep(model: model)
        case .activity: ActivityStep(model: model)
        case .goal: GoalStep(model: model)
        case .diet: DietStep(model: model)
        case .allergies: AllergiesStep(model: model)
        case .targets: TargetsStep(model: model)
        case .plan:
            EmptyView() // mostrato a schermo intero in `body`
        }
    }

    private var footer: some View {
        Group {
            if model.step == .targets {
                LoadingButton(title: "Salva e continua", isLoading: model.isSaving) {
                    Task {
                        if let result = await model.save() {
                            savedResult = result
                            model.next()
                        }
                    }
                }
            } else {
                Button("Continua") { model.next() }.buttonStyle(.primary)
            }
        }
        .disabled(!model.canContinue)
        .padding(.horizontal, DS.Spacing.screen)
        .padding(.vertical, DS.Spacing.s)
        .background(DS.Palette.background)
    }

    /// Dopo la scelta del piano: guida a funzioni e pulsanti, poi l'app.
    private func finish() {
        guard savedResult != nil else { return }
        showingGuide = true
    }

    private func complete() {
        guard let result = savedResult else { return }
        app.completeOnboarding(profile: result.0, targets: result.1)
    }
}

// MARK: - Passi

private struct IntroStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("Ti faremo qualche domanda per calcolare un fabbisogno calorico su misura. Ci vogliono circa due minuti e potrai modificare tutto in seguito.")
                .foregroundStyle(DS.Palette.textSecondary)
            Label("Stime basate su formule scientifiche riconosciute", systemImage: "function")
            Label("Obiettivi graduali, mai restrizioni estreme", systemImage: "shield.lefthalf.filled")
            Label("I tuoi dati restano tuoi: puoi esportarli o cancellarli quando vuoi", systemImage: "lock")
            Label("Alla fine una breve guida ti mostra tutte le funzioni e i pulsanti dell'app", systemImage: "questionmark.circle")
        }
        .font(DS.Font.callout)
        .labelStyle(BrandLabelStyle())
    }
}

/// Consenso esplicito al trattamento dei dati relativi alla salute (art. 9(2)(a) GDPR),
/// separato dai termini e mai preselezionato. Il consenso all'analisi AI delle foto è facoltativo.
private struct ConsentStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("Per calcolare i tuoi obiettivi e tenere il diario, CaloScan tratta dati relativi alla salute: peso, altezza, alimentazione, allergie ed eventuali esigenze alimentari. Questi dati sono usati solo per fornirti il servizio, non vengono venduti né usati per pubblicità.")
                .font(DS.Font.callout)
                .foregroundStyle(DS.Palette.textSecondary)

            Card {
                Toggle(isOn: $model.healthConsent) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Acconsento al trattamento dei miei dati relativi alla salute").font(DS.Font.headline)
                        Text("Necessario per usare CaloScan. Puoi revocarlo in qualsiasi momento da Impostazioni → Privacy: in quel caso i dati verranno cancellati.")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                    }
                }
            }
            Card {
                Toggle(isOn: $model.aiPhotoConsent) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Analisi delle foto con intelligenza artificiale").font(DS.Font.headline)
                        Text("Facoltativo. Le foto dei piatti vengono inviate in modo cifrato a un fornitore di AI per riconoscere gli alimenti, non sono usate per addestrare modelli e vengono cancellate automaticamente. Senza questo consenso puoi inserire i pasti manualmente.")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                    }
                }
            }
            Link("Leggi l'informativa sulla privacy", destination: LegalLinks.privacyPolicy)
                .font(DS.Font.callout.weight(.semibold))
        }
        .toggleStyle(CheckboxToggleStyle())
    }
}

private struct NameStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        LabeledField(label: "Nome") {
            TextField("Il tuo nome", text: $model.name)
                .textContentType(.givenName)
                .submitLabel(.next)
                .onSubmit { model.next() }
        }
    }
}

private struct PersonalStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                DatePicker("Data di nascita", selection: $model.birthDate, in: model.birthDateRange,
                           displayedComponents: .date)
                    .font(DS.Font.headline)
                Text("Età: \(model.age) anni").font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
                if let error = model.ageError {
                    Text(error).font(DS.Font.caption).foregroundStyle(DS.Palette.danger)
                }
            }
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                Text("Sesso biologico").font(DS.Font.headline)
                Text("Serve solo per stimare il metabolismo: le formule differiscono tra corpo maschile e femminile. Se preferisci non indicarlo useremo una media.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                ForEach(BiologicalSex.allCases, id: \.self) { option in
                    SelectionCard(title: option.title, isSelected: model.sex == option) { model.sex = option }
                }
            }
        }
    }
}

private struct BodyStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            NumericField(label: "Altezza", value: $model.heightCm, unit: "cm", fractionDigits: 0, error: model.heightError)
            NumericField(label: "Peso attuale", value: $model.weightKg, unit: "kg", error: model.weightError)
            NumericField(label: "Peso desiderato (facoltativo)", value: $model.targetWeightKg, unit: "kg",
                         error: model.targetWeightError)
        }
    }
}

private struct ActivityStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            ForEach(ActivityLevel.allCases, id: \.self) { level in
                SelectionCard(title: level.title, subtitle: level.subtitle, systemImage: level.symbol,
                              isSelected: model.activity == level) { model.activity = level }
            }
        }
    }
}

private struct GoalStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            ForEach(NutritionGoal.allCases, id: \.self) { goal in
                SelectionCard(title: goal.title, systemImage: goal.symbol, isSelected: model.goal == goal) {
                    model.goal = goal
                }
            }
            if model.goal == .loseWeight && model.age < 18 {
                EstimateNotice(text: "Sotto i 18 anni non impostiamo un deficit calorico: l'obiettivo sarà il mantenimento. Per perdere peso in sicurezza rivolgiti al tuo medico.")
            }
        }
    }
}

private struct DietStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            ForEach(DietPreference.allCases, id: \.self) { diet in
                SelectionCard(title: diet.title, isSelected: model.diet == diet) { model.diet = diet }
            }
            if model.diet == .other {
                LabeledField(label: "Descrivi la tua alimentazione") {
                    TextField("Es. pescetariana, flexitariana…", text: $model.otherDietNote)
                }
            }
        }
    }
}

private struct AllergiesStep: View {
    @Bindable var model: OnboardingViewModel

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: DS.Spacing.xs)]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("Seleziona tutto ciò che vale per te: il coach AI e la lista della spesa suggerita escluderanno questi alimenti. Se non hai allergie o intolleranze, tocca Continua. Potrai modificarle in qualsiasi momento dal Profilo.")
                .font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(Allergen.allCases, id: \.self) { allergen in
                    Chip(title: allergen.title, isSelected: model.allergens.contains(allergen)) {
                        model.toggle(allergen)
                    }
                }
            }
            if model.allergens.contains(.other) {
                LabeledField(label: "Altre allergie o intolleranze") {
                    TextField("Specifica", text: $model.otherAllergyNote)
                }
            }
            LabeledField(label: "Esigenze alimentari particolari (facoltativo)") {
                TextField("Es. indicazioni ricevute dal medico", text: $model.dietaryNotes, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(.vertical, DS.Spacing.xs)
            }
            EstimateNotice(text: "CaloScan non è un dispositivo medico e non sostituisce il parere di un medico o di un nutrizionista. Se hai una patologia, sei in gravidanza o allatti, consulta un professionista prima di modificare la tua alimentazione. Il segnale di allergene non garantisce l'assenza di tracce negli alimenti.")
        }
    }
}

private struct TargetsStep: View {
    @Bindable var model: OnboardingViewModel
    @State private var editing = false

    var body: some View {
        if let targets = model.finalTargets {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                Card {
                    Text("Obiettivo giornaliero").font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                    Text(Format.kcal(Double(targets.calorieTarget))).font(DS.Font.metricLarge)
                        .contentTransition(.numericText())
                    HStack(spacing: DS.Spacing.xs) {
                        StatTile(title: "Proteine", value: "\(targets.proteinG) g", tint: DS.Palette.protein)
                        StatTile(title: "Carboidrati", value: "\(targets.carbsG) g", tint: DS.Palette.carbs)
                        StatTile(title: "Grassi", value: "\(targets.fatG) g", tint: DS.Palette.fat)
                    }
                }
                HStack(spacing: DS.Spacing.xs) {
                    StatTile(title: "Metabolismo basale", value: Format.kcal(Double(targets.bmr)))
                    StatTile(title: "Fabbisogno (TDEE)", value: Format.kcal(Double(targets.tdee)))
                }
                if targets.isAdjustedForSafety {
                    EstimateNotice(text: "Abbiamo adattato l'obiettivo per rispettare le soglie minime di sicurezza.")
                }
                DisclosureGroup("Modifica l'obiettivo calorico", isExpanded: $editing) {
                    Stepper(value: Binding(
                        get: { model.customCalories ?? targets.calorieTarget },
                        set: { model.customCalories = $0 }), in: 1000...6000, step: 50) {
                        Text(Format.kcal(Double(model.customCalories ?? targets.calorieTarget)))
                            .font(DS.Font.headline.monospacedDigit())
                    }
                    if let error = model.customCaloriesError {
                        Text(error).font(DS.Font.caption).foregroundStyle(DS.Palette.danger)
                    }
                }
                .font(DS.Font.headline)
                EstimateNotice(text: "Calcolo con la formula di Mifflin-St Jeor e il tuo livello di attività. È una stima: il fabbisogno reale varia da persona a persona. Potrai modificarlo dal Profilo in qualsiasi momento.")
            }
        }
    }
}

// MARK: - Componenti locali

struct Chip: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.callout.weight(.medium))
                .padding(.horizontal, DS.Spacing.s)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(isSelected ? DS.Palette.onBrand : DS.Palette.textPrimary)
                .background(isSelected ? DS.Palette.brand : DS.Palette.surface, in: .capsule)
                .overlay(Capsule().strokeBorder(isSelected ? .clear : DS.Palette.separator))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct BrandLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.s) {
            configuration.icon.foregroundStyle(DS.Palette.brand).frame(width: 24)
            configuration.title
        }
    }
}
