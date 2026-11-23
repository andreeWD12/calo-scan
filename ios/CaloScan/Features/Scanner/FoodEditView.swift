import SwiftUI
import CaloScanCore

/// Modifica di un alimento: quantità, sostituzione con un altro alimento, eliminazione.
struct FoodEditView: View {
    let services: AppServices
    let onSave: (DraftItem) -> Void
    var onDelete: (() -> Void)?

    @State private var item: DraftItem
    @State private var gramsText: Double?
    @State private var replacing = false
    @Environment(\.dismiss) private var dismiss

    init(services: AppServices, item: DraftItem, onSave: @escaping (DraftItem) -> Void, onDelete: (() -> Void)? = nil) {
        self.services = services
        self.onSave = onSave
        self.onDelete = onDelete
        _item = State(initialValue: item)
        _gramsText = State(initialValue: item.grams)
        // Alimento senza valori: si apre subito la ricerca già compilata con il nome riconosciuto.
        _replacing = State(initialValue: item.food == nil)
    }

    private var gramsError: String? {
        guard let g = gramsText else { return String(localized: "Inserisci una quantità.") }
        return MealItem.gramsRange.contains(g) ? nil : String(localized: "Inserisci una quantità tra 1 e 3000 g.")
    }

    var body: some View {
        Form {
            Section {
                Button { replacing = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.food?.name ?? item.detectedName).font(DS.Font.headline)
                                .foregroundStyle(DS.Palette.textPrimary)
                            if let food = item.food {
                                Text(food.source.label).font(DS.Font.caption).foregroundStyle(DS.Palette.textTertiary)
                            } else {
                                Text("Nessuna corrispondenza: scegli l'alimento").font(DS.Font.caption)
                                    .foregroundStyle(DS.Palette.warning)
                            }
                        }
                        Spacer()
                        Text("Cambia").font(DS.Font.callout.weight(.semibold))
                    }
                }
                if item.detectedName != item.food?.name, item.food != nil {
                    LabeledContent("Riconosciuto come", value: item.detectedName)
                }
            }

            Section("Quantità") {
                NumericField(label: "Peso", value: $gramsText, unit: "g", fractionDigits: 0, error: gramsError)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(quickPortions, id: \.self) { g in
                            Button(Format.grams(g)) { gramsText = g }
                                .buttonStyle(.bordered)
                                .tint(gramsText == g ? DS.Palette.brand : .secondary)
                        }
                    }
                }
                .contentMargins(.vertical, 0, for: .scrollContent)
            }

            if let food = item.food, let g = gramsText, gramsError == nil {
                let n = food.per100g.scaled(per100gTo: g)
                Section("Valori nutrizionali") {
                    LabeledContent("Calorie", value: Format.kcal(n.kcal))
                    LabeledContent("Proteine", value: Format.grams(n.proteinG))
                    LabeledContent("Carboidrati", value: Format.grams(n.carbsG))
                    LabeledContent("Grassi", value: Format.grams(n.fatG))
                }
            }

            if let onDelete {
                Section {
                    Button("Elimina alimento", role: .destructive, action: onDelete)
                }
            }
        }
        .navigationTitle("Modifica alimento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Fatto") {
                    if let g = gramsText { item.grams = g }
                    onSave(item)
                }
                .disabled(gramsError != nil || item.food == nil)
            }
        }
        // In un foglio con la sua barra: dentro la navigazione la barra di ricerca copriva la prima riga.
        .sheet(isPresented: $replacing) {
            NavigationStack {
            FoodSearchView(services: services, initialQuery: item.detectedName) { food in
                let wasUnresolved = item.food == nil
                item.food = food
                replacing = false
                // Se mancava solo la corrispondenza, la scelta conclude la modifica: niente "Fatto" in più.
                if wasUnresolved, let g = gramsText, gramsError == nil {
                    item.grams = g
                    onSave(item)
                }
            }
            .navigationTitle("Cambia alimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { replacing = false } }
            }
            }
        }
    }

    private var quickPortions: [Double] {
        var values: [Double] = [50, 100, 150, 200, 250]
        if let serving = item.food?.defaultServingG, !values.contains(serving) { values.insert(serving, at: 0) }
        return values
    }
}
