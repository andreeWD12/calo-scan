import Foundation
import Supabase
import CaloScanCore

/// Pesate (`weight_entries`) e misure corporee (`body_measurements`), entrambe con RLS sul proprietario.
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

    private struct MeasurementRow: Codable {
        let id: UUID
        let date: Date
        let waistCm: Double?
        let hipsCm: Double?
        let chestCm: Double?
        let armCm: Double?
        let thighCm: Double?
        enum CodingKeys: String, CodingKey {
            case id, date, waistCm = "waist_cm", hipsCm = "hips_cm", chestCm = "chest_cm", armCm = "arm_cm", thighCm = "thigh_cm"
        }
    }

    private static func round1(_ v: Double?) -> Double? { v.map { ($0 * 10).rounded() / 10 } }

    func measurements() async throws -> [BodyMeasurement] {
        do {
            let rows: [MeasurementRow] = try await client.from("body_measurements")
                .select("id, date, waist_cm, hips_cm, chest_cm, arm_cm, thigh_cm")
                .order("date", ascending: false)
                .limit(1000)
                .execute()
                .value
            return rows.map {
                BodyMeasurement(id: $0.id, date: $0.date, waistCm: $0.waistCm, hipsCm: $0.hipsCm,
                                chestCm: $0.chestCm, armCm: $0.armCm, thighCm: $0.thighCm)
            }
        } catch {
            throw APIError.from(error)
        }
    }

    func add(_ m: BodyMeasurement) async throws {
        do {
            try await client.from("body_measurements")
                .insert(MeasurementRow(id: m.id, date: m.date, waistCm: Self.round1(m.waistCm), hipsCm: Self.round1(m.hipsCm),
                                       chestCm: Self.round1(m.chestCm), armCm: Self.round1(m.armCm), thighCm: Self.round1(m.thighCm)))
                .execute()
        } catch let error as PostgrestError where error.code == "23514" {
            throw APIError.invalidInput(String(localized: "Una o più misure sono fuori dai valori ammessi."))
        } catch let error as PostgrestError where error.message.contains("measurements_full") {
            throw APIError.invalidInput(String(localized: "Hai raggiunto il numero massimo di rilevazioni salvate."))
        } catch {
            throw APIError.from(error)
        }
    }

    func delete(measurementID: UUID) async throws {
        do {
            try await client.from("body_measurements").delete().eq("id", value: measurementID.uuidString).execute()
        } catch {
            throw APIError.from(error)
        }
    }
}
