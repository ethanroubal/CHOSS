import SwiftUI

enum ConnectionsTab: String, CaseIterable, Identifiable, Hashable {
    case followers
    case following
    case places

    var id: Self { self }

    var title: String {
        switch self {
        case .followers: "Followers"
        case .following: "Following"
        case .places: "Places"
        }
    }
}

/// A profile's followers, the climbers they follow, and the places they follow, with a
/// forgiving search (typos, initials, towns for places).
struct ConnectionsView: View {
    @Environment(AppStore.self) private var store
    let userID: User.ID

    @State private var tab: ConnectionsTab
    @State private var query = ""

    init(userID: User.ID, tab: ConnectionsTab) {
        self.userID = userID
        _tab = State(initialValue: tab)
    }

    var body: some View {
        List {
            switch tab {
            case .followers, .following:
                let people = matchingPeople
                if people.isEmpty {
                    emptyState
                } else {
                    ForEach(people) { user in
                        NavigationLink(value: Route.user(user.id)) {
                            UserRow(user: user)
                        }
                    }
                }
            case .places:
                let places = matchingPlaces
                if places.isEmpty {
                    emptyState
                } else {
                    ForEach(places) { place in
                        NavigationLink(value: Route.place(place.id)) {
                            PlaceRow(place: place)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        // The tabs and search box stay pinned above the list, so the first rows are always
        // right below them (and never tucked under the navigation bar).
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 10) {
                Picker("List", selection: $tab) {
                    ForEach(ConnectionsTab.allCases) { tab in
                        Text("\(count(tab)) \(tab.title)").tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                InlineSearchField(prompt: prompt, text: $query)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle(store.user(userID)?.username ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var prompt: String {
        switch tab {
        case .followers: "Search followers"
        case .following: "Search following"
        case .places: "Search places by name or town"
        }
    }

    private func count(_ tab: ConnectionsTab) -> Int {
        switch tab {
        case .followers: store.followerCount(ofUser: userID)
        case .following: store.followingCount(ofUser: userID)
        case .places: store.followedPlaces(of: userID).count
        }
    }

    /// Best match first; everyone alphabetically when the search is empty.
    private var matchingPeople: [User] {
        let people = tab == .followers ? store.followers(of: userID) : store.followedUsers(of: userID)
        return NameMatcher.rank(people, query: query)
    }

    private var matchingPlaces: [Place] {
        let places = store.followedPlaces(of: userID)
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return places }
        return places
            .compactMap { place -> (Place, Double)? in
                NameMatcher.score(query: query, names: [place.name, place.city, place.region, place.country])
                    .map { (place, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    private var emptyMessage: String {
        let isMe = userID == store.currentUserID
        let subject = isMe ? "You aren't" : "\(store.user(userID)?.username ?? "This climber") isn't"
        switch tab {
        case .followers: return "No followers yet."
        case .following: return "\(subject) following anyone yet."
        case .places: return "\(subject) following any gyms or crags yet."
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
                .listRowSeparator(.hidden)
        } else {
            Text(emptyMessage)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .listRowSeparator(.hidden)
        }
    }
}

#Preview {
    NavigationStack {
        ConnectionsView(userID: SampleData.currentUserID, tab: .followers)
            .withAppRoutes()
    }
    .environment(AppStore.preview)
}
