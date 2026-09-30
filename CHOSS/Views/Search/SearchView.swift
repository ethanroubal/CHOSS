import SwiftUI

struct SearchView: View {
    @Environment(AppStore.self) private var store

    enum Scope: String, CaseIterable, Identifiable {
        case places = "Places"
        case climbs = "Climbs"
        case climbers = "Climbers"
        var id: Self { self }
    }

    @State private var query = ""
    @State private var scope: Scope = .places
    @State private var addingClimb = false
    @State private var results = SearchResults()
    @State private var pageLimit = Paging.pageSize

    var body: some View {
        NavigationStack {
            List {
                let ids = resultIDs
                let shown = Array(ids.prefix(pageLimit))
                switch scope {
                case .places:
                    ForEach(shown, id: \.self) { id in
                        if let place = store.place(id) {
                            NavigationLink(value: Route.place(place.id)) { PlaceRow(place: place) }
                        }
                    }
                case .climbs:
                    // Outdoor climbs across all crags: open one to see everyone's beta videos.
                    ForEach(shown, id: \.self) { id in
                        if let climb = store.climb(id) {
                            NavigationLink(value: Route.climb(climb.id)) { ClimbRow(climb: climb, showsCrag: true) }
                        }
                    }
                case .climbers:
                    ForEach(shown, id: \.self) { id in
                        if let user = store.user(id) {
                            NavigationLink(value: Route.user(user.id)) { UserRow(user: user) }
                        }
                    }
                }
                if ids.count > pageLimit {
                    LoadMoreRow { pageLimit += Paging.pageSize }
                }
                if scope == .climbs {
                    Button {
                        addingClimb = true
                    } label: {
                        Label(isQueryEmpty ? "Add a climb" : "Can't find it? Add “\(query)”",
                              systemImage: "plus.circle")
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if results.isEmpty(for: query) {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Gyms, crags, climbs, climbers")
            .searchScopes($scope, activation: .onSearchPresentation) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .runSearch(query, context: scope.rawValue, version: store.searchIndexVersion, into: $results) { [store, scope] text in
                switch scope {
                case .places: return await store.searchPlaceIDs(text)
                case .climbs: return await store.searchClimbIDs(text)
                case .climbers: return await store.searchUserIDs(text)
                }
            }
            .onChange(of: scope) {
                results = SearchResults()
                pageLimit = Paging.pageSize
            }
            .onChange(of: query) { pageLimit = Paging.pageSize }
            .sheet(isPresented: $addingClimb) {
                // No crag pre-selected here: the climber searches for it in the form.
                AddClimbView(suggestedName: query) { _ in }
            }
            .withAppRoutes()
        }
    }

    private var isQueryEmpty: Bool { SearchResults.clean(query).isEmpty }

    /// Search results, or (before typing) suggestions: popular places and climbers,
    /// and the most-filmed climbs. All precomputed, so this is cheap.
    private var resultIDs: [String] {
        guard isQueryEmpty else { return results.ids }
        switch scope {
        case .places: return store.popularPlaceIDs()
        case .climbs: return store.mostFilmedClimbIDs()
        case .climbers: return store.popularUserIDs().filter { $0 != store.currentUserID }
        }
    }
}

#Preview {
    SearchView().environment(AppStore.preview)
}
