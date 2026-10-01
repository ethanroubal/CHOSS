import SwiftUI

/// Which data the app runs against.
///
/// - Debug builds (run from Xcode) use the **test** Supabase project, so experiments never
///   touch real users. Release builds (TestFlight / App Store) use **production**.
/// - **Demo** is the old on-device sample data, with no sign-in. It's used if the Supabase
///   library isn't available, or when launched with `-useDemoData YES` (Xcode: Product ▸
///   Scheme ▸ Edit Scheme ▸ Arguments).
///
/// The publishable keys below are meant to ship inside the app: they only allow what the
/// database's Row Level Security rules allow. Secret / service-role keys must never be here.
enum BackendEnvironment: String {
    case demo
    case test
    case production

    static var current: BackendEnvironment {
        if UserDefaults.standard.bool(forKey: "useDemoData") { return .demo }
        #if canImport(Supabase)
        #if DEBUG
        return .test
        #else
        return .production
        #endif
        #else
        return .demo
        #endif
    }

    var supabaseURL: URL? {
        switch self {
        case .demo: nil
        case .test: URL(string: "https://qwnoanczqsqcygpjauoa.supabase.co")
        case .production: URL(string: "https://acfijpwcfvltqizgjgoo.supabase.co")
        }
    }

    var publishableKey: String? {
        switch self {
        case .demo: nil
        case .test: "sb_publishable_b3GVMMUTdeMhse7bkEIZvA_C84OS1S_"
        case .production: "sb_publishable_SxCm1EY99_PwiJKi_2vH8A_LznYahzj"
        }
    }

    var displayName: String {
        switch self {
        case .demo: "Demo data"
        case .test: "Test server"
        case .production: "Live"
        }
    }
}

/// Sign out / delete account, provided by the signed-in session (nil in demo mode, where
/// there's no account). Settings shows the buttons only when these exist.
struct AccountActions {
    var email: String?
    var signOut: () async -> Void
    /// Returns false (and sets an error on the session) if it failed.
    var deleteAccount: () async -> Bool
}

private struct AccountActionsKey: EnvironmentKey {
    static let defaultValue: AccountActions? = nil
}

extension EnvironmentValues {
    var accountActions: AccountActions? {
        get { self[AccountActionsKey.self] }
        set { self[AccountActionsKey.self] = newValue }
    }
}
