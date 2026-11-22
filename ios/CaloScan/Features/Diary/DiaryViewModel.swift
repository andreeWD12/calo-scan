import Foundation
import CaloScanCore

@Observable
@MainActor
final class DiaryViewModel {
    enum Mode: String, CaseIterable, Identifiable {
        case day, week, month
        var id: String { rawValue }
        var title: String {
            switch self {
            case .day: String(localized: "Giorno")
            case .week: String(localized: "Settimana")
            case .month: String(localized: "Mese")
            }
        }
    }

    var mode: Mode = .day
    var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    private(set) var day: Loadable<DayLog> = .idle
    private(set) var period: Loadable<[DayLog]> = .idle
    private(set) var weights: [WeightEntry] = []
    /// Giorni con almeno un pasto nel mese mostrato dal calendario.
    private(set) var loggedDays: Set<Date> = []

    private let services: AppServices
    private var calendar: Calendar { .current }

    init(services: AppServices) {
        self.services = services
    }

    // MARK: Intervalli

    var interval: DateInterval {
        let component: Calendar.Component = mode == .week ? .weekOfYear : .month
        return calendar.dateInterval(of: mode == .day ? .day : component, for: selectedDate)
            ?? DateInterval(start: selectedDate, duration: 86_400)
    }

    var periodTitle: String {
        switch mode {
        case .day: return Format.dayTitle(selectedDate)
        case .week:
            let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(interval.start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year()).capitalized
        }
    }

    var canGoForward: Bool { mode == .day ? !calendar.isDateInToday(selectedDate) : interval.end <= .now }

    func shift(by value: Int) {
        let component: Calendar.Component = switch mode {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
        guard let date = calendar.date(byAdding: component, value: value, to: selectedDate) else { return }
        selectedDate = min(calendar.startOfDay(for: date), calendar.startOfDay(for: .now))
    }

    // MARK: Caricamento

    func load() async {
        switch mode {
        case .day: await loadDay()
        case .week, .month: await loadPeriod()
        }
    }

    private func loadDay() async {
        day = .loading
        do { day = .loaded(try await services.meals.dayLog(for: selectedDate)) }
        catch { day = .failed(APIError.from(error)) }
    }

    private func loadPeriod() async {
        period = .loading
        do {
            let end = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
            let logs = try await services.meals.dayLogs(from: interval.start, to: end)
            period = .loaded(logs)
            if mode == .month {
                weights = ((try? await services.weight.entries()) ?? []).filter { interval.contains($0.date) }
            }
        } catch {
            period = .failed(APIError.from(error))
        }
    }

    func loadCalendar(month: Date) async {
        guard let range = calendar.dateInterval(of: .month, for: month) else { return }
        let logs = (try? await services.meals.dayLogs(from: range.start, to: range.end.addingTimeInterval(-1))) ?? []
        loggedDays = Set(logs.filter { !$0.isEmpty }.map { calendar.startOfDay(for: $0.day) })
    }


    /// Segna o toglie lo sgarro su un pasto già registrato.
    func toggleCheat(_ meal: Meal) async {
        var updated = meal
        updated.isCheatMeal.toggle()
        do {
            try await services.meals.save(updated)
            await load()
        } catch {
            day = .failed(APIError.from(error))
        }
    }

    func delete(_ meal: Meal) async {
        do {
            try await services.meals.delete(mealID: meal.id)
            await load()
        } catch {
            day = .failed(APIError.from(error))
        }
    }

    // MARK: Analisi

    /// Ripartizione delle calorie tra i pasti nel periodo (0…1 per tipo).
    static func mealDistribution(_ logs: [DayLog]) -> [MealShare] {
        let total = logs.map(\.totals.kcal).reduce(0, +)
        guard total > 0 else { return [] }
        return MealType.allCases.map { type in
            MealShare(type: type, share: logs.map { $0.totals(of: type).kcal }.reduce(0, +) / total)
        }
    }

    /// Alimenti registrati più spesso nel periodo.
    static func topFoods(_ logs: [DayLog], limit: Int = 5) -> [FoodFrequency] {
        var counts: [String: Int] = [:]
        for log in logs { for meal in log.meals { for item in meal.items { counts[item.food.name, default: 0] += 1 } } }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit).map { FoodFrequency(name: $0.key, count: $0.value) }
    }
}

struct MealShare: Identifiable, Hashable {
    let type: MealType
    let share: Double
    var id: MealType { type }
}

struct FoodFrequency: Identifiable, Hashable {
    let name: String
    let count: Int
    var id: String { name }
}
