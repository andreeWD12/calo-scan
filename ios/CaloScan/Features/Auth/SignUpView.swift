import SwiftUI
import CaloScanCore

struct SignUpView: View {
    @Bindable var model: AuthViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                Text("Crea il tuo account").font(DS.Font.title)
                LabeledField(label: "Email", error: model.emailError) {
                    TextField("nome@esempio.it", text: $model.email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledField(label: "Password", error: model.passwordError) {
                    SecureField("Almeno 8 caratteri", text: $model.password)
                        .textContentType(.newPassword)
                }
                LabeledField(label: "Conferma password", error: model.confirmationError) {
                    SecureField("Ripeti la password", text: $model.passwordConfirmation)
                        .textContentType(.newPassword)
                }

                // Consensi separati e non preselezionati (art. 7 GDPR).
                Toggle(isOn: $model.confirmedMinimumAge) {
                    Text("Confermo di avere almeno \(AgePolicy.minimumAccountAge) anni.")
                        .font(DS.Font.callout)
                }
                Toggle(isOn: $model.acceptedTerms) {
                    Text("Accetto i Termini di servizio e ho letto l'Informativa sulla privacy.")
                        .font(DS.Font.callout)
                }
                HStack(spacing: DS.Spacing.m) {
                    Link("Termini di servizio", destination: LegalLinks.terms)
                    Link("Informativa privacy", destination: LegalLinks.privacyPolicy)
                }
                .font(DS.Font.caption.weight(.semibold))
                .padding(.leading, 36)

                if let info = model.infoMessage {
                    Label(info, systemImage: "envelope.badge")
                        .font(DS.Font.callout)
                        .padding(DS.Spacing.s)
                        .background(DS.Palette.brandSoft, in: .rect(cornerRadius: DS.Radius.s))
                }

                LoadingButton(title: "Crea account", isLoading: model.isLoading) {
                    Task { await model.signUp() }
                }
                .disabled(!model.canSignUp)
            }
            .padding(DS.Spacing.screen)
            .toggleStyle(CheckboxToggleStyle())
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.background.ignoresSafeArea())
        .navigationTitle("Registrazione")
        .navigationBarTitleDisplayMode(.inline)
        .authAlert(model)
    }
}

/// Casella di spunta accessibile (iOS non ne fornisce una nativa).
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .top, spacing: DS.Spacing.s) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? DS.Palette.brand : DS.Palette.textTertiary)
                configuration.label
                    .foregroundStyle(DS.Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isButton, .isSelected] : .isButton)
    }
}
