import SwiftUI

/// What was picked in the route picker.
enum RouteChoice {
    /// An outdoor climb from the climb list (existing, or just added via "Add a climb").
    case climb(Climb, isNew: Bool)
}

/// "Problem / route" in the composer. Only outdoor climbs have names (for now), so this searches
/// the climb list and picks one, or adds a new one through "Add a climb" (which gives it a crag,
/// area and type).
/// - Crag tagged: that crag's climbs.
/// - No place: every crag's climbs, with the same fast fuzzy search as places. Picking one tags
///   its crag.
struct RoutePickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let placeID: Place.ID?
    let onPick: (RouteChoice) -> Void

    @State private var query = ""
    @State private var addingClimb = false
    /// Search across every crag, used when no place is tagged.
    @State private var results = SearchResults()

    private var place: Place? { store.place(placeID) }

    var body: some View {
        List {
            let climbs = matchingClimbs
            if !climbs.isEmpty {
                Section(sectionTitle) {
                    ForEach(Array(climbs.enumerated()), id: \.element.id) { index, climb in
                        Button {
                            choose(.climb(climb, isNew: false))
                        } label: {
                            ClimbRow(climb: climb, showsCrag: placeID == nil,
                                     isBestMatch: index == 0 && !trimmedQuery.isEmpty)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Button {
                    addingClimb = true
                } label: {
                    Label(trimmedQuery.isEmpty ? "Add a new climb" : "Add “\(trimmedQuery)” as a new climb",
                          systemImage: "plus.circle")
                }
            } footer: {
                if placeID == nil && trimmedQuery.isEmpty {
                    Text("Type to search climbs at every crag.")
                }
            }
        }
        .overlay {
            if placeID == nil && results.isEmpty(for: query) {
                ContentUnavailableView.search(text: query)
            } else if let placeID, matchingClimbs.isEmpty, store.isLoadingClimbs(at: placeID) {
                ProgressView("Loading climbs…")
            }
        }
        // The crag's climbs come from the server (there can be thousands).
        .task(id: placeID) {
            if let placeID { await store.loadClimbs(at: placeID) }
        }
        .navigationTitle("Problem / route")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: place.map { "Search climbs at \($0.name)" } ?? "Search climbs at every crag")
        .autocorrectionDisabled()
        .onSubmit(of: .search) { submitBestMatch() }
        .runSearch(placeID == nil ? query : "", version: store.searchIndexVersion, into: $results) { [store] text in
            await store.searchClimbIDs(text, limit: 50)
        }
        .sheet(isPresented: $addingClimb) {
            AddClimbView(placeID: placeID, suggestedName: trimmedQuery) { climb in
                // AddClimbView returns an existing climb if you tapped "Did you mean…?".
                let isNew = climb.createdBy == store.currentUserID && store.postCount(ofClimb: climb.id) == 0
                choose(.climb(climb, isNew: isNew))
            }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sectionTitle: String {
        if !trimmedQuery.isEmpty { return "Matches" }
        return "Climbs at \(place?.name ?? "this crag")"
    }

    /// The crag's climbs (filtered by the query), or search results from every crag.
    private var matchingClimbs: [Climb] {
        if let placeID {
            return store.searchClimbs(query, at: placeID)
        }
        return trimmedQuery.isEmpty ? [] : results.ids.compactMap { store.climb($0) }
    }

    /// Return picks the best match, or offers to add the typed name as a new climb.
    private func submitBestMatch() {
        guard !trimmedQuery.isEmpty else { return }
        if let placeID {
            if let best = store.searchClimbs(trimmedQuery, at: placeID).first {
                choose(.climb(best, isNew: false))
            } else {
                addingClimb = true
            }
            return
        }
        // Search now, in case the typed results haven't landed yet.
        let text = trimmedQuery
        Task {
            if let id = await store.searchClimbIDs(text, limit: 1).first, let climb = store.climb(id) {
                choose(.climb(climb, isNew: false))
            } else {
                addingClimb = true
            }
        }
    }

    private func choose(_ choice: RouteChoice) {
        onPick(choice)
        dismiss()
    }
}
