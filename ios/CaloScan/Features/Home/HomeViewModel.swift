import Foundation
import CaloScanCore

@Observable
@MainActor
final class HomeViewModel {
    private(set) var today: Loadable<DayLog> = .idle
    private(set) var insights: [CoachInsight] = []

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    func load() async {
        if today.value == nil { today = .loading }
        do {
            today = .loaded(try await services.meals.dayLog(for: Calendar.current.startOfDay(for: .now)))
        } catch {
            today = .failed(APIError.from(error))
        }
        // I consigli sono accessori: un errore qui non blocca la dashboard.
        insights = (try? await services.coach.dailyInsights()) ?? []
    }

    func delete(_ meal: Meal) async {
        do {
            try await services.meals.delete(mealID: meal.id)
            await load()
        } catch {
            today = .failed(APIError.from(error))
        }
    }

    static func greeting(for date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: String(localized: "Buongiorno")
        case 12..<18: String(localized: "Buon pomeriggio")
        default: String(localized: "Buonasera")
        }
    }
}
