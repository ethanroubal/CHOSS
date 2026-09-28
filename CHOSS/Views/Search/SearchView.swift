import SwiftUI

struct SearchView: View {
    @Environment(AppStore.self) private var store

    enum Scope: String, CaseIterable, Identifiable {
        case places = "Places"
        case climbers = "Climbers"
        case sends = "Sends"
        var id: Self { self }
    }

    @State private var query = ""
    @State private var scope: Scope = .places

    var body: some View {
        NavigationStack {
            List {
                switch scope {
                case .places:
                    ForEach(store.searchPlaces(query)) { place in
                        NavigationLink(value: Route.place(place.id)) { PlaceRow(place: place) }
                    }
                case .climbers:
                    ForEach(store.searchUsers(query)) { user in
                        NavigationLink(value: Route.user(user.id)) { UserRow(user: user) }
                    }
                case .sends:
                    ForEach(store.searchPosts(query)) { post in
                        NavigationLink(value: Route.post(post.id)) { SendRow(post: post) }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if !query.isEmpty && isEmptyResult {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Gyms, crags, climbers, routes")
            .searchScopes($scope, activation: .onSearchPresentation) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .withAppRoutes()
        }
    }

    private var isEmptyResult: Bool {
        switch scope {
        case .places: store.searchPlaces(query).isEmpty
        case .climbers: store.searchUsers(query).isEmpty
        case .sends: store.searchPosts(query).isEmpty
        }
    }
}

private struct SendRow: View {
    @Environment(AppStore.self) private var store
    let post: Post

    var body: some View {
        HStack(spacing: 12) {
            VideoThumbnailView(post: post)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(post.routeName.isEmpty ? "Unnamed route" : post.routeName).font(.headline).lineLimit(1)
                    GradeBadge(grade: post.grade)
                }
                Text([store.user(post.authorID)?.username, store.place(post.placeID)?.name]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    SearchView().environment(AppStore.preview)
}
