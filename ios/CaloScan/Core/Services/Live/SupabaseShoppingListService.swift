import Foundation
import Supabase
import CaloScanCore

/// Lista della spesa (tabella `shopping_items`, RLS sul proprietario, massimo 200 prodotti).
/// I suggerimenti dell'AI arrivano con la fase del coach: fino ad allora restano non collegati.
struct SupabaseShoppingListService: ShoppingListService {
    let client: SupabaseClient

    private struct Row: Codable, Sendable {
        let id: UUID
        let name: String
        let quantity: String?
        let category: ShoppingCategory
        let isChecked: Bool
        let source: ShoppingItemSource
        let addedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, name, quantity, category, source
            case isChecked = "is_checked", addedAt = "added_at"
        }

        init(_ i: ShoppingItem) {
            id = i.id; name = i.name; quantity = i.quantity; category = i.category
            isChecked = i.isChecked; source = i.source; addedAt = i.addedAt
        }

        var item: ShoppingItem {
            ShoppingItem(id: id, name: name, quantity: quantity, category: category,
                         isChecked: isChecked, source: source, addedAt: addedAt)
        }
    }

    func items() async throws -> [ShoppingItem] {
        do {
            let rows: [Row] = try await client.from("shopping_items")
                .select("id, name, quantity, category, is_checked, source, added_at")
                .order("added_at", ascending: true)
                .execute()
                .value
            return rows.map(\.item)
        } catch {
            throw APIError.from(error)
        }
    }

    func save(_ items: [ShoppingItem]) async throws {
        guard !items.isEmpty else { return }
        do {
            try await client.from("shopping_items").upsert(items.map(Row.init), onConflict: "id").execute()
        } catch let error as PostgrestError where error.message.contains("shopping_list_full") {
            throw APIError.invalidInput(String(localized: "La lista può contenere al massimo \(ShoppingItem.maxItems) prodotti."))
        } catch let error as PostgrestError where error.code == "23514" {
            throw APIError.invalidInput(String(localized: "Nome o quantità troppo lunghi."))
        } catch {
            throw APIError.from(error)
        }
    }

    func delete(itemIDs: [UUID]) async throws {
        guard !itemIDs.isEmpty else { return }
        do {
            try await client.from("shopping_items").delete().in("id", values: itemIDs.map(\.uuidString)).execute()
        } catch {
            throw APIError.from(error)
        }
    }

    func suggest(request: String?) async throws -> [ShoppingSuggestion] { throw APIError.notConnected }
}
