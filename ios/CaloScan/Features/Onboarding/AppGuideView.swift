import SwiftUI

/// Guida a tutte le funzioni e ai pulsanti dell'app. Mostrata alla fine dell'onboarding
/// e riapribile da Profilo → Guida all'app. Si può saltare in qualsiasi momento.
struct AppGuideView: View {
    let onFinish: () -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages = GuidePage.all

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pagina \(page + 1) di \(pages.count)")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.textTertiary)
                Spacer()
                if page < pages.count - 1 {
                    Button("Salta", action: onFinish).font(DS.Font.callout.weight(.semibold))
                }
            }
            .padding(.horizontal, DS.Spacing.screen)
            .frame(minHeight: 44)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, guide in
                    GuidePageView(page: guide).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(page == pages.count - 1 ? "Inizia a usare CaloScan" : "Avanti") {
                if page == pages.count - 1 { onFinish() }
                else { withMotion(reduceMotion: reduceMotion) { page += 1 } }
            }
            .buttonStyle(.primary)
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.vertical, DS.Spacing.s)
        }
        .background(DS.Palette.background.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: page)
    }
}

private struct GuidePageView: View {
    let page: GuidePage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                Image(systemName: page.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(DS.Palette.brand)
                    .frame(width: 68, height: 68)
                    .background(DS.Palette.brandSoft, in: .rect(cornerRadius: DS.Radius.l))
                    .accessibilityHidden(true)
                Text(page.title).font(DS.Font.title).accessibilityAddTraits(.isHeader)
                Text(page.intro).font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    ForEach(Array(page.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: DS.Spacing.s) {
                            Image(systemName: item.symbol)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(DS.Palette.brand)
                                .frame(width: 32, height: 32)
                                .background(DS.Palette.surface, in: .rect(cornerRadius: DS.Radius.s))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(DS.Font.callout.weight(.semibold))
                                Text(item.text).font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.bottom, DS.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct GuidePage: Identifiable {
    struct Item {
        let symbol: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey
    }

    let symbol: String
    let title: LocalizedStringKey
    let intro: LocalizedStringKey
    let items: [Item]
    var id: String { symbol }

    static let all: [GuidePage] = [
        GuidePage(symbol: "house.fill", title: "Home: la tua giornata",
                  intro: "Appena apri l'app vedi a che punto sei oggi.",
                  items: [
                    Item(symbol: "circle.dashed", title: "Anello delle calorie",
                         text: "Al centro le calorie che ti restano; accanto obiettivo, calorie consumate e percentuale raggiunta."),
                    Item(symbol: "chart.bar.fill", title: "Barre dei macronutrienti",
                         text: "Proteine, carboidrati e grassi di oggi rispetto al tuo obiettivo."),
                    Item(symbol: "camera.viewfinder", title: "Scansiona il tuo piatto",
                         text: "Il pulsante verde apre la fotocamera. Sotto vedi quante scansioni AI ti restano oggi."),
                    Item(symbol: "sparkles", title: "Consiglio del coach",
                         text: "Un suggerimento sui tuoi dati di oggi. Toccalo per parlare con il coach."),
                    Item(symbol: "plus.circle.fill", title: "Pasti del giorno",
                         text: "Colazione, pranzo, cena e spuntini. Il + aggiunge un alimento cercandolo nel database."),
                    Item(symbol: "crown", title: "Icona in alto: piani",
                         text: "La corona porta subito ai piani Plus e Pro, o alla gestione dell'abbonamento."),
                    Item(symbol: "sparkles", title: "Icona in alto: coach",
                         text: "Apre l'AI Nutrition Coach da qualsiasi momento."),
                  ]),
        GuidePage(symbol: "camera.viewfinder", title: "Scanner",
                  intro: "Il pulsante centrale della barra in basso. Fotografa il piatto e l'AI riconosce gli alimenti; i valori nutrizionali arrivano dai database USDA e Open Food Facts.",
                  items: [
                    Item(symbol: "circle.inset.filled", title: "Scatta",
                         text: "Inquadra il piatto dall'alto con una buona luce e tocca il pulsante bianco."),
                    Item(symbol: "photo.on.rectangle", title: "Galleria",
                         text: "A sinistra: usa una foto che hai già scattato."),
                    Item(symbol: "magnifyingglass", title: "Cerca a mano",
                         text: "A destra: cerca l'alimento per nome senza usare la foto."),
                    Item(symbol: "text.bubble", title: "Descrivi a parole",
                         text: "Scrivi cosa hai mangiato, per esempio \"pasta al pomodoro, un piatto medio\". Utile anche se la foto non viene riconosciuta."),
                    Item(symbol: "slider.horizontal.3", title: "Controlla il risultato",
                         text: "Correggi i grammi con − e +, tocca un alimento per sostituirlo, aggiungi ingredienti o elimina con uno swipe. Scegli il pasto e conferma."),
                    Item(symbol: "party.popper", title: "Segna come sgarro",
                         text: "Se vuoi, prima di salvare indica che è uno sgarro: conta nelle calorie e lo vedi a parte nelle statistiche."),
                  ]),
        GuidePage(symbol: "book.closed.fill", title: "Diario",
                  intro: "Tutto quello che hai mangiato, giorno per giorno, con le statistiche.",
                  items: [
                    Item(symbol: "rectangle.split.3x1", title: "Giorno, Settimana, Mese",
                         text: "In alto scegli la vista: dettaglio del giorno, medie della settimana o andamento del mese."),
                    Item(symbol: "chevron.left.chevron.right", title: "Frecce",
                         text: "Passi al giorno, alla settimana o al mese precedente e successivo."),
                    Item(symbol: "calendar", title: "Calendario",
                         text: "L'icona in alto apre il calendario: i giorni con un puntino hanno pasti registrati."),
                    Item(symbol: "hand.tap", title: "Tieni premuto un alimento",
                         text: "Per segnare il pasto come sgarro o eliminarlo."),
                    Item(symbol: "list.clipboard", title: "Registra come da piano",
                         text: "Se hai inserito il piano del medico, i pasti previsti si registrano con un tocco, correggendo i grammi se serve."),
                  ]),
        GuidePage(symbol: "chart.line.uptrend.xyaxis", title: "Progressi",
                  intro: "Il tuo percorso nel tempo.",
                  items: [
                    Item(symbol: "scalemass.fill", title: "Peso",
                         text: "Registra il peso e guarda il grafico avvicinarsi all'obiettivo."),
                    Item(symbol: "ruler.fill", title: "Misure",
                         text: "Vita, fianchi e altre misure del corpo, se vuoi tenerne traccia."),
                    Item(symbol: "flag.checkered", title: "Obiettivo",
                         text: "Quanto manca al peso desiderato, con un ritmo graduale e sicuro."),
                  ]),
        GuidePage(symbol: "sparkles", title: "AI Nutrition Coach",
                  intro: "Un assistente basato sull'intelligenza artificiale che conosce i tuoi dati. Dà consigli informativi e non sostituisce medico o dietista.",
                  items: [
                    Item(symbol: "text.bubble", title: "Fai una domanda",
                         text: "Per esempio \"Quante calorie mi restano?\" o \"Cosa mangio stasera?\". Puoi anche toccare i suggerimenti."),
                    Item(symbol: "number", title: "Messaggi del giorno",
                         text: "Sotto la casella vedi quanti messaggi ti restano oggi con il tuo piano."),
                  ]),
        GuidePage(symbol: "person.crop.circle.fill", title: "Profilo e impostazioni",
                  intro: "I tuoi dati, gli obiettivi e tutte le preferenze.",
                  items: [
                    Item(symbol: "person.text.rectangle", title: "Dati personali",
                         text: "Modifica peso, altezza, attività e obiettivo: le calorie vengono ricalcolate."),
                    Item(symbol: "target", title: "Obiettivi",
                         text: "Cambia calorie e ripartizione dei macronutrienti, sempre entro limiti sicuri."),
                    Item(symbol: "stethoscope", title: "Piano del medico o dietista",
                         text: "Inserisci calorie, macronutrienti, indicazioni e i pasti con le grammature: diventano il tuo obiettivo."),
                    Item(symbol: "bell.badge", title: "Promemoria e notifiche",
                         text: "In Impostazioni attivi i promemoria dei pasti, del peso e il report settimanale. Sono tutti spenti finché non li accendi."),
                    Item(symbol: "hand.raised.fill", title: "Privacy e account",
                         text: "Gestisci i consensi, esporta i tuoi dati o elimina l'account."),
                    Item(symbol: "questionmark.circle", title: "Guida all'app",
                         text: "Questa guida resta sempre disponibile dal Profilo."),
                  ]),
        GuidePage(symbol: "crown.fill", title: "Piani Free, Plus e Pro",
                  intro: "Puoi usare CaloScan gratis. Con Plus e Pro hai più scansioni e funzioni avanzate, con abbonamento mensile o annuale gestito da Apple.",
                  items: [
                    Item(symbol: "gift", title: "Free",
                         text: "Diario, calcolo del fabbisogno, 3 scansioni AI e 5 messaggi al coach al giorno."),
                    Item(symbol: "star.fill", title: "Plus",
                         text: "20 scansioni al giorno, statistiche complete, consigli personalizzati e analisi delle abitudini."),
                    Item(symbol: "crown.fill", title: "Pro",
                         text: "100 scansioni al giorno, coach avanzato, piani pasto, ricette, lista della spesa e report avanzati."),
                    Item(symbol: "arrow.clockwise", title: "Ripristina acquisti",
                         text: "Se cambi iPhone, l'abbonamento si recupera dalla schermata dei piani."),
                  ]),
    ]
}
