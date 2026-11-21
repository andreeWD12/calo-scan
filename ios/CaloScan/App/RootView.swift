import SwiftUI

/// Routing radice in base allo stato della sessione.
struct RootView: View {
    @Environment(AppState.self) private var app
    @AppStorage("appearance") private var appearance: AppearancePreference = .system

    var body: some View {
        Group {
            switch app.session {
            case .unknown:
                SplashView()
            case .signedOut:
                WelcomeFlowView(services: app.services)
            case .needsOnboarding:
                OnboardingFlowView(services: app.services)
            case .signedIn:
                MainTabView()
            }
        }
        .animation(DS.Motion.standard, value: app.session)
        .tint(DS.Palette.brand)
        .preferredColorScheme(appearance.colorScheme)
        .task { await app.start() }
    }
}

/// Splash mostrata mentre si verifica la sessione salvata nel Keychain.
struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            DS.Palette.background.ignoresSafeArea()
            VStack(spacing: DS.Spacing.s) {
                AppMark(size: 88)
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)
                Text("CaloScan").font(DS.Font.display).foregroundStyle(DS.Palette.textPrimary)
            }
        }
        .onAppear { withAnimation(DS.Motion.standard) { appeared = true } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("CaloScan, caricamento"))
    }
}

/// Logo dell'app disegnato in SwiftUI (nitido a ogni dimensione, segue light/dark).
struct AppMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28).fill(DS.Palette.brand)
            Image(systemName: "viewfinder")
                .font(.system(size: size * 0.62, weight: .light))
                .foregroundStyle(DS.Palette.onBrand.opacity(0.9))
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(DS.Palette.onBrand)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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
