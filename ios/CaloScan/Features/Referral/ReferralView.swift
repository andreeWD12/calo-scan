import SwiftUI
import UIKit
import CaloScanCore

@Observable
@MainActor
final class ReferralViewModel {
    private(set) var state: Loadable<ReferralStatus> = .idle
    private let services: AppServices

    init(services: AppServices) { self.services = services }

    var status: ReferralStatus? { state.value }

    func load() async {
        if state.value == nil { state = .loading }
        do { state = .loaded(try await services.referrals.referralStatus()) }
        catch { state = .failed(APIError.from(error)) }
    }

    /// Messaggio condiviso: link e codice. Nessun contatto viene letto o caricato dall'app.
    func shareMessage(_ s: ReferralStatus) -> String {
        String(localized: "Sto usando CaloScan per tenere traccia di quello che mangio: fotografi il piatto e ti stima calorie e macro. Scaricala da qui: \(s.shareURL.absoluteString) e quando ti iscrivi inserisci il mio codice \(ReferralCode.formatted(s.code)).")
    }
}

/// "Invita un amico": codice personale, condivisione e premio.
/// Il premio è uno sconto sul primo mese, uno solo e non accumulabile, consegnato come codice offerta Apple.
struct ReferralView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var model: ReferralViewModel
    @State private var copied = false

    init(services: AppServices) {
        _model = State(initialValue: ReferralViewModel(services: services))
    }

    var body: some View {
        List {
            switch model.state {
            case .idle, .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case .failed(let error):
                Section { ErrorStateView(error: error) { Task { await model.load() } } }
            case .empty:
                EmptyView()
            case .loaded(let s):
                header(s)
                codeSection(s)
                rewardSection(s)
                if s.canEnterCode {
                    Section {
                        InviteCodeEntry(services: app.services) { Task { await model.load() } }
                    } header: {
                        Text("Ti ha invitato qualcuno?")
                    } footer: {
                        Text("Puoi inserire il codice di un amico entro 14 giorni dall'iscrizione.")
                    }
                }
                rulesSection(s)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Invita un amico")
        .task { await model.load() }
        .refreshable { await model.load() }
        .sensoryFeedback(.success, trigger: copied)
    }

    private func header(_ s: ReferralStatus) -> some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Image(systemName: "person.2.fill").font(.largeTitle).foregroundStyle(DS.Palette.brand)
                Text("Invita un amico, ottieni il \(s.discountLabel) sul primo mese")
                    .font(DS.Font.headline)
                Text("Quando un amico si iscrive con il tuo codice e inizia a usare CaloScan, ricevi uno sconto sul primo mese di Plus o Pro.")
                    .font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
            }
            .padding(.vertical, DS.Spacing.xs)
        }
    }

    private func codeSection(_ s: ReferralStatus) -> some View {
        Section {
            HStack {
                Text(ReferralCode.formatted(s.code))
                    .font(.title2.monospaced().weight(.bold))
                    .textSelection(.enabled)
                    .accessibilityLabel(Text("Il tuo codice: \(s.code.map(String.init).joined(separator: " "))"))
                Spacer()
                Button {
                    UIPasteboard.general.string = ReferralCode.formatted(s.code)
                    copied.toggle()
                    app.toasts.success(String(localized: "Codice copiato"), symbol: "doc.on.doc")
                } label: {
                    Image(systemName: "doc.on.doc").frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Copia il codice"))
            }
            ShareLink(item: model.shareMessage(s)) {
                Label("Condividi l'invito", systemImage: "square.and.arrow.up")
                    .font(DS.Font.callout.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            LabeledContent("Amici iscritti", value: "\(s.invitedCount)")
            LabeledContent("Inviti validi", value: "\(s.qualifiedCount)")
        } header: {
            Text("Il tuo codice")
        } footer: {
            Text("Un invito è valido quando l'amico completa la configurazione e registra il primo pasto. Non vediamo e non chiediamo i tuoi contatti.")
        }
    }

    @ViewBuilder
    private func rewardSection(_ s: ReferralStatus) -> some View {
        Section("Il tuo premio") {
            switch s.reward {
            case .waiting where s.qualifiedCount > 0:
                // Invito valido ma nessun codice offerta ancora disponibile (es. prima dell'approvazione di Apple):
                // il server lo assegna appena ce n'è uno e manda una notifica.
                Label("Hai diritto allo sconto: lo stiamo preparando. Ti avvisiamo con una notifica appena è pronto.",
                      systemImage: "gift")
                    .foregroundStyle(DS.Palette.textSecondary)
            case .waiting:
                Label("In attesa del primo invito valido", systemImage: "hourglass")
                    .foregroundStyle(DS.Palette.textSecondary)
            case .available:
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Label("Sconto del \(s.discountLabel) sul primo mese", systemImage: "gift.fill")
                        .font(DS.Font.headline).foregroundStyle(DS.Palette.brand)
                    if let expires = s.offerExpiresAt {
                        Text("Riscattalo entro il \(expires.formatted(date: .long, time: .omitted)).")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                    }
                }
                if let offer = s.offerCode {
                    LabeledContent("Codice") {
                        Text(offer).font(.body.monospaced()).textSelection(.enabled)
                    }
                }
                if let id = AppConfig.appStoreID, let url = s.redeemURL(appStoreID: id) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Riscatta lo sconto", systemImage: "giftcard.fill")
                            .font(DS.Font.callout.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                } else {
                    RedeemCodeButton(style: .row)
                }
            case .redeemed:
                Label("Sconto già riscattato", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(DS.Palette.brand)
            case .notEligible:
                Label("Sei già abbonato: lo sconto vale solo sul primo mese di abbonamento.", systemImage: "info.circle")
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
    }

    private func rulesSection(_ s: ReferralStatus) -> some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                rule("Ricevi un solo sconto, anche se inviti più amici: non è accumulabile.")
                rule("Lo sconto vale sul primo mese di Plus o Pro, per chi non è mai stato abbonato.")
                rule("Lo sconto si riscatta con Apple e si applica al tuo account App Store.")
                rule("Dopo il primo mese l'abbonamento si rinnova al prezzo pieno, salvo disdetta.")
            }
            .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
            Link("Regolamento completo", destination: LegalLinks.terms)
        } header: {
            Text("Come funziona")
        }
    }

    private func rule(_ text: LocalizedStringKey) -> some View {
        Label { Text(text) } icon: { Image(systemName: "checkmark").foregroundStyle(DS.Palette.brand) }
    }
}

/// Campo per il codice dell'amico che ha invitato l'utente. Usato nell'onboarding e in "Invita un amico".
struct InviteCodeEntry: View {
    let services: AppServices
    var onApplied: (() -> Void)?

    @State private var code = ""
    @State private var isSending = false
    @State private var result: ReferralApplyResult?
    @State private var error: APIError?

    private var normalized: String? { ReferralCode.normalize(code) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if result == .applied {
                Label("Codice dell'amico registrato. Grazie!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DS.Palette.brand)
            } else {
                HStack {
                    TextField("Codice invito (es. ABCD-2345)", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .submitLabel(.done)
                        .onSubmit(apply)
                    Button(action: apply) {
                        if isSending { ProgressView() } else { Text("Applica").fontWeight(.semibold) }
                    }
                    .disabled(normalized == nil || isSending)
                    .frame(minWidth: 44, minHeight: 44)
                }
                if let message {
                    Text(message).font(DS.Font.caption).foregroundStyle(DS.Palette.danger)
                }
            }
        }
        .animation(DS.Motion.snappy, value: result)
    }

    private var message: String? {
        if let error { return error.localizedDescription }
        switch result {
        case .invalidCode: return String(localized: "Codice non valido. Controlla di averlo scritto bene.")
        case .ownCode: return String(localized: "Non puoi usare il tuo codice.")
        case .alreadyReferred: return String(localized: "Hai già inserito il codice di un amico.")
        case .tooLate: return String(localized: "Il codice si può inserire solo entro 14 giorni dall'iscrizione.")
        case .applied, nil: return nil
        }
    }

    private func apply() {
        guard let c = normalized, !isSending else { return }
        isSending = true
        error = nil
        Task {
            defer { isSending = false }
            do {
                result = try await services.referrals.applyReferral(code: c)
                if result == .applied { onApplied?() }
            } catch {
                self.error = APIError.from(error)
            }
        }
    }
}
