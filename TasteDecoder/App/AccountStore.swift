import Foundation
import GoogleSignIn
import Observation
import Supabase
import UIKit

/// The signed-in Taste Decoder account (Google sign-in, via Supabase Auth).
/// Signing in is optional: it turns on sync, the Claude proxy and Pinterest import.
@MainActor
@Observable
final class AccountStore {
    struct Account: Equatable {
        let id: UUID
        var name: String?
        var email: String?
        var avatarURL: URL?
    }

    private(set) var account: Account?
    private(set) var isWorking = false
    var errorMessage: String?

    var isConfigured: Bool { Backend.isConfigured }
    var isSignedIn: Bool { account != nil }

    @ObservationIgnored private var listener: Task<Void, Never>?

    init() {
        guard let client = Backend.client else { return }
        if let session = client.auth.currentSession { account = Self.account(from: session.user) }
        listener = Task { [weak self] in
            for await (event, session) in client.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .signedOut:
                    self.account = nil
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let session, !session.isExpired || event != .initialSession {
                        self.account = Self.account(from: session.user)
                    }
                default:
                    break
                }
            }
        }
    }

    func signInWithGoogle() async {
        guard let client = Backend.client else {
            errorMessage = BackendError.notConfigured.localizedDescription
            return
        }
        guard let googleClientID = Backend.googleClientID else {
            errorMessage = "Google sign-in isn't set up in this build (GOOGLE_IOS_CLIENT_ID). See the README."
            return
        }
        guard let presenter = Self.topViewController() else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID)
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google didn't return an ID token. Try again."
                return
            }
            let session = try await client.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(
                provider: .google, idToken: idToken, accessToken: result.user.accessToken.tokenString
            ))
            account = Self.account(from: session.user)
        } catch let error as GIDSignInError where error.code == .canceled {
            // The user closed the Google sheet.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        isWorking = true
        defer { isWorking = false }
        GIDSignIn.sharedInstance.signOut()
        try? await Backend.client?.auth.signOut()
        account = nil
    }

    /// Google Sign-In's redirect back into the app.
    func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: - Helpers

    private static func account(from user: User) -> Account {
        func string(_ key: String) -> String? { user.userMetadata[key]?.stringValue }
        return Account(
            id: user.id,
            name: string("full_name") ?? string("name"),
            email: user.email,
            avatarURL: (string("avatar_url") ?? string("picture")).flatMap(URL.init(string:))
        )
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
