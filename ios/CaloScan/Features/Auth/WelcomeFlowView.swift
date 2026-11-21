import SwiftUI
import AuthenticationServices

enum AuthRoute: Hashable { case signUp, signIn, forgotPassword }

/// Welcome → Registrazione / Login → Recupero password.
struct WelcomeFlowView: View {
    @State private var model: AuthViewModel
    @State private var path: [AuthRoute] = []

    init(services: AppServices) {
        _model = State(initialValue: AuthViewModel(auth: services.auth))
    }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(model: model, path: $path)
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .signUp: SignUpView(model: model)
                    case .signIn: SignInView(model: model, path: $path)
                    case .forgotPassword: ForgotPasswordView(model: model)
                    }
                }
        }
        .onOpenURL { _ = GoogleSignInCoordinator.handle($0) }
    }
}

struct WelcomeView: View {
    @Bindable var model: AuthViewModel
    @Binding var path: [AuthRoute]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: DS.Spacing.l) {
            Spacer()
            AppMark(size: 96)
            VStack(spacing: DS.Spacing.xs) {
                Text("CaloScan").font(DS.Font.display)
                Text("Fotografa il piatto, conosci cosa mangi.\nUn assistente per un'alimentazione più consapevole.")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                feature("camera.viewfinder", "Analisi del piatto con l'intelligenza artificiale")
                feature("chart.pie", "Calorie e macronutrienti, giorno per giorno")
                feature("sparkles", "Consigli personalizzati sui tuoi obiettivi")
            }
            .padding(.top, DS.Spacing.s)
            Spacer()
            SocialSignInButtons(model: model)
            Button("Registrati con email") { path.append(.signUp) }
                .buttonStyle(.secondary)
            Button("Hai già un account? Accedi") { path.append(.signIn) }
                .font(DS.Font.callout.weight(.semibold))
                .foregroundStyle(DS.Palette.brand)
                .frame(minHeight: 44)
            LegalFootnote()
        }
        .padding(.horizontal, DS.Spacing.screen)
        .padding(.bottom, DS.Spacing.m)
        .background(DS.Palette.background.ignoresSafeArea())
        .authAlert(model)
    }

    private func feature(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label { Text(text).font(DS.Font.callout) } icon: {
            Image(systemName: symbol).foregroundStyle(DS.Palette.brand).frame(width: 28)
        }
    }
}

/// Pulsanti Apple e Google (Apple per primo: linea guida App Store 4.8).
struct SocialSignInButtons: View {
    @Bindable var model: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            SignInWithAppleButton(.continue) { request in
                model.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await model.handleApple(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 54)
            .clipShape(.rect(cornerRadius: DS.Radius.m))
            .disabled(model.isLoading)

            Button {
                Task { await model.signInWithGoogle() }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "g.circle.fill").font(.title3)
                    Text("Continua con Google")
                }
            }
            .buttonStyle(.secondary)
            .disabled(model.isLoading)
        }
    }
}

/// Nota legale con link a termini e privacy.
struct LegalFootnote: View {
    var body: some View {
        Text(markdown: String(localized: "Continuando accetti i [Termini di servizio](\(LegalLinks.terms.absoluteString)) e confermi di aver letto l'[Informativa sulla privacy](\(LegalLinks.privacyPolicy.absoluteString))."))
            .font(DS.Font.caption)
            .foregroundStyle(DS.Palette.textTertiary)
            .multilineTextAlignment(.center)
            .tint(DS.Palette.textSecondary)
    }
}

extension View {
    /// Mostra errori e messaggi informativi del flusso di autenticazione.
    func authAlert(_ model: AuthViewModel) -> some View {
        alert("Accesso non riuscito",
              isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.dismissError() } }),
              presenting: model.error) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }
}
