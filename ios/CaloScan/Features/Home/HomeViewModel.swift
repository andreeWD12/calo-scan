import Foundation
import Observation
import CaloScanCore

@Observable
@MainActor
final class HomeViewModel {
    private(set) var today: Loadable<DayLog> = .idle
    private(set) var insights: [CoachInsight] = []
    /// Giorni consecutivi con almeno un alimento registrato (fino a oggi o ieri).
    private(set) var streak = 0

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    func load() async {
        if today.value == nil { today = .loading }
        do {
            // Una sola richiesta per oggi e gli ultimi 59 giorni: serve anche per la serie.
            let calendar = Calendar.current
            let todayStart = calendar.startOfDay(for: .now)
            let from = calendar.date(byAdding: .day, value: -59, to: todayStart) ?? todayStart
            let logs = try await services.meals.dayLogs(from: from, to: todayStart)
            streak = Self.streak(in: logs, today: todayStart, calendar: calendar)
            today = .loaded(logs.last { calendar.isDate($0.day, inSameDayAs: todayStart) } ?? DayLog(day: todayStart, meals: []))
        } catch {
            today = .failed(APIError.from(error))
        }
        // I consigli sono accessori: un errore qui non blocca la dashboard.
        insights = (try? await services.coach.dailyInsights()) ?? []
    }


    /// Segna o toglie lo sgarro su un pasto già registrato.
    func toggleCheat(_ meal: Meal) async {
        var updated = meal
        updated.isCheatMeal.toggle()
        do {
            try await services.meals.save(updated)
            await load()
        } catch {
            today = .failed(APIError.from(error))
        }
    }

    /// Salva un pasto modificato (grammi, alimento sostituito o tolto). Senza alimenti il pasto viene eliminato.
    func update(_ meal: Meal) async {
        if meal.items.isEmpty { await delete(meal); return }
        do {
            try await services.meals.save(meal)
            await load()
        } catch {
            today = .failed(APIError.from(error))
        }
    }

    /// Registra di nuovo lo stesso pasto adesso (es. la colazione di ieri).
    func repeatNow(_ meal: Meal) async -> Bool {
        do {
            try await services.meals.save(meal.repeated())
            await load()
            return true
        } catch {
            today = .failed(APIError.from(error))
            return false
        }
    }

    func delete(_ meal: Meal) async {
        do {
            try await services.meals.delete(mealID: meal.id)
            await MealPhotoStore.shared.remove(meal.id)
            await load()
        } catch {
            today = .failed(APIError.from(error))
        }
    }

    /// Conta i giorni di fila con pasti registrati. Se oggi è ancora vuoto la serie parte da ieri,
    /// così non si "perde" al mattino prima della colazione.
    static func streak(in logs: [DayLog], today: Date, calendar: Calendar = .current) -> Int {
        let logged = Set(logs.filter { !$0.isEmpty }.map { calendar.startOfDay(for: $0.day) })
        var day = calendar.startOfDay(for: today)
        if !logged.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while logged.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    static func greeting(for date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: String(localized: "Buongiorno")
        case 12..<18: String(localized: "Buon pomeriggio")
        default: String(localized: "Buonasera")
        }
    }
}
