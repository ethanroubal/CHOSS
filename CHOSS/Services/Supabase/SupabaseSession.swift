#if canImport(Supabase)
import Foundation
import Observation
import Supabase
import CryptoKit
import AuthenticationServices

/// The signed-in state for the Supabase backend: who's signed in, and signing in / out.
/// Supabase keeps the session in the Keychain and refreshes it, so people stay signed in.
@MainActor
@Observable
final class SupabaseSession {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(userID: String)
    }

    let client: SupabaseClient
    let environment: BackendEnvironment
    private(set) var state: State = .loading
    /// Signed in through a password-reset link: the app shows the "choose a new password"
    /// screen until it's done. Only a reset link (see `handleOpenURL`) sets this.
    private(set) var isResettingPassword = false
    private(set) var email: String?
    var errorMessage: String?
    var isWorking = false

    init(environment: BackendEnvironment) {
        self.environment = environment
        client = SupabaseClient(
            supabaseURL: environment.supabaseURL!,
            supabaseKey: environment.publishableKey!,
            // Emit the saved session as-is at launch (`listenForChanges` already treats an
            // expired one as signed out). Opts in to the library's upcoming behaviour and
            // silences its warning in the console.
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
        Task { await listenForChanges() }
    }

    /// Follows sign-in / sign-out / token refresh, starting with the saved session (if any).
    private func listenForChanges() async {
        for await (event, session) in client.auth.authStateChanges {
            if event == .passwordRecovery { isResettingPassword = true }
            if let session, !session.isExpired {
                // Postgres prints uuids in lowercase; keep ids comparable with what it returns.
                state = .signedIn(userID: session.user.id.uuidString.lowercased())
                email = session.user.email
            } else {
                state = .signedOut
                email = nil
            }
        }
    }

    // MARK: Sign in with Apple

    /// A random nonce: its SHA-256 goes in the Apple request, the raw value to Supabase, which
    /// checks they match (so a stolen Apple token can't be replayed).
    func makeNonce() -> (raw: String, hashed: String) {
        let raw = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let hashed = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        return (raw, hashed)
    }

    func signInWithApple(idToken: String, rawNonce: String) async {
        await run {
            try await self.client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: rawNonce)
            )
        }
    }

    // MARK: Google

    /// Where Google sign-in returns to the app. Must be listed in Supabase → Authentication →
    /// URL Configuration → Redirect URLs.
    static let oauthRedirectURL = URL(string: "com.choss.app://login-callback")!

    /// Signs in with Google in a secure in-app browser sheet (Supabase runs the Google side).
    /// New Google users get an account straight away, then set up their profile like anyone else.
    func signInWithGoogle() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await client.auth.signInWithOAuth(provider: .google, redirectTo: Self.oauthRedirectURL)
        } catch {
            // Closing the sheet isn't an error worth showing.
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            let message = error.localizedDescription
            errorMessage = message.localizedCaseInsensitiveContains("provider is not enabled")
                ? "Google sign-in isn't switched on for this server yet. Use email for now."
                : message
        }
    }

    // MARK: Email

    func signIn(email: String, password: String) async {
        await run { try await self.client.auth.signIn(email: email, password: password) }
    }

    /// Returns true if the account is ready; false if Supabase sent a confirmation email first.
    func signUp(email: String, password: String) async -> Bool {
        var signedIn = false
        await run {
            let response = try await self.client.auth.signUp(email: email, password: password)
            signedIn = response.session != nil
        }
        return signedIn
    }

    func sendPasswordReset(email: String) async {
        await run {
            try await self.client.auth.resetPasswordForEmail(email, redirectTo: Self.passwordResetURL)
        }
    }

    // MARK: Password reset

    /// Where the reset email's link sends people: back into the app. Must be listed in
    /// Supabase → Authentication → URL Configuration → Redirect URLs.
    static let passwordResetURL = URL(string: "com.choss.app://reset-password")!

    /// A link opened the app. A password-reset link signs you in (proving you own the email)
    /// and opens the new-password screen; anything else is ignored.
    func handleOpenURL(_ url: URL) async {
        guard url.scheme == Self.passwordResetURL.scheme, url.host == Self.passwordResetURL.host else { return }
        errorMessage = nil
        do {
            _ = try await client.auth.session(from: url)
            isResettingPassword = true
        } catch {
            isResettingPassword = false
            errorMessage = "That reset link has expired or was already used. "
                + "Request a new one with “Forgot password?” (and open it on this phone)."
        }
    }

    /// Saves the new password (you're signed in by the reset link). Returns false (with
    /// `errorMessage` set) if it didn't work.
    func setNewPassword(_ password: String) async -> Bool {
        var saved = false
        await run {
            try await self.client.auth.update(user: UserAttributes(password: password))
            saved = true
        }
        return saved
    }

    /// Closes the reset screen after a successful change and carries on into the app.
    func finishPasswordReset() {
        isResettingPassword = false
    }

    /// Leaves the reset screen without changing the password: signs out, so the link's
    /// sign-in can't be used for anything else.
    func cancelPasswordReset() async {
        isResettingPassword = false
        await signOut()
    }

    // MARK: Account

    func signOut() async {
        await run { try await self.client.auth.signOut() }
    }

    /// Deletes the account and everything in it (server function), then signs out.
    func deleteAccount() async -> Bool {
        var ok = false
        await run {
            let _: DeleteAccountResponse = try await self.client.functions.invoke(
                "delete-account", options: FunctionInvokeOptions(method: .post)
            )
            ok = true
        }
        if ok { try? await client.auth.signOut() }
        return ok
    }

    var accountActions: AccountActions {
        AccountActions(
            email: email,
            signOut: { [weak self] in await self?.signOut() },
            deleteAccount: { [weak self] in await self?.deleteAccount() ?? false }
        )
    }

    private func run(_ operation: @escaping () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            errorMessage = Self.friendly(error)
        }
    }

    private static func friendly(_ error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("invalid login credentials") {
            return "That email and password don't match."
        }
        if message.localizedCaseInsensitiveContains("email not confirmed") {
            return "Confirm your email first: check your inbox for the link."
        }
        return message
    }
}

private struct DeleteAccountResponse: Decodable {
    let ok: Bool
}
#endif
