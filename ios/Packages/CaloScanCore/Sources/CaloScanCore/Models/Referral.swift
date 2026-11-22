import Foundation

/// Codice invito personale. Alfabeto senza caratteri ambigui (niente 0/O, 1/I/L).
/// Regole identiche a `normalizeReferralCode` in `supabase/functions/_shared/referral.ts`.
public enum ReferralCode {
    public static let alphabet: Set<Character> = Set("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    public static let length = 8

    /// Normalizza quanto inserito dall'utente ("abcd-2345", " ABCD 2345 ") nel formato salvato.
    /// Nil se il codice non può essere valido.
    public static func normalize(_ input: String) -> String? {
        let cleaned = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count == length, cleaned.allSatisfy(alphabet.contains) else { return nil }
        return cleaned
    }

    /// "ABCD2345" → "ABCD-2345", più leggibile da dettare o copiare.
    public static func formatted(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(4))-\(code.suffix(4))"
    }
}

/// Stato del programma "Invita un amico" per l'utente.
///
/// Regole (applicate solo dal server, vedi `docs/ARCHITECTURE.md` › Inviti):
/// - l'amico inserisce il codice entro 14 giorni dalla creazione del suo account, una sola volta;
/// - l'invito conta quando l'amico completa l'onboarding e registra almeno un pasto;
/// - chi invita riceve **un solo** sconto sul primo mese, non accumulabile, sotto forma di
///   codice offerta Apple monouso (solo se non è mai stato abbonato).
public struct ReferralStatus: Codable, Equatable, Sendable {
    public enum RewardState: String, Codable, Sendable {
        /// Ancora nessun amico ha completato i requisiti.
        case waiting
        /// Codice offerta assegnato, da riscattare.
        case available
        /// Codice già riscattato.
        case redeemed
        /// L'utente è già stato abbonato: lo sconto sul primo mese non si applica.
        case notEligible = "not_eligible"
    }

    public var code: String
    public var shareURL: URL
    public var invitedCount: Int
    public var qualifiedCount: Int
    public var reward: RewardState
    /// Codice offerta Apple monouso, presente solo con `reward == .available`.
    public var offerCode: String?
    public var offerExpiresAt: Date?
    /// Sconto del primo mese come lo mostra il server, es. "50%".
    public var discountLabel: String
    /// `true` se l'utente può ancora inserire il codice di un amico che lo ha invitato.
    public var canEnterCode: Bool
    public var wasReferred: Bool

    public init(code: String, shareURL: URL, invitedCount: Int = 0, qualifiedCount: Int = 0,
                reward: RewardState = .waiting, offerCode: String? = nil, offerExpiresAt: Date? = nil,
                discountLabel: String, canEnterCode: Bool = false, wasReferred: Bool = false) {
        self.code = code; self.shareURL = shareURL; self.invitedCount = invitedCount
        self.qualifiedCount = qualifiedCount; self.reward = reward; self.offerCode = offerCode
        self.offerExpiresAt = offerExpiresAt; self.discountLabel = discountLabel
        self.canEnterCode = canEnterCode; self.wasReferred = wasReferred
    }

    /// Link di Apple che apre il riscatto con il codice già compilato.
    public func redeemURL(appStoreID: String) -> URL? {
        guard let offerCode, !appStoreID.isEmpty else { return nil }
        var c = URLComponents(string: "https://apps.apple.com/redeem")
        c?.queryItems = [.init(name: "ctx", value: "offercodes"), .init(name: "id", value: appStoreID),
                         .init(name: "code", value: offerCode)]
        return c?.url
    }
}

/// Esito dell'inserimento del codice di un amico. Stessi valori di `ApplyReferralResult` (TS).
public enum ReferralApplyResult: String, Codable, Sendable {
    case applied
    case invalidCode = "invalid_code"
    case ownCode = "own_code"
    case alreadyReferred = "already_referred"
    case tooLate = "too_late"
}
