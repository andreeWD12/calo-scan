import SwiftUI
import Charts
import CaloScanCore

// MARK: - Giorno

struct DayStatsView: View {
    let log: DayLog
    let targets: DailyTargets
    let onAdd: (MealType) -> Void
    let onDelete: (Meal) -> Void
    var plan: ProfessionalPlan? = nil
    var onLogPlanned: ((PlannedMeal) -> Void)? = nil
    var onToggleCheat: ((Meal) -> Void)? = nil
    var onUpdate: ((Meal) -> Void)? = nil
    var onRepeat: ((Meal) -> Void)? = nil

    var body: some View {
        let totals = log.totals
        VStack(spacing: DS.Spacing.m) {
            Card {
                HStack(spacing: DS.Spacing.xs) {
                    StatTile(title: "Calorie", value: Format.kcalNumber(totals.kcal),
                             caption: "su \(Format.kcalNumber(Double(targets.calorieTarget)))")
                    StatTile(title: "Proteine", value: Format.grams(totals.proteinG), tint: DS.Palette.protein)
                    StatTile(title: "Carboidrati", value: Format.grams(totals.carbsG), tint: DS.Palette.carbs)
                    StatTile(title: "Grassi", value: Format.grams(totals.fatG), tint: DS.Palette.fat)
                }
            }
            if totals.kcal > 0 {
                Card {
                    SectionHeader(title: "Distribuzione dei pasti")
                    MealDistributionChart(distribution: DiaryViewModel.mealDistribution([log]))
                }
                .premiumLocked(.plus, title: "Distribuzione dei pasti")
            }
            let cheats = NutritionStats.cheatMeals([log])
            if cheats.count > 0 {
                HStack {
                    CheatBadge()
                    Text("\(cheats.count) oggi · \(Format.kcal(cheats.kcal))")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                    Spacer()
                }
            }
            ForEach(MealType.allCases) { type in
                let planned = plan?.plannedMeal(type, on: log.day)
                MealSectionCard(type: type, meals: log.meals(of: type), onAdd: { onAdd(type) }, onDelete: onDelete,
                                planned: planned,
                                onLogPlanned: planned.flatMap { p in onLogPlanned.map { handler in { handler(p) } } },
                                onToggleCheat: onToggleCheat,
                                plannedWeek: plan.flatMap { $0.rotationWeeks > 1 ? $0.rotationWeek(on: log.day) : nil },
                                onUpdate: onUpdate, onRepeat: onRepeat)
            }
        }
    }
}

/// Barra orizzontale segmentata con la quota di calorie per pasto.
struct MealDistributionChart: View {
    let distribution: [MealShare]

    private func color(_ type: MealType) -> Color {
        switch type {
        case .breakfast: DS.Palette.carbs
        case .lunch: DS.Palette.brand
        case .dinner: DS.Palette.protein
        case .snack: DS.Palette.fat
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Chart(distribution) { item in
                BarMark(x: .value("Quota", item.share), stacking: .normalized)
                    .foregroundStyle(color(item.type))
            }
            .chartXAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 14)
            .clipShape(.capsule)
            HStack(spacing: DS.Spacing.s) {
                ForEach(distribution.filter { $0.share > 0 }) { item in
                    HStack(spacing: 4) {
                        Circle().fill(color(item.type)).frame(width: 6, height: 6)
                        Text("\(item.type.title) \(Format.percent(item.share))")
                    }
                }
            }
            .font(DS.Font.caption)
            .foregroundStyle(DS.Palette.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(distribution.map { "\($0.type.title) \(Format.percent($0.share))" }.joined(separator: ", ")))
    }
}

// MARK: - Settimana

struct WeekStatsView: View {
    let logs: [DayLog]
    let interval: DateInterval
    let targets: DailyTargets

    var body: some View {
        let stats = NutritionStats.summarize(logs, calorieTarget: targets.calorieTarget)
        VStack(spacing: DS.Spacing.m) {
            Card {
                HStack(spacing: DS.Spacing.xs) {
                    StatTile(title: "Media giornaliera", value: Format.kcal(stats.average.kcal))
                    StatTile(title: "Totale settimana", value: Format.kcal(stats.total.kcal))
                }
                HStack(spacing: DS.Spacing.xs) {
                    StatTile(title: "In linea", value: "\(stats.daysOnTarget)", tint: DS.Palette.brand)
                    StatTile(title: "Sopra", value: "\(stats.daysOver)", tint: DS.Palette.warning)
                    StatTile(title: "Sotto", value: "\(stats.daysUnder)", tint: DS.Palette.protein)
                }
                CheatSummaryRow(summary: NutritionStats.cheatMeals(logs))
                Text("Calcolato sui \(stats.loggedDays) giorni registrati, con una tolleranza del ±10% sull'obiettivo.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.textTertiary)
            }
            Card {
                SectionHeader(title: "Calorie per giorno")
                DailyCaloriesChart(logs: logs, target: targets.calorieTarget, unit: .weekday)
                    .frame(height: 180)
            }
            // Andamento dei macronutrienti: Plus e Pro.
            Card {
                SectionHeader(title: "Andamento dei macronutrienti")
                MacroTrendChart(logs: logs).frame(height: 180)
                HStack(spacing: DS.Spacing.xs) {
                    StatTile(title: "Proteine medie", value: Format.grams(stats.average.proteinG), tint: DS.Palette.protein)
                    StatTile(title: "Carboidrati medi", value: Format.grams(stats.average.carbsG), tint: DS.Palette.carbs)
                    StatTile(title: "Grassi medi", value: Format.grams(stats.average.fatG), tint: DS.Palette.fat)
                }
            }
            .premiumLocked(.plus, title: "Andamento dei macronutrienti")
        }
    }
}

struct DailyCaloriesChart: View {
    enum AxisUnit { case weekday, dayOfMonth }
    let logs: [DayLog]
    let target: Int
    let unit: AxisUnit

