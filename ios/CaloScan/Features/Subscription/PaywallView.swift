import SwiftUI

/// Paywall Plus/Pro. Prezzi, durata e rinnovo vengono da StoreKit (linee guida App Store 3.1.1 e 3.1.2).
struct PaywallView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: PaywallViewModel
    var highlight: Plan = .plus
    var onPurchased: (() -> Void)?

    init(services: AppServices, highlight: Plan = .plus, onPurchased: (() -> Void)? = nil) {
        _model = State(initialValue: PaywallViewModel(purchases: services.purchases))
        self.highlight = highlight
        self.onPurchased = onPurchased
    }

    var body: some View {
        NavigationStack {
            PaywallContent(model: model, onPurchased: purchased)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Chiudi") { dismiss() }
                    }
                }
        }
        .onAppear { model.selectedPlan = highlight }
    }

    private func purchased() {
        Task { await app.refreshEntitlements() }
        onPurchased?()
        dismiss()
    }
}

/// Contenuto riutilizzato sia nel paywall sia nella scelta del piano in onboarding.
struct PaywallContent: View {
    @Bindable var model: PaywallViewModel
    let onPurchased: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Sblocca CaloScan Premium").font(DS.Font.title)
                    Text("Più scansioni, statistiche complete e un coach che conosce i tuoi obiettivi.")
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                Picker("Durata", selection: $model.period) {
                    Text("Annuale").tag(PlanOffer.Period.yearly)
                    Text("Mensile").tag(PlanOffer.Period.monthly)
                }
                .pickerStyle(.segmented)

                switch model.offers {
                case .idle, .loading:
                    LoadingStateView(message: "Caricamento dei piani…")
                case .failed(let error):
                    ErrorStateView(error: error) { Task { await model.load() } }
                case .empty:
                    EmptyStateView(title: "Piani non disponibili",
                                   message: "Al momento non è possibile acquistare abbonamenti. Riprova più tardi.",
                                   systemImage: "bag")
                case .loaded:
                    ForEach([Plan.plus, .pro], id: \.self) { plan in
                        PlanCard(plan: plan, offer: model.offer(for: plan), isSelected: model.selectedPlan == plan) {
                            model.selectedPlan = plan
                        }
                    }
                    purchaseSection
                }
            }
            .padding(DS.Spacing.screen)
        }
        .background(DS.Palette.background.ignoresSafeArea())
        .task { if case .idle = model.offers { await model.load() } }
        .alert("Acquisto non riuscito",
               isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } }),
               presenting: model.error) { _ in Button("OK", role: .cancel) {} } message: { Text($0.localizedDescription) }
        .alert("Acquisto in attesa",
               isPresented: Binding(get: { model.pendingMessage != nil }, set: { if !$0 { model.pendingMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.pendingMessage ?? "") }
    }

    @ViewBuilder
    private var purchaseSection: some View {
        if let offer = model.selectedOffer {
            VStack(spacing: DS.Spacing.s) {
                LoadingButton(title: "Abbonati a \(offer.plan.displayName)", isLoading: model.purchasingID != nil) {
                    Task { if await model.purchaseSelected() { onPurchased() } }
                }
                // Termini obbligatori vicino al pulsante d'acquisto (linea guida 3.1.2).
                Text("\(offer.displayPrice) \(offer.period == .yearly ? String(localized: "all'anno") : String(localized: "al mese")). L'abbonamento si rinnova automaticamente allo stesso prezzo salvo disdetta almeno 24 ore prima della scadenza. L'addebito avviene sul tuo account Apple; puoi gestire o disdire l'abbonamento nelle impostazioni dell'account App Store.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .multilineTextAlignment(.center)
                HStack(spacing: DS.Spacing.m) {
                    Button("Ripristina acquisti") {
                        Task { if await model.restore() { onPurchased() } }
                    }
                    .disabled(model.isRestoring)
                    Link("Termini (EULA)", destination: LegalLinks.terms)
                    Link("Privacy", destination: LegalLinks.privacyPolicy)
                }
                .font(DS.Font.caption.weight(.semibold))
            }
        }
    }
}

private struct PlanCard: View {
    let plan: Plan
    let offer: PlanOffer?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                HStack {
                    PlanBadge(plan: plan)
                    Spacer()
                    if let offer {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(offer.displayPrice).font(DS.Font.headline.monospacedDigit())
                            if let perMonth = offer.pricePerMonthText {
                                Text("\(perMonth)/mese").font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                            }
                        }
                    }
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? DS.Palette.brand : DS.Palette.separator)
                }
                if let intro = offer?.introOffer {
                    Text(intro).font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.brand)
                }
                ForEach(Array(plan.features.enumerated()), id: \.offset) { _, feature in
                    Label { Text(feature).font(DS.Font.callout) } icon: {
                        Image(systemName: "checkmark").foregroundStyle(DS.Palette.brand)
                    }
                    .labelStyle(BrandLabelStyle())
                }
            }
            .padding(DS.Spacing.m)
            .background(isSelected ? DS.Palette.brandSoft : DS.Palette.surface, in: .rect(cornerRadius: DS.Radius.l))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.l)
                .strokeBorder(isSelected ? DS.Palette.brand : DS.Palette.separator, lineWidth: isSelected ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.Palette.textPrimary)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Scelta del piano al termine dell'onboarding: il piano Free è sempre selezionabile.
struct PlanChoiceView: View {
    @State private var model: PaywallViewModel
    let onContinueFree: () -> Void
    let onPurchased: () -> Void
    @Environment(AppState.self) private var app

    init(services: AppServices, onContinueFree: @escaping () -> Void, onPurchased: @escaping () -> Void) {
        _model = State(initialValue: PaywallViewModel(purchases: services.purchases))
        self.onContinueFree = onContinueFree
        self.onPurchased = onPurchased
    }

    var body: some View {
        VStack(spacing: 0) {
            PaywallContent(model: model) {
                Task { await app.refreshEntitlements() }
                onPurchased()
            }
            VStack(spacing: DS.Spacing.xs) {
                Button("Continua con il piano Free", action: onContinueFree)
                    .buttonStyle(.secondary)
                Text("Il piano Free include diario, inserimento manuale, calcolo del fabbisogno e alcune scansioni AI al giorno.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.vertical, DS.Spacing.s)
            .background(DS.Palette.background)
        }
    }
}
