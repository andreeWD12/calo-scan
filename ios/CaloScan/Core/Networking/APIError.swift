import Foundation

/// Errori applicativi mostrati all'utente. Ogni servizio converte gli errori di rete in questo tipo.
enum APIError: LocalizedError, Equatable {
    case offline
    case unauthorized
    case quotaExceeded(plan: String)
    case planRequired(minimum: String)
    case aiUnavailable
    case invalidInput(String)
    case server(status: Int)
    case decoding
    /// Funzione il cui backend non è ancora collegato (solo durante lo sviluppo per fasi).
    case notConnected
    case unknown

    var errorDescription: String? {
        switch self {
        case .offline: String(localized: "Sei offline. Controlla la connessione e riprova.")
        case .unauthorized: String(localized: "La sessione è scaduta. Accedi di nuovo.")
        case .quotaExceeded: String(localized: "Hai raggiunto il limite di oggi per il tuo piano.")
        case .planRequired(let minimum): String(localized: "Questa funzione richiede il piano \(minimum).")
        case .aiUnavailable: String(localized: "L'analisi non è disponibile in questo momento. Riprova tra poco o inserisci il pasto manualmente.")
        case .invalidInput(let message): message
        case .server: String(localized: "Si è verificato un problema sul server. Riprova.")
        case .decoding: String(localized: "Risposta non valida dal server.")
        case .notConnected: String(localized: "Questa funzione non è ancora collegata al server.")
        case .unknown: String(localized: "Si è verificato un errore imprevisto.")
        }
    }

    /// Solo gli errori transitori meritano un nuovo tentativo automatico.
    var isRetryable: Bool {
        switch self {
        case .offline, .aiUnavailable: true
        case .server(let status): status >= 500
        default: false
        }
    }

    /// Corpo d'errore standard restituito dalle Edge Functions: `{ "error": { "code": "...", ... } }`.
    struct ServerBody: Decodable {
        struct Detail: Decodable { let code: String; let message: String?; let plan: String?; let minimum: String? }
        let error: Detail
    }

    static func from(status: Int, body: Data?) -> APIError {
        if let body, let parsed = try? JSONDecoder().decode(ServerBody.self, from: body) {
            switch parsed.error.code {
            case "unauthorized": return .unauthorized
            case "quota_exceeded": return .quotaExceeded(plan: parsed.error.plan ?? "free")
            case "plan_required": return .planRequired(minimum: parsed.error.minimum ?? "Plus")
            case "ai_unavailable": return .aiUnavailable
            case "invalid_input": return .invalidInput(parsed.error.message ?? "Dati non validi.")
            default: break
            }
        }
        if status == 401 { return .unauthorized }
        return .server(status: status)
    }

    static func from(_ error: Error) -> APIError {
        if let api = error as? APIError { return api }
        if let url = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost].contains(url.code) {
            return .offline
        }
        if error is DecodingError { return .decoding }
        #if DEBUG
        // In sviluppo si mostra l'errore originale (es. di PostgREST o di Auth) per capire subito la causa.
        return .invalidInput(String(localized: "Si è verificato un errore imprevisto.") + "\n[sviluppo] " + String(String(describing: error).prefix(400)))
        #else
        return .unknown
        #endif
    }
}
