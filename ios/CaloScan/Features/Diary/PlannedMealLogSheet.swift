import SwiftUI
import CaloScanCore

/// Registrazione di un pasto dal piano del professionista: l'utente conferma gli alimenti
/// e, se ha mangiato quantità diverse, corregge i grammi prima di salvare.
struct PlannedMealLogSheet: View {
    let meal: PlannedMeal
    let services: AppServices
    var day: Date = .now
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row]
    @State private var isSaving = false
    @State private var error: APIError?

    private struct Row: Identifiable {
        let planned: PlannedFood
        var grams: Double?
        var included: Bool
        var id: UUID { planned.id }
    }

    init(meal: PlannedMeal, services: AppServices, day: Date = .now, onSaved: @escaping () -> Void) {
        self.meal = meal
        self.services = services
        self.day = day
        self.onSaved = onSaved
        _rows = State(initialValue: meal.foods.map { Row(planned: $0, grams: $0.grams, included: $0.food != nil) })
    }

    private var items: [MealItem] {
        rows.compactMap { row in
            guard row.included, let food = row.planned.food, let g = row.grams, MealItem.gramsRange.contains(g) else { return nil }
            return MealItem(food: food, grams: g)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Toggle(isOn: $row.included.animation(DS.Motion.snappy)) {
                                Text(row.planned.name).font(DS.Font.callout)
                            }
                            .disabled(row.planned.food == nil)
                            .tint(DS.Palette.brand)
                            if row.planned.food == nil {
                                Text("Non collegato al database: aggiungilo dalla ricerca se vuoi conteggiarlo.")
                                    .font(DS.Font.caption).foregroundStyle(DS.Palette.warning)
                            } else if row.included {
                                NumericField(label: "Quantità mangiata", value: $row.grams, unit: "g", fractionDigits: 0)
                            }
                        }
                    }
                } header: {
                    Text("Previsto dal piano")
                } footer: {
                    Text("Se hai mangiato quantità diverse, correggile: nel diario restano i valori reali.")
                }
                Section {
                    let totals = items.map(\.nutrients).total
                    LabeledContent("Calorie", value: Format.kcal(totals.kcal))
                    MacroInline(protein: totals.proteinG, carbs: totals.carbsG, fat: totals.fatG)
                }
            }
            .navigationTitle(meal.type.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                LoadingButton(title: "Registra come da piano", isLoading: isSaving) { Task { await save() } }
                    .disabled(items.isEmpty)
                    .padding(DS.Spacing.screen)
                    .background(.bar)
            }
            .alert("Salvataggio non riuscito",
                   isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
                   presenting: error) { _ in Button("OK", role: .cancel) {} } message: { Text($0.localizedDescription) }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let cal = Calendar.current
        let loggedAt = cal.isDateInToday(day) ? Date.now
            : (cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day)
        do {
            try await services.meals.save(Meal(type: meal.type, loggedAt: loggedAt, items: items, source: .plan))
            onSaved()
            dismiss()
        } catch {
            self.error = APIError.from(error)
        }
    }
}
