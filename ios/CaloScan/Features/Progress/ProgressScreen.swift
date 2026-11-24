import SwiftUI
import Charts
import CaloScanCore

/// Monitoraggio del peso e delle misure corporee.
struct ProgressScreen: View {
    @Environment(AppState.self) private var app
    @State private var model: ProgressViewModel
    @State private var showAddWeight = false
    @State private var showAddMeasurement = false

    init(services: AppServices) {
        _model = State(initialValue: ProgressViewModel(weight: services.weight))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.m) { content }
                    .padding(.horizontal, DS.Spacing.screen)
                    .padding(.bottom, DS.Spacing.xl)
            }
            .background { AppBackground() }
            .navigationTitle("Progressi")
            .refreshable { await model.load() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddWeight = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text("Registra il peso"))
                }
            }
            .sheet(isPresented: $showAddWeight) {
                AddWeightSheet(initial: model.entries.value?.last?.weightKg ?? app.profile?.weightKg) { kg, date in
                    let saved = await model.add(weightKg: kg, date: date)
                    if saved {
                        app.toasts.success(String(localized: "Peso registrato"), subtitle: Format.kg(kg), symbol: "scalemass.fill")
                        app.weightSaved(entries: model.entries.value ?? [])
                    }
                    return saved
                }
            }
            .sheet(isPresented: $showAddMeasurement) {
                AddMeasurementSheet { measurement in
                    let saved = await model.add(measurement)
                    if saved { app.toasts.success(String(localized: "Misure salvate"), symbol: "ruler.fill") }
                    return saved
                }
            }
            .alert("Operazione non riuscita",
                   isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } }),
                   presenting: model.error) { _ in Button("OK", role: .cancel) {} } message: { Text($0.localizedDescription) }
        }
        .task { await model.load() }
        .onChange(of: app.router.pending, initial: true) { _, link in
            if link == .logWeight { showAddWeight = true; app.router.pending = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.entries {
        case .idle, .loading:
            LoadingStateView()
        case .failed(let error):
            ErrorStateView(error: error) { Task { await model.load() } }
        case .empty:
            EmptyStateView(title: "Nessun peso registrato", message: "Registra il tuo peso per seguire i progressi nel tempo.",
                           systemImage: "scalemass", actionTitle: "Registra il peso") { showAddWeight = true }
        case .loaded(let entries):
            if let progress = WeightProgress(entries: entries, goal: app.profile?.targetWeightKg) {
                SummaryGrid(progress: progress)
            }
            Card {
                Picker("Periodo", selection: $model.range.animation(DS.Motion.standard)) {
                    ForEach(ProgressViewModel.Range.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if model.range == .all && app.entitlements.plan < .plus {
                    // Storico completo del peso: Plus e Pro.
                    WeightChart(entries: model.visibleEntries, goal: app.profile?.targetWeightKg)
                        .frame(height: 220)
                        .premiumLocked(.plus, title: "Andamento del peso dall'inizio", cornerRadius: DS.Radius.m)
                } else if model.visibleEntries.count >= 2 {
                    WeightChart(entries: model.visibleEntries, goal: app.profile?.targetWeightKg)
                        .frame(height: 220)
                } else {
                    Text("Servono almeno due registrazioni in questo periodo per mostrare il grafico.")
                        .font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            MeasurementsCard(measurements: model.measurements, onAdd: { showAddMeasurement = true },
                             onDelete: { m in Task { await model.delete(m) } })
                .premiumLocked(.plus, title: "Misure corporee")
            HistoryCard(entries: entries.reversed(), goal: app.profile?.targetWeightKg) { entry in Task { await model.delete(entry) } }
        }
    }
}

private struct SummaryGrid: View {
    let progress: WeightProgress

    var body: some View {
        Card {
            HStack(spacing: DS.Spacing.xs) {
                StatTile(title: "Iniziale", value: Format.kg(progress.start))
                StatTile(title: "Attuale", value: Format.kg(progress.current), tint: DS.Palette.brand)
                StatTile(title: "Obiettivo", value: progress.goal.map(Format.kg) ?? "—")
            }
            HStack {
                Text("Differenza dall'inizio").font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
                Spacer()
                Text(Format.signedKg(progress.change)).font(DS.Font.headline.monospacedDigit())
            }
            if let fraction = progress.fractionToGoal {
                ProgressView(value: fraction) {
                    Text("Verso l'obiettivo: \(Format.percent(fraction))").font(DS.Font.caption)
                }
                .tint(DS.Palette.brand)
            }
        }
    }
}

struct WeightChart: View {
    let entries: [WeightEntry]
    let goal: Double?

    private var yDomain: ClosedRange<Double> {
        let values = entries.map(\.weightKg) + (goal.map { [$0] } ?? [])
        let lo = (values.min() ?? 0) - 1, hi = (values.max() ?? 1) + 1
        return lo...hi
    }

    var body: some View {
        Chart {
            ForEach(entries) { e in
                AreaMark(x: .value("Data", e.date), yStart: .value("Min", yDomain.lowerBound), yEnd: .value("kg", e.weightKg))
                    .foregroundStyle(LinearGradient(colors: [DS.Palette.brand.opacity(0.25), .clear],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Data", e.date), y: .value("kg", e.weightKg))
                    .foregroundStyle(DS.Palette.brand)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                PointMark(x: .value("Data", e.date), y: .value("kg", e.weightKg))
                    .foregroundStyle(DS.Palette.brand)
                    .symbolSize(24)
            }
            if let goal {
                RuleMark(y: .value("Obiettivo", goal))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYScale(domain: yDomain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Grafico del peso"))
        .accessibilityValue(Text(entries.last.map { "Ultimo valore \(Format.kg($0.weightKg))" } ?? ""))
    }
}

private struct MeasurementsCard: View {
    let measurements: [BodyMeasurement]
    let onAdd: () -> Void
    let onDelete: (BodyMeasurement) -> Void

    var body: some View {
        let changes = BodyMeasurement.changes(in: measurements)
        Card {
            SectionHeader(title: "Misure corporee", trailing: AnyView(
                Button("Aggiungi", action: onAdd).font(DS.Font.callout.weight(.semibold))))
            if let latest = measurements.first {
                Text("Ultima rilevazione: \(latest.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.xs) {
                    ForEach(BodyMeasurement.Kind.allCases, id: \.self) { kind in
                        if let value = latestValue(kind) {
                            StatTile(title: kind.title, value: Self.cm(value), caption: changes[kind].map(Self.change))
                        }
                    }
                }
                if let oldest = measurements.last, measurements.count > 1 {
                    Text("Variazioni rispetto al \(oldest.date.formatted(date: .abbreviated, time: .omitted)).")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.textTertiary)
                }
                Divider()
                ForEach(measurements.prefix(10)) { m in
                    HStack(alignment: .firstTextBaseline) {
                        Text(m.date.formatted(date: .abbreviated, time: .omitted)).font(DS.Font.callout)
                        Spacer()
                        Text(BodyMeasurement.Kind.allCases.compactMap { kind in
                            m.value(kind).map { "\(kind.short) \(Self.number($0))" }
                        }.joined(separator: " · "))
                        .font(DS.Font.caption.monospacedDigit()).foregroundStyle(DS.Palette.textSecondary)
                        .multilineTextAlignment(.trailing)
                    }
                    .frame(minHeight: 32)
                    .contextMenu {
                        Button("Elimina", systemImage: "trash", role: .destructive) { onDelete(m) }
                    }
                }
                Text("Tieni premuta una rilevazione per eliminarla.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.textTertiary)
            } else {
                Text("Facoltative: vita, fianchi, petto, braccio e coscia aiutano a vedere i cambiamenti che la bilancia non mostra.")
                    .font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
            }
        }
    }

    /// Valore più recente di una misura, anche se l'ultima rilevazione non la contiene.
    private func latestValue(_ kind: BodyMeasurement.Kind) -> Double? {
        measurements.lazy.compactMap { $0.value(kind) }.first
    }

    private static func number(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }
    private static func cm(_ v: Double) -> String { "\(number(v)) cm" }
    private static func change(_ v: Double) -> String {
        v == 0 ? String(localized: "invariata") : "\(v > 0 ? "+" : "−")\(number(abs(v))) cm"
    }
}

extension BodyMeasurement.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .waist: "Vita"
        case .hips: "Fianchi"
        case .chest: "Petto"
        case .arm: "Braccio"
        case .thigh: "Coscia"
        }
    }

    /// Abbreviazione per lo storico.
    var short: String {
        switch self {
        case .waist: String(localized: "Vita")
        case .hips: String(localized: "Fianchi")
        case .chest: String(localized: "Petto")
        case .arm: String(localized: "Braccio")
        case .thigh: String(localized: "Coscia")
        }
    }
}

/// Storico del peso raggruppato per mese: per ogni mese la variazione, per ogni pesata la data in un
/// riquadro, il peso, una barra che mostra dove si colloca tra il minimo e il massimo e la differenza
/// dalla pesata precedente. Colori neutri: verde quando ci si avvicina all'obiettivo, mai rosso.
private struct HistoryCard: View {
    /// Dal più recente al più vecchio.
    let entries: [WeightEntry]
    let goal: Double?
    let onDelete: (WeightEntry) -> Void
    @State private var showAll = false

    private struct Month: Identifiable {
        let id: Date
        let entries: [(entry: WeightEntry, delta: Double?)]
        var change: Double? {
            guard let newest = entries.first?.entry.weightKg, let oldest = entries.last?.entry.weightKg, entries.count >= 2 else { return nil }
            return newest - oldest
        }
    }

    private var months: [Month] {
        let calendar = Calendar.current
        let shown = Array(entries.prefix(showAll ? 200 : 20))
        var rows: [(WeightEntry, Double?)] = []
        for (i, e) in shown.enumerated() {
            let previous = i + 1 < entries.count ? entries[i + 1].weightKg : nil
            rows.append((e, previous.map { e.weightKg - $0 }))
        }
        let groups = Dictionary(grouping: rows) { calendar.dateInterval(of: .month, for: $0.0.date)?.start ?? $0.0.date }
        return groups.keys.sorted(by: >).map { key in
            Month(id: key, entries: groups[key]!.sorted { $0.0.date > $1.0.date }.map { (entry: $0.0, delta: $0.1) })
        }
    }

    private var range: ClosedRange<Double> {
        let values = entries.prefix(showAll ? 200 : 20).map(\.weightKg)
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        return lo...max(hi, lo + 0.1)
    }

    var body: some View {
        Card {
            SectionHeader(title: "Storico")
            ForEach(months) { month in
                HStack {
                    Text(month.id.formatted(.dateTime.month(.wide).year()).capitalized)
                        .font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.textSecondary)
                    Spacer()
                    if let change = month.change {
                        DeltaChip(delta: change, goal: goal, current: month.entries.first?.entry.weightKg, label: String(localized: "nel mese"))
                    }
                }
                .padding(.top, DS.Spacing.xs)
                ForEach(month.entries, id: \.entry.id) { row in
                    WeightRow(entry: row.entry, delta: row.delta, range: range, goal: goal)
                        .contextMenu {
                            Button("Elimina", systemImage: "trash", role: .destructive) { onDelete(row.entry) }
                        }
                }
            }
            if entries.count > 20 {
                Button(showAll ? "Mostra meno" : "Mostra tutte le \(entries.count) pesate") {
                    withAnimation(DS.Motion.standard) { showAll.toggle() }
                }
                .font(DS.Font.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Spacing.xs)
            }
        }
    }
}

private struct WeightRow: View {
    let entry: WeightEntry
    let delta: Double?
    let range: ClosedRange<Double>
    let goal: Double?

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            VStack(spacing: 0) {
                Text(entry.date.formatted(.dateTime.day())).font(DS.Font.headline.monospacedDigit())
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).textCase(.uppercase)
            }
            .foregroundStyle(DS.Palette.brand)
            .frame(width: 44, height: 44)
            .background(DS.Palette.brandSoft, in: .rect(cornerRadius: DS.Radius.s))

            VStack(alignment: .leading, spacing: 6) {
                Text(Format.kg(entry.weightKg)).font(DS.Font.headline.monospacedDigit())
                    .foregroundStyle(DS.Palette.textPrimary)
                GeometryReader { geo in
                    let fraction = (entry.weightKg - range.lowerBound) / (range.upperBound - range.lowerBound)
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.Palette.surfaceMuted)
                        Capsule().fill(LinearGradient(colors: [DS.Palette.brand.opacity(0.35), DS.Palette.brand],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(geo.size.width * (0.15 + 0.85 * fraction), 8))
                    }
                }
                .frame(height: 6)
            }
            Spacer(minLength: 0)
            if let delta {
                DeltaChip(delta: delta, goal: goal, current: entry.weightKg, label: nil)
            }
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

/// Differenza di peso con freccia. Verde se va verso l'obiettivo, grigio altrimenti (mai rosso).
private struct DeltaChip: View {
    let delta: Double
    let goal: Double?
    let current: Double?
    let label: String?

    private var towardGoal: Bool {
        guard let goal, let current else { return false }
        let previous = current - delta
        return abs(goal - current) < abs(goal - previous)
    }

    var body: some View {
        let steady = abs(delta) < 0.05
        let symbol = steady ? "equal" : (delta < 0 ? "arrow.down.right" : "arrow.up.right")
        let tint = towardGoal ? DS.Palette.brand : DS.Palette.textSecondary
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.caption2.weight(.bold))
            Text(steady ? String(localized: "stabile") : Format.signedKg(delta)).font(DS.Font.caption.weight(.semibold).monospacedDigit())
            if let label { Text(label).font(DS.Font.caption) }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

private struct AddWeightSheet: View {
    @State private var weight: Double?
    @State private var date = Date.now
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss
    let save: (Double, Date) async -> Bool

    init(initial: Double?, save: @escaping (Double, Date) async -> Bool) {
        _weight = State(initialValue: initial)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                NumericField(label: "Peso", value: $weight, unit: "kg")
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                DatePicker("Data", selection: $date, in: ...Date.now, displayedComponents: .date)
            }
            .navigationTitle("Registra il peso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        guard let weight else { return }
                        Task {
                            isSaving = true
                            if await save(weight, date) { dismiss() }
                            isSaving = false
                        }
                    }
                    .disabled(weight == nil || isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct AddMeasurementSheet: View {
    @State private var draft = BodyMeasurement(date: .now)
    @Environment(\.dismiss) private var dismiss
    let save: (BodyMeasurement) async -> Bool

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Data", selection: $draft.date, in: ...Date.now, displayedComponents: .date)
                Section {
                    ForEach(BodyMeasurement.Kind.allCases, id: \.self) { kind in
                        NumericField(label: kind.title, value: $draft[dynamicMember: kind.keyPath], unit: "cm",
                                     error: draft.invalidKinds.contains(kind)
                                        ? String(localized: "Valore tra \(Int(kind.range.lowerBound)) e \(Int(kind.range.upperBound)) cm.")
                                        : nil)
                    }
                } footer: {
                    Text("Compila solo le misure che vuoi monitorare.")
                }
            }
            .navigationTitle("Misure corporee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { Task { if await save(draft) { dismiss() } } }
                        .disabled(draft.isEmpty || !draft.invalidKinds.isEmpty)
                }
            }
        }
    }
}
