import SwiftUI
import CaloScanCore

@Observable
@MainActor
final class FoodSearchViewModel {
    var query = ""
    private(set) var results: Loadable<[FoodItem]> = .idle
    private let foods: any FoodSearchService

    init(foods: any FoodSearchService) {
        self.foods = foods
    }

    /// Ricerca con debounce: viene annullata se l'utente continua a scrivere.
    func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { results = .idle; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        results = .loading
        do {
            let list = try await foods.search(q)
            guard !Task.isCancelled else { return }
            results = list.isEmpty ? .empty : .loaded(list)
        } catch {
            guard !Task.isCancelled else { return }
            results = .failed(APIError.from(error))
        }
    }
}

/// Ricerca manuale degli alimenti nei database nutrizionali.
struct FoodSearchView: View {
    @State private var model: FoodSearchViewModel
    @State private var showsCustomFood = false
    @State private var customFood: FoodItem?
    let onSelect: (FoodItem) -> Void

    init(services: AppServices, onSelect: @escaping (FoodItem) -> Void) {
        _model = State(initialValue: FoodSearchViewModel(foods: services.foods))
        self.onSelect = onSelect
    }

    var body: some View {
        List {
            Section {
                Button { showsCustomFood = true } label: {
                    Label("Inserisci i valori dell'etichetta", systemImage: "square.and.pencil")
                        .font(DS.Font.callout.weight(.medium))
                }
            } footer: {
                Text("Per un alimento che non trovi, con calorie e macro letti dalla confezione.")
            }
            switch model.results {
            case .idle:
                Section {
                    Text("Scrivi almeno due lettere, ad esempio \"pasta\", \"mela\" o il nome di un prodotto.")
                        .font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
                }
            case .loading:
                LoadingStateView(message: "Ricerca…").listRowBackground(Color.clear)
            case .empty:
                EmptyStateView(title: "Nessun risultato",
                               message: "Prova con un termine più generico o controlla l'ortografia.",
                               systemImage: "magnifyingglass")
                    .listRowBackground(Color.clear)
            case .failed(let error):
                ErrorStateView(error: error) { Task { await model.search() } }.listRowBackground(Color.clear)
            case .loaded(let foods):
                Section {
                    ForEach(foods) { food in
                        Button { onSelect(food) } label: { FoodRow(food: food) }
                            .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Valori per 100 g da USDA FoodData Central e Open Food Facts.")
                }
            }
        }
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Cerca un alimento"))
        .autocorrectionDisabled()
        .task(id: model.query) { await model.search() }
        // L'alimento passa avanti solo a foglio chiuso, così la navigazione successiva non si blocca.
        .sheet(isPresented: $showsCustomFood, onDismiss: {
            if let food = customFood { customFood = nil; onSelect(food) }
        }) {
            CustomFoodView { customFood = $0 }
        }
    }
}

struct FoodRow: View {
    let food: FoodItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name).font(DS.Font.callout.weight(.medium)).foregroundStyle(DS.Palette.textPrimary)
                Text([food.brand, food.source.label].compactMap { $0 }.joined(separator: " · "))
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.textTertiary)
                PregnancyFoodBadge(name: food.name)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.kcal(food.per100g.kcal)).font(DS.Font.callout.monospacedDigit())
                Text("per 100 g").font(DS.Font.caption).foregroundStyle(DS.Palette.textTertiary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
