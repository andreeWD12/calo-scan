import Foundation
import Observation

@Observable
@MainActor
final class CoachViewModel {
    private(set) var messages: Loadable<[CoachMessage]> = .idle
    private(set) var insights: [CoachInsight] = []
    private(set) var isSending = false
    var draft = ""
    var sendError: APIError?

    static let maxLength = 1000

    /// Domande suggerite per chi apre il coach la prima volta.
    static let suggestions: [String] = [
        String(localized: "Quante calorie mi rimangono oggi?"),
        String(localized: "Cosa posso mangiare stasera?"),
        String(localized: "Come posso aumentare le proteine?"),
        String(localized: "Come posso rendere più equilibrata la mia alimentazione?"),
        String(localized: "Quali alimenti sono più adatti ai miei obiettivi?"),
    ]

    private let coach: any CoachService

    init(coach: any CoachService) {
        self.coach = coach
    }

    func load() async {
        if messages.value == nil { messages = .loading }
        do {
            let history = try await coach.history()
            messages = .loaded(history)
        } catch {
            messages = .failed(APIError.from(error))
        }
        insights = (try? await coach.dailyInsights()) ?? []
    }

    var canSend: Bool {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t.count <= Self.maxLength && !isSending
    }

    func send(_ text: String? = nil) async {
        let content = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, content.count <= Self.maxLength, !isSending else { return }
        let pending = CoachMessage(id: UUID(), role: .user, text: content, createdAt: .now)
        var list = messages.value ?? []
        list.append(pending)
        messages = .loaded(list)
        draft = ""
        isSending = true
        defer { isSending = false }
        do {
            let reply = try await coach.send(content)
            list.append(reply)
            messages = .loaded(list)
        } catch {
            // Il messaggio non inviato torna nella casella di testo per poterlo riprovare.
            list.removeAll { $0.id == pending.id }
            messages = .loaded(list)
            draft = content
            sendError = APIError.from(error)
        }
    }
}
