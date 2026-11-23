import SwiftUI

/// Aperta dal link di recupero password (caloscan://auth-callback, type=recovery):
/// l'utente ha già una sessione di recupero e sceglie la nuova password.
struct NewPasswordView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let services: AppServices

    @State private var password = ""
    @State private var confirmation = ""
    @State private var isSaving = false
    @State private var error: APIError?

    private var passwordError: String? {
        password.isEmpty ? nil : AuthViewModel.passwordIssues(password).first
    }
    private var confirmationError: String? {
        confirmation.isEmpty || confirmation == password ? nil : String(localized: "Le password non coincidono.")
    }
    private var canSave: Bool {
        AuthViewModel.passwordIssues(password).isEmpty && password == confirmation && !isSaving
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                Text("Scegli una nuova password").font(DS.Font.title)
                LabeledField(label: "Nuova password", error: passwordError) {
                    SecureField("Almeno 8 caratteri", text: $password)
                        .textContentType(.newPassword)
                }
                LabeledField(label: "Conferma password", error: confirmationError) {
                    SecureField("Ripeti la password", text: $confirmation)
                        .textContentType(.newPassword)
                }
                Text("Almeno 8 caratteri, con lettere maiuscole, minuscole e cifre.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                LoadingButton(title: "Salva la nuova password", isLoading: isSaving) {
                    Task { await save() }
                }
                .disabled(!canSave)
                Spacer()
            }
            .padding(DS.Spacing.screen)
            .background { AppBackground() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
            .alert("Password non aggiornata",
                   isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
                   presenting: error) { _ in Button("OK", role: .cancel) {} } message: { Text($0.localizedDescription) }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await services.auth.updatePassword(password)
            app.toasts.success(String(localized: "Password aggiornata"), symbol: "lock.fill")
            dismiss()
        } catch {
            self.error = APIError.from(error)
        }
    }
}
