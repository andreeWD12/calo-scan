import Foundation
import CaloScanCore

/// Coach AI (funzione `coach-chat`): conversazione, proposte di stile alimentare.
/// Limiti, consenso, filtri di sicurezza e contesto (profilo, obiettivi, pasti) sono tutti sul server.
struct SupabaseCoachService: CoachService {
    let functions: EdgeFunctionClient

    private struct Body: Encodable, Sendable {
        let action: String
        var text: String? = nil
        var request: EatingStyleRequest? = nil
        let timeZone = TimeZone.current.identifier
    }
    private struct HistoryResponse: Decodable { let messages: [CoachMessage] }
    private struct ProposalsResponse: Decodable { let proposals: [EatingStyleProposal] }

    func history() async throws -> [CoachMessage] {
        let response: HistoryResponse = try await functions.invoke(.coachChat, body: Body(action: "history"))
        return response.messages
    }

    func send(_ text: String) async throws -> CoachMessage {
        try await functions.invoke(.coachChat, body: Body(action: "send", text: text))
    }

    func clearHistory() async throws {
        try await functions.send(.coachChat, body: Body(action: "clear"))
    }

    func proposeEatingStyles(_ request: EatingStyleRequest) async throws -> [EatingStyleProposal] {
        let response: ProposalsResponse = try await functions.invoke(.coachChat, body: Body(action: "eating_styles", request: request))
        return response.proposals
    }
}
