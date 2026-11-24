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
            HistoryCard(entries: entries.reversed()) { entry in Task { await model.delete(entry) } }
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

private struct HistoryCard: View {
    let entries: [WeightEntry]
    let onDelete: (WeightEntry) -> Void

    var body: some View {
        Card {
            SectionHeader(title: "Storico")
            ForEach(entries.prefix(30)) { entry in
                HStack {
                    Text(entry.date.formatted(date: .abbreviated, time: .omitted)).font(DS.Font.callout)
                    Spacer()
                    Text(Format.kg(entry.weightKg)).font(DS.Font.callout.monospacedDigit())
                }
                .frame(minHeight: 32)
                .contextMenu {
                    Button("Elimina", systemImage: "trash", role: .destructive) { onDelete(entry) }
                }
            }
        }
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
