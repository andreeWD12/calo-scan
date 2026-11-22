import SwiftUI
import CaloScanCore

enum HomeRoute: Hashable { case coach, subscription, shopping }

/// Dashboard: calorie e macro di oggi, pulsante di scansione, consigli, pasti del giorno.
struct HomeView: View {
    @Environment(AppState.self) private var app
    @State private var model: HomeViewModel
    @State private var addingTo: MealType?
    @State private var loggingPlanned: PlannedMeal?
    @State private var showPaywall = false
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
                ToolbarItem(placement: .topBarLeading) {
                    Button { path.append(.shopping) } label: { Image(systemName: "cart") }
                        .accessibilityLabel(Text("Lista della spesa"))
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    PlanShortcut(plan: app.entitlements.plan) {
                        // Free e Plus vedono i piani; Pro va alla gestione dell'abbonamento.
                        if app.entitlements.plan == .pro { path.append(.subscription) } else { showPaywall = true }
                    }
                    Button { path.append(.coach) } label: { Image(systemName: "sparkles") }
                        .accessibilityLabel(Text("Apri AI Nutrition Coach"))
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .coach: CoachView(services: app.services)
                case .subscription: ManageSubscriptionView()
                case .shopping: ShoppingListView(services: app.services)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(services: app.services, highlight: app.entitlements.plan == .plus ? .pro : .plus)
            }
            .sheet(item: $addingTo) { type in
                AddFoodFlowView(services: app.services, mealType: type) {
                    app.mealSaved(type)
                }
            }
            .sheet(item: $loggingPlanned) { planned in
                PlannedMealLogSheet(meal: planned, services: app.services) {
                    app.mealSaved(planned.type, source: .plan)
                }
            }
        }
        .task(id: app.diaryRevision) { await model.load() }
        .onChange(of: app.router.pending, initial: true) { _, link in
            if link == .coach { path = [.coach]; app.router.pending = nil }
        }
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
                SummaryCard(day: day, targets: targets, professional: app.professionalPlan?.professional).appear(index: 0)
            }
            ScanCallToAction(scansRemaining: app.entitlements.scansRemaining, action: onScan).appear(index: 1)
            if let insight = model.insights.first {
                InsightCard(insight: insight) { path.append(.coach) }
                    .appear(index: 2)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let window = app.profile?.eatingStyle?.window, app.entitlements.plan != .free {
                EatingWindowCard(window: window)
                    .appear(index: 3)
            }
            ForEach(Array(MealType.allCases.enumerated()), id: \.element) { index, type in
                let planned = app.professionalPlan?.plannedMeal(type, on: .now)
                MealSectionCard(type: type, meals: day.meals(of: type),
                                onAdd: { addingTo = type },
                                onDelete: { meal in Task { await model.delete(meal) } },
                                planned: planned,
                                onLogPlanned: planned.map { p in { loggingPlanned = p } },
                                onToggleCheat: { meal in Task { await model.toggleCheat(meal) } },
                                plannedWeek: app.professionalPlan.flatMap { $0.rotationWeeks > 1 ? $0.rotationWeek(on: .now) : nil })
                    .appear(index: 3 + index)
                    .cardScrollEffect()
            }
        }
    }
}

private struct SummaryCard: View {
    let day: DayLog
    let targets: DailyTargets
    /// Presente se l'obiettivo viene dal piano di un professionista.
    let professional: HealthProfessional?

    var body: some View {
        let totals = day.totals
        let progress = NutritionStats.progress(consumed: totals.kcal, target: targets.calorieTarget)
        Card {
            HStack(spacing: DS.Spacing.l) {
                CalorieRing(consumed: totals.kcal, target: targets.calorieTarget)
                    .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    metric(professional?.targetLabel ?? "Obiettivo", Format.kcal(Double(targets.calorieTarget)))
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
        .buttonStyle(.pressable)
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
    /// Pasto previsto dal piano del professionista per questo giorno.
    var planned: PlannedMeal? = nil
    var onLogPlanned: (() -> Void)? = nil
    var onToggleCheat: ((Meal) -> Void)? = nil
    /// Settimana della rotazione del piano, mostrata solo se il piano ruota su più settimane.
    var plannedWeek: Int? = nil

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
                    .symbolEffect(.bounce, value: items.count)
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
            if items.isEmpty, let planned, let onLogPlanned {
                PlannedMealPreview(meal: planned, week: plannedWeek, action: onLogPlanned)
            } else if items.isEmpty {
                Text("Nessun alimento registrato").font(DS.Font.callout).foregroundStyle(DS.Palette.textTertiary)
            } else {
                MacroInline(protein: totals.proteinG, carbs: totals.carbsG, fat: totals.fatG)
                Divider()
                ForEach(items) { row in
                    let item = row.item
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.food.name).font(DS.Font.callout)
                            HStack(spacing: DS.Spacing.xxs) {
                                Text(Format.grams(item.grams)).font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                                if row.meal.isCheatMeal { CheatBadge() }
                                if row.meal.source == .plan {
                                    Image(systemName: "list.clipboard").font(.caption2).foregroundStyle(DS.Palette.brand)
                                        .accessibilityLabel(Text("Dal piano"))
                                }
                            }
                        }
                        Spacer()
                        Text(Format.kcal(item.nutrients.kcal)).font(DS.Font.callout.monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
                    .contextMenu {
                        if let onToggleCheat {
                            Button(row.meal.isCheatMeal ? "Non è uno sgarro" : "Segna come sgarro",
                                   systemImage: row.meal.isCheatMeal ? "xmark.circle" : "party.popper") { onToggleCheat(row.meal) }
                        }
                        if let onDelete {
                            Button("Elimina pasto", systemImage: "trash", role: .destructive) { onDelete(row.meal) }
                        }
                    }
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                            removal: .opacity.combined(with: .scale(scale: 0.95))))
                }
            }
        }
        .animation(DS.Motion.standard, value: items.map(\.id))
    }
}

/// Etichetta discreta per gli sgarri: informa senza giudicare.
struct CheatBadge: View {
    var body: some View {
        Label("Sgarro", systemImage: "party.popper.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(DS.Palette.fat)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(DS.Palette.fat.opacity(0.12), in: .capsule)
    }
}

/// Anteprima del pasto previsto dal piano, con registrazione rapida.
private struct PlannedMealPreview: View {
    let meal: PlannedMeal
    var week: Int? = nil
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Label(week.map { String(localized: "Dal tuo piano · settimana \($0)") } ?? String(localized: "Dal tuo piano"),
                  systemImage: "list.clipboard")
                .font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.brand)
            Text(meal.foods.map { "\($0.name) \(Format.grams($0.grams))" }.formatted(.list(type: .and)))
                .font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
            Button(action: action) {
                Label("Registra come da piano", systemImage: "checkmark.circle.fill")
                    .font(DS.Font.callout.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.pressable)
            .foregroundStyle(DS.Palette.brand)
            .background(DS.Palette.brandSoft, in: .rect(cornerRadius: DS.Radius.m))
        }
    }
}

/// Icona in alto per raggiungere subito i piani (o la gestione dell'abbonamento per Pro).
private struct PlanShortcut: View {
    let plan: Plan
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if plan == .free {
                Image(systemName: "crown")
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "crown.fill")
                    Text(plan.displayName).font(.caption.weight(.bold))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(DS.Palette.brandSoft, in: .capsule)
            }
        }
        .foregroundStyle(DS.Palette.brand)
        .accessibilityLabel(Text(plan == .pro ? "Gestisci l'abbonamento Pro" : "Scopri i piani Premium"))
    }
}
