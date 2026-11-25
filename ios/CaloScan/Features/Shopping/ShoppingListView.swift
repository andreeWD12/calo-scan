import SwiftUI
import CaloScanCore

/// Lista della spesa: inserimento manuale gratuito, prodotti dal piano del professionista (gratuito)
/// e suggerimenti dell'AI per Plus e Pro.
struct ShoppingListView: View {
    @Environment(AppState.self) private var app
    @State private var model: ShoppingListViewModel
    @State private var showSuggestions = false
    @State private var showPaywall = false
    @State private var confirmClear = false
    @FocusState private var nameFocused: Bool

    init(services: AppServices) {
        _model = State(initialValue: ShoppingListViewModel(services: services))
    }

    private var hasPlanMeals: Bool { !(app.professionalPlan?.mealPlan.isEmpty ?? true) }

    var body: some View {
        List {
            Section {
                addRow
            } footer: {
                Text("Il reparto viene scelto in automatico; tieni premuto un prodotto per cambiarlo.")
            }

            Section {
                aiButton
                if hasPlanMeals, let plan = app.professionalPlan {
                    Button {
                        Task {
                            let n = await model.addFromPlan(plan)
                            app.toasts.success(String(localized: "Aggiunti dal piano"),
                                               subtitle: String(localized: "\(n) prodotti per 7 giorni"), symbol: "list.clipboard")
                        }
                    } label: {
                        Label("Aggiungi i prodotti del piano (7 giorni)", systemImage: "list.clipboard")
                    }
                }
            }

            content
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Lista della spesa")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: model.shareText) { Label("Condividi la lista", systemImage: "square.and.arrow.up") }
                        .disabled(model.remainingCount == 0)
                    Button("Rimuovi i prodotti presi", systemImage: "checkmark.circle.badge.xmark") { confirmClear = true }
                        .disabled(model.checkedCount == 0)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(Text("Altre azioni"))
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
        .animation(DS.Motion.snappy, value: model.items)
        .sensoryFeedback(.success, trigger: model.checkedCount)
        .confirmationDialog("Rimuovere i prodotti già presi?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Rimuovi \(model.checkedCount)", role: .destructive) { Task { await model.removeChecked() } }
        }
        .sheet(isPresented: $showSuggestions) {
            ShoppingSuggestionsSheet(model: model, allergens: app.profile?.allergens ?? [])
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(services: app.services, highlight: .plus)
        }
        .alert("Operazione non riuscita",
               isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } }),
               presenting: model.error) { _ in Button("OK", role: .cancel) {} } message: { Text($0.localizedDescription) }
    }

    private var addRow: some View {
        HStack(spacing: DS.Spacing.xs) {
            TextField("Aggiungi un prodotto", text: $model.newName)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { Task { await model.addManual(); nameFocused = true } }
            TextField("Quantità", text: $model.newQuantity)
                .frame(maxWidth: 90)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(DS.Palette.textSecondary)
            Button {
                Task { await model.addManual() }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title2)
                    .foregroundStyle(model.canAdd ? DS.Palette.brand : DS.Palette.separator)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .disabled(!model.canAdd)
            .accessibilityLabel(Text("Aggiungi alla lista"))
        }
    }

    private var aiButton: some View {
        Button {
            if app.entitlements.plan == .free { showPaywall = true } else { showSuggestions = true }
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suggerisci con l'AI").foregroundStyle(DS.Palette.textPrimary)
                        Text("In base ai tuoi obiettivi, al piano e alle allergie")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                    }
                } icon: {
                    Image(systemName: "sparkles").foregroundStyle(DS.Palette.brand)
                }
                Spacer()
                if app.entitlements.plan == .free {
                    Label("Plus", systemImage: "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DS.Palette.brand)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(DS.Palette.brandSoft, in: .capsule)
                }
            }
        }
        .accessibilityHint(Text(app.entitlements.plan == .free ? "Disponibile con Plus e Pro" : "Apre i suggerimenti"))
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            Section { ProgressView().frame(maxWidth: .infinity) }
        case .failed(let error):
            Section { ErrorStateView(error: error) { Task { await model.load() } } }
        case .empty, .loaded:
            if model.items.isEmpty {
                Section {
                    ContentUnavailableView("La lista è vuota", systemImage: "cart",
                                           description: Text("Aggiungi i prodotti che ti servono: quando li prendi, toccali per spuntarli."))
                }
            } else {
                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.items) { item in row(item) }
                            .onDelete { offsets in Task { await model.delete(offsets.map { section.items[$0].id }) } }
                    } header: {
                        Label(section.category.title, systemImage: section.category.symbol)
                    }
                }
            }
        }
    }

    private func row(_ item: ShoppingItem) -> some View {
        Button { Task { await model.toggle(item) } } label: {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? DS.Palette.brand : DS.Palette.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? DS.Palette.textTertiary : DS.Palette.textPrimary)
                    PregnancyFoodBadge(name: item.name)
                    if item.source != .manual {
                        Label(item.source == .ai ? "Suggerito dall'AI" : "Dal piano",
                              systemImage: item.source == .ai ? "sparkles" : "list.clipboard")
                            .font(.caption2).foregroundStyle(DS.Palette.textTertiary)
                    }
                }
                Spacer()
                if let q = item.quantity {
                    Text(q).font(DS.Font.callout.monospacedDigit()).foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(item.isChecked ? .isSelected : [])
        .contextMenu {
            Menu("Sposta in…", systemImage: "folder") {
                ForEach(ShoppingCategory.allCases, id: \.self) { category in
                    Button(category.title) { Task { await model.setCategory(category, for: item) } }
                }
            }
            Button("Elimina", systemImage: "trash", role: .destructive) { Task { await model.delete([item.id]) } }
        }
    }
}

