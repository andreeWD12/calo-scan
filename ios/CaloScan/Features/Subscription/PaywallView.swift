import SwiftUI

/// Paywall Plus/Pro. Prezzi, durata e rinnovo vengono da StoreKit (linee guida App Store 3.1.1 e 3.1.2).
struct PaywallView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: PaywallViewModel
    var highlight: Plan = .plus
    var showsPregnancyOffer = false
    var onPurchased: (() -> Void)?

    init(services: AppServices, highlight: Plan = .plus, showsPregnancyOffer: Bool = false, onPurchased: (() -> Void)? = nil) {
        _model = State(initialValue: PaywallViewModel(purchases: services.purchases))
        self.highlight = highlight
        self.showsPregnancyOffer = showsPregnancyOffer
        self.onPurchased = onPurchased
    }

    var body: some View {
        NavigationStack {
            PaywallContent(model: model, showsPregnancyOffer: showsPregnancyOffer, onPurchased: purchased)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Chiudi") { dismiss() }
                    }
                }
        }
        .onAppear { model.selectedPlan = highlight }
    }

    private func purchased() {
        Task {
            await app.refreshEntitlements()
            app.toasts.success(String(localized: "Benvenuto in CaloScan \(app.entitlements.plan.displayName)"),
                               subtitle: String(localized: "Le funzioni Premium sono attive"), symbol: "crown.fill")
        }
        onPurchased?()
        dismiss()
    }
}

/// Contenuto riutilizzato sia nel paywall sia nella scelta del piano in onboarding.
struct PaywallContent: View {
    @Bindable var model: PaywallViewModel
    /// Chi ha indicato la gravidanza vede in cima l'offerta Pro dedicata (se Apple gliela concede).
    var showsPregnancyOffer = false
    let onPurchased: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Sblocca CaloScan Premium").font(DS.Font.title)
                    Text("Lo scanner AI, statistiche complete e un coach che conosce i tuoi obiettivi.")
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
                    if showsPregnancyOffer, let offer = model.pregnancyOffer {
                        PregnancyOfferCard(offer: offer, isPurchasing: model.purchasingID == offer.id) {
                            Task { if await model.purchase(offer) { onPurchased() } }
                        }
                        Text("Oppure scegli un altro piano").font(DS.Font.headline).padding(.top, DS.Spacing.s)
                    }
                    ForEach([Plan.plus, .pro], id: \.self) { plan in
                        PlanCard(plan: plan, offer: model.offer(for: plan), isSelected: model.selectedPlan == plan) {
                            model.selectedPlan = plan
                        }
                    }
                    purchaseSection
                }
                // Sempre visibile, anche se i piani non si caricano: il codice si riscatta comunque con Apple.
                RedeemCodeButton(style: .prominent, onRedeemed: onPurchased)
            }
            .padding(DS.Spacing.screen)
        }
        .background { AppBackground() }
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

/// Offerta Pro per la gravidanza: offerta introduttiva Apple del 30% per 3 mesi su un prodotto dedicato.
/// Prezzo scontato, durata e prezzo successivo sono scritti accanto al pulsante (linea guida 3.1.2,
/// Codice del Consumo art. 17-bis: lo sconto è calcolato sul prezzo normale di Pro mensile, che non cambia).
private struct PregnancyOfferCard: View {
    let offer: PlanOffer
    let isPurchasing: Bool
    let action: () -> Void

    private var months: Int { offer.introMonths ?? 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Label("Offerta per la gravidanza", systemImage: "heart.fill")
                .font(DS.Font.caption.weight(.semibold))
                .foregroundStyle(DS.Palette.brand)
            Text("Pro a \(offer.introPrice ?? "") al mese per i primi \(months) mesi")
                .font(DS.Font.headline)
            Text("Invece di \(offer.displayPrice) al mese: il 30% in meno.")
                .font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
            ForEach(Array(Self.features.enumerated()), id: \.offset) { _, feature in
                Label { Text(feature).font(DS.Font.callout) } icon: {
                    Image(systemName: "checkmark").foregroundStyle(DS.Palette.brand)
                }
                .labelStyle(BrandLabelStyle())
            }
            LoadingButton(title: "Attiva l'offerta", isLoading: isPurchasing, action: action)
            Text("\(offer.introPrice ?? "") al mese per i primi \(months) mesi, poi \(offer.displayPrice) al mese. L'abbonamento si rinnova automaticamente salvo disdetta almeno 24 ore prima della scadenza. L'addebito avviene sul tuo account Apple; puoi disdire in qualsiasi momento nelle impostazioni dell'account App Store.")
                .font(DS.Font.caption).foregroundStyle(DS.Palette.textTertiary)
            Text("Ti proponiamo questa offerta perché hai indicato di essere in gravidanza. Il dato resta nel tuo profilo e non viene usato per pubblicità.")
                .font(DS.Font.caption).foregroundStyle(DS.Palette.textTertiary)
        }
        .padding(DS.Spacing.m)
        .background(DS.Palette.brandSoft, in: .rect(cornerRadius: DS.Radius.l))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.l).strokeBorder(DS.Palette.brand, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
    }

    static var features: [LocalizedStringKey] { [
        "Energia, proteine e consigli per la tua settimana di gravidanza (EFSA)",
        "Avvisi automatici su scansioni, ricerca e lista della spesa",
        "Suggerimenti AI senza gli alimenti da evitare",
        "Tutte le funzioni di Pro",
    ] }
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
    let isPregnant: Bool
    let onContinueFree: () -> Void
    let onPurchased: () -> Void
    @Environment(AppState.self) private var app

    init(services: AppServices, isPregnant: Bool = false, onContinueFree: @escaping () -> Void, onPurchased: @escaping () -> Void) {
        _model = State(initialValue: PaywallViewModel(purchases: services.purchases))
        self.isPregnant = isPregnant
        self.onContinueFree = onContinueFree
        self.onPurchased = onPurchased
    }

    var body: some View {
        VStack(spacing: 0) {
            PaywallContent(model: model, showsPregnancyOffer: isPregnant) {
                Task { await app.refreshEntitlements() }
                onPurchased()
            }
            VStack(spacing: DS.Spacing.xs) {
                Button("Continua con il piano Free", action: onContinueFree)
                    .buttonStyle(.secondary)
                Text(isPregnant
                     ? "Con il piano Free in gravidanza: obiettivo di mantenimento (mai in deficit), niente digiuni e l'elenco degli alimenti da evitare."
                     : "Il piano Free include diario, ricerca alimenti, codici a barre, inserimento manuale e calcolo del fabbisogno. Lo scanner AI è incluso in Plus e Pro.")
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
