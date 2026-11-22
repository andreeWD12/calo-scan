import SwiftUI
import CaloScanCore

extension HealthProfessional {
    var title: LocalizedStringKey {
        switch self {
        case .doctor: "Medico"
        case .dietitian: "Dietista"
        case .nutritionist: "Biologo nutrizionista"
        }
    }

    /// Etichetta breve per Home e Profilo, es. "Obiettivo del medico".
    var targetLabel: LocalizedStringKey {
        switch self {
        case .doctor: "Obiettivo del medico"
        case .dietitian: "Obiettivo del dietista"
        case .nutritionist: "Obiettivo del nutrizionista"
        }
    }
}

/// Inserimento delle calorie e della dieta indicate da un professionista sanitario.
/// L'app registra i valori così come li inserisce l'utente e li usa come obiettivo nel diario:
/// non li genera, non li corregge e non dà indicazioni cliniche (resta fuori dal perimetro MDR).
struct ProfessionalPlanView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var professional: HealthProfessional = .doctor
    @State private var professionalName = ""
    @State private var calories: Double?
    @State private var includeMacros = false
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var notes = ""
    @State private var startDate = Date.now
    @State private var hasReview = false
    @State private var reviewDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var confirmed = false
    @State private var isSaving = false
    @State private var confirmRemoval = false
    @State private var error: APIError?
    @State private var loaded = false

    private var isEditing: Bool { app.professionalPlan != nil }
    private var sex: BiologicalSex { app.profile?.sex ?? .unspecified }

    private var draft: ProfessionalPlan? {
        guard let calories else { return nil }
        let name = professionalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProfessionalPlan(
            professional: professional,
            professionalName: name.isEmpty ? nil : name,
            calorieTarget: Int(calories.rounded()),
            proteinG: includeMacros ? protein.map { Int($0.rounded()) } : nil,
            carbsG: includeMacros ? carbs.map { Int($0.rounded()) } : nil,
            fatG: includeMacros ? fat.map { Int($0.rounded()) } : nil,
            notes: text.isEmpty ? nil : text,
            startDate: Calendar.current.startOfDay(for: startDate),
            reviewDate: hasReview ? Calendar.current.startOfDay(for: reviewDate) : nil,
            confirmedAt: app.professionalPlan?.confirmedAt ?? .now)
    }

    private var issues: [ProfessionalPlan.Issue] { draft?.validate() ?? [] }
    private var canSave: Bool { draft != nil && issues.isEmpty && confirmed && !isSaving }

    var body: some View {
        Form {
            Section {
                Label {
                    Text("Se un medico o un dietista ti ha indicato quante calorie assumere, inseriscile qui. CaloScan userà questi valori come obiettivo nel diario al posto della propria stima.")
                        .font(DS.Font.callout)
                } icon: {
                    Image(systemName: "stethoscope").foregroundStyle(DS.Palette.brand)
                }
            }

            Section("Chi ti ha indicato il piano") {
                Picker("Professionista", selection: $professional) {
                    ForEach(HealthProfessional.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Nome (facoltativo)", text: $professionalName)
                    .textContentType(.name)
            }

            Section {
                NumericField(label: "Calorie giornaliere", value: $calories, unit: "kcal", fractionDigits: 0,
                             error: issues.contains(.caloriesOutOfRange)
                                ? String(localized: "Inserisci un valore tra \(ProfessionalPlan.calorieRange.lowerBound) e \(ProfessionalPlan.calorieRange.upperBound) kcal.")
                                : nil)
            } footer: {
                if let draft, draft.isBelowAppFloor(for: sex), !issues.contains(.caloriesOutOfRange) {
                    Label("Questo valore è sotto la soglia che CaloScan usa nei propri calcoli. Seguilo solo sotto il controllo del professionista che te l'ha indicato.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Palette.warning)
                }
            }

            Section {
                Toggle("Il piano indica anche i macronutrienti", isOn: $includeMacros.animation(DS.Motion.snappy))
                if includeMacros {
                    NumericField(label: "Proteine", value: $protein, unit: "g", fractionDigits: 0)
                    NumericField(label: "Carboidrati", value: $carbs, unit: "g", fractionDigits: 0)
                    NumericField(label: "Grassi", value: $fat, unit: "g", fractionDigits: 0)
                }
            } footer: {
                if issues.contains(.macrosDoNotMatchCalories), let p = protein, let c = carbs, let f = fat {
                    Text("Con questi grammi si arriva a circa \(Int(p * 4 + c * 4 + f * 9)) kcal, lontano dalle calorie indicate. Controlla di averli copiati correttamente.")
                        .foregroundStyle(DS.Palette.danger)
                } else if issues.contains(.macroOutOfRange) {
                    Text("Ogni valore deve essere tra 0 e \(ProfessionalPlan.macroRange.upperBound) g.")
                        .foregroundStyle(DS.Palette.danger)
                } else if includeMacros {
                    Text("Puoi compilarne anche solo alcuni: quelli mancanti vengono distribuiti sulle calorie restanti.")
                }
            }

            Section {
                TextField("Es. dieta mediterranea, 5 pasti al giorno, pochi zuccheri semplici, legumi 3 volte a settimana",
                          text: $notes, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("Indicazioni della dieta")
            } footer: {
                HStack(alignment: .top) {
                    Text("Facoltativo. Il coach AI terrà conto di queste indicazioni e non ti proporrà obiettivi diversi.")
                    Spacer(minLength: DS.Spacing.s)
                    Text("\(notes.count)/\(ProfessionalPlan.notesMaxLength)").monospacedDigit()
                        .foregroundStyle(notes.count > ProfessionalPlan.notesMaxLength ? DS.Palette.danger : DS.Palette.textTertiary)
                }
            }

            Section {
                DatePicker("In vigore dal", selection: $startDate, displayedComponents: .date)
                Toggle("Prossimo controllo", isOn: $hasReview.animation(DS.Motion.snappy))
                if hasReview {
                    DatePicker("Data del controllo", selection: $reviewDate, in: startDate..., displayedComponents: .date)
                }
            } footer: {
                if hasReview {
                    Text("Ti ricorderemo di aggiornare il piano dopo il controllo.")
                }
            }

            Section {
                Toggle(isOn: $confirmed) {
                    Text("Confermo che questi valori mi sono stati indicati da un professionista sanitario")
                        .font(DS.Font.callout)
                }
                .tint(DS.Palette.brand)
            } footer: {
                Text("CaloScan non verifica, non modifica e non sostituisce il piano del professionista. In caso di dubbi rivolgiti a chi lo ha indicato.")
            }

            if isEditing {
                Section {
                    Button("Rimuovi il piano e torna agli obiettivi calcolati", role: .destructive) { confirmRemoval = true }
                }
            }
        }
        .navigationTitle("Piano del professionista")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") { Task { await save() } }.disabled(!canSave)
            }
        }
        .onAppear(perform: loadCurrent)
        .confirmationDialog("Rimuovere il piano?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Rimuovi", role: .destructive) { Task { await remove() } }
        } message: {
            Text("Il diario tornerà a usare gli obiettivi calcolati da CaloScan.")
        }
        .alert("Salvataggio non riuscito",
               isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
               presenting: error) { _ in Button("OK", role: .cancel) {} } message: { Text($0.localizedDescription) }
        .sensoryFeedback(.selection, trigger: confirmed)
    }

    private func loadCurrent() {
        guard !loaded else { return }
        loaded = true
        guard let p = app.professionalPlan else { return }
        professional = p.professional
        professionalName = p.professionalName ?? ""
        calories = Double(p.calorieTarget)
        includeMacros = p.hasMacros
        protein = p.proteinG.map(Double.init)
        carbs = p.carbsG.map(Double.init)
        fat = p.fatG.map(Double.init)
        notes = p.notes ?? ""
        startDate = p.startDate
        hasReview = p.reviewDate != nil
        if let r = p.reviewDate { reviewDate = r }
        confirmed = true
    }

    private func save() async {
        guard canSave, let plan = draft else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await app.services.profile.save(professionalPlan: plan)
            app.setProfessionalPlan(plan)
            await ReminderScheduler.scheduleProfessionalReview(on: plan.reviewDate)
            app.toasts.success(String(localized: "Piano salvato"),
                               subtitle: String(localized: "Obiettivo: \(Format.kcal(Double(plan.calorieTarget)))"),
                               symbol: "stethoscope")
            dismiss()
        } catch {
            self.error = APIError.from(error)
        }
    }

    private func remove() async {
        do {
            try await app.services.profile.deleteProfessionalPlan()
            app.setProfessionalPlan(nil)
            await ReminderScheduler.scheduleProfessionalReview(on: nil)
            app.toasts.success(String(localized: "Piano rimosso"),
                               subtitle: String(localized: "Torni agli obiettivi calcolati"))
            dismiss()
        } catch {
            self.error = APIError.from(error)
        }
    }
}
