import SwiftUI
import StoreKit
import UIKit

/// "Riscatta un codice": apre il foglio di Apple per i codici offerta creati in App Store Connect.
///
/// L'app non gestisce codici promozionali propri: i contenuti digitali si sbloccano solo tramite
/// In-App Purchase (linea guida App Store 3.1.1). Apple verifica il codice, applica l'offerta e
/// invia la transazione, che passa dalla stessa verifica server degli acquisti normali.
struct RedeemCodeButton: View {
    @Environment(AppState.self) private var app
    @State private var isPresented = false
    /// Chiamato se dopo il riscatto il piano risulta superiore a prima.
    var onRedeemed: (() -> Void)? = nil

    var body: some View {
        Button("Riscatta un codice") { isPresented = true }
            .modifier(OfferCodeSheet(isPresented: $isPresented) {
                Task {
                    let before = app.entitlements.plan
                    await app.refreshEntitlements()
                    if app.entitlements.plan > before { onRedeemed?() }
                }
            })
            .accessibilityHint(Text("Apre il foglio di Apple per inserire un codice offerta"))
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
