import SwiftUI

@main
struct CaloScanApp: App {
    /// Se la configurazione manca l'app lo dice chiaramente invece di fallire in modo silenzioso.
    private let bootstrap: Result<AppState, Error>

    init() {
        // `App` è isolato sul MainActor, quindi lo stato può essere creato qui.
        bootstrap = Result { try Self.makeState() }
        Log.app.info("CaloScan avviata")
    }

    private static func makeState() throws -> AppState {
        #if DEBUG
        // Modalità anteprima per sviluppo e UI test: servizi in memoria con dati d'esempio.
        // Si attiva solo nelle build Debug con l'argomento di avvio `-PreviewMode`; mai in Release.
        if ProcessInfo.processInfo.arguments.contains("-PreviewMode") {
            return AppState(services: .preview())
        }
        #endif
        let container = AppContainer(config: try AppConfig.load())
        return AppState(services: .live(container: container))
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case .success(let state):
                RootView().environment(state)
            case .failure(let error):
                ConfigurationErrorView(message: error.localizedDescription)
            }
        }
    }
}
