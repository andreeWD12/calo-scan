import SwiftUI

@main
struct CaloScanApp: App {
    /// Se la configurazione manca l'app lo dice chiaramente invece di fallire in modo silenzioso.
    private let bootstrap: Result<AppContainer, Error>

    init() {
        // `App` è isolato sul MainActor, quindi il container può essere creato qui.
        bootstrap = Result { AppContainer(config: try AppConfig.load()) }
        Log.app.info("CaloScan avviata")
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case .success(let container):
                RootView()
                    .environment(\.container, container)
            case .failure(let error):
                ConfigurationErrorView(message: error.localizedDescription)
            }
        }
    }
}
