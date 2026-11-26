import SwiftUI
import UIKit

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
        // iPad: contenuto in una colonna centrata, come su iPhone ma più larga, per non allungare
        // schede e liste su tutto lo schermo. Fogli e fotocamera restano quelli di sistema.
        .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 760 : .infinity)
        .frame(maxWidth: .infinity)
        .background(DS.Palette.background.ignoresSafeArea())
        .animation(DS.Motion.standard, value: app.session)
        .tint(DS.Palette.brand)
        .preferredColorScheme(appearance.colorScheme)
        .task { await app.start() }
        .sheet(isPresented: Binding(get: { app.showsNewPassword }, set: { app.showsNewPassword = $0 })) {
            NewPasswordView(services: app.services)
        }
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

/// Logo dell'app: pera nel mirino dello scanner. Asset vettoriale (Assets.xcassets/Logo)
/// con variante per la dark mode; sorgenti in design/logo/.
struct AppMark: View {
    var size: CGFloat = 64

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
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