    var body: some View {
        Chart {
            ForEach(logs, id: \.day) { log in
                BarMark(x: .value("Giorno", log.day, unit: .day),
                        y: .value("kcal", log.totals.kcal))
                    .foregroundStyle(barColor(log.totals.kcal))
                    .cornerRadius(4)
            }
            RuleMark(y: .value("Obiettivo", target))
                .foregroundStyle(DS.Palette.textSecondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Obiettivo").font(.caption2).foregroundStyle(DS.Palette.textSecondary)
                }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: unit == .weekday ? 1 : 7)) { _ in
                AxisValueLabel(format: unit == .weekday ? .dateTime.weekday(.narrow) : .dateTime.day())
                AxisGridLine()
            }
        }
    }

    private func barColor(_ kcal: Double) -> Color {
        let t = Double(target)
        if kcal > t * 1.1 { return DS.Palette.warning }
        if kcal < t * 0.9 { return DS.Palette.brand.opacity(0.5) }
        return DS.Palette.brand
    }
}

struct MacroTrendChart: View {
    let logs: [DayLog]

    var body: some View {
        Chart {
            ForEach(logs.filter { !$0.isEmpty }, id: \.day) { log in
                let t = log.totals
                LineMark(x: .value("Giorno", log.day, unit: .day), y: .value("g", t.proteinG))
                    .foregroundStyle(by: .value("Macro", String(localized: "Proteine")))
                LineMark(x: .value("Giorno", log.day, unit: .day), y: .value("g", t.carbsG))
                    .foregroundStyle(by: .value("Macro", String(localized: "Carboidrati")))
                LineMark(x: .value("Giorno", log.day, unit: .day), y: .value("g", t.fatG))
                    .foregroundStyle(by: .value("Macro", String(localized: "Grassi")))
            }
        }
        .chartForegroundStyleScale([
            String(localized: "Proteine"): DS.Palette.protein,
            String(localized: "Carboidrati"): DS.Palette.carbs,
            String(localized: "Grassi"): DS.Palette.fat,
        ])
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
        }
    }
}

// MARK: - Mese

struct MonthStatsView: View {
    let logs: [DayLog]
    let weights: [WeightEntry]
    let targets: DailyTargets

    var body: some View {
        let stats = NutritionStats.summarize(logs, calorieTarget: targets.calorieTarget)
        let top = DiaryViewModel.topFoods(logs)
        VStack(spacing: DS.Spacing.m) {
            Card {
                SectionHeader(title: "Calorie del mese")
                DailyCaloriesChart(logs: logs, target: targets.calorieTarget, unit: .dayOfMonth)
                    .frame(height: 200)
                HStack(spacing: DS.Spacing.xs) {
                    StatTile(title: "Media giornaliera", value: Format.kcal(stats.average.kcal))
                    StatTile(title: "Giorni registrati", value: "\(stats.loggedDays)")
                }
                CheatSummaryRow(summary: NutritionStats.cheatMeals(logs))
            }
            Card {
                SectionHeader(title: "Costanza")
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.percent(stats.consistency)).font(DS.Font.metric)
                    Text("dei giorni registrati in linea con l'obiettivo")
                        .font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
                }
                ProgressView(value: stats.consistency).tint(DS.Palette.brand)
            }
            Card {
                SectionHeader(title: "Evoluzione del peso")
                if weights.count >= 2 {
                    WeightChart(entries: weights, goal: nil).frame(height: 160)
                } else {
                    Text("Registra il peso almeno due volte nel mese per vedere l'andamento.")
                        .font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
                }
            }
            Card {
                SectionHeader(title: "Abitudini alimentari")
                MealDistributionChart(distribution: DiaryViewModel.mealDistribution(logs))
                if !top.isEmpty {
                    Text("Alimenti più frequenti").font(DS.Font.caption.weight(.semibold))
                        .foregroundStyle(DS.Palette.textSecondary).padding(.top, DS.Spacing.xs)
                    ForEach(top) { food in
                        HStack {
                            Text(food.name).font(DS.Font.callout)
                            Spacer()
                            Text("\(food.count)×").font(DS.Font.callout.monospacedDigit()).foregroundStyle(DS.Palette.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

/// Sgarri del periodo: numero, calorie e quota sul totale. Testo neutro, senza giudizi.
struct CheatSummaryRow: View {
    let summary: CheatMealSummary

    var body: some View {
        if summary.count > 0 {
            HStack(spacing: DS.Spacing.xs) {
                StatTile(title: "Sgarri", value: "\(summary.count)", tint: DS.Palette.fat)
                StatTile(title: "Calorie da sgarri", value: Format.kcal(summary.kcal), tint: DS.Palette.fat)
                StatTile(title: "Sul totale", value: Format.percent(summary.shareOfTotal), tint: DS.Palette.fat)
            }
        }
    }
}
