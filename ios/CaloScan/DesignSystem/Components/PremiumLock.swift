import SwiftUI
import CaloScanCore

/// Filigrana per le sezioni dei piani a pagamento: il contenuto (sempre con i dati veri dell'utente)
/// resta intravisto sotto un velo semi opaco con un lucchetto; un tocco apre i piani.
/// È solo presentazione: dove serve, il server applica gli stessi limiti.
private struct PremiumLockModifier: ViewModifier {
    @Environment(AppState.self) private var app
    @State private var showPaywall = false
    let required: Plan
    let title: LocalizedStringKey
    var cornerRadius: CGFloat = DS.Radius.l

    func body(content: Content) -> some View {
        if app.entitlements.plan >= required {
            content
        } else {
            content
                .blur(radius: 5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .overlay {
                    Button { showPaywall = true } label: {
                        LockWatermark(required: required, title: title, cornerRadius: cornerRadius)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(Text(title))
                    .accessibilityHint(Text("Disponibile con \(required.displayName). Tocca per vedere i piani."))
                }
                .clipShape(.rect(cornerRadius: cornerRadius))
                .sheet(isPresented: $showPaywall) { PaywallView(services: app.services, highlight: required) }
        }
    }
}

private struct LockWatermark: View {
    let required: Plan
    let title: LocalizedStringKey
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(DS.Palette.surface.opacity(0.55))
            // Lucchetto grande e trasparente come filigrana.
            Image(systemName: "lock.fill")
                .font(.system(size: 96, weight: .bold))
                .foregroundStyle(DS.Palette.brand.opacity(0.08))
                .rotationEffect(.degrees(-12))
            VStack(spacing: DS.Spacing.xs) {
                Image(systemName: "lock.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(DS.Palette.onBrand)
                    .frame(width: 48, height: 48)
                    .background(DS.Palette.brand, in: .circle)
                    .shadow(color: DS.Palette.brand.opacity(0.3), radius: 8, y: 4)
                Text(title).font(DS.Font.headline).foregroundStyle(DS.Palette.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Con \(required.displayName) · Tocca per sbloccare")
                    .font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.brand)
            }
            .padding(DS.Spacing.m)
        }
        .contentShape(.rect)
    }
}

/// Etichetta compatta "lucchetto + piano" per righe di elenco e menu.
struct PlanLockBadge: View {
    let plan: Plan

    var body: some View {
        Label(plan.displayName, systemImage: "lock.fill").font(.caption.weight(.bold))
            .foregroundStyle(DS.Palette.brand)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(DS.Palette.brandSoft, in: .capsule)
            .accessibilityLabel(Text("Disponibile con \(plan.displayName)"))
    }
}

extension View {
    /// Mostra la sezione sotto una filigrana con lucchetto se il piano dell'utente è inferiore a `required`.
    func premiumLocked(_ required: Plan, title: LocalizedStringKey, cornerRadius: CGFloat = DS.Radius.l) -> some View {
        modifier(PremiumLockModifier(required: required, title: title, cornerRadius: cornerRadius))
    }
}
