import SwiftUI
import CaloScanCore

extension EatingStyle {
    var title: String {
        switch self {
        case .balanced: String(localized: "Equilibrata")
        case .mediterranean: String(localized: "Mediterranea")
        case .highProtein: String(localized: "Ricca di proteine")
        case .moderateLowCarb: String(localized: "Pochi carboidrati (moderata)")
        case .vegetarian: String(localized: "Vegetariana")
        case .vegan: String(localized: "Vegana")
        case .fasting12: String(localized: "Digiuno intermittente 12:12")
        case .fasting14: String(localized: "Digiuno intermittente 14:10")
        case .fasting16: String(localized: "Digiuno intermittente 16:8")
        }
    }

    /// Descrizione neutra, senza indicazioni sulla salute (Reg. UE 1924/2006). Uguale a `NEUTRAL_REASON` (TS).
    var summary: String {
        switch self {
        case .balanced: String(localized: "Un'alimentazione varia con tutti i gruppi di alimenti, facile da seguire ogni giorno.")
        case .mediterranean: String(localized: "Verdura, legumi, cereali integrali, pesce e olio d'oliva, con pochi prodotti molto lavorati.")
        case .highProtein: String(localized: "Più proteine distribuite nei pasti, utile se ti alleni con regolarità.")
        case .moderateLowCarb: String(localized: "Meno carboidrati raffinati, senza eliminarli del tutto.")
        case .vegetarian: String(localized: "Niente carne e pesce, con uova e latticini come fonti di proteine.")
        case .vegan: String(localized: "Solo alimenti vegetali, con attenzione a proteine, ferro e vitamina B12.")
        case .fasting12: String(localized: "Mangi in una finestra di 12 ore, per esempio dalle 8 alle 20.")
        case .fasting14: String(localized: "Mangi in una finestra di 10 ore e osservi 14 ore di pausa, notte compresa.")
        case .fasting16: String(localized: "Mangi in una finestra di 8 ore e osservi 16 ore di pausa, notte compresa.")
        }
    }

    var symbol: String {
        switch self {
        case .balanced: "circle.grid.cross"
        case .mediterranean: "leaf"
        case .highProtein: "dumbbell"
        case .moderateLowCarb: "chart.bar.xaxis"
        case .vegetarian: "carrot"
        case .vegan: "leaf.circle"
        case .fasting12, .fasting14, .fasting16: "clock"
        }
    }
}

extension EatingStyleBlock {
    var explanation: String {
        switch self {
        case .professionalPlan: String(localized: "Segui già il piano del tuo medico o dietista: vale quello.")
        case .underAge: String(localized: "Il digiuno intermittente non è indicato prima dei 18 anni.")
        case .lowBMI: String(localized: "Con il tuo peso attuale non è indicato ridurre il tempo per mangiare.")
        case .pregnancy: String(localized: "In gravidanza o allattamento serve il parere del medico.")
        case .diabetesMedication: String(localized: "Con farmaci per il diabete può causare ipoglicemie: parlane con il medico.")
        case .eatingDisorder: String(localized: "Per proteggere il tuo benessere non proponiamo stili restrittivi.")
        case .medicalSupervision: String(localized: "Con una condizione seguita dal medico, decidilo insieme a lui.")
        }
    }
}

@Observable
@MainActor
final class EatingStyleViewModel {
    enum Step: Int { case screening, preferences, proposals, window }

    var step: Step = .screening
    // Risposte di sicurezza: nil = non ancora risposto.
    var pregnant: Bool?
    var diabetes: Bool?
    var eatingDisorder: Bool?
    var medical: Bool?
    var mealsPerDay: EatingStyleRequest.MealsPerDay = .three
    var hunger: EatingStyleRequest.Hunger = .even
    var trains = false
    var note = ""
    private(set) var proposals: Loadable<[EatingStyleProposal]> = .idle
    var selected: EatingStyle?
    var windowStart = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now
    var reminders = false
    var isSaving = false
    var error: APIError?

    private let services: AppServices
    init(services: AppServices) { self.services = services }

    var screeningComplete: Bool { [pregnant, diabetes, eatingDisorder, medical].allSatisfy { $0 != nil } }
    var anyRisk: Bool { [pregnant, diabetes, eatingDisorder, medical].contains { $0 == true } }

