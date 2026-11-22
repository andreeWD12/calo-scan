import SwiftUI
import CaloScanCore

extension PregnancyFoodFlag.Risk {
    /// Spiegazione breve e neutra, dalle indicazioni di Ministero della Salute, ISS ed EFSA.
    var advice: String {
        switch self {
        case .toxoplasmosis: String(localized: "Carne cruda e salumi crudi possono trasmettere la toxoplasmosi. Cuoci bene la carne.")
        case .listeria: String(localized: "Può contenere listeria: evitalo crudo o affumicato a freddo, va bene se ben cotto.")
        case .salmonella: String(localized: "Contiene uova crude: scegli versioni con uova cotte o pastorizzate.")
        case .mercury: String(localized: "Pesce che può contenere molto mercurio.")
        case .alcohol: String(localized: "In gravidanza la quantità sicura di alcol è zero.")
        case .caffeine: String(localized: "Contiene caffeina: resta entro 200 mg al giorno (circa 2 tazzine di caffè) in totale.")
        case .vitaminA: String(localized: "Fegato e paté contengono molta vitamina A e possono contenere listeria.")
        case .glycyrrhizin: String(localized: "La liquirizia va consumata con moderazione.")
        }
    }
}

extension PregnancyWeekPlan.Phase {
    /// Consigli della fase, da indicazioni pubbliche (Ministero della Salute, ISS). Nessun integratore o dosaggio.
    var advice: String {
        switch self {
        case .early: String(localized: "Contro la nausea aiutano pasti piccoli e frequenti, anche pane secco o cracker. L'acido folico va preso già da prima del concepimento: dose e durata le indica il medico. Se non conosci l'esito del test sulla toxoplasmosi, chiedilo.")
        case .middle: String(localized: "Il fabbisogno aumenta, ma non serve \"mangiare per due\": basta uno spuntino in più. Ferro da legumi, carne ben cotta e verdure a foglia verde, insieme a frutta ricca di vitamina C. Calcio da latte e yogurt pastorizzati e formaggi a pasta dura.")
        case .late: String(localized: "È il periodo con il fabbisogno più alto. Pasti più piccoli e frequenti aiutano con reflusso e pesantezza. Pesce a basso contenuto di mercurio (salmone, sardine, merluzzo) 2-3 volte a settimana, sempre ben cotto.")
        case .term: String(localized: "Nessuna dieta: pasti regolari, acqua a sufficienza e fibre (frutta, verdura, cereali integrali) contro la stitichezza. Per le ultime settimane segui le indicazioni dell'ostetrica.")
        }
    }
}

/// Come indicare la gravidanza: a che settimana sei (predefinito) oppure la data presunta del parto.
/// In entrambi i casi si salva la data, così la settimana avanza da sola.
struct PregnancyDatingFields: View {
    @Binding var byWeek: Bool
    @Binding var week: Int
    @Binding var dueDate: Date
    let dueDateRange: ClosedRange<Date>

    var body: some View {
        Group {
            Picker("Come vuoi indicarlo", selection: $byWeek) {
                Text("Settimana").tag(true)
                Text("Data del parto").tag(false)
            }
            .pickerStyle(.segmented)
            if byWeek {
                Stepper(value: $week, in: PregnancyInfo.weekRange) {
                    LabeledContent("A che settimana sei?", value: String(localized: "\(week)ª settimana"))
                }
            } else {
                DatePicker("Data presunta del parto", selection: $dueDate, in: dueDateRange, displayedComponents: .date)
            }
        }
    }
}

/// Avviso accanto al nome di un alimento, visibile solo con la modalità gravidanza attiva.
struct PregnancyFoodBadge: View {
    @Environment(AppState.self) private var app
    let name: String
    var showsAdvice = false

