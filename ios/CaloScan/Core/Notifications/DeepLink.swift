import Foundation
import Observation

/// Destinazioni raggiungibili da una notifica (campo `route` nel payload) o da un URL `caloscan://`.
enum DeepLink: String, Sendable {
    case home, diary, scanner, progress, profile, coach, logWeight = "log-weight"
    case professionalPlan = "professional-plan"

    init?(url: URL) {
        guard url.scheme == "caloscan", let host = url.host() else { return nil }
        self.init(rawValue: host)
    }
}

/// Ponte tra il delegato delle notifiche (UIKit) e la navigazione SwiftUI.
@Observable
@MainActor
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()
    /// Ultima destinazione richiesta; la navigazione la consuma e la azzera.
    var pending: DeepLink?

    func open(_ link: DeepLink) { pending = link }
}
