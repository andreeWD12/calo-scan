import SwiftUI
import CaloScanCore

/// Riepilogo della scansione: alimenti riconosciuti, quantità modificabili, totali stimati.
struct ScanResultView: View {
    @Bindable var model: ScannerViewModel
    let services: AppServices
    let onDescribe: () -> Void
    let onSaved: () -> Void

    @State private var editing: DraftItem?
    @State private var addingIngredient = false

    var body: some View {
        List {
            Section {
                if let data = model.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(height: 180).frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: DS.Radius.m))
                        .listRowInsets(EdgeInsets())
                        .accessibilityHidden(true)
                }
            }
            .listRowBackground(Color.clear)

            Section {
                TotalsRow(totals: model.totals, confidence: model.overallConfidence)
                EstimateNotice(text: model.mealSource == .description
                    ? "Valori stimati dalla tua descrizione: dove non hai indicato le quantità usiamo porzioni standard. Controlla e correggi prima di salvare."
                    : "Valori stimati da una foto: peso, olio, condimenti e ingredienti nascosti non sono determinabili con precisione. Controlla e correggi le quantità prima di salvare.")
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            if !model.questions.isEmpty {
                Section("Da confermare") {
                    ForEach(model.questions, id: \.self) { q in
                        Label(q, systemImage: "questionmark.circle").font(DS.Font.callout)
                    }
                }
            }

            Section {
                ForEach(model.items) { item in
                    Button { editing = item } label: { DraftItemRow(item: item) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Elimina", systemImage: "trash", role: .destructive) { model.remove(item) }
                        }
                }
                Button { addingIngredient = true } label: {
                    Label("Aggiungi alimento o ingrediente", systemImage: "plus")
                }
                Button(action: onDescribe) {
                    Label(model.mealSource == .description ? "Modifica la descrizione" : "Non è corretto? Descrivi il piatto",
                          systemImage: "text.bubble")
                }
            } header: {
                Text("Alimenti riconosciuti")
            } footer: {
                if model.unresolvedCount > 0 {
                    Text("Tocca gli alimenti segnalati per scegliere la corrispondenza corretta, oppure eliminali.")
                }
            }

            Section {
                Picker("Pasto", selection: $model.mealType) {
                    ForEach(MealType.allCases) { Text($0.title).tag($0) }
                }
                Toggle(isOn: $model.isCheatMeal.animation(DS.Motion.snappy)) {
                    Label("Segna come sgarro", systemImage: "party.popper")
                }
                .tint(DS.Palette.fat)
            } footer: {
                if model.isCheatMeal {
                    Text("Gli sgarri contano nelle calorie della giornata come ogni pasto; nelle statistiche li vedi anche a parte.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Risultato")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: DS.Spacing.xs) {
                LoadingButton(title: "Conferma e salva nel diario", isLoading: model.isSaving) {
                    Task { if await model.save() { onSaved() } }
                }
                .disabled(!model.canSave)
                Button("Scatta di nuovo") { model.retake() }
                    .font(DS.Font.callout.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.top, DS.Spacing.xs)
            .background(.bar)
        }
        .sheet(item: $editing) { item in
            NavigationStack {
                FoodEditView(services: services, item: item,
                             onSave: { model.update($0); editing = nil },
                             onDelete: { model.remove(item); editing = nil })
            }
        }
        .sheet(isPresented: $addingIngredient) {
            NavigationStack {
                FoodSearchView(services: services) { food in
                    model.add(food: food, grams: food.defaultServingG ?? 100)
                    addingIngredient = false
                }
                .navigationTitle("Aggiungi")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { addingIngredient = false } }
                }
            }
        }
        .alert("Salvataggio non riuscito",
               isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } }),
               presenting: model.saveError) { _ in Button("OK", role: .cancel) {} } message: { Text($0.localizedDescription) }
    }
}

private struct TotalsRow: View {
    let totals: Nutrients
    let confidence: Confidence?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("Totale stimato").font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                    Text("≈ \(Format.kcal(totals.kcal))").font(DS.Font.metric)
                }
                Spacer()
                if let confidence { ConfidenceBadge(confidence: confidence) }
            }
            HStack(spacing: DS.Spacing.xs) {
                StatTile(title: "Proteine", value: Format.grams(totals.proteinG), tint: DS.Palette.protein)
                StatTile(title: "Carboidrati", value: Format.grams(totals.carbsG), tint: DS.Palette.carbs)
                StatTile(title: "Grassi", value: Format.grams(totals.fatG), tint: DS.Palette.fat)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}

private struct DraftItemRow: View {
    let item: DraftItem

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.food?.name ?? item.detectedName).font(DS.Font.headline)
                if item.food == nil {
                    Label("Scegli l'alimento corrispondente", systemImage: "exclamationmark.triangle.fill")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.warning)
                } else if let n = item.nutrients {
                    MacroInline(protein: n.proteinG, carbs: n.carbsG, fat: n.fatG)
                }
                if !item.ingredients.isEmpty {
                    Text(item.ingredients.joined(separator: ", "))
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.textTertiary).lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("≈ \(Format.grams(item.grams))").font(DS.Font.callout.monospacedDigit())
                if let n = item.nutrients {
                    Text(Format.kcal(n.kcal)).font(DS.Font.caption.monospacedDigit()).foregroundStyle(DS.Palette.textSecondary)
                }
                if let c = item.confidence, c != .high { ConfidenceBadge(confidence: c) }
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Tocca per modificare"))
    }
}
