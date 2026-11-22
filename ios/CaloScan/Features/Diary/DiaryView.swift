import SwiftUI
import CaloScanCore

/// Diario: vista giornaliera, settimanale e mensile, con calendario.
struct DiaryView: View {
    @Environment(AppState.self) private var app
    @State private var model: DiaryViewModel
    @State private var showCalendar = false
    @State private var addingTo: MealType?

    init(services: AppServices) {
        _model = State(initialValue: DiaryViewModel(services: services))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.m) {
                    Picker("Vista", selection: $model.mode.animation(DS.Motion.snappy)) {
                        ForEach(DiaryViewModel.Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    periodNavigator
                    content
                        .id("\(model.mode.rawValue)-\(model.selectedDate.timeIntervalSince1970)")
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.bottom, DS.Spacing.xl)
            }
            .background(DS.Palette.background.ignoresSafeArea())
            .navigationTitle("Diario")
            .refreshable { await model.load() }
            .animation(DS.Motion.standard, value: model.mode)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCalendar = true } label: { Image(systemName: "calendar") }
                        .accessibilityLabel(Text("Apri calendario"))
                }
            }
            .sheet(isPresented: $showCalendar) {
                CalendarSheet(model: model) { date in
                    model.selectedDate = date
                    model.mode = .day
                    showCalendar = false
                }
            }
            .sheet(item: $addingTo) { type in
                AddFoodFlowView(services: app.services, mealType: type, day: model.selectedDate) {
                    app.mealSaved(type)
                }
            }
        }
        .task(id: "\(model.mode.rawValue)-\(model.selectedDate.timeIntervalSince1970)-\(app.diaryRevision)") {
            await model.load()
        }
    }

    private var periodNavigator: some View {
        HStack {
            Button { withAnimation(DS.Motion.snappy) { model.shift(by: -1) } } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel(Text("Periodo precedente"))
            Spacer()
            Text(model.periodTitle).font(DS.Font.headline).contentTransition(.numericText())
            Spacer()
            Button { withAnimation(DS.Motion.snappy) { model.shift(by: 1) } } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(!model.canGoForward)
                .accessibilityLabel(Text("Periodo successivo"))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let targets = app.targets {
            switch model.mode {
            case .day:
                switch model.day {
                case .idle, .loading: LoadingStateView()
                case .empty: EmptyView()
                case .failed(let e): ErrorStateView(error: e) { Task { await model.load() } }
                case .loaded(let log):
                    DayStatsView(log: log, targets: targets,
                                 onAdd: { addingTo = $0 },
                                 onDelete: { meal in Task { await model.delete(meal) } })
                }
            case .week, .month:
                switch model.period {
                case .idle, .loading: LoadingStateView()
                case .empty: EmptyView()
                case .failed(let e): ErrorStateView(error: e) { Task { await model.load() } }
                case .loaded(let logs):
                    if logs.allSatisfy(\.isEmpty) {
                        EmptyStateView(title: "Nessun pasto registrato",
                                       message: "Quando registri i pasti qui vedrai medie, andamento e progressi.",
                                       systemImage: "chart.bar")
                    } else if model.mode == .week {
                        WeekStatsView(logs: logs, interval: model.interval, targets: targets,
                                      isAdvanced: app.entitlements.plan >= .plus)
                    } else if app.entitlements.plan >= .plus {
                        MonthStatsView(logs: logs, weights: model.weights, targets: targets)
                    } else {
                        UpgradeCard(title: "Statistiche mensili complete",
                                    message: "Grafico delle calorie, evoluzione del peso, costanza e analisi delle abitudini sono inclusi in Plus e Pro.")
                    }
                }
            }
        } else {
            LoadingStateView()
        }
    }
}

/// Invito all'upgrade per funzioni dei piani a pagamento. Il server applica comunque gli stessi limiti.
struct UpgradeCard: View {
    @Environment(AppState.self) private var app
    @State private var showPaywall = false
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var plan: Plan = .plus

    var body: some View {
        Card {
            HStack { PlanBadge(plan: plan); Spacer() }
            Text(title).font(DS.Font.headline)
            Text(message).font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
            Button("Scopri i piani") { showPaywall = true }.buttonStyle(.primary)
        }
        .sheet(isPresented: $showPaywall) { PaywallView(services: app.services, highlight: plan) }
    }
}

// MARK: - Calendario

private struct CalendarSheet: View {
    let model: DiaryViewModel
    let onSelect: (Date) -> Void
    @State private var month = Calendar.current.startOfDay(for: .now)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.m) {
                MonthCalendarView(month: $month, selected: model.selectedDate,
                                  marked: model.loggedDays, onSelect: onSelect)
                HStack(spacing: DS.Spacing.xs) {
                    Circle().fill(DS.Palette.brand).frame(width: 6, height: 6)
                    Text("Giorni con pasti registrati").font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                }
                Spacer()
            }
            .padding(DS.Spacing.screen)
            .navigationTitle("Calendario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
            .task(id: month) { await model.loadCalendar(month: month) }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Calendario mensile con indicatori dei giorni registrati.
struct MonthCalendarView: View {
    @Binding var month: Date
    let selected: Date
    let marked: Set<Date>
    let onSelect: (Date) -> Void

    private var calendar: Calendar { .current }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var days: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading)
            + (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            HStack {
                Button { change(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel(Text("Mese precedente"))
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()).capitalized).font(DS.Font.headline)
                Spacer()
                Button { change(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
                    .accessibilityLabel(Text("Mese successivo"))
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.textTertiary)
                        .accessibilityHidden(true)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date { dayCell(date) } else { Color.clear.frame(height: 40) }
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selected)
        let isFuture = date > .now
        let isMarked = marked.contains(calendar.startOfDay(for: date))
        return Button { onSelect(date) } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(DS.Font.callout.monospacedDigit())
                    .fontWeight(calendar.isDateInToday(date) ? .bold : .regular)
                Circle().fill(isMarked ? (isSelected ? DS.Palette.onBrand : DS.Palette.brand) : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(isSelected ? DS.Palette.onBrand : (isFuture ? DS.Palette.textTertiary : DS.Palette.textPrimary))
            .background(isSelected ? DS.Palette.brand : .clear, in: .rect(cornerRadius: DS.Radius.s))
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(Text(date.formatted(date: .complete, time: .omitted)))
        .accessibilityValue(Text(isMarked ? "Pasti registrati" : "Nessun pasto"))
    }

    private func change(_ value: Int) {
        if let d = calendar.date(byAdding: .month, value: value, to: month) { month = d }
    }
}
