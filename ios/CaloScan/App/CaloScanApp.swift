import SwiftUI

@main
struct CaloScanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Se la configurazione manca l'app lo dice chiaramente invece di fallire in modo silenzioso.
    private let bootstrap: Result<AppState, Error>

    init() {
        // `App` è isolato sul MainActor, quindi lo stato può essere creato qui.
        bootstrap = Result { try Self.makeState() }
        if case .success(let state) = bootstrap { AppDelegate.pushService = state.services.push }
        Log.app.info("CaloScan avviata")
    }

    private static func makeState() throws -> AppState {
        #if DEBUG
        // Modalità anteprima per sviluppo e UI test: servizi in memoria con dati d'esempio.
        // Si attiva solo nelle build Debug con l'argomento di avvio `-PreviewMode`; mai in Release.
        if ProcessInfo.processInfo.arguments.contains("-PreviewMode") {
            let state = AppState(services: .preview())
            // `-PreviewCelebration big|small`: mostra subito una festa o un pop-up (solo per gli screenshot dei test).
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-PreviewCelebration"), i + 1 < args.count {
                let defaults = UserDefaults.standard
                for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("celebrations.") && key != CelebrationCenter.enabledKey {
                    defaults.removeObject(forKey: key)
                }
                state.celebrations.offer(args[i + 1] == "big" ? [.streak(7)] : [.habitTip(2)], delay: .seconds(2))
            }
            return state
        }
        #endif
        let container = AppContainer(config: try AppConfig.load())
        return AppState(services: .live(container: container))
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case .success(let state):
                RootView()
                    .environment(state)
                    .toastOverlay(state.toasts)
                    .celebrationOverlay(state.celebrations)
                    .onOpenURL { url in
                        if GoogleSignInCoordinator.handle(url) { return }
                        Task { await state.open(url) }
                    }
            case .failure(let error):
                ConfigurationErrorView(message: error.localizedDescription)
            }
        }
    }
}
