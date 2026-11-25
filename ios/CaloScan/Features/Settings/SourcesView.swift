import SwiftUI

/// Impostazioni › Fonti scientifiche e metodo.
/// App Store 1.4.1: le app che danno informazioni sulla salute devono indicare le fonti in modo facile da trovare.
/// Elenca da dove vengono formule, valori di riferimento e dati nutrizionali usati dall'app.
struct SourcesView: View {
    struct Source: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        let url: URL
    }

    struct SourceGroup: Identifiable {
        let id = UUID()
        let header: LocalizedStringKey
        let usage: LocalizedStringKey
        let sources: [Source]
    }

    static let groups: [SourceGroup] = [
        SourceGroup(header: "Fabbisogno calorico",
              usage: "Metabolismo basale con la formula di Mifflin-St Jeor, moltiplicato per il livello di attività (da 1,2 a 1,9). Per perdere peso l'app toglie al massimo il 15% (e non più di 500 kcal); non scende mai sotto il metabolismo basale né sotto 1.200 kcal (donne) o 1.500 kcal (uomini), e non propone deficit ai minorenni.",
              sources: [
                Source(title: "Mifflin MD, St Jeor ST et al. (1990)",
                       detail: "A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr 51(2):241-7",
                       url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/")!),
                Source(title: "EFSA (2013) – Valori di riferimento per l'energia",
                       detail: "Livelli di attività fisica (PAL) ed energia aggiuntiva in gravidanza. EFSA Journal 11(1):3005",
                       url: URL(string: "https://doi.org/10.2903/j.efsa.2013.3005")!),
              ]),
        SourceGroup(header: "Proteine, grassi e carboidrati",
              usage: "Proteine da 1,6 a 2,0 g per kg di peso (mai oltre 2,2 g/kg né oltre il 35% delle calorie), grassi intorno al 30% delle calorie, il resto carboidrati.",
              sources: [
                Source(title: "EFSA (2012) – Valori di riferimento per le proteine",
                       detail: "EFSA Journal 10(2):2557",
                       url: URL(string: "https://doi.org/10.2903/j.efsa.2012.2557")!),
                Source(title: "EFSA (2010) – Valori di riferimento per i grassi",
                       detail: "EFSA Journal 8(3):1461",
                       url: URL(string: "https://doi.org/10.2903/j.efsa.2010.1461")!),
                Source(title: "EFSA (2010) – Valori di riferimento per carboidrati e fibre",
                       detail: "EFSA Journal 8(3):1462",
                       url: URL(string: "https://doi.org/10.2903/j.efsa.2010.1462")!),
                Source(title: "Jäger R. et al. (2017) – Proteine e attività fisica",
                       detail: "International Society of Sports Nutrition Position Stand. J Int Soc Sports Nutr 14:20",
                       url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/28642676/")!),
              ]),
        SourceGroup(header: "Peso corporeo",
              usage: "Il peso obiettivo non può corrispondere a un indice di massa corporea (BMI) inferiore a 18,5, la soglia di sottopeso dell'OMS.",
              sources: [
                Source(title: "Organizzazione Mondiale della Sanità – Obesità e sovrappeso",
                       detail: "Classificazione del BMI negli adulti",
                       url: URL(string: "https://www.who.int/news-room/fact-sheets/detail/obesity-and-overweight")!),
              ]),
        SourceGroup(header: "Gravidanza",
              usage: "Energia e proteine aggiuntive per trimestre secondo EFSA; alimenti da evitare e consigli di sicurezza alimentare secondo Ministero della Salute e Istituto Superiore di Sanità; caffeina entro i limiti EFSA. Non sostituisce ginecologo od ostetrica.",
              sources: [
                Source(title: "Ministero della Salute",
                       detail: "Alimentazione e sicurezza alimentare in gravidanza",
                       url: URL(string: "https://www.salute.gov.it/")!),
                Source(title: "EFSA (2015) – Sicurezza della caffeina",
                       detail: "EFSA Journal 13(5):4102",
                       url: URL(string: "https://doi.org/10.2903/j.efsa.2015.4102")!),
              ]),
        SourceGroup(header: "Valori nutrizionali degli alimenti",
              usage: "Calorie e macronutrienti degli alimenti cercati, scansionati o riconosciuti nelle foto. Quando un alimento non si trova, l'app usa una stima dell'intelligenza artificiale e lo indica con l'etichetta \"stima\".",
              sources: [
                Source(title: "USDA FoodData Central",
                       detail: "Dipartimento dell'Agricoltura degli Stati Uniti, dominio pubblico",
                       url: URL(string: "https://fdc.nal.usda.gov/")!),
                Source(title: "Open Food Facts",
                       detail: "Database collaborativo dei prodotti confezionati, licenza ODbL",
                       url: URL(string: "https://world.openfoodfacts.org/")!),
              ]),
    ]

    var body: some View {
        List {
            Section {
                Text("CaloScan è un'app di benessere: dà stime e informazioni generali, non diagnosi né terapie. Per esigenze di salute, gravidanza o disturbi alimentari parla con il medico o con un dietista.")
                    .font(DS.Font.callout).foregroundStyle(DS.Palette.textSecondary)
            }
            ForEach(Self.groups) { group in
                Section {
                    Text(group.usage).font(DS.Font.callout)
                    ForEach(group.sources) { source in
                        Link(destination: source.url) {
                            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                                Text(source.title).font(DS.Font.callout.weight(.semibold))
                                Text(source.detail).font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityHint(Text("Apre la fonte nel browser"))
                    }
                } header: {
                    Text(group.header)
                }
            }
        }
        .navigationTitle("Fonti scientifiche")
        .navigationBarTitleDisplayMode(.inline)
    }
}
