import SwiftUI
import UIKit

/// Impostazioni › Assistenza: domande frequenti, email precompilata e pagina web di supporto
/// (contatto richiesto dalla linea guida App Store 1.5).
/// L'email contiene solo versione dell'app, versione di iOS e modello: niente dati sulla salute,
/// a meno che l'utente non li scriva.
struct SupportView: View {
    @Environment(\.openURL) private var openURL
    @State private var noMailApp = false

    var body: some View {
        Form {
            Section {
                ForEach(SupportFAQ.all) { faq in
                    DisclosureGroup {
                        Text(faq.answer).font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
                            .padding(.vertical, DS.Spacing.xxs)
                    } label: {
                        Text(faq.question).font(DS.Font.callout.weight(.semibold))
                    }
                }
            } header: {
                Text("Domande frequenti")
            }

            Section {
                if let email = LegalLinks.supportEmail {
                    Button {
                        writeEmail(to: email)
                    } label: {
                        Label("Scrivici", systemImage: "envelope")
                    }
                    LabeledContent("Email", value: email)
                        .textSelection(.enabled)
                }
                Link(destination: LegalLinks.support) {
                    Label("Pagina di assistenza", systemImage: "safari")
                }
            } header: {
                Text("Contattaci")
            } footer: {
                Text("Per rimborsi degli abbonamenti decide Apple: usa la pagina \"Segnala un problema\" di Apple. Non scriverci dati sulla salute se non servono a risolvere il problema.")
            }
        }
        .navigationTitle("Assistenza")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Nessuna app di posta", isPresented: $noMailApp) {
            if let email = LegalLinks.supportEmail {
                Button("Copia indirizzo") { UIPasteboard.general.string = email }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Scrivici dal tuo programma di posta all'indirizzo \(LegalLinks.supportEmail ?? "").")
        }
    }

    private func writeEmail(to email: String) {
        let body = String(localized: "Descrivi qui il problema:\n\n\n—\nCaloScan \(Bundle.main.appVersion) · iOS \(UIDevice.current.systemVersion) · \(SupportView.deviceModel)")
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = email
        c.queryItems = [URLQueryItem(name: "subject", value: String(localized: "Assistenza CaloScan")),
                        URLQueryItem(name: "body", value: body)]
        guard let url = c.url else { noMailApp = true; return }
        openURL(url) { accepted in if !accepted { noMailApp = true } }
    }

    /// Identificativo del modello (es. "iPhone15,2"): aiuta a riprodurre i problemi, non identifica la persona.
    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

struct SupportFAQ: Identifiable, Sendable {
    let id: Int
    let question: LocalizedStringResource
    let answer: LocalizedStringResource

    static let all: [SupportFAQ] = [
        SupportFAQ(id: 1, question: "Quante scansioni AI ho?",
                   answer: "Free: 3 al giorno. Plus: 20 al giorno. Pro: illimitate. Le analisi non riuscite non vengono contate. Puoi sempre aggiungere un pasto a mano o descriverlo a parole."),
        SupportFAQ(id: 2, question: "I valori di una scansione sono esatti?",
                   answer: "Sono stime: l'AI riconosce gli alimenti e stima le quantità, i valori nutrizionali vengono da USDA e Open Food Facts. Prima di salvare puoi correggere alimenti e grammi."),
        SupportFAQ(id: 3, question: "Come disdico l'abbonamento?",
                   answer: "Da Profilo › Abbonamento › \"Gestisci o disdici su App Store\", oppure da Impostazioni di iPhone › il tuo nome › Abbonamenti. Disdici almeno 24 ore prima del rinnovo: le funzioni restano attive fino alla scadenza."),
        SupportFAQ(id: 4, question: "Ho cambiato iPhone e non vedo il mio abbonamento",
                   answer: "Accedi con lo stesso account CaloScan e lo stesso Apple ID, poi tocca \"Ripristina acquisti\" nella schermata dei piani."),
        SupportFAQ(id: 5, question: "Come uso un codice promozionale o di invito?",
                   answer: "Da Profilo › Abbonamento › \"Riscatta un codice\", oppure dalla schermata dei piani. Il codice si riscatta con Apple."),
        SupportFAQ(id: 6, question: "Come scarico o cancello i miei dati?",
                   answer: "Da Profilo › Privacy e account puoi esportare tutti i tuoi dati, cambiare i consensi ed eliminare l'account con tutti i dati. L'abbonamento Apple va disdetto a parte."),
        SupportFAQ(id: 7, question: "Non ricevo i promemoria",
                   answer: "Controlla che siano attivi in Impostazioni › Promemoria e che le notifiche di CaloScan siano consentite in Impostazioni di iPhone › Notifiche."),
    ]
}
