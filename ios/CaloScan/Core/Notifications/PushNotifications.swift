import UIKit
import UserNotifications

/// Registrazione del token APNs sul backend. Il server lo usa per il report settimanale e i suggerimenti
/// (Fase 9); i promemoria quotidiani restano notifiche locali e non richiedono il token.
protocol PushTokenService: Sendable {
    func register(deviceToken: String, environment: PushEnvironment) async throws
    func unregister() async throws
}

enum PushEnvironment: String, Sendable { case sandbox, production }

/// Categorie con azioni rapide (tenendo premuta la notifica).
enum NotificationCategory {
    static let mealReminder = "MEAL_REMINDER"
    static let weighIn = "WEIGH_IN"
    static let report = "REPORT"

    enum Action {
        static let scan = "SCAN_MEAL"
        static let openDiary = "OPEN_DIARY"
        static let logWeight = "LOG_WEIGHT"
    }

    static func register() {
        let scan = UNNotificationAction(identifier: Action.scan, title: String(localized: "Scansiona il piatto"),
                                        options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "camera.viewfinder"))
        let diary = UNNotificationAction(identifier: Action.openDiary, title: String(localized: "Apri il diario"),
                                         options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "book.closed"))
        let weight = UNNotificationAction(identifier: Action.logWeight, title: String(localized: "Registra il peso"),
                                          options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "scalemass"))
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: mealReminder, actions: [scan, diary], intentIdentifiers: []),
            UNNotificationCategory(identifier: weighIn, actions: [weight], intentIdentifiers: []),
            UNNotificationCategory(identifier: report, actions: [diary], intentIdentifiers: []),
        ])
    }
}

/// Delegato dell'app per APNs e per le notifiche ricevute.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Impostato da `CaloScanApp` all'avvio.
    nonisolated(unsafe) static var pushService: (any PushTokenService)?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationCategory.register()
        // Se l'utente ha già autorizzato le notifiche, il token viene rinnovato a ogni avvio.
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status == .authorized || status == .provisional {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let environment = PushEnvironment.sandbox
        #else
        let environment = PushEnvironment.production
        #endif
        Task {
            do { try await Self.pushService?.register(deviceToken: token, environment: environment) }
            catch { Log.app.error("Registrazione token push fallita") }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.app.error("APNs non disponibile: \(error.localizedDescription, privacy: .public)")
    }

    /// Notifica arrivata con l'app aperta: mostrata come banner, come fanno le app di sistema.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Tocco sulla notifica o su un'azione rapida: apre la schermata corrispondente.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let route = response.notification.request.content.userInfo["route"] as? String
        let link: DeepLink? = switch response.actionIdentifier {
        case NotificationCategory.Action.scan: .scanner
        case NotificationCategory.Action.openDiary: .diary
        case NotificationCategory.Action.logWeight: .logWeight
        default: route.flatMap(DeepLink.init(rawValue:))
        }
        guard let link else { return }
        await MainActor.run { DeepLinkRouter.shared.open(link) }
    }
}

enum PushPermission {
    /// Chiede il permesso (solo dopo un'azione esplicita dell'utente) e registra il dispositivo su APNs.
    @MainActor
    static func request() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }
}
