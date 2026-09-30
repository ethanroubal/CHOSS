import SwiftUI

/// What was picked in the route picker.
enum RouteChoice {
    /// An outdoor climb from the crag's list (existing, or just added via "Add a climb").
    case climb(Climb, isNew: Bool)
    /// A route already posted at this gym (or by you, when no place is tagged).
    case known(KnownRoute)
    /// A route name nobody has posted yet.
    case new(String)
}

/// "Problem / route" in the composer: search the climbs at the tagged place and pick one,
/// or add a new one.
/// - Crag: the crag's climbs; new ones go through "Add a climb" (so they get a crag, area and type).
/// - Gym: routes people have already posted there; a new one is just its name.
/// - No place: your own earlier routes, plus (once you type) every crag's climbs and routes
///   posted at gyms, found with the same fast fuzzy search as places. Picking one tags its place.
struct RoutePickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let placeID: Place.ID?
    let onPick: (RouteChoice) -> Void

    @State private var query = ""
    @State private var addingClimb = false
    /// Searches everywhere, used when no place is tagged.
    @State private var climbResults = SearchResults()
    @State private var routeResults = SearchResults()

    private var place: Place? { store.place(placeID) }
    private var isCrag: Bool { place?.kind == .crag }

    var body: some View {
        List {
            if isCrag, let placeID {
                let climbs = store.searchClimbs(query, at: placeID)
                Section(query.isEmpty ? "Climbs at \(place?.name ?? "this crag")" : "Matches") {
                    ForEach(Array(climbs.enumerated()), id: \.element.id) { index, climb in
                        Button {
                            choose(.climb(climb, isNew: false))
                        } label: {
                            ClimbRow(climb: climb, isBestMatch: index == 0 && !query.isEmpty)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                let routes = matchingRoutes
                if !routes.isEmpty {
                    Section(query.isEmpty ? routesHeader : "Matches") {
                        ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                            Button {
                                choose(.known(route))
                            } label: {
                                KnownRouteRow(route: route, isBestMatch: index == 0 && !query.isEmpty)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if placeID == nil && !trimmedQuery.isEmpty {
                    everywhereSections
                }
            }

            Section {
                Button {
                    if isCrag {
                        addingClimb = true
                    } else {
                        choose(.new(trimmedQuery))
                    }
                } label: {
                    Label(trimmedQuery.isEmpty ? "Add a new climb" : "Add “\(trimmedQuery)” as a new climb",
                          systemImage: "plus.circle")
                }
                .disabled(!isCrag && trimmedQuery.isEmpty)
            } footer: {
                if placeID == nil && trimmedQuery.isEmpty {
                    Text("Type to search climbs at every crag and routes posted at gyms, or to add a new one.")
                } else if !isCrag && trimmedQuery.isEmpty {
                    Text("Type the climb's name above to add it.")
                }
            }
        }
        .navigationTitle("Problem / route")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: isCrag ? "Search climbs at \(place?.name ?? "this crag")" : "Search or type a climb name")
        .autocorrectionDisabled()
        .onSubmit(of: .search) { submitBestMatch() }
        .runSearch(placeID == nil ? query : "", context: "climbs", version: store.searchIndexVersion,
                   into: $climbResults) { [store] text in
            await store.searchClimbIDs(text, limit: 30)
        }
        .runSearch(placeID == nil ? query : "", context: "routes", version: store.searchIndexVersion,
                   into: $routeResults) { [store] text in
            await store.searchRouteKeys(text, limit: 30)
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

    /// Outdoor climbs and gym routes from everywhere, best match first.
    @ViewBuilder
    private var everywhereSections: some View {
        let climbs = climbResults.ids.compactMap { store.climb($0) }
        if !climbs.isEmpty {
            Section("Outdoor climbs") {
                ForEach(Array(climbs.enumerated()), id: \.element.id) { index, climb in
                    Button {
                        choose(.climb(climb, isNew: false))
                    } label: {
                        ClimbRow(climb: climb, showsCrag: true,
                                 isBestMatch: index == 0 && matchingRoutes.isEmpty)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        let routes = routeResults.ids.compactMap { store.knownRoute(forKey: $0) }
        if !routes.isEmpty {
            Section("Gym routes") {
                ForEach(routes, id: \.climbKey) { route in
                    Button {
                        choose(.known(route))
                    } label: {
                        KnownRouteRow(route: route, placeName: store.place(route.placeID)?.name)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var routesHeader: String {
        placeID == nil ? "Your climbs" : "Climbs posted at \(place?.name ?? "this gym")"
    }

    private var matchingRoutes: [KnownRoute] {
        let routes = store.knownRoutes(at: placeID)
        guard !trimmedQuery.isEmpty else { return routes }
        return routes
            .compactMap { route in NameMatcher.score(query: trimmedQuery, names: [route.name]).map { (route, $0) } }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    /// Return picks the best match, or adds the typed name as a new climb.
    private func submitBestMatch() {
        guard !trimmedQuery.isEmpty else { return }
        if isCrag, let placeID {
            if let best = store.searchClimbs(trimmedQuery, at: placeID).first {
                choose(.climb(best, isNew: false))
            } else {
                addingClimb = true
            }
        } else if let best = matchingRoutes.first {
            choose(.known(best))
        } else if placeID == nil {
            // Search everywhere now, in case the typed results haven't landed yet.
            let text = trimmedQuery
            Task {
                if let id = await store.searchClimbIDs(text, limit: 1).first, let climb = store.climb(id) {
                    choose(.climb(climb, isNew: false))
                } else if let key = await store.searchRouteKeys(text, limit: 1).first,
                          let route = store.knownRoute(forKey: key) {
                    choose(.known(route))
                } else {
                    choose(.new(text))
                }
            }
        } else {
            choose(.new(trimmedQuery))
        }
    }

    private func choose(_ choice: RouteChoice) {
        onPick(choice)
        dismiss()
    }
}

private struct KnownRouteRow: View {
    let route: KnownRoute
    var isBestMatch = false
    /// Shown when the list mixes routes from different gyms.
    var placeName: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            DisciplineIcon(discipline: route.discipline, size: 26)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(route.name).font(.headline).lineLimit(1)
                    if isBestMatch {
                        Text("Best match")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                }
                Text([placeName, route.discipline.displayName,
                      "\(route.postCount) \(route.postCount == 1 ? "video" : "videos")"]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let grade = route.grade {
                GradeBadge(grade: grade)
            }
        }
    }
}
