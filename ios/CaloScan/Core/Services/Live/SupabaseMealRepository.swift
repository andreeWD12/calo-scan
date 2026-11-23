import Foundation
import Supabase
import CaloScanCore

/// Diario dei pasti (tabella `meals`, RLS sul proprietario). Gli alimenti sono salvati con i loro
/// valori per 100 g, così il diario resta corretto anche se il database alimenti cambia.
/// I giorni sono calcolati nel fuso orario del telefono.
struct SupabaseMealRepository: MealRepository {
    let client: SupabaseClient
    var calendar: Calendar = .current

    private struct Row: Codable, Sendable {
        let id: UUID
        let type: MealType
        let loggedAt: Date
        let source: MealSource
        let scanId: UUID?
        let isCheatMeal: Bool
        let items: [MealItem]

        enum CodingKeys: String, CodingKey {
            case id, type, source, items
            case loggedAt = "logged_at", scanId = "scan_id", isCheatMeal = "is_cheat_meal"
        }

        init(_ m: Meal) {
            id = m.id; type = m.type; loggedAt = m.loggedAt; source = m.source
            scanId = m.scanID; isCheatMeal = m.isCheatMeal; items = m.items
        }

        var meal: Meal {
            Meal(id: id, type: type, loggedAt: loggedAt, items: items, source: source, scanID: scanId, isCheatMeal: isCheatMeal)
        }
    }

    private static let pageSize = 1000
    private static let columns = "id, type, logged_at, source, scan_id, is_cheat_meal, items"

    func dayLog(for day: Date) async throws -> DayLog {
        let start = calendar.startOfDay(for: day)
        return try await dayLogs(from: start, to: start).first ?? DayLog(day: start, meals: [])
    }

    /// Un DayLog per ogni giorno da `start` a `end` inclusi, anche se vuoto.
    func dayLogs(from start: Date, to end: Date) async throws -> [DayLog] {
        let first = calendar.startOfDay(for: min(start, end))
        let last = calendar.startOfDay(for: max(start, end))
        guard let until = calendar.date(byAdding: .day, value: 1, to: last) else { return [] }
        do {
            // Supabase restituisce al massimo 1000 righe per richiesta: i periodi lunghi arrivano a pagine.
            var rows: [Row] = []
            while true {
                let page: [Row] = try await client.from("meals")
                    .select(Self.columns)
                    .gte("logged_at", value: first.ISO8601Format())
                    .lt("logged_at", value: until.ISO8601Format())
                    .order("logged_at", ascending: true)
                    .order("id", ascending: true)
                    .range(from: rows.count, to: rows.count + Self.pageSize - 1)
                    .execute()
                    .value
                rows += page
                if page.count < Self.pageSize { break }
            }
            let byDay = Dictionary(grouping: rows.map(\.meal)) { calendar.startOfDay(for: $0.loggedAt) }
            var logs: [DayLog] = []
            var day = first
            while day <= last {
                logs.append(DayLog(day: day, meals: byDay[day] ?? []))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return logs
        } catch {
            throw APIError.from(error)
        }
    }

    /// Crea il pasto o lo aggiorna se esiste già (stesso id).
    func save(_ meal: Meal) async throws {
        do {
            try await client.from("meals").upsert(Row(meal), onConflict: "id").execute()
        } catch {
            throw Self.map(error)
        }
    }

    func delete(mealID: UUID) async throws {
        do {
            try await client.from("meals").delete().eq("id", value: mealID.uuidString).execute()
        } catch {
            throw APIError.from(error)
        }
    }

    /// Il database rifiuta grammature o valori fuori dai limiti dell'app (vincolo `meal_items_valid`).
    private static func map(_ error: Error) -> APIError {
        if let pg = error as? PostgrestError, pg.code == "23514" {
            return .invalidInput(String(localized: "Alcuni alimenti hanno quantità o valori non validi. Controllali e riprova."))
        }
        return APIError.from(error)
    }
}
