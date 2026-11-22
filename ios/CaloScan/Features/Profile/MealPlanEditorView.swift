import SwiftUI
import CaloScanCore

/// Pasti del piano del professionista, con alimenti e grammature.
/// Il piano può essere uguale ogni giorno oppure diverso per ogni giorno della settimana.
struct MealPlanEditorView: View {
    @Binding var days: [PlannedDay]
    let services: AppServices
    /// Calorie giornaliere indicate nel piano, per confrontarle con la somma degli alimenti.
    let calorieTarget: Int?

    @State private var perWeekday = false
    @State private var weekday = Calendar.current.component(.weekday, from: .now)
    @State private var adding: MealType?
    @State private var editing: EditingFood?
    @State private var confirmCopy = false

    private struct EditingFood: Identifiable {
        let type: MealType
        var food: PlannedFood
        var id: UUID { food.id }
    }

    /// Giorni della settimana nell'ordine del calendario locale (in Italia da lunedì).
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private var currentKey: Int? { perWeekday ? weekday : nil }

    private var currentDay: PlannedDay {
        days.first { $0.weekday == currentKey } ?? PlannedDay(weekday: currentKey)
    }

    var body: some View {
        Form {
            Section {
                Picker("Il piano è", selection: $perWeekday.animation(DS.Motion.snappy)) {
                    Text("Uguale ogni giorno").tag(false)
                    Text("Diverso per giorno").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                if perWeekday {
                    weekdayPicker
                }
            } footer: {
                Text("Copia gli alimenti e le grammature come li trovi nel piano. Nel diario potrai registrare ogni pasto con un tocco.")
            }

            ForEach(MealType.allCases) { type in
                mealSection(type)
            }

            Section {
                let totals = currentDay.totals
                LabeledContent("Totale degli alimenti", value: Format.kcal(totals.kcal))
                if let calorieTarget, totals.kcal > 0 {
                    LabeledContent("Calorie indicate nel piano", value: Format.kcal(Double(calorieTarget)))
                }
                if perWeekday {
                    Button("Copia questo giorno su tutta la settimana") { confirmCopy = true }
                        .disabled(currentDay.meals.allSatisfy(\.foods.isEmpty))
                }
            } footer: {
                Text("Il totale considera solo gli alimenti collegati al database. Le calorie del piano restano quelle che hai inserito.")
            }
        }
        .navigationTitle("Pasti del piano")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            perWeekday = days.contains { $0.weekday != nil }
        }
        .onChange(of: perWeekday) { _, isPerDay in switchMode(perDay: isPerDay) }
        .sheet(item: $adding) { type in
            PlannedFoodPicker(services: services, mealTitle: type.title) { food in
                update(type) { $0.foods.append(food) }
            }
        }
        .sheet(item: $editing) { item in
            NavigationStack {
                PlannedFoodForm(food: item.food, foodItem: item.food.food) { updated in
                    update(item.type) { meal in
                        if let i = meal.foods.firstIndex(where: { $0.id == updated.id }) { meal.foods[i] = updated }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Copiare su tutta la settimana?", isPresented: $confirmCopy, titleVisibility: .visible) {
            Button("Copia e sostituisci") { copyToAllDays() }
        } message: {
            Text("I pasti degli altri giorni verranno sostituiti con quelli di questo giorno.")
        }
    }

    private var weekdayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                ForEach(orderedWeekdays, id: \.self) { day in
                    let selected = day == weekday
                    let hasFoods = days.first { $0.weekday == day }?.meals.contains { !$0.foods.isEmpty } ?? false
                    Button {
                        withAnimation(DS.Motion.snappy) { weekday = day }
                    } label: {
                        VStack(spacing: 2) {
                            Text(Calendar.current.shortWeekdaySymbols[day - 1].capitalized)
                                .font(DS.Font.callout.weight(.semibold))
                            Circle().fill(hasFoods ? DS.Palette.brand : .clear).frame(width: 5, height: 5)
                        }
                        .frame(width: 46, height: 50)
                        .foregroundStyle(selected ? DS.Palette.onBrand : DS.Palette.textPrimary)
                        .background(selected ? DS.Palette.brand : DS.Palette.surfaceMuted, in: .rect(cornerRadius: DS.Radius.s))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(Text(Calendar.current.weekdaySymbols[day - 1]))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, DS.Spacing.xs)
        }
    }

    private func mealSection(_ type: MealType) -> some View {
        let meal = currentDay.meals.first { $0.type == type } ?? PlannedMeal(type: type)
        return Section {
            ForEach(meal.foods) { food in
                Button { editing = EditingFood(type: type, food: food) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name).font(DS.Font.callout).foregroundStyle(DS.Palette.textPrimary)
                            if food.food == nil {
                                Label("Non collegato al database: non conta nelle calorie", systemImage: "exclamationmark.circle")
                                    .font(DS.Font.caption).foregroundStyle(DS.Palette.warning)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Format.grams(food.grams)).font(DS.Font.callout.monospacedDigit())
                                .foregroundStyle(DS.Palette.textPrimary)
                            if let n = food.nutrients {
                                Text(Format.kcal(n.kcal)).font(DS.Font.caption.monospacedDigit())
                                    .foregroundStyle(DS.Palette.textSecondary)
                            }
                        }
                    }
                }
                .accessibilityHint(Text("Modifica la grammatura"))
            }
            .onDelete { offsets in update(type) { $0.foods.remove(atOffsets: offsets) } }
            .onMove { from, to in update(type) { $0.foods.move(fromOffsets: from, toOffset: to) } }
            Button { adding = type } label: {
                Label("Aggiungi alimento", systemImage: "plus.circle.fill")
            }
        } header: {
            HStack {
                Text(type.title)
                Spacer()
                if meal.totals.kcal > 0 { Text(Format.kcal(meal.totals.kcal)).monospacedDigit() }
            }
        }
    }

    // MARK: Modifiche

    private func update(_ type: MealType, _ change: (inout PlannedMeal) -> Void) {
        var day = currentDay
        if let i = day.meals.firstIndex(where: { $0.type == type }) {
            change(&day.meals[i])
        } else {
            var meal = PlannedMeal(type: type)
            change(&meal)
            day.meals.append(meal)
        }
        withAnimation(DS.Motion.snappy) {
            if let i = days.firstIndex(where: { $0.weekday == currentKey }) { days[i] = day } else { days.append(day) }
            days.removeAll { $0.meals.allSatisfy(\.foods.isEmpty) }
        }
    }

    /// Passando a "diverso per giorno" il piano di ogni giorno parte da quello comune, e viceversa.
    private func switchMode(perDay: Bool) {
        if perDay {
            guard let common = days.first(where: { $0.weekday == nil }) else { return }
            days = (1...7).map { PlannedDay(weekday: $0, meals: common.meals) }
        } else {
            let today = Calendar.current.component(.weekday, from: .now)
            let source = days.first { $0.weekday == today } ?? days.first
            days = source.map { [PlannedDay(weekday: nil, meals: $0.meals)] } ?? []
        }
    }

    private func copyToAllDays() {
        let meals = currentDay.meals
        days = (1...7).map { PlannedDay(weekday: $0, meals: meals) }
    }
}