    var body: some View {
        if let pregnancy = app.pregnancy, app.hasPregnancyPlan,
           let flag = PregnancyFoodSafety.check(name, toxoplasmosisImmune: pregnancy.toxoplasmosisImmune) {
            VStack(alignment: .leading, spacing: 2) {
                Label(flag.level == .avoid ? "Da evitare in gravidanza" : "Con moderazione in gravidanza",
                      systemImage: flag.level == .avoid ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(flag.level == .avoid ? DS.Palette.danger : DS.Palette.warning)
                if showsAdvice {
                    Text(flag.risk.advice).font(.caption2).foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Profilo › Gravidanza.
/// Per tutti (tutela di sicurezza): mai deficit, niente digiuni, elenco degli alimenti da evitare.
/// Con Plus o Pro (dieta per la gravidanza): energia, proteine e consigli della settimana, avvisi automatici sugli alimenti.
struct PregnancyView: View {
    @Environment(AppState.self) private var app
    @State private var showPaywall = false
    @State private var enabled = false
    @State private var dueDate = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    @State private var byWeek = true
    @State private var week = 12
    /// Giorni oltre la settimana compiuta, per non spostare la data salvata se l'utente non cambia la settimana.
    @State private var extraDays = 0
    @State private var immune: Bool?
    @State private var isSaving = false
    @State private var error: APIError?
    @State private var loaded = false

    private var effectiveDueDate: Date { byWeek ? PregnancyInfo.dueDate(week: week, days: extraDays) : dueDate }
    private var draft: PregnancyInfo? { enabled ? PregnancyInfo(dueDate: effectiveDueDate, toxoplasmosisImmune: immune) : nil }
    private var hasChanges: Bool { draft != app.profile?.pregnancy }

    var body: some View {
        Form {
            Section {
                Toggle("Sono in gravidanza", isOn: $enabled.animation(DS.Motion.snappy))
                if enabled {
                    PregnancyDatingFields(byWeek: $byWeek,
                                          // Se l'utente cambia la settimana, si conta dall'inizio di quella settimana.
                                          week: Binding(get: { week }, set: { week = $0; extraDays = 0 }),
                                          dueDate: $dueDate, dueDateRange: PregnancyInfo.dueDateRange())
                    Picker("Immune alla toxoplasmosi", selection: $immune) {
                        Text("Non lo so").tag(Bool?.none)
                        Text("Sì").tag(Bool?.some(true))
                        Text("No").tag(Bool?.some(false))
                    }
                }
            } footer: {
                Text(enabled
                     ? "L'esito del test sulla toxoplasmosi è nei tuoi esami del primo trimestre. Se non lo sai, consideriamo i salumi crudi da evitare."
                     : "Con la modalità gravidanza CaloScan non imposta mai un deficit calorico né digiuni e ti mostra gli alimenti da evitare. Con Plus anche il fabbisogno per trimestre e gli avvisi automatici sugli alimenti.")
            }

            if let draft {
                let plan = PregnancyNutrition.weekPlan(week: draft.week())
                let tri = plan.trimester
                Section {
                    LabeledContent("Settimana", value: "\(plan.week)ª")
                    LabeledContent("Trimestre", value: "\(tri)º")
                    if app.professionalPlan != nil {
                        Label("Vale il piano del tuo medico o dietista per calorie e macronutrienti.", systemImage: "stethoscope")
                            .font(DS.Font.callout)
                    } else if !app.hasPregnancyPlan {
                        Label("Obiettivo di mantenimento: nessun deficit calorico.", systemImage: "checkmark.shield")
                            .font(DS.Font.callout)
                        pregnancyPlusCard(trimester: tri)
                    } else {
                        LabeledContent("Energia in più al giorno", value: "+\(plan.extraKcal) kcal")
                        LabeledContent("Proteine in più al giorno", value: "+\(plan.extraProteinG) g")
                        if let next = plan.nextChangeWeek, let kcal = plan.nextExtraKcal {
                            Label("Dalla settimana \(next): +\(kcal) kcal al giorno. Gli obiettivi si aggiornano da soli.",
                                  systemImage: "calendar.badge.clock")
                                .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                        }
                    }
                } header: {
                    Text("Il tuo fabbisogno")
                } footer: {
                    Text(app.hasPregnancyPlan
                         ? "Valori di riferimento EFSA aggiunti al tuo fabbisogno di mantenimento. Non è prevista alcuna dieta dimagrante. L'aumento di peso adatto a te lo stabiliscono ginecologo e ostetrica."
                         : "Non è prevista alcuna dieta dimagrante. L'aumento di peso adatto a te lo stabiliscono ginecologo e ostetrica.")
                }

                if app.hasPregnancyPlan {
                    Section("Settimana \(plan.week): cosa conta adesso") {
                        Text(plan.phase.advice).font(DS.Font.callout)
                    }
                }

                Section("Da evitare") {
                    foodGroup("Alcol", "wineglass", "Vino, birra, aperitivi e superalcolici: nessuna quantità è sicura.")
                    foodGroup("Carne cruda o poco cotta", "flame", "Carpaccio, tartare, carne al sangue. Cuoci bene la carne.")
                    foodGroup("Salumi crudi", "fork.knife",
                              immune == true ? "Prosciutto crudo, salame, bresaola: sei immune alla toxoplasmosi, ma restano da limitare per il rischio listeria."
                                             : "Prosciutto crudo, salame, speck, bresaola. I salumi cotti vanno bene.")
                    foodGroup("Pesce crudo e affumicato", "fish", "Sushi, sashimi, ostriche, crudi di mare, salmone affumicato.")
                    foodGroup("Uova crude", "oval.portrait", "Tiramisù, zabaione, maionese fatta in casa. Le uova ben cotte vanno bene.")
                    foodGroup("Latte crudo e alcuni formaggi", "drop", "Latte non pastorizzato, gorgonzola, brie, camembert, taleggio, se non cotti.")
                    foodGroup("Fegato e paté", "exclamationmark.triangle", "Troppa vitamina A e rischio listeria.")
                    foodGroup("Pesci predatori grandi", "water.waves", "Pesce spada, squalo, verdesca, palombo, luccio: troppo mercurio.")
                }
                Section("Con moderazione") {
                    foodGroup("Caffeina", "cup.and.saucer", "Fino a 200 mg al giorno in totale: circa 2 tazzine di caffè. Conta anche tè, cola e cioccolato.")
                    foodGroup("Tonno", "fish", "Al massimo 1-2 porzioni a settimana.")
                    foodGroup("Frutta e verdura crude", "leaf", "Lavale con cura sotto l'acqua corrente.")
                }
                Section {
                    Text(app.hasPregnancyPlan
                         ? "Gli avvisi su scansioni, ricerca alimenti e lista della spesa si basano sul nome dell'alimento e non possono riconoscere tutto: controlla sempre l'etichetta. Integratori (come l'acido folico) e dubbi specifici vanno discussi con ginecologo, ostetrica o medico di base."
                         : "Controlla sempre l'etichetta. Integratori (come l'acido folico) e dubbi specifici vanno discussi con ginecologo, ostetrica o medico di base.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
                    Link("Fonte: Ministero della Salute (sezione Salute della donna › Gravidanza)",
                         destination: URL(string: "https://www.salute.gov.it/")!)
                        .font(DS.Font.caption)
                }
            }
        }
        .navigationTitle("Gravidanza")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") { Task { await save() } }
                    .disabled(!hasChanges || isSaving || (enabled && !PregnancyInfo.isValidDueDate(effectiveDueDate)))
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let p = app.profile?.pregnancy {
                enabled = true; dueDate = p.dueDate; immune = p.toxoplasmosisImmune
                week = min(max(p.week(), PregnancyInfo.weekRange.lowerBound), PregnancyInfo.weekRange.upperBound)
                extraDays = p.extraDays()
            }
        }
        .onChange(of: byWeek) { _, isWeek in
            // Passando da un modo all'altro si parte dalla stessa gravidanza.
            if isWeek {
                let p = PregnancyInfo(dueDate: dueDate)
                week = min(max(p.week(), PregnancyInfo.weekRange.lowerBound), PregnancyInfo.weekRange.upperBound)
                extraDays = p.extraDays()
            } else {
                dueDate = PregnancyInfo.dueDate(week: week, days: extraDays)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(services: app.services, highlight: .plus, showsPregnancyOffer: true)
        }
        .alert("Salvataggio non riuscito",
               isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
               presenting: error) { _ in Button("OK", role: .cancel) {} } message: { Text($0.localizedDescription) }
    }

    /// Invito a Plus per il piano Free. L'offerta del 30% compare nel paywall solo se Apple la concede.
    private func pregnancyPlusCard(trimester: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Label("Dieta per la gravidanza con Plus", systemImage: "lock.fill")
                .font(DS.Font.callout.weight(.semibold))
            Text("Energia, proteine e consigli per la tua settimana, che si aggiornano da soli (ora +\(PregnancyNutrition.extraKcal(trimester: trimester)) kcal e +\(PregnancyNutrition.extraProteinG(trimester: trimester)) g di proteine al giorno), avvisi automatici su scansioni, ricerca e lista della spesa, suggerimenti AI senza gli alimenti da evitare.")
                .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
            Button("Scopri l'offerta") { showPaywall = true }
                .font(DS.Font.callout.weight(.semibold))
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private func foodGroup(_ title: LocalizedStringKey, _ symbol: String, _ text: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.Font.callout.weight(.semibold))
                Text(text).font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(DS.Palette.brand)
        }
    }

    private func save() async {
        guard var profile = app.profile, let targets = app.computedTargets else { return }
        isSaving = true
        defer { isSaving = false }
        profile.pregnancy = draft
        // In gravidanza i digiuni e gli stili restrittivi non sono adatti: lo stile scelto viene rimosso.
        if draft != nil, profile.eatingStyle?.style.isRestrictive == true {
            profile.eatingStyle = nil
            await ReminderScheduler.scheduleEatingWindow(nil)
        }
        do {
            try await app.services.profile.save(profile: profile, targets: targets)
            app.updateProfile(profile, targets: targets)
            app.toasts.success(draft == nil ? String(localized: "Modalità gravidanza disattivata")
                                            : String(localized: "Modalità gravidanza attiva"),
                               symbol: "heart.fill")
        } catch {
            self.error = APIError.from(error)
        }
    }
}
