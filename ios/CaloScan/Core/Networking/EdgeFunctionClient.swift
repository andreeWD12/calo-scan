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
        case saveProfile = "save-profile"
        case deleteAccount = "delete-account"
    }

    /// Date in ISO 8601 e chiavi come nei modelli Swift (camelCase), le stesse che leggono le funzioni TS.
    /// Il corpo viene codificato qui e non dall'SDK, che userebbe il formato data predefinito di Foundation.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

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
            return try await client.functions.invoke(function.rawValue, options: try options(body), decoder: Self.decoder)
        } catch let FunctionsError.httpError(code, data) {
            throw APIError.from(status: code, body: data)
        } catch {
            throw APIError.from(error)
        }
    }

    /// Per le funzioni che non restituiscono dati (es. 204).
    func send<Body: Encodable & Sendable>(_ function: Function, body: Body) async throws {
        do {
            try await client.functions.invoke(function.rawValue, options: try options(body))
        } catch let FunctionsError.httpError(code, data) {
            throw APIError.from(status: code, body: data)
        } catch {
            throw APIError.from(error)
        }
    }

    private func options<Body: Encodable>(_ body: Body) throws -> FunctionInvokeOptions {
        FunctionInvokeOptions(headers: ["Content-Type": "application/json"], body: try Self.encoder.encode(body))
    }
}
