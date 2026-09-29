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
/// - No place: your own earlier routes.
struct RoutePickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let placeID: Place.ID?
    let onPick: (RouteChoice) -> Void

    @State private var query = ""
    @State private var addingClimb = false

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
                if !isCrag && trimmedQuery.isEmpty {
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
        .sheet(isPresented: $addingClimb) {
            AddClimbView(placeID: placeID, suggestedName: trimmedQuery) { climb in
                // AddClimbView returns an existing climb if you tapped "Did you mean…?".
                let isNew = climb.createdBy == store.currentUserID && store.posts(ofClimb: climb.id).isEmpty
                choose(.climb(climb, isNew: isNew))
            }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
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
                Text("\(route.discipline.displayName) · \(route.postCount) \(route.postCount == 1 ? "video" : "videos")")
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
