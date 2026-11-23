import OSLog

/// Logger per categoria. Non registrare mai dati personali o sanitari: usa `privacy: .private`.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.andrewnalini.caloscan.app"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let scanner = Logger(subsystem: subsystem, category: "scanner")
    static let purchases = Logger(subsystem: subsystem, category: "purchases")
}
