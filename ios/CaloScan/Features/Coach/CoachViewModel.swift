import Foundation
import Observation
import CaloScanCore

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
    private let meals: any MealRepository

    init(coach: any CoachService, meals: any MealRepository) {
        self.coach = coach
        self.meals = meals
    }

    /// - Parameter chatIncluded: false per Free: la conversazione non viene caricata (la chat è di Plus e Pro).
    func load(chatIncluded: Bool, targets: DailyTargets?, profile: UserProfile?) async {
        await loadInsights(targets: targets, profile: profile)
        guard chatIncluded else { messages = .loaded([]); return }
        if messages.value == nil { messages = .loading }
        do {
            let history = try await coach.history()
            messages = .loaded(history)
        } catch {
            messages = .failed(APIError.from(error))
        }
    }

    /// Consigli del giorno: regole fisse sul diario di oggi e degli ultimi 7 giorni, senza AI.
    func loadInsights(targets: DailyTargets?, profile: UserProfile?, now: Date = .now) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -7, to: today),
              let logs = try? await meals.dayLogs(from: start, to: today) else { return }
        let todayLog = logs.first { calendar.isDate($0.day, inSameDayAs: today) } ?? DayLog(day: today, meals: [])
        let recent = logs.filter { !calendar.isDate($0.day, inSameDayAs: today) }
        insights = DailyTips.make(today: todayLog, recent: recent, targets: targets, diet: profile?.diet,
                                  allergens: profile?.allergens ?? [], now: now, calendar: calendar)
            .map(CoachInsight.init)
    }

    func clear() async {
        do {
            try await coach.clearHistory()
            messages = .loaded([])
        } catch {
            sendError = APIError.from(error)
        }
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

extension CoachInsight {
    /// Id stabile derivato dal testo, così le animazioni non ripartono a ogni ricaricamento.
    init(_ tip: DailyTip) {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, b) in tip.text.utf8.enumerated() { bytes[i % 16] = bytes[i % 16] &* 31 &+ b }
        let tone: Tone = switch tip.tone {
        case .positive: .positive
        case .suggestion: .suggestion
        case .info: .info
        }
        self.init(id: UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                                  bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])),
                  text: tip.text, tone: tone)
    }
}
