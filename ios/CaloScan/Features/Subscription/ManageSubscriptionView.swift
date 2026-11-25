import SwiftUI
import StoreKit

/// Gestione abbonamento: piano attivo, utilizzo di oggi, cambio piano, disdetta tramite Apple.
struct ManageSubscriptionView: View {
    @Environment(AppState.self) private var app
    @State private var showPaywall = false
    @State private var showManageSheet = false

    var body: some View {
        let e = app.entitlements
        List {
            Section {
                HStack {
                    Text("Piano attuale")
                    Spacer()
                    if e.plan == .free { Text("Free").foregroundStyle(DS.Palette.textSecondary) }
                    else { PlanBadge(plan: e.plan) }
                }
                if let expires = e.expiresAt {
                    LabeledContent(e.willRenew ? "Rinnovo" : "Scade il",
                                   value: expires.formatted(date: .long, time: .omitted))
                }
            }
            Section("Utilizzo di oggi") {
                if let limit = e.scansLimitToday {
                    usageRow("Scansioni AI", used: e.scansUsedToday, limit: limit)
                } else {
                    LabeledContent("Scansioni AI", value: String(localized: "Illimitate · \(e.scansUsedToday) oggi"))
                }
                usageRow("Messaggi al coach", used: e.coachMessagesUsedToday, limit: e.coachMessagesLimitToday)
            }
            Section {
                if e.plan < .pro {
                    Button(e.plan == .free ? "Passa a Plus o Pro" : "Passa a Pro") { showPaywall = true }
                }
                if e.plan != .free {
                    Button("Gestisci o disdici su App Store") { showManageSheet = true }
                }
                RedeemCodeButton(style: .row) {
                    app.toasts.success(String(localized: "Codice riscattato"),
                                       subtitle: String(localized: "Ora hai CaloScan \(app.entitlements.plan.displayName)"), symbol: "gift.fill")
                }
            } footer: {
                Text("Gli abbonamenti sono gestiti da Apple. La disdetta ha effetto alla fine del periodo già pagato. I codici offerta si riscattano tramite Apple.")
            }
        }
        .navigationTitle("Abbonamento")
        .refreshable { await app.refreshEntitlements() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(services: app.services, highlight: e.plan == .plus ? .pro : .plus)
        }
        .manageSubscriptionsSheet(isPresented: $showManageSheet)
        .onChange(of: showManageSheet) { _, isShown in
            if !isShown { Task { await app.refreshEntitlements() } }
        }
    }

    private func usageRow(_ title: LocalizedStringKey, used: Int, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack {
                Text(title)
                Spacer()
                Text("\(used) / \(limit)").monospacedDigit().foregroundStyle(DS.Palette.textSecondary)
            }
            ProgressView(value: Double(min(used, limit)), total: Double(max(limit, 1)))
                .tint(used >= limit ? DS.Palette.warning : DS.Palette.brand)
        }
        .accessibilityElement(children: .combine)
    }
}
