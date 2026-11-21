import SwiftUI
import CaloScanCore

/// Inserimento manuale di un pasto senza fotocamera: ricerca → quantità → salvataggio.
struct AddFoodFlowView: View {
    let services: AppServices
    /// Giorno del diario a cui aggiungere il pasto (oggi per default).
    var day: Date = .now
    let onSaved: () -> Void

    @State private var mealType: MealType
    @State private var selected: FoodItem?
    @State private var grams: Double?
    @State private var isSaving = false
    @State private var error: APIError?
    @Environment(\.dismiss) private var dismiss

    init(services: AppServices, mealType: MealType, day: Date = .now, onSaved: @escaping () -> Void) {
        self.services = services
        self.day = day
        self.onSaved = onSaved
        _mealType = State(initialValue: mealType)
    }

    var body: some View {
        NavigationStack {
            FoodSearchView(services: services) { food in
                grams = food.defaultServingG ?? 100
                selected = food
            }
            .navigationTitle("Aggiungi a \(mealType.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
            .navigationDestination(item: $selected) { food in
                portionForm(food)
            }
        }
    }

    private func portionForm(_ food: FoodItem) -> some View {
        let valid = grams.map { MealItem.gramsRange.contains($0) } ?? false
        return Form {
            Section { FoodRow(food: food) }
            Section("Quantità") {
                NumericField(label: "Peso", value: $grams, unit: "g", fractionDigits: 0,
                             error: valid ? nil : String(localized: "Inserisci una quantità tra 1 e 3000 g."))
                Picker("Pasto", selection: $mealType) {
                    ForEach(MealType.allCases) { Text($0.title).tag($0) }
                }
            }
            if valid, let g = grams {
                let n = food.per100g.scaled(per100gTo: g)
                Section("Valori nutrizionali") {
                    LabeledContent("Calorie", value: Format.kcal(n.kcal))
                    MacroInline(protein: n.proteinG, carbs: n.carbsG, fat: n.fatG)
                }
            }
        }
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            LoadingButton(title: "Aggiungi al diario", isLoading: isSaving) {
                Task { await save(food) }
            }
            .disabled(!valid)
            .padding(DS.Spacing.screen)
            .background(.bar)
        }
        .alert("Salvataggio non riuscito",
               isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
               presenting: error) { _ in Button("OK", role: .cancel) {} } message: { Text($0.localizedDescription) }
    }

    private func save(_ food: FoodItem) async {
        guard let g = grams else { return }
        isSaving = true
        defer { isSaving = false }
        let cal = Calendar.current
        // Per un giorno passato il pasto viene registrato a mezzogiorno di quel giorno.
        let loggedAt = cal.isDateInToday(day) ? Date.now
            : (cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day)
        let meal = Meal(type: mealType, loggedAt: loggedAt, items: [MealItem(food: food, grams: g)], source: .manual)
        do {
            try await services.meals.save(meal)
            onSaved()
            dismiss()
        } catch {
            self.error = APIError.from(error)
        }
    }
}
