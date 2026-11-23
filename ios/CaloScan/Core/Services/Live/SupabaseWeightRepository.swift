import Foundation
import Supabase
import CaloScanCore

/// Pesate (tabella `weight_entries`, RLS sul proprietario). Le misure corporee arrivano nella Fase 6.
struct SupabaseWeightRepository: WeightRepository {
    let client: SupabaseClient

    private struct Row: Codable {
        let id: UUID
        let date: Date
        let weightKg: Double
        enum CodingKeys: String, CodingKey { case id, date, weightKg = "weight_kg" }
    }

    func entries() async throws -> [WeightEntry] {
        do {
            let rows: [Row] = try await client.from("weight_entries")
                .select("id, date, weight_kg")
                .order("date", ascending: false)
                .execute()
                .value
            return rows.map { WeightEntry(id: $0.id, date: $0.date, weightKg: $0.weightKg) }
        } catch {
            throw APIError.from(error)
        }
    }

    func add(_ entry: WeightEntry) async throws {
        do {
            // user_id è impostato dal database (default auth.uid()) e verificato dalla RLS.
            try await client.from("weight_entries")
                .insert(Row(id: entry.id, date: entry.date, weightKg: (entry.weightKg * 10).rounded() / 10))
                .execute()
        } catch {
            throw APIError.from(error)
        }
    }

    func delete(entryID: UUID) async throws {
        do {
            try await client.from("weight_entries").delete().eq("id", value: entryID.uuidString).execute()
        } catch {
            throw APIError.from(error)
        }
    }

    func measurements() async throws -> [BodyMeasurement] { throw APIError.notConnected }
    func add(_ measurement: BodyMeasurement) async throws { throw APIError.notConnected }
}
