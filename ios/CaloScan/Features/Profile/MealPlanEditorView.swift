import SwiftUI
import CaloScanCore

/// Pasti del piano del professionista, con alimenti e grammature.
/// Il piano può essere uguale ogni giorno oppure diverso per ogni giorno della settimana,
/// e può ruotare su più settimane (settimana 1, 2…). Si ripete da solo: non va ricompilato.
struct MealPlanEditorView: View {
    @Binding var days: [PlannedDay]
    @Binding var rotationWeeks: Int
    @Binding var rotationAnchor: Date?
    /// Data di inizio del piano: ancora predefinita della rotazione.
    let startDate: Date
    let services: AppServices
    /// Calorie giornaliere indicate nel piano, per confrontarle con la somma degli alimenti.
    let calorieTarget: Int?

    @State private var perWeekday = false
    @State private var weekday = Calendar.current.component(.weekday, from: .now)
    @State private var week = 1
    @State private var adding: MealType?
    @State private var editing: EditingFood?
    @State private var confirmCopy = false
    @State private var confirmCopyWeek = false
    @State private var pendingWeeks: Int?

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
        days.first { $0.week == week && $0.weekday == currentKey } ?? PlannedDay(week: week, weekday: currentKey)
    }

    /// Settimana della rotazione in corso oggi.
    private var currentRotationWeek: Int {
        ProfessionalPlan.rotationWeek(on: .now, anchor: rotationAnchor ?? startDate, weeks: rotationWeeks)
    }

    private func weekHasFoods(_ w: Int) -> Bool {
        days.contains { $0.week == w && $0.meals.contains { !$0.foods.isEmpty } }
    }

    var body: some View {
        Form {
            rotationSection

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
                if rotationWeeks > 1 {
                    Button("Copia la settimana \(week) sulle altre") { confirmCopyWeek = true }
                        .disabled(!weekHasFoods(week))
                }
            } footer: {
                Text("Il totale considera solo gli alimenti collegati al database. Le calorie del piano restano quelle che hai inserito.")
            }
        }
        .navigationTitle("Pasti del piano")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            perWeekday = days.contains { $0.weekday != nil }
            week = min(max(currentRotationWeek, 1), rotationWeeks)
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
        .confirmationDialog("Copiare sulle altre settimane?", isPresented: $confirmCopyWeek, titleVisibility: .visible) {
            Button("Copia e sostituisci") { copyWeekToOthers() }
        } message: {
            Text("I pasti delle altre settimane verranno sostituiti con quelli della settimana \(week).")
        }
        .confirmationDialog("Ridurre le settimane del piano?",
                            isPresented: Binding(get: { pendingWeeks != nil }, set: { if !$0 { pendingWeeks = nil } }),
                            titleVisibility: .visible, presenting: pendingWeeks) { n in
            Button("Rimuovi le settimane in più", role: .destructive) { applyRotation(n) }
        } message: { n in
            Text("I pasti delle settimane dalla \(n + 1) in poi verranno eliminati.")
        }
    }

    // MARK: Rotazione

    private var rotationSection: some View {
        Section {
            Picker("Il piano si ripete", selection: Binding(get: { rotationWeeks }, set: { requestRotation($0) })) {
                Text("Ogni settimana").tag(1)
                ForEach(2...ProfessionalPlan.rotationRange.upperBound, id: \.self) { n in
                    Text("Ogni \(n) settimane").tag(n)
                }
            }
            if rotationWeeks > 1 {
                Picker("Settimana", selection: $week.animation(DS.Motion.snappy)) {
                    ForEach(1...rotationWeeks, id: \.self) { w in
                        Text("Sett. \(w)").tag(w)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Questa settimana è la", selection: Binding(
                    get: { currentRotationWeek },
                    set: { rotationAnchor = ProfessionalPlan.anchor(making: $0) })) {
                    ForEach(1...rotationWeeks, id: \.self) { w in
                        Text("Settimana \(w)").tag(w)
                    }
                }
            }
        } header: {
            Text("Rotazione")
        } footer: {
            if rotationWeeks > 1 {
                Text("Il piano ricomincia da solo dalla settimana 1 dopo la settimana \(rotationWeeks). Se l'app è fuori passo rispetto al tuo piano, indica qui quale settimana stai seguendo.")
            } else {
                Text("Il piano si ripete da solo ogni settimana: non devi ricompilarlo. Se il tuo piano alterna settimane diverse (es. settimana 1 e settimana 2), scegli ogni quante settimane ricomincia.")
            }
        }
    }

    private func requestRotation(_ n: Int) {
        guard n != rotationWeeks else { return }
        if n < rotationWeeks, ((n + 1)...rotationWeeks).contains(where: { weekHasFoods($0) }) {
            pendingWeeks = n
        } else {
            applyRotation(n)
        }
    }

    /// Aggiungendo settimane si parte dalla settimana 1, così basta cambiare ciò che è diverso.
    private func applyRotation(_ n: Int) {
        withAnimation(DS.Motion.snappy) {
            if n > rotationWeeks {
                let base = days.filter { $0.week == 1 }
                for w in (rotationWeeks + 1)...n where !weekHasFoods(w) {
                    days.append(contentsOf: base.map { PlannedDay(week: w, weekday: $0.weekday, meals: $0.meals) })
                }
            } else {
                days.removeAll { $0.week > n }
            }
            rotationWeeks = n
            if n == 1 { rotationAnchor = nil }
            week = min(week, n)
        }
        pendingWeeks = nil
    }

    private func copyWeekToOthers() {
        let source = days.filter { $0.week == week }
        days = (1...rotationWeeks).flatMap { w in
            source.map { PlannedDay(week: w, weekday: $0.weekday, meals: $0.meals) }
        }
    }

    private var weekdayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                ForEach(orderedWeekdays, id: \.self) { day in
                    let selected = day == weekday
                    let hasFoods = days.first { $0.week == week && $0.weekday == day }?.meals.contains { !$0.foods.isEmpty } ?? false
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
            if let i = days.firstIndex(where: { $0.week == week && $0.weekday == currentKey }) { days[i] = day } else { days.append(day) }
            days.removeAll { $0.meals.allSatisfy(\.foods.isEmpty) }
        }
    }

    /// Passando a "diverso per giorno" il piano di ogni giorno parte da quello comune, e viceversa.
    /// Vale per ogni settimana della rotazione.
    private func switchMode(perDay: Bool) {
        let today = Calendar.current.component(.weekday, from: .now)
        days = (1...rotationWeeks).flatMap { w -> [PlannedDay] in
            let inWeek = days.filter { $0.week == w }
            if perDay {
                guard !inWeek.contains(where: { $0.weekday != nil }) else { return inWeek }
                guard let common = inWeek.first(where: { $0.weekday == nil }) else { return [] }
                return (1...7).map { PlannedDay(week: w, weekday: $0, meals: common.meals) }
            } else {
                guard inWeek.contains(where: { $0.weekday != nil }) else { return inWeek }
                let source = inWeek.first { $0.weekday == today } ?? inWeek.first
                return source.map { [PlannedDay(week: w, weekday: nil, meals: $0.meals)] } ?? []
            }
        }
    }

    private func copyToAllDays() {
        let meals = currentDay.meals
        days.removeAll { $0.week == week }
        days += (1...7).map { PlannedDay(week: week, weekday: $0, meals: meals) }
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
