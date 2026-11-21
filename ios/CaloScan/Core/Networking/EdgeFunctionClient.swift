import Foundation
import Supabase

/// Unico punto d'accesso alle Edge Functions. Il JWT dell'utente viene allegato da supabase-swift;
/// le chiavi dei provider AI esistono solo sul server.
struct EdgeFunctionClient: Sendable {
    let client: SupabaseClient

    enum Function: String {
        case analyzeFood = "analyze-food"
        case coachChat = "coach-chat"
        case foodSearch = "food-search"
        case verifyPurchase = "verify-purchase"
        case exportData = "export-data"
        case deleteAccount = "delete-account"
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func invoke<Body: Encodable & Sendable, Response: Decodable>(
        _ function: Function,
        body: Body,
        as: Response.Type = Response.self
    ) async throws -> Response {
        do {
            return try await client.functions.invoke(
                function.rawValue,
                options: FunctionInvokeOptions(body: body),
                decoder: Self.decoder
            )
        } catch let FunctionsError.httpError(code, data) {
            throw APIError.from(status: code, body: data)
        } catch {
            throw APIError.from(error)
        }
    }
}
