import Foundation
import Observation
import CaloScanCore

@Observable
@MainActor
final class ShoppingListViewModel {
    private(set) var state: Loadable<[ShoppingItem]> = .idle
    private(set) var suggestions: [ShoppingSuggestion] = []
    private(set) var isSuggesting = false
    var newName = ""
    var newQuantity = ""
    var error: APIError?

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    var items: [ShoppingItem] { state.value ?? [] }
    var remainingCount: Int { items.filter { !$0.isChecked }.count }
    var checkedCount: Int { items.count - remainingCount }

    /// Prodotti raggruppati per reparto; quelli già presi in fondo a ogni gruppo.
    var sections: [ShoppingSection] {
        ShoppingCategory.allCases.compactMap { category in
            let group = items.filter { $0.category == category }
                .sorted { ($0.isChecked ? 1 : 0, $0.addedAt) < ($1.isChecked ? 1 : 0, $1.addedAt) }
            return group.isEmpty ? nil : ShoppingSection(category: category, items: group)
        }
    }

    var canAdd: Bool { ShoppingItem.sanitized(name: newName, quantity: newQuantity) != nil }

    /// Testo da condividere (Messaggi, WhatsApp, Note…).
    var shareText: String {
        sections.map { section in
            let category = section.category
            let lines = section.items.filter { !$0.isChecked }.map { "• \($0.name)\($0.quantity.map { " — \($0)" } ?? "")" }
            return lines.isEmpty ? "" : "\(category.title)\n" + lines.joined(separator: "\n")
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    func load() async {
        if state.value == nil { state = .loading }
        do { state = .loaded(try await services.shopping.items()) }
        catch { state = .failed(APIError.from(error)) }
    }

    func addManual() async {
        guard let (name, quantity) = ShoppingItem.sanitized(name: newName, quantity: newQuantity) else { return }
        newName = ""
        newQuantity = ""
        await add([ShoppingItem(name: name, quantity: quantity)])
    }

    /// Aggiunge prodotti evitando i doppioni ancora da comprare.
    func add(_ new: [ShoppingItem]) async {
        let before = Set(items.map(\.id))
        let merged = ShoppingListBuilder.merge(new, into: items)
        let changed = merged.filter { item in !before.contains(item.id) || new.contains { $0.name.lowercased() == item.name.lowercased() } }
        state = .loaded(merged)
        do { try await services.shopping.save(changed) }
        catch { self.error = APIError.from(error); await load() }
    }

    func toggle(_ item: ShoppingItem) async {
        var updated = item
        updated.isChecked.toggle()
        await update(updated)
    }

    func setCategory(_ category: ShoppingCategory, for item: ShoppingItem) async {
        var updated = item
        updated.category = category
        await update(updated)
    }

    private func update(_ item: ShoppingItem) async {
        var list = items
        guard let i = list.firstIndex(where: { $0.id == item.id }) else { return }
        list[i] = item
        state = .loaded(list)
        do { try await services.shopping.save([item]) }
        catch { self.error = APIError.from(error); await load() }
    }

    func delete(_ ids: [UUID]) async {
        state = .loaded(items.filter { !ids.contains($0.id) })
        do { try await services.shopping.delete(itemIDs: ids) }
        catch { self.error = APIError.from(error); await load() }
    }

    func removeChecked() async {
        await delete(items.filter(\.isChecked).map(\.id))
    }

    // MARK: Dal piano e dall'AI

    func addFromPlan(_ plan: ProfessionalPlan) async -> Int {
        let fromPlan = ShoppingListBuilder.items(from: plan)
        await add(fromPlan)
        return fromPlan.count
    }

    func requestSuggestions(_ request: String?) async {
        isSuggesting = true
        defer { isSuggesting = false }
        let text = request?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let existing = Set(items.filter { !$0.isChecked }.map { $0.name.lowercased() })
            suggestions = try await services.shopping.suggest(request: (text?.isEmpty ?? true) ? nil : String(text!.prefix(200)))
                .filter { !existing.contains($0.name.lowercased()) }
        } catch {
            suggestions = []
            self.error = APIError.from(error)
        }
    }

    func clearSuggestions() { suggestions = [] }
}

struct ShoppingSection: Identifiable {
    let category: ShoppingCategory
    let items: [ShoppingItem]
    var id: ShoppingCategory { category }
}

extension ShoppingCategory {
    var title: String {
        switch self {
        case .produce: String(localized: "Frutta e verdura")
        case .meatFish: String(localized: "Carne e pesce")
        case .dairyEggs: String(localized: "Latticini e uova")
        case .bakery: String(localized: "Pane e prodotti da forno")
        case .pantry: String(localized: "Dispensa")
        case .frozen: String(localized: "Surgelati")
        case .drinks: String(localized: "Bevande")
        case .other: String(localized: "Altro")
        }
    }

    var symbol: String {
        switch self {
        case .produce: "carrot"
        case .meatFish: "fish"
        case .dairyEggs: "oval.portrait"
        case .bakery: "birthday.cake"
        case .pantry: "cabinet"
        case .frozen: "snowflake"
        case .drinks: "waterbottle"
        case .other: "basket"
        }
    }
}
