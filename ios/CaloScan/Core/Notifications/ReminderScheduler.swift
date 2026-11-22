import Foundation
import UserNotifications

/// Promemoria locali (nessun dato lascia il dispositivo). Tutti disattivati di default;
/// al massimo un promemoria per tipo, con orari scelti dall'utente.
struct ReminderSettings: Codable, Equatable, Sendable {
    var breakfast = Reminder(enabled: false, hour: 8, minute: 30)
    var lunch = Reminder(enabled: false, hour: 13, minute: 0)
    var dinner = Reminder(enabled: false, hour: 20, minute: 0)
    var dailySummary = Reminder(enabled: false, hour: 21, minute: 30)
    /// Settimanale, il lunedì.
    var weighIn = Reminder(enabled: false, hour: 8, minute: 0)

    struct Reminder: Codable, Equatable, Sendable {
        var enabled: Bool
        var hour: Int
        var minute: Int
    }

    private static let key = "reminderSettings.v1"

    static func load(from defaults: UserDefaults = .standard) -> ReminderSettings {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(ReminderSettings.self, from: data) else { return ReminderSettings() }
        return value
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    var anyEnabled: Bool { [breakfast, lunch, dinner, dailySummary, weighIn].contains { $0.enabled } }
}

enum ReminderScheduler {
    private static let ids = ["reminder.breakfast", "reminder.lunch", "reminder.dinner", "reminder.summary", "reminder.weighin"]

    /// Chiede il permesso solo quando l'utente attiva un promemoria.
    @MainActor
    static func requestAuthorization() async -> Bool {
        await PushPermission.request()
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Sostituisce tutti i promemoria con quelli attivi nelle impostazioni.
    static func apply(_ settings: ReminderSettings) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard settings.anyEnabled else { return }

        let items: [(String, ReminderSettings.Reminder, String, String, Int?)] = [
            (ids[0], settings.breakfast, String(localized: "Colazione"), String(localized: "Ricordati di registrare la colazione."), nil),
            (ids[1], settings.lunch, String(localized: "Pranzo"), String(localized: "Hai pranzato? Registra il pasto in pochi secondi."), nil),
            (ids[2], settings.dinner, String(localized: "Cena"), String(localized: "Ricordati di registrare la cena."), nil),
            (ids[3], settings.dailySummary, String(localized: "Riepilogo della giornata"), String(localized: "Dai un'occhiata a come è andata oggi."), nil),
            (ids[4], settings.weighIn, String(localized: "Aggiorna il peso"), String(localized: "È il momento della pesata settimanale."), 2),
        ]
        for (id, reminder, title, body, weekday) in items where reminder.enabled {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            switch id {
            case ids[4]:
                content.categoryIdentifier = NotificationCategory.weighIn
                content.userInfo = ["route": DeepLink.logWeight.rawValue]
            case ids[3]:
                content.categoryIdentifier = NotificationCategory.report
                content.userInfo = ["route": DeepLink.diary.rawValue]
            default:
                content.categoryIdentifier = NotificationCategory.mealReminder
                content.userInfo = ["route": DeepLink.scanner.rawValue]
            }
            var components = DateComponents()
            components.hour = reminder.hour
            components.minute = reminder.minute
            components.weekday = weekday
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
