import XCTest

/// Screenshot per la pagina App Store, in modalità anteprima (dati d'esempio, nessun server) con il piano Pro attivo.
/// In CI gira su un iPhone "Pro Max" (6,9 pollici, 1320 × 2868), la misura richiesta da App Store Connect,
/// con la barra di stato pulita (9:41, batteria piena). Le immagini finiscono nell'artifact "app-store-screenshots".
/// Si attiva solo con la variabile d'ambiente STORE_SCREENSHOTS=1, così non rallenta la build normale.
final class AppStoreScreenshotsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(ProcessInfo.processInfo.environment["STORE_SCREENSHOTS"] == "1",
                          "Screenshot App Store solo su richiesta (STORE_SCREENSHOTS=1)")
    }

    @MainActor
    func testStoreScreenshots() throws {
        shot("01-home", route: nil)
        scanResult()
        shot("03-diario", route: "diary")
        shot("04-progressi", route: "progress")
        shot("05-coach", route: "coach")
        paywall()
    }

    /// Paywall con i prezzi d'esempio (piano Free): per "Informazioni per la revisione" degli abbonamenti.
    @MainActor
    private func paywall() {
        let app = XCUIApplication()
        app.launchArguments = ["-PreviewMode", "-PreviewPaywall", "-celebrations.enabled", "NO",
                               "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 20))
        sleep(4)
        save(app, "06-abbonamenti")
        app.terminate()
    }

    // MARK: -

    @MainActor
    private func launch(route: String?) -> XCUIApplication {
        let app = XCUIApplication()
        // "-chiave valore" imposta UserDefaults solo per questo avvio: niente feste o pop-up sopra le schermate.
        app.launchArguments = ["-PreviewMode", "-PreviewPlan", "pro", "-celebrations.enabled", "NO",
                               "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        if let route { app.launchArguments += ["-PreviewRoute", route] }
        app.launch()
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 20))
        return app
    }

    @MainActor
    private func shot(_ name: String, route: String?) {
        let app = launch(route: route)
        sleep(3)  // dati caricati e animazioni finite
        save(app, name)
        app.terminate()
    }

    /// Scanner › Descrivi a parole › esempio › Analizza › risultato con alimenti, grammi e valori.
    @MainActor
    private func scanResult() {
        let app = launch(route: "scanner")
        allowSystemAlertIfShown()
        let describe = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Descrivi a parole")).firstMatch
        guard describe.waitForExistence(timeout: 10) else { return XCTFail("Pulsante Descrivi a parole non trovato") }
        describe.tap()
        let example = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Petto di pollo")).firstMatch
        guard example.waitForExistence(timeout: 10) else { return XCTFail("Esempio non trovato") }
        example.tap()
        sleep(1)
        let analyze = app.buttons["Analizza"]
        guard analyze.waitForExistence(timeout: 5) else { return XCTFail("Pulsante Analizza non trovato") }
        analyze.tap()
        let result = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "pollo")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "Risultato della scansione non mostrato")
        sleep(2)
        save(app, "02-scansione")
        app.terminate()
    }

    /// Il simulatore può chiedere il permesso della fotocamera: lo si accetta per arrivare alla schermata.
    @MainActor
    private func allowSystemAlertIfShown() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 4) else { return }
        for label in ["Allow", "OK", "Consenti"] where alert.buttons[label].exists {
            alert.buttons[label].tap()
            return
        }
        alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
    }

    @MainActor
    private func save(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