/// Suggerimenti dell'AI: l'utente sceglie quali aggiungere. Gli allergeni vengono esclusi dal server.
private struct ShoppingSuggestionsSheet: View {
    @Bindable var model: ShoppingListViewModel
    let allergens: Set<Allergen>

    @Environment(\.dismiss) private var dismiss
    @State private var request = ""
    @State private var selected: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Facoltativo: es. cene veloci per 3 giorni", text: $request, axis: .vertical)
                        .lineLimit(1...3)
                    Button {
                        Task {
                            await model.requestSuggestions(request)
                            selected = Set(model.suggestions.map(\.id))
                        }
                    } label: {
                        HStack {
                            Label(model.suggestions.isEmpty ? "Genera la lista" : "Genera di nuovo", systemImage: "sparkles")
                            Spacer()
                            if model.isSuggesting { ProgressView() }
                        }
                    }
                    .disabled(model.isSuggesting)
                } footer: {
                    if allergens.isEmpty {
                        Text("Se hai allergie o intolleranze, indicale nel Profilo: verranno escluse dalle proposte.")
                    } else {
                        Text("Gli alimenti con le allergie e intolleranze indicate nel tuo profilo (\(allergens.count)) vengono esclusi.")
                    }
                }

                if !model.suggestions.isEmpty {
                    Section("Proposte") {
                        ForEach(model.suggestions) { s in
                            Button {
                                if selected.contains(s.id) { selected.remove(s.id) } else { selected.insert(s.id) }
                            } label: {
                                HStack(alignment: .top, spacing: DS.Spacing.s) {
                                    Image(systemName: selected.contains(s.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(s.id) ? DS.Palette.brand : DS.Palette.textTertiary)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(s.name).foregroundStyle(DS.Palette.textPrimary)
                                            Spacer()
                                            if let q = s.quantity { Text(q).foregroundStyle(DS.Palette.textSecondary) }
                                        }
                                        if let reason = s.reason {
                                            Text(reason).font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected.contains(s.id) ? .isSelected : [])
                        }
                    }
                }

                Section {
                    Text("Proposte generate dall'intelligenza artificiale: controlla sempre le etichette dei prodotti, soprattutto per allergeni e tracce.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .navigationTitle("Suggerimenti AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { model.clearSuggestions(); dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if !model.suggestions.isEmpty {
                    Button("Aggiungi \(selected.count) alla lista") {
                        let chosen = model.suggestions.filter { selected.contains($0.id) }.map { $0.asItem() }
                        Task {
                            await model.add(chosen)
                            model.clearSuggestions()
                            dismiss()
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(selected.isEmpty)
                    .padding(DS.Spacing.screen)
                    .background(.bar)
                }
            }
        }
    }
}
