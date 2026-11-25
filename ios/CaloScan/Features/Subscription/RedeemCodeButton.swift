import SwiftUI
import StoreKit
import UIKit

/// "Riscatta un codice": apre il foglio di Apple per i codici offerta creati in App Store Connect.
///
/// L'app non gestisce codici promozionali propri: i contenuti digitali si sbloccano solo tramite
/// In-App Purchase (linea guida App Store 3.1.1). Apple verifica il codice, applica l'offerta e
/// invia la transazione, che passa dalla stessa verifica server degli acquisti normali.
struct RedeemCodeButton: View {
    enum Style { case prominent, row }

    @Environment(AppState.self) private var app
    @State private var isPresented = false
    var style: Style = .prominent
    /// Chiamato se dopo il riscatto il piano risulta superiore a prima.
    var onRedeemed: (() -> Void)? = nil

    var body: some View {
        Button { isPresented = true } label: { label }
            .buttonStyle(.pressable)
            .modifier(OfferCodeSheet(isPresented: $isPresented) {
                Task {
                    let before = app.entitlements.plan
                    await app.refreshEntitlements()
                    if app.entitlements.plan > before { onRedeemed?() }
                }
            })
            .accessibilityHint(Text("Apre il foglio di Apple per inserire un codice offerta"))
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .prominent:
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: "giftcard.fill").font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hai un codice?").font(DS.Font.callout.weight(.semibold))
                    Text("Riscatta un codice offerta o lo sconto di un invito")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                }
                Spacer()
                Text("Riscatta").font(DS.Font.callout.weight(.semibold))
                    .padding(.horizontal, DS.Spacing.s).padding(.vertical, 6)
                    .background(DS.Palette.brand, in: .capsule)
                    .foregroundStyle(DS.Palette.onBrand)
            }
            .foregroundStyle(DS.Palette.brand)
            .padding(DS.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(DS.Palette.brandSoft, in: .rect(cornerRadius: DS.Radius.m))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.m).strokeBorder(DS.Palette.brand.opacity(0.35),
                                                                               style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        case .row:
            Label("Riscatta un codice", systemImage: "giftcard.fill")
                .foregroundStyle(DS.Palette.brand)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
        }
    }
}

private struct OfferCodeSheet: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 17.2, *) {
            content.offerCodeRedemption(isPresented: $isPresented) { _ in onDismiss() }
        } else {
            content.onChange(of: isPresented) { _, shown in
                guard shown else { return }
                isPresented = false
                Task { @MainActor in
                    let scene = UIApplication.shared.connectedScenes
                        .first { $0.activationState == .foregroundActive } as? UIWindowScene
                    if let scene { try? await AppStore.presentOfferCodeRedeemSheet(in: scene) }
                    onDismiss()
                }
            }
        }
    }
}
