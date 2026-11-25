import SwiftUI

/// Privacy e gestione account: consensi, esportazione (art. 20 GDPR), cancellazione (art. 17 GDPR,
/// App Store 5.1.1(v)), disconnessione.
struct PrivacyAccountView: View {
    @Environment(AppState.self) private var app
    @State private var consents: Loadable<ConsentState> = .idle
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var isDeleting = false
    @State private var confirmDelete = false
    @State private var confirmWithdrawHealth = false
    @State private var error: APIError?

    var body: some View {
        Form {
            Section {
                switch consents {
                case .idle, .loading:
                    ProgressView()
                case .failed(let e):
                    Button("Riprova") { Task { await load() } }
                    Text(e.localizedDescription).font(DS.Font.caption).foregroundStyle(DS.Palette.danger)
                case .empty:
                    EmptyView()
                case .loaded(let state):
                    Toggle("Trattamento dei dati relativi alla salute", isOn: Binding(
                        get: { state.healthDataProcessing },
                        set: { if !$0 { confirmWithdrawHealth = true } }))
                    Toggle("Analisi AI delle foto", isOn: Binding(
                        get: { state.aiImageAnalysis },
                        set: { v in var s = state; s.aiImageAnalysis = v; Task { await update(s) } }))
                    Toggle("Email su novità e suggerimenti", isOn: Binding(
                        get: { state.productEmails },
                        set: { v in var s = state; s.productEmails = v; Task { await update(s) } }))
                }
            } header: {
                Text("Consensi")
            } footer: {
                Text("Puoi revocare i consensi in qualsiasi momento. La revoca non pregiudica la liceità del trattamento precedente.")
            }

            Section {
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Condividi il file esportato", systemImage: "square.and.arrow.up") }
                } else {
                    Button {
                        Task { await export() }
                    } label: {
                        HStack {
                            Label("Esporta i miei dati", systemImage: "arrow.down.doc")
                            if isExporting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isExporting)
                }
            } header: {
                Text("I tuoi dati")
            } footer: {
                Text("Ricevi un file JSON con profilo, diario, pesi, conversazioni con il coach e consensi.")
            }

            Section {
                Link("Informativa sulla privacy", destination: LegalLinks.privacyPolicy)
                Link("Termini di servizio", destination: LegalLinks.terms)
            } footer: {
                Text("Le foto dei piatti vengono cancellate automaticamente dopo il periodo indicato nell'informativa. I dati sono cifrati in transito e conservati su server nell'Unione Europea.")
            }

            Section {
                Button("Esci dall'account") { Task { try? await app.services.auth.signOut() } }
                Button(role: .destructive) { confirmDelete = true } label: {
                    HStack {
                        Text("Elimina account e dati")
                        if isDeleting { Spacer(); ProgressView() }
                    }
                }
                .disabled(isDeleting)
            } footer: {
                Text("L'eliminazione è definitiva: cancella account, diario, pesi, foto e conversazioni. Se hai un abbonamento attivo, disdicilo anche nelle impostazioni dell'App Store per evitare rinnovi.")
            }
        }
        .navigationTitle("Privacy e account")
        .task { await load() }
        .confirmationDialog("Eliminare definitivamente l'account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina account", role: .destructive) { Task { await deleteAccount() } }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Tutti i tuoi dati verranno cancellati e non potranno essere recuperati.")
        }
        .confirmationDialog("Revocare il consenso ai dati sulla salute?", isPresented: $confirmWithdrawHealth, titleVisibility: .visible) {
            Button("Revoca ed elimina l'account", role: .destructive) { Task { await deleteAccount() } }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Senza questo consenso CaloScan non può funzionare: revocandolo verranno eliminati l'account e tutti i dati.")
        }
        .alert("Operazione non riuscita",
               isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
               presenting: error) { _ in Button("OK", role: .cancel) {} } message: { Text($0.localizedDescription) }
    }

    private func load() async {
        consents = .loading
        do { consents = .loaded(try await app.services.account.consents()) }
        catch { consents = .failed(APIError.from(error)) }
    }

    private func update(_ state: ConsentState) async {
        let previous = consents
        consents = .loaded(state)
        do { try await app.services.account.update(consents: state) }
        catch { consents = previous; self.error = APIError.from(error) }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do { exportURL = try await app.services.account.exportData() }
        catch { self.error = APIError.from(error) }
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await app.services.account.deleteAccount()
            try? await app.services.auth.signOut()
        } catch {
            self.error = APIError.from(error)
        }
    }
}
