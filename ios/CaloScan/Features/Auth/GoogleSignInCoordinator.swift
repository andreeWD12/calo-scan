import UIKit
import GoogleSignIn

/// Ottiene i token Google tramite l'SDK ufficiale; Supabase li verifica lato server.
@MainActor
enum GoogleSignInCoordinator {
    struct Tokens: Sendable { let idToken: String; let accessToken: String }

    enum Failure: Error { case cancelled, notConfigured, noPresenter, missingToken }

    static func signIn() async throws -> Tokens {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty, !clientID.hasPrefix("YOUR-") else { throw Failure.notConfigured }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first?.topMost else { throw Failure.noPresenter }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else { throw Failure.missingToken }
            return Tokens(idToken: idToken, accessToken: result.user.accessToken.tokenString)
        } catch let error as GIDSignInError where error.code == .canceled {
            throw Failure.cancelled
        }
    }

    /// Gestisce il ritorno dall'app/pagina Google (chiamato da `.onOpenURL`).
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}

private extension UIViewController {
    var topMost: UIViewController {
        presentedViewController?.topMost ?? self
    }
}