    var screening: EatingStyleScreening {
        EatingStyleScreening(pregnantOrBreastfeeding: pregnant ?? true, diabetesMedication: diabetes ?? true,
                             eatingDisorderHistory: eatingDisorder ?? true, medicalSupervision: medical ?? true)
    }

    func blocks(_ style: EatingStyle, profile: UserProfile, hasPlan: Bool) -> [EatingStyleBlock] {
        EatingStyleSafety.blocks(for: style, ageYears: profile.ageYears(), bmi: profile.bmi,
                                 screening: screening, hasProfessionalPlan: hasPlan)
    }

    func askCoach() async {
        proposals = .loading
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = EatingStyleRequest(screening: screening, mealsPerDay: mealsPerDay, hunger: hunger,
                                         trainsRegularly: trains, note: trimmed.isEmpty ? nil : String(trimmed.prefix(300)))
        do {
            let list = try await services.coach.proposeEatingStyles(request)
            proposals = list.isEmpty ? .empty : .loaded(list)
            selected = list.first?.style
        } catch {
            proposals = .failed(APIError.from(error))
        }
    }

    var windowMinute: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: windowStart)
        return (c.hour ?? 12) * 60 + (c.minute ?? 0)
    }

    /// Salva lo stile nel profilo. Ricontrolla le regole di sicurezza anche qui (il server fa lo stesso).
    func save(app: AppState) async -> Bool {
        guard let style = selected, var profile = app.profile, let targets = app.computedTargets,
              blocks(style, profile: profile, hasPlan: app.professionalPlan != nil).isEmpty else { return false }
        isSaving = true
        defer { isSaving = false }
        let choice = EatingStyleChoice(style: style, window: EatingWindow(startMinute: windowMinute, hours: style.eatingWindowHours ?? 0),
                                       remindersEnabled: style.isFasting && reminders)
        profile.eatingStyle = choice
        do {
            try await services.profile.save(profile: profile, targets: targets)
            app.updateProfile(profile, targets: targets)
            if choice.remindersEnabled, await ReminderScheduler.requestAuthorization() {
                await ReminderScheduler.scheduleEatingWindow(choice.window)
            } else {
                await ReminderScheduler.scheduleEatingWindow(nil)
            }
            return true
        } catch {
            self.error = APIError.from(error)
            return false
        }
    }

    func remove(app: AppState) async {
        guard var profile = app.profile, let targets = app.computedTargets else { return }
        profile.eatingStyle = nil
        do {
            try await services.profile.save(profile: profile, targets: targets)
            app.updateProfile(profile, targets: targets)
            await ReminderScheduler.scheduleEatingWindow(nil)
        } catch { self.error = APIError.from(error) }
    }
}

