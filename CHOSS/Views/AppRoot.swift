import SwiftUI

/// Picks the data source (see `BackendEnvironment`): the on-device demo, or a Supabase
/// project with sign-in.
struct AppRoot: View {
    var body: some View {
        if BackendEnvironment.current == .demo {
            DemoRoot()
        } else {
            LiveRoot()
        }
    }
}

/// The original sample data: no account, demo users switchable from the profile.
private struct DemoRoot: View {
    @State private var store = AppStore()

    var body: some View {
        RootTabView()
            .environment(store)
            .task { await store.load() }
            .task { await AppOpenAdManager.shared.showOnLaunchIfReady() }
    }
}

#if canImport(Supabase)
/// Signed out → sign in. Signed in → load your data; set up your profile the first time.
private struct LiveRoot: View {
    @State private var session = SupabaseSession(environment: BackendEnvironment.current)

    var body: some View {
        switch session.state {
        case .loading:
            SplashView()
        case .signedOut:
            SignInView(session: session)
        case .signedIn(let userID):
            SignedInRoot(session: session, userID: userID)
                .id(userID)   // a fresh store per account
        }
    }
}

private struct SignedInRoot: View {
    let session: SupabaseSession
    @State private var store: AppStore

    init(session: SupabaseSession, userID: String) {
        self.session = session
        _store = State(initialValue: AppStore(
            repository: SupabaseClimbingRepository(client: session.client, userID: userID),
            currentUserID: userID
        ))
    }

    var body: some View {
        Group {
            if store.isLoaded && store.currentUser == nil {
                // Signed in for the first time: pick a username, name, photo, home gym…
                EditProfileView(newAccountID: store.currentUserID)
            } else if !store.isLoaded, let error = store.lastError {
                LoadFailedView(message: error) {
                    Task { await store.load() }
                } signOut: {
                    Task { await session.signOut() }
                }
            } else {
                RootTabView()
                    // The ad when the app opens, once the main screen is up.
                    .task { await AppOpenAdManager.shared.showOnLaunchIfReady() }
            }
        }
        .environment(store)
        .environment(\.accountActions, session.accountActions)
        .task { await store.load() }
    }
}

private struct LoadFailedView: View {
    let message: String
    let retry: () -> Void
    let signOut: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't load CHOSS", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: retry).buttonStyle(.borderedProminent)
            Button("Sign out", action: signOut)
        }
    }
}
#else
/// Without the Supabase library there's no live backend; fall back to the demo.
private struct LiveRoot: View {
    var body: some View { DemoRoot() }
}
#endif
