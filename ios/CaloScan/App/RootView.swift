import SwiftUI

/// Routing radice in base allo stato della sessione.
/// Fase 1: struttura del routing. Le schermate reali (Welcome, Onboarding, TabView a 5 sezioni)
/// vengono collegate nelle Fasi 2–3.
struct RootView: View {
    @Environment(\.container) private var container

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("CaloScan")
                .font(.largeTitle.bold())
            if let url = container?.config.supabaseURL.host() {
                Text("Backend: \(url)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Mostrata solo se Secrets.xcconfig non è stato configurato.
struct ConfigurationErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Configurazione incompleta", systemImage: "wrench.and.screwdriver")
        } description: {
            Text(message)
        }
    }
}
