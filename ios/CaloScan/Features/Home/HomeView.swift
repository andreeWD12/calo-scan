import SwiftUI
import CaloScanCore

enum HomeRoute: Hashable { case coach }

/// Dashboard: calorie e macro di oggi, pulsante di scansione, consigli, pasti del giorno.
struct HomeView: View {
    @Environment(AppState.self) private var app
    @State private var model: HomeViewModel
    @State private var addingTo: MealType?
    @State private var path: [HomeRoute] = []
    let onScan: () -> Void

    init(services: AppServices, onScan: @escaping () -> Void) {
        _model = State(initialValue: HomeViewModel(services: services))
        self.onScan = onScan
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.m) {
                    header
                    content
                }
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.bottom, DS.Spacing.xl)
            }
            .background(DS.Palette.background.ignoresSafeArea())
            .refreshable { await model.load() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(.coach) } label: { Image(systemName: "sparkles") }
                        .accessibilityLabel(Text("Apri AI Nutrition Coach"))
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .coach: CoachView(services: app.services)
                }
            }
            .sheet(item: $addingTo) { type in
                AddFoodFlowView(services: app.services, mealType: type) {
                    app.diaryDidChange()
                }
            }
        }
        .task(id: app.diaryRevision) { await model.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                .font(DS.Font.caption.weight(.semibold))
                .foregroundStyle(DS.Palette.textSecondary)
            Text("\(HomeViewModel.greeting()), \(app.profile?.displayName ?? "")")
                .font(DS.Font.title)
                .foregroundStyle(DS.Palette.textPrimary)
        }
        .padding(.top, DS.Spacing.xs)
    }

    @ViewBuilder
    private var content: some View {
        switch model.today {
        case .idle, .loading:
            LoadingStateView()
        case .failed(let error):
            ErrorStateView(error: error) { Task { await model.load() } }
        case .empty:
            EmptyView()
        case .loaded(let day):
            if let targets = app.targets {
                SummaryCard(day: day, targets: targets)
            }
            ScanCallToAction(scansRemaining: app.entitlements.scansRemaining, action: onScan)
            if let insight = model.insights.first {
                InsightCard(insight: insight) { path.append(.coach) }
            }
            ForEach(MealType.allCases, id: \.self) { type in
                MealSectionCard(type: type, meals: day.meals(of: type),
                                onAdd: { addingTo = type },
                                onDelete: { meal in Task { await model.delete(meal) } })
            }
        }
    }
}

private struct SummaryCard: View {
    let day: DayLog
    let targets: DailyTargets

    var body: some View {
        let totals = day.totals
        let progress = NutritionStats.progress(consumed: totals.kcal, target: targets.calorieTarget)
        Card {
            HStack(spacing: DS.Spacing.l) {
                CalorieRing(consumed: totals.kcal, target: targets.calorieTarget)
                    .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    metric("Obiettivo", Format.kcal(Double(targets.calorieTarget)))
                    metric("Consumate", Format.kcal(totals.kcal))
                    metric("Raggiunto", Format.percent(progress))
                }
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: DS.Spacing.s) {
                MacroBar(title: "Proteine", consumed: totals.proteinG, target: targets.proteinG, tint: DS.Palette.protein)
                MacroBar(title: "Carboidrati", consumed: totals.carbsG, target: targets.carbsG, tint: DS.Palette.carbs)
                MacroBar(title: "Grassi", consumed: totals.fatG, target: targets.fatG, tint: DS.Palette.fat)
            }
            .padding(.top, DS.Spacing.xs)
        }
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
            Text(value).font(DS.Font.headline.monospacedDigit()).contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }
}

/// Il fulcro dell'app: pulsante grande per scansionare un piatto.
private struct ScanCallToAction: View {
    let scansRemaining: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.m) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("SCANSIONA IL TUO PIATTO").font(DS.Font.headline).tracking(0.3)
                    Text(scansRemaining > 0 ? LocalizedStringKey("\(scansRemaining) scansioni disponibili oggi") : LocalizedStringKey("Scansioni di oggi esaurite"))
                        .font(DS.Font.caption)
                        .opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.headline)
            }
            .foregroundStyle(DS.Palette.onBrand)
            .padding(DS.Spacing.m)
            .frame(minHeight: 76)
            .background(
                LinearGradient(colors: [DS.Palette.brand, DS.Palette.brand.opacity(0.85)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: DS.Radius.l))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Apre la fotocamera per analizzare un piatto"))
    }
}

private struct InsightCard: View {
    let insight: CoachInsight
    let openCoach: () -> Void

    var body: some View {
        Button(action: openCoach) {
            HStack(alignment: .top, spacing: DS.Spacing.s) {
                Image(systemName: "sparkles").foregroundStyle(DS.Palette.brand).font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Il consiglio del coach AI").font(DS.Font.caption.weight(.semibold))
                        .foregroundStyle(DS.Palette.textSecondary)
                    Text(insight.text).font(DS.Font.callout).foregroundStyle(DS.Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Spacing.m)
            .background(DS.Palette.brandSoft, in: .rect(cornerRadius: DS.Radius.l))
        }
        .buttonStyle(.plain)
    }
}

/// Sezione di un pasto con alimenti, calorie e macro.
struct MealSectionCard: View {
    let type: MealType
    let meals: [Meal]
    var onAdd: (() -> Void)?
    var onDelete: ((Meal) -> Void)?

    private var totals: Nutrients { meals.map(\.totals).total }
    private struct Row: Identifiable {
        let meal: Meal
        let item: MealItem
        var id: UUID { item.id }
    }

    private var items: [Row] { meals.flatMap { meal in meal.items.map { Row(meal: meal, item: $0) } } }

    var body: some View {
        Card {
            HStack {
                Label(type.title, systemImage: type.symbol).font(DS.Font.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(Format.kcal(totals.kcal)).font(DS.Font.callout.monospacedDigit())
                    .foregroundStyle(DS.Palette.textSecondary)
                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(DS.Palette.brand)
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(Text("Aggiungi a \(type.title)"))
                }
            }
            if items.isEmpty {
                Text("Nessun alimento registrato").font(DS.Font.callout).foregroundStyle(DS.Palette.textTertiary)
            } else {
                MacroInline(protein: totals.proteinG, carbs: totals.carbsG, fat: totals.fatG)
                Divider()
                ForEach(items) { row in
                    let item = row.item
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.food.name).font(DS.Font.callout)
                            Text(Format.grams(item.grams)).font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                        }
                        Spacer()
                        Text(Format.kcal(item.nutrients.kcal)).font(DS.Font.callout.monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
                    .contextMenu {
                        if let onDelete {
                            Button("Elimina pasto", systemImage: "trash", role: .destructive) { onDelete(row.meal) }
                        }
                    }
                }
            }
        }
    }
}