/// Scelta dell'alimento dal database, oppure inserimento solo con nome e grammatura.
private struct PlannedFoodPicker: View {
    let services: AppServices
    let mealTitle: String
    let onAdd: (PlannedFood) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: FoodItem?
    @State private var manual = false

    var body: some View {
        NavigationStack {
            FoodSearchView(services: services) { selected = $0 }
                .navigationTitle("Aggiungi a \(mealTitle)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Non lo trovo: inserisci solo nome e grammi") { manual = true }
                            .font(DS.Font.callout)
                    }
                }
                .navigationDestination(item: $selected) { item in
                    PlannedFoodForm(food: PlannedFood(name: item.name, grams: item.defaultServingG ?? 100, food: item),
                                    foodItem: item) { onAdd($0); dismiss() }
                }
                .navigationDestination(isPresented: $manual) {
                    PlannedFoodForm(food: PlannedFood(name: "", grams: 100), foodItem: nil) { onAdd($0); dismiss() }
                }
        }
    }
}

/// Nome (solo se non collegato al database) e grammatura di un alimento del piano.
private struct PlannedFoodForm: View {
    let foodItem: FoodItem?
    let onSave: (PlannedFood) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlannedFood
    @State private var grams: Double?

    init(food: PlannedFood, foodItem: FoodItem?, onSave: @escaping (PlannedFood) -> Void) {
        self.foodItem = foodItem
        self.onSave = onSave
        _draft = State(initialValue: food)
        _grams = State(initialValue: food.grams)
    }

    private var isValid: Bool {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= ProfessionalPlan.nameMaxLength
            && grams.map { MealItem.gramsRange.contains($0) } == true
    }

    var body: some View {
        Form {
            if let foodItem {
                Section { FoodRow(food: foodItem) }
            } else {
                Section {
                    TextField("Es. Pane integrale", text: $draft.name)
                } header: {
                    Text("Alimento")
                } footer: {
                    Text("Senza collegamento al database l'alimento resta nel piano come promemoria, ma non viene conteggiato nelle calorie.")
                }
            }
            Section("Grammatura") {
                NumericField(label: "Peso", value: $grams, unit: "g", fractionDigits: 0,
                             error: grams.map { MealItem.gramsRange.contains($0) } == false
                                ? String(localized: "Inserisci una quantità tra 1 e 3000 g.") : nil)
                if let foodItem, let g = grams, MealItem.gramsRange.contains(g) {
                    let n = foodItem.per100g.scaled(per100gTo: g)
                    LabeledContent("Calorie", value: Format.kcal(n.kcal))
                    MacroInline(protein: n.proteinG, carbs: n.carbsG, fat: n.fatG)
                }
            }
        }
        .navigationTitle(foodItem?.name ?? String(localized: "Nuovo alimento"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fatto") {
                    guard let grams else { return }
                    draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.grams = grams
                    onSave(draft)
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
    }
}
