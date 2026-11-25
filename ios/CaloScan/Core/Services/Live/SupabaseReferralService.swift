import CaloScanCore
import DeviceCheck
import Foundation

/// "Invita un amico" (funzione `referral`). Tutte le regole sono sul server; l'app invia solo il codice inserito
/// e, se disponibile, un token DeviceCheck (generato da Apple, non identifica l'utente) contro gli account multipli.
struct SupabaseReferralService: ReferralService {
    let functions: EdgeFunctionClient

    private struct StatusBody: Encodable, Sendable { let action = "status" }
    private struct ApplyBody: Encodable, Sendable {
        let action = "apply"
        let code: String
        let deviceToken: String?
        let environment: String
    }
    private struct ApplyResponse: Decodable { let result: ReferralApplyResult }

    func referralStatus() async throws -> ReferralStatus {
        try await functions.invoke(.referral, body: StatusBody())
    }

    func applyReferral(code: String) async throws -> ReferralApplyResult {
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let response: ApplyResponse = try await functions.invoke(
            .referral, body: ApplyBody(code: code, deviceToken: await Self.deviceToken(), environment: environment))
        return response.result
    }

    private static func deviceToken() async -> String? {
        guard DCDevice.current.isSupported else { return nil }
        return try? await DCDevice.current.generateToken().base64EncodedString()
    }
}
