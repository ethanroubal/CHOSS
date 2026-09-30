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
                    ToolbarItem(placement: .topBarTrailing) {
                        // Value-based, like every in-app link, so links on the pushed screens
                        // (e.g. a liked video) resolve through `withAppRoutes`.
                        NavigationLink(value: Route.settings) {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
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
        case reposts = "Reposts"
        case places = "Places"
        var id: Self { self }
    }

    @State private var tab: Tab = .sends
    @State private var editing = false

    var body: some View {
        ScrollView {
            if let user = store.user(userID) {
                VStack(alignment: .leading, spacing: 14) {
                    header(user)
                    bio(user)
                    profileActions(user)

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
                            PostGrid(posts: sends, title: user.username)
                        }
                    case .reposts:
                        let reposted = store.repostedPosts(by: user.id)
                        if reposted.isEmpty {
                            ContentUnavailableView("No reposts yet", systemImage: "arrow.2.squarepath")
                        } else {
                            PostGrid(posts: reposted, title: "Reposted by \(user.username)")
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

                    BrandFooter()
                }
                .navigationTitle(user.username)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $editing) {
                    EditProfileView(user: user)
                }
            } else {
                ContentUnavailableView("Climber not found", systemImage: "person.fill.questionmark")
            }
        }
    }

    private func header(_ user: User) -> some View {
        HStack(spacing: 16) {
            AvatarView(user: user, size: 84)
            StatView(value: store.postCount(by: user.id), label: "Sends")
            // Tap a count to see (and search) the list.
            statLink(user, .followers, value: store.followerCount(ofUser: user.id))
            statLink(user, .following, value: store.followingCount(ofUser: user.id))
            statLink(user, .places, value: store.followedPlaces(of: user.id).count)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func statLink(_ user: User, _ tab: ConnectionsTab, value: Int) -> some View {
        NavigationLink(value: Route.connections(user.id, tab)) {
            StatView(value: value, label: tab.title)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func profileActions(_ user: User) -> some View {
        Group {
            if user.id == store.currentUserID {
                Button {
                    editing = true
                } label: {
                    Text("Edit profile")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                FollowButton(isFollowing: store.isFollowing(user: user.id)) {
                    store.toggleFollow(user: user.id)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    private func bio(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(user.displayName).font(.headline)
            // Self-reported level, only if the climber chose to show it.
            if !user.visibleGradeRanges.isEmpty {
                GradeRangeChips(ranges: user.visibleGradeRanges)
            } else if user.id == store.currentUserID, user.boulderRange != nil || user.ropeRange != nil {
                Label("Your grade is hidden from others", systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !user.bio.isEmpty {
                Text(user.bio).font(.subheadline)
            }
            let homes = user.homePlaceIDs.compactMap { store.place($0) }
            if !homes.isEmpty {
                // Home gyms / crags as tappable chips.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Home").font(.subheadline).foregroundStyle(.secondary)
                        ForEach(homes) { home in
                            NavigationLink(value: Route.place(home.id)) {
                                Label(home.name, systemImage: home.kind.symbolName)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.tint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            // Optional: climbers can hide it in Edit profile.
            let hardest = user.showsHardestSend ? store.hardestGrades(for: user.id) : []
            if !hardest.isEmpty {
                HStack(spacing: 6) {
                    Text("Hardest send:").font(.subheadline).foregroundStyle(.secondary)
                    ForEach(hardest, id: \.self) { GradeBadge(grade: $0) }
                }
            }
            projectsLink(user)
        }
        .padding(.horizontal)
    }

    /// "Projects" under Hardest send. Others see it only if the climber shows it; you always see
    /// your own (marked "Only seen by you" when hidden).
    @ViewBuilder
    private func projectsLink(_ user: User) -> some View {
        let isMe = user.id == store.currentUserID
        let count = user.projectClimbIDs.count
        if isMe || (user.showsProjects && count > 0) {
            NavigationLink(value: Route.projects(user.id)) {
                HStack(spacing: 6) {
                    Label("Projects", systemImage: "bookmark")
                        .font(.subheadline.weight(.semibold))
                    Text("\(count)")
                        .font(.caption.bold().monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                    if isMe && !user.showsProjects {
                        Label("Only seen by you", systemImage: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
    }
}

/// Lets you view the app as any sample user while there's no real auth,
/// and walk through new-account profile setup.
private struct DemoAccountMenu: View {
    @Environment(AppStore.self) private var store
    @State private var settingUp = false

    var body: some View {
        @Bindable var store = store
        Menu {
            Picker("Signed in as", selection: $store.currentUserID) {
                ForEach(store.allUsers) { user in
                    Text("@\(user.username)").tag(user.id)
                }
            }
            Divider()
            Button("Create new account…", systemImage: "person.badge.plus") {
                settingUp = true
            }
        } label: {
            Image(systemName: "person.2.circle")
        }
        .accessibilityLabel("Switch demo account")
        .sheet(isPresented: $settingUp) {
            EditProfileView()
        }
    }
}

#Preview {
    MyProfileTab().environment(AppStore.preview)
}
