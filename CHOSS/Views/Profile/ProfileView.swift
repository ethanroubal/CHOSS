import SwiftUI

/// The signed-in user's profile tab.
struct MyProfileTab: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            ProfileView(userID: store.currentUserID)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        DemoAccountMenu()
                    }
                }
                .withAppRoutes()
        }
    }
}

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    let userID: User.ID

    private enum Tab: String, CaseIterable, Identifiable {
        case sends = "Sends"
        case places = "Places"
        var id: Self { self }
    }

    @State private var tab: Tab = .sends

    var body: some View {
        ScrollView {
            if let user = store.user(userID) {
                VStack(alignment: .leading, spacing: 14) {
                    header(user)
                    bio(user)
                    if user.id != store.currentUserID {
                        FollowButton(isFollowing: store.isFollowing(user: user.id)) {
                            store.toggleFollow(user: user.id)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                    }

                    Picker("Section", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    switch tab {
                    case .sends:
                        let sends = store.posts(by: user.id)
                        if sends.isEmpty {
                            ContentUnavailableView("No sends yet", systemImage: "video.slash")
                        } else {
                            PostGrid(posts: sends)
                        }
                    case .places:
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(store.followedPlaces(of: user.id)) { place in
                                NavigationLink(value: Route.place(place.id)) { PlaceRow(place: place) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .navigationTitle(user.username)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Climber not found", systemImage: "person.fill.questionmark")
            }
        }
    }

    private func header(_ user: User) -> some View {
        HStack(spacing: 16) {
            AvatarView(user: user, size: 84)
            StatView(value: store.posts(by: user.id).count, label: "Sends")
            StatView(value: store.followerCount(ofUser: user.id), label: "Followers")
            StatView(value: store.followingCount(ofUser: user.id), label: "Following")
            StatView(value: store.followedPlaces(of: user.id).count, label: "Places")
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func bio(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(user.displayName).font(.headline)
            if !user.bio.isEmpty {
                Text(user.bio).font(.subheadline)
            }
            if let home = store.place(user.homePlaceID) {
                NavigationLink(value: Route.place(home.id)) {
                    Label("Home: \(home.name)", systemImage: home.kind.symbolName)
                        .font(.subheadline)
                }
            }
            let hardest = store.hardestGrades(for: user.id)
            if !hardest.isEmpty {
                HStack(spacing: 6) {
                    Text("Hardest:").font(.subheadline).foregroundStyle(.secondary)
                    ForEach(hardest, id: \.self) { GradeBadge(grade: $0) }
                }
            }
        }
        .padding(.horizontal)
    }
}

/// Lets you view the app as any sample user while there's no real auth.
private struct DemoAccountMenu: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Menu {
            Picker("Signed in as", selection: $store.currentUserID) {
                ForEach(store.allUsers) { user in
                    Text("@\(user.username)").tag(user.id)
                }
            }
        } label: {
            Image(systemName: "person.2.circle")
        }
        .accessibilityLabel("Switch demo account")
    }
}

#Preview {
    MyProfileTab().environment(AppStore.preview)
}
