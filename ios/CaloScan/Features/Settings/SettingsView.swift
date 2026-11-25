import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self { case .system: "Automatico"; case .light: "Chiaro"; case .dark: "Scuro" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

/// Impostazioni: aspetto, promemoria, informazioni sull'app.
struct SettingsView: View {
    @AppStorage("appearance") private var appearance: AppearancePreference = .system
    @State private var reminders = ReminderSettings.load()
    @State private var permissionDenied = false
    /// Notifiche push dal server: report settimanale e suggerimenti (massimo 2 a settimana).
    @AppStorage("push.weeklyReport") private var weeklyReport = false
    @AppStorage("push.tips") private var tips = false
    /// Feste per i traguardi e pop-up di incoraggiamento (`CelebrationCenter`).
    @AppStorage(CelebrationCenter.enabledKey) private var celebrations = true

    var body: some View {
        Form {
            Section {
                Picker("Tema", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Animazioni per i traguardi", isOn: $celebrations)
            } header: {
                Text("Aspetto")
            } footer: {
                Text("Festeggia gli obiettivi raggiunti e mostra brevi incoraggiamenti e consigli sulle abitudini (al massimo tre al giorno).")
            }
            Section {
                reminderRow("Colazione", $reminders.breakfast)
                reminderRow("Pranzo", $reminders.lunch)
                reminderRow("Cena", $reminders.dinner)
                reminderRow("Riepilogo giornaliero", $reminders.dailySummary)
                reminderRow("Pesata settimanale (lunedì)", $reminders.weighIn)
            } header: {
                Text("Promemoria")
            } footer: {
                if permissionDenied {
                    Text("Le notifiche sono disattivate per CaloScan. Puoi attivarle in Impostazioni di iOS → Notifiche.")
                } else {
                    Text("Tutti i promemoria sono facoltativi e generati sul dispositivo. Attiva solo quelli che ti sono utili.")
                }
            }
            Section {
                Toggle("Report settimanale", isOn: $weeklyReport)
                Toggle("Suggerimenti del coach", isOn: $tips)
            } header: {
                Text("Notifiche push")
            } footer: {
                Text("Al massimo due notifiche a settimana, mai pubblicitarie. Il report arriva la domenica sera.")
            }
            .onChange(of: weeklyReport || tips) { _, wantsPush in
                guard wantsPush else { return }
                Task { permissionDenied = !(await PushPermission.request()) }
            }

            Section("Informazioni") {
                LabeledContent("Versione", value: Bundle.main.appVersion)
                Link("Termini di servizio", destination: LegalLinks.terms)
                Link("Informativa sulla privacy", destination: LegalLinks.privacyPolicy)
                NavigationLink("Fonti scientifiche e metodo") { SourcesView() }
                NavigationLink("Assistenza") { SupportView() }
            }
            Section {
                Text("I valori nutrizionali provengono da USDA FoodData Central e Open Food Facts (licenza ODbL); formule e valori di riferimento sono in “Fonti scientifiche e metodo”. Le stime da foto e i consigli del coach sono generati dall'intelligenza artificiale e possono contenere errori.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .navigationTitle("Impostazioni")
        .onChange(of: reminders) { _, new in
            Task {
                if new.anyEnabled {
                    if await ReminderScheduler.authorizationStatus() == .notDetermined {
                        _ = await ReminderScheduler.requestAuthorization()
                    }
                    permissionDenied = await ReminderScheduler.authorizationStatus() == .denied
                }
                new.save()
                await ReminderScheduler.apply(new)
            }
        }
        .task { permissionDenied = await ReminderScheduler.authorizationStatus() == .denied }
    }

    private func reminderRow(_ title: LocalizedStringKey, _ reminder: Binding<ReminderSettings.Reminder>) -> some View {
        VStack(alignment: .leading) {
            Toggle(title, isOn: reminder.enabled)
            if reminder.wrappedValue.enabled {
                DatePicker("Orario", selection: Binding(
                    get: {
                        Calendar.current.date(bySettingHour: reminder.wrappedValue.hour,
                                              minute: reminder.wrappedValue.minute, second: 0, of: .now) ?? .now
                    },
                    set: { date in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                        reminder.wrappedValue.hour = c.hour ?? 0
                        reminder.wrappedValue.minute = c.minute ?? 0
                    }), displayedComponents: .hourAndMinute)
                    .font(DS.Font.callout)
            }
        }
    }
}

extension Bundle {
    var appVersion: String {
        let v = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let b = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "\(v) (\(b))"
    }
}
