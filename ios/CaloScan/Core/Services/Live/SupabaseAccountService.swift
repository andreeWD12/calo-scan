import Foundation
import Supabase

/// Consensi (tabella `consents`, con storico automatico in `consent_events`) ed eliminazione dell'account.
struct SupabaseAccountService: AccountService {
    let client: SupabaseClient
    let functions: EdgeFunctionClient

    private struct Row: Codable {
        var userId: UUID?
        let healthDataProcessing: Bool
        let aiImageAnalysis: Bool
        let productEmails: Bool
        enum CodingKeys: String, CodingKey {
            case userId = "user_id", healthDataProcessing = "health_data_processing"
            case aiImageAnalysis = "ai_image_analysis", productEmails = "product_emails"
        }
    }

    private struct Empty: Encodable, Sendable {}
    private struct DeleteResponse: Decodable { let deleted: Bool }

    func consents() async throws -> ConsentState {
        do {
            let rows: [Row] = try await client.from("consents")
                .select("health_data_processing, ai_image_analysis, product_emails")
                .limit(1)
                .execute()
                .value
            guard let r = rows.first else {
                return ConsentState(healthDataProcessing: false, aiImageAnalysis: false, productEmails: false)
            }
            return ConsentState(healthDataProcessing: r.healthDataProcessing, aiImageAnalysis: r.aiImageAnalysis,
                                productEmails: r.productEmails)
        } catch {
            throw APIError.from(error)
        }
    }

    func update(consents c: ConsentState) async throws {
        do {
            let userID = try await client.auth.session.user.id
            try await client.from("consents")
                .upsert(Row(userId: userID, healthDataProcessing: c.healthDataProcessing,
                            aiImageAnalysis: c.aiImageAnalysis, productEmails: c.productEmails),
                        onConflict: "user_id")
                .execute()
        } catch {
            throw APIError.from(error)
        }
    }

    // Esportazione completa dei dati (art. 20 GDPR): Fase 9, quando tutte le tabelle esistono.
    func exportData() async throws -> URL { throw APIError.notConnected }

    func deleteAccount() async throws {
        let response: DeleteResponse = try await functions.invoke(.deleteAccount, body: Empty())
        guard response.deleted else { throw APIError.unknown }
    }
}