/// Scelta dello stile alimentare insieme al coach AI. Solo Plus e Pro.
struct EatingStyleView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: EatingStyleViewModel
    @State private var showPaywall = false
    @State private var changing = false
    @State private var confirmRemove = false

    init(services: AppServices) {
        _model = State(initialValue: EatingStyleViewModel(services: services))
    }

    private var isLocked: Bool { app.entitlements.plan == .free }

    var body: some View {
        Form {
            Section {
                EstimateNotice(text: "Le proposte sono generate da un assistente AI a scopo informativo: non sono una dieta terapeutica e non sostituiscono il parere di un medico o di un dietista.")
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            if isLocked {
                lockedSection
            } else if app.professionalPlan != nil {
                Section {
                    Label(EatingStyleBlock.professionalPlan.explanation, systemImage: "stethoscope")
                    Text("Il coach tiene conto del tuo piano e non propone stili diversi. Se vuoi provare un altro stile, chiedilo a chi ti segue.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                }
            } else if let current = app.profile?.eatingStyle, !changing {
                currentSection(current)
            } else {
                flow
            }
        }
        .navigationTitle("Stile alimentare")
        .navigationBarTitleDisplayMode(.inline)
        .animation(DS.Motion.standard, value: model.step)
        .sheet(isPresented: $showPaywall) { PaywallView(services: app.services, highlight: .plus) }
        .confirmationDialog("Rimuovere lo stile alimentare?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Rimuovi", role: .destructive) { Task { await model.remove(app: app) } }
        }
        .alert("Operazione non riuscita",
               isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } }),
               presenting: model.error) { _ in Button("OK", role: .cancel) {} } message: { Text($0.localizedDescription) }
    }

    // MARK: Sezioni

    private var lockedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Label("Scegli lo stile con il coach", systemImage: "sparkles").font(DS.Font.headline)
                Text("Mediterranea, ricca di proteine, vegetariana, digiuno intermittente e altri: il coach ti propone gli stili adatti alle tue abitudini, escludendo quelli non indicati per te.")
                    .font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
            }
            Button {
                showPaywall = true
            } label: {
                Label("Disponibile con Plus e Pro", systemImage: "lock.fill")
                    .font(DS.Font.callout.weight(.semibold))
            }
        }
    }

    private func currentSection(_ c: EatingStyleChoice) -> some View {
        Section {
            Label(c.style.title, systemImage: c.style.symbol).font(DS.Font.headline)
            Text(c.style.summary).font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
            if let w = c.window {
                LabeledContent("Finestra alimentare", value: windowText(w))
                LabeledContent("Promemoria", value: c.remindersEnabled ? String(localized: "Attivi") : String(localized: "Spenti"))
            }
            Button("Cambia stile con il coach") { changing = true; model.step = .screening }
            Button("Rimuovi lo stile", role: .destructive) { confirmRemove = true }
        } header: {
            Text("Il tuo stile")
        } footer: {
            Text("Scelto il \(c.chosenAt.formatted(date: .long, time: .omitted)). Se noti stanchezza, capogiri o fame difficile da gestire, interrompi e parlane con il medico.")
        }
    }

    @ViewBuilder
    private var flow: some View {
        switch model.step {
        case .screening: screeningSection
        case .preferences: preferencesSection
        case .proposals: proposalsSection
        case .window: windowSection
        }
    }

    private var screeningSection: some View {
        Section {
            yesNo("Sei in gravidanza o allatti?", $model.pregnant)
            yesNo("Prendi insulina o farmaci per il diabete?", $model.diabetes)
            yesNo("Hai o hai avuto disturbi alimentari?", $model.eatingDisorder)
            yesNo("Hai altre condizioni seguite da un medico?", $model.medical)
            Button("Continua") { model.step = .preferences }
                .disabled(!model.screeningComplete)
        } header: {
            Text("Prima, qualche domanda per la tua sicurezza")
        } footer: {
            Text(model.anyRisk
                 ? "Grazie. Il coach ti proporrà solo stili non restrittivi: per gli altri è meglio parlarne con il tuo medico."
                 : "Le risposte servono solo a escludere gli stili non indicati per te. Le trattiamo come dati sanitari, con il tuo consenso.")
        }
    }

    private func yesNo(_ title: LocalizedStringKey, _ value: Binding<Bool?>) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title)
            Picker(title, selection: value) {
                Text("No").tag(Bool?.some(false))
                Text("Sì").tag(Bool?.some(true))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private var preferencesSection: some View {
        Section {
            Picker("Pasti al giorno", selection: $model.mealsPerDay) {
                Text("2").tag(EatingStyleRequest.MealsPerDay.two)
                Text("3").tag(EatingStyleRequest.MealsPerDay.three)
                Text("4 o più").tag(EatingStyleRequest.MealsPerDay.fourOrMore)
            }
            Picker("Hai più fame", selection: $model.hunger) {
                Text("Al mattino").tag(EatingStyleRequest.Hunger.morning)
                Text("La sera").tag(EatingStyleRequest.Hunger.evening)
                Text("In modo uniforme").tag(EatingStyleRequest.Hunger.even)
            }
            Toggle("Mi alleno con regolarità", isOn: $model.trains)
            TextField("Facoltativo: es. lavoro su turni", text: $model.note, axis: .vertical)
                .lineLimit(1...3)
            Button {
                model.step = .proposals
                Task { await model.askCoach() }
            } label: {
                Label("Chiedi al coach", systemImage: "sparkles")
            }
            Button("Indietro") { model.step = .screening }
        } header: {
            Text("Le tue abitudini")
        } footer: {
            Text("Il coach usa anche obiettivo, preferenze alimentari e allergie del tuo profilo.")
        }
    }

    @ViewBuilder
    private var proposalsSection: some View {
        switch model.proposals {
        case .idle, .loading:
            Section { HStack { ProgressView(); Text("Il coach sta valutando…").foregroundStyle(DS.Palette.textSecondary) } }
        case .failed(let error):
            Section { ErrorStateView(error: error) { Task { await model.askCoach() } } }
        case .empty:
            Section { Text("Il coach non ha trovato proposte. Riprova più tardi.") }
        case .loaded(let list):
            Section {
                ForEach(list) { p in
                    Button { model.selected = p.style } label: { proposalRow(p) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.selected == p.style ? .isSelected : [])
                }
            } header: {
                Text("Le proposte del coach")
            }
            if let profile = app.profile {
                Section("Altri stili") {
                    ForEach(EatingStyle.allCases.filter { s in !list.contains { $0.style == s } }, id: \.self) { s in
                        let blocks = model.blocks(s, profile: profile, hasPlan: false)
                        Button { if blocks.isEmpty { model.selected = s } } label: {
                            HStack(alignment: .top) {
                                Image(systemName: model.selected == s ? "checkmark.circle.fill" : (blocks.isEmpty ? "circle" : "nosign"))
                                    .foregroundStyle(model.selected == s ? DS.Palette.brand : DS.Palette.textTertiary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.title).foregroundStyle(blocks.isEmpty ? DS.Palette.textPrimary : DS.Palette.textTertiary)
                                    Text(blocks.first?.explanation ?? s.summary)
                                        .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!blocks.isEmpty)
                    }
                }
            }
            Section {
                Button("Continua") {
                    if model.selected?.isFasting == true { model.step = .window } else { save() }
                }
                .disabled(model.selected == nil || model.isSaving)
                Button("Indietro") { model.step = .preferences }
            }
        }
    }

    private func proposalRow(_ p: EatingStyleProposal) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.s) {
            Image(systemName: model.selected == p.style ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(model.selected == p.style ? DS.Palette.brand : DS.Palette.textTertiary)
            VStack(alignment: .leading, spacing: 4) {
                Label(p.style.title, systemImage: p.style.symbol).font(DS.Font.headline)
                Text(p.reason).font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
                ForEach(p.firstSteps, id: \.self) { step in
                    Label(step, systemImage: "arrow.right.circle").font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var windowSection: some View {
        Section {
            if let s = model.selected, let hours = s.eatingWindowHours {
                DatePicker("Inizio della finestra", selection: $model.windowStart, displayedComponents: .hourAndMinute)
                LabeledContent("Finestra", value: windowText(EatingWindow(startMinute: model.windowMinute, hours: hours)))
                Toggle("Promemoria di apertura e chiusura", isOn: $model.reminders)
                LoadingButton(title: "Salva lo stile", isLoading: model.isSaving) { save() }
            }
            Button("Indietro") { model.step = .proposals }
        } header: {
            Text("La tua finestra alimentare")
        } footer: {
            Text("Bevi acqua durante la pausa. Se noti stanchezza, capogiri o fame difficile da gestire, interrompi e parlane con il medico. I promemoria restano sul tuo iPhone.")
        }
    }

    private func save() {
        Task {
            if await model.save(app: app) {
                changing = false
                model.step = .screening
                app.toasts.success(String(localized: "Stile salvato"), subtitle: model.selected?.title, symbol: "fork.knife")
            }
        }
    }

    private func windowText(_ w: EatingWindow) -> String {
        func t(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
        return "\(t(w.startMinute))–\(t(w.endMinute))"
    }
}

/// Riquadro in Home per chi segue un digiuno intermittente: dice solo se la finestra è aperta e fino a quando.
struct EatingWindowCard: View {
    let window: EatingWindow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let eating = window.isEating(at: context.date)
            let next = window.nextChange(after: context.date)
            Card {
                HStack(spacing: DS.Spacing.s) {
                    Image(systemName: eating ? "fork.knife.circle.fill" : "moon.zzz.fill")
                        .font(.title)
                        .foregroundStyle(eating ? DS.Palette.brand : DS.Palette.textSecondary)
                        .contentTransition(.symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: 2) {
                        let time = next.formatted(date: .omitted, time: .shortened)
                        Group {
                            if eating { Text("Finestra alimentare aperta") } else { Text("Pausa dal cibo") }
                        }
                        .font(DS.Font.headline)
                        Group {
                            if eating { Text("Fino alle \(time)") } else { Text("Si mangia dalle \(time)") }
                        }
                        .font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
                    }
                    Spacer()
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
