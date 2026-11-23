import Foundation
import Observation
import CaloScanCore

@Observable
@MainActor
final class ProgressViewModel {
    enum Range: String, CaseIterable, Identifiable {
        case week, month, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .week: String(localized: "Settimana")
            case .month: String(localized: "Mese")
            case .all: String(localized: "Tutto")
            }
        }
    }

    private(set) var entries: Loadable<[WeightEntry]> = .idle
    private(set) var measurements: [BodyMeasurement] = []
    var range: Range = .month
    var error: APIError?

    private let weight: any WeightRepository

    init(weight: any WeightRepository) {
        self.weight = weight
    }

    func load() async {
        if entries.value == nil { entries = .loading }
        do {
            let list = try await weight.entries().sorted { $0.date < $1.date }
            entries = list.isEmpty ? .empty : .loaded(list)
        } catch {
            entries = .failed(APIError.from(error))
        }
        // Le misure sono separate: se non si caricano, il peso resta visibile.
        if let list = try? await weight.measurements() {
            measurements = list.sorted { $0.date > $1.date }
        }
    }

    var visibleEntries: [WeightEntry] {
        let all = entries.value ?? []
        let days: Int? = switch range {
        case .week: 7
        case .month: 31
        case .all: nil
        }
        guard let days, let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return all }
        return all.filter { $0.date >= start }
    }

    func add(weightKg: Double, date: Date) async -> Bool {
        guard BodyMetrics.weightRange.contains(weightKg) else {
            error = .invalidInput(String(localized: "Inserisci un peso tra 30 e 350 kg."))
            return false
        }
        do {
            try await weight.add(WeightEntry(date: date, weightKg: weightKg))
            await load()
            return true
        } catch {
            self.error = APIError.from(error)
            return false
        }
    }

    func delete(_ entry: WeightEntry) async {
        do { try await weight.delete(entryID: entry.id); await load() }
        catch { self.error = APIError.from(error) }
    }

    func delete(_ measurement: BodyMeasurement) async {
        do { try await weight.delete(measurementID: measurement.id); await load() }
        catch { self.error = APIError.from(error) }
    }

    func add(_ measurement: BodyMeasurement) async -> Bool {
        guard !measurement.isEmpty else { return false }
        guard measurement.invalidKinds.isEmpty else {
            error = .invalidInput(String(localized: "Controlla le misure: alcuni valori non sono plausibili."))
            return false
        }
        do {
            try await weight.add(measurement)
            await load()
            return true
        } catch {
            self.error = APIError.from(error)
            return false
        }
    }
}
