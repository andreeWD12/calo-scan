import SwiftUI

struct ForgotPasswordView: View {
    @Bindable var model: AuthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("Recupera la password").font(DS.Font.title)
            Text("Inserisci l'email del tuo account: ti invieremo un link per sceglierne una nuova.")
                .font(DS.Font.callout)
                .foregroundStyle(DS.Palette.textSecondary)
            LabeledField(label: "Email", error: model.emailError) {
                TextField("nome@esempio.it", text: $model.email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if let info = model.infoMessage {
                Label(info, systemImage: "checkmark.circle")
                    .font(DS.Font.callout)
                    .padding(DS.Spacing.s)
                    .background(DS.Palette.brandSoft, in: .rect(cornerRadius: DS.Radius.s))
            }
            LoadingButton(title: "Invia link", isLoading: model.isLoading) {
                Task { await model.sendPasswordReset() }
            }
            .disabled(!AuthViewModel.isValidEmail(model.email))
            Spacer()
        }
        .padding(DS.Spacing.screen)
        .background { AppBackground() }
        .navigationTitle("Password dimenticata")
        .navigationBarTitleDisplayMode(.inline)
        .authAlert(model)
    }
}
