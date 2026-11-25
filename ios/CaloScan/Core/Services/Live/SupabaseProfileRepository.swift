import Foundation
import Supabase
import CaloScanCore

/// Profilo e obiettivi. La lettura passa da PostgREST (RLS: solo il proprio profilo);
/// la scrittura dalla funzione `save-profile`, che rivalida gli obiettivi sul server.
struct SupabaseProfileRepository: ProfileRepository {
    let client: SupabaseClient
    let functions: EdgeFunctionClient

    private struct Row: Decodable {
        let profile: UserProfile
        let targets: DailyTargets
    }

    private struct PlanRow: Decodable { let plan: ProfessionalPlan }

    private struct SaveBody: Encodable, Sendable {
        let profile: UserProfile
        let targets: DailyTargets
    }

    func loadProfile() async throws -> UserProfile? {
        try await row()?.profile
    }

    func loadTargets() async throws -> DailyTargets? {
        try await row()?.targets
    }

    func save(profile: UserProfile, targets: DailyTargets) async throws {
        do {
            try await functions.send(.saveProfile, body: SaveBody(profile: profile, targets: targets))
            if let id = try? await client.auth.session.user.id { SupabaseAuthService.markOnboarded(userID: id) }
        } catch APIError.invalidInput(let codes) {
            throw APIError.invalidInput(Self.message(for: codes))
        }
    }

    func loadProfessionalPlan() async throws -> ProfessionalPlan? {
        do {
            let rows: [PlanRow] = try await client.from("professional_plans").select("plan").limit(1).execute().value
            return rows.first?.plan
        } catch {
            throw APIError.from(error)
        }
    }

    // Salvataggio del piano del professionista: Fase 4 (rivalidazione con validateProfessionalPlan).
    func save(professionalPlan: ProfessionalPlan) async throws { throw APIError.notConnected }
    func deleteProfessionalPlan() async throws { throw APIError.notConnected }

    private func row() async throws -> Row? {
        do {
            // RLS restituisce solo la riga dell'utente collegato.
            let rows: [Row] = try await client.from("profiles").select("profile, targets").limit(1).execute().value
            return rows.first
        } catch {
            throw APIError.from(error)
        }
    }

    /// Traduce i codici di `validateProfilePayload` (save-profile) in messaggi per l'utente.
    static func message(for codes: String) -> String {
        let list = codes.split(separator: ",").map(String.init)
        if list.contains("under_minimum_age") {
            return String(localized: "CaloScan è riservata a chi ha almeno \(AgePolicy.minimumAccountAge) anni.")
        }
        if list.contains("unsafe_calorie_target") {
            return String(localized: "L'obiettivo calorico è fuori dall'intervallo sicuro. Scegli un valore più alto.")
        }
        if list.contains("note_too_long") {
            return String(localized: "Le note sono troppo lunghe (massimo 500 caratteri).")
        }
        return String(localized: "Alcuni dati del profilo non sono validi. Controllali e riprova.")
    }
}
