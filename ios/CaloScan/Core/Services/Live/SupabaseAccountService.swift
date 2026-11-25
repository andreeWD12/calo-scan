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

    private struct ExportResponse: Decodable { let fileName: String; let content: String }
    private struct DeleteBody: Encodable, Sendable { let appleAuthorizationCode: String? }

    /// Esportazione completa dei dati (art. 15 e 20 GDPR), preparata dal server (`export-data`) e salvata
    /// in un file temporaneo da condividere. Il file non resta nell'app.
    func exportData() async throws -> URL {
        let response: ExportResponse = try await functions.invoke(.exportData, body: Empty())
        let name = response.fileName.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        do { try Data(response.content.utf8).write(to: url, options: [.atomic, .completeFileProtection]) }
        catch { throw APIError.unknown }
        return url
    }

    func usesAppleSignIn() async -> Bool {
        guard let user = try? await client.auth.session.user else { return false }
        return (user.identities ?? []).contains { $0.provider == "apple" }
    }

    func deleteAccount(appleAuthorizationCode: String?) async throws {
        let response: DeleteResponse = try await functions.invoke(.deleteAccount,
                                                                  body: DeleteBody(appleAuthorizationCode: appleAuthorizationCode))
        guard response.deleted else { throw APIError.unknown }
    }
}
