import XCTest

/// Apre ogni sezione in modalità anteprima (dati d'esempio, nessun server), scorre fino in fondo e
/// salva uno screenshot. In CI le immagini finiscono tra gli artifact della build (cartella SCREENSHOT_DIR).
final class ScreensUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testScrollToBottomOfEveryTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PreviewMode"]
        app.launch()
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 20))
        save(app, "0-home-top")

        for (index, title) in ["Home", "Diario", "Progressi", "Profilo"].enumerated() {
            let tab = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
            if tab.waitForExistence(timeout: 5) { tab.tap() }
            sleep(1)
            for _ in 0..<8 { app.swipeUp(velocity: .fast) }
            sleep(1)
            save(app, "\(index + 1)-\(title.lowercased())-bottom")
        }
    }

    @MainActor
    private func save(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: url)
        }
    }
}
