import SwiftUI

struct SignInView: View {
    @Bindable var model: AuthViewModel
    @Binding var path: [AuthRoute]
    @FocusState private var focused: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                Text("Bentornato").font(DS.Font.title)
                LabeledField(label: "Email", error: model.emailError) {
                    TextField("nome@esempio.it", text: $model.email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                }
                LabeledField(label: "Password") {
                    SecureField("Password", text: $model.password)
                        .textContentType(.password)
                        .focused($focused, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { if model.canSignIn { Task { await model.signIn() } } }
                }
                Button("Password dimenticata?") { path.append(.forgotPassword) }
                    .font(DS.Font.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.brand)
                    .frame(minHeight: 44)
                LoadingButton(title: "Accedi", isLoading: model.isLoading) {
                    Task { await model.signIn() }
                }
                .disabled(!model.canSignIn)
                DividerLabel(text: "oppure")
                SocialSignInButtons(model: model)
            }
            .padding(DS.Spacing.screen)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.background.ignoresSafeArea())
        .navigationTitle("Accedi")
        .navigationBarTitleDisplayMode(.inline)
        .authAlert(model)
    }
}

struct DividerLabel: View {
    let text: LocalizedStringKey
    var body: some View {
        HStack {
            Rectangle().fill(DS.Palette.separator).frame(height: 1)
            Text(text).font(DS.Font.caption).foregroundStyle(DS.Palette.textTertiary)
            Rectangle().fill(DS.Palette.separator).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}
