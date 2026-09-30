import SwiftUI
import MapKit

/// A gym or crag's page: follow it, see every send posted there, post your own.
/// Crags also list their (permanent) climbs, each with its own page of beta videos.
struct PlaceDetailView: View {
    @Environment(AppStore.self) private var store
    let placeID: Place.ID

    private enum Tab: String, CaseIterable, Identifiable {
        case sends = "Sends"
        case climbs = "Climbs"
        case leaders = "Leaderboard"
        var id: Self { self }
    }

    /// How a crag's climbs are ordered while browsing (a search is ordered by best match).
    private enum ClimbSort: String, CaseIterable, Identifiable {
        case popularity = "Most sends"
        case area = "Area"
        case difficulty = "Difficulty"
        var id: Self { self }

        var symbolName: String {
            switch self {
            case .popularity: "flame"
            case .area: "map"
            case .difficulty: "chart.bar"
            }
        }
    }

    @State private var tab: Tab = .sends
    @State private var climbSort: ClimbSort = .popularity
    @State private var hardestFirst = true
    @State private var discipline: ClimbDiscipline?
    @State private var climbQuery = ""
    @State private var composing = false
    @State private var addingClimb = false
    @State private var showingMap = false

    var body: some View {
        ScrollView {
            if let place = store.place(placeID) {
                VStack(alignment: .leading, spacing: 14) {
                    header(place)
                    actionRow(place)
                    mapPreview(place)

                    if place.kind == .crag {
                        Picker("Section", selection: $tab) {
                            ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }

                    switch place.kind == .crag ? tab : .sends {
                    case .sends: sends(place)
                    case .climbs: climbList(place)
                    case .leaders: LeaderboardView(placeID: place.id)
                    }
                    BrandFooter()
                }
                .navigationTitle(place.name)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $composing) {
                    ComposeView(initialPlaceID: place.id)
                }
                .fullScreenCover(isPresented: $showingMap) {
                    PlaceMapView(place: place)
                }
                .sheet(isPresented: $addingClimb) {
                    AddClimbView(placeID: place.id, suggestedName: climbQuery) { _ in }
                }
            } else {
                ContentUnavailableView("Place not found", systemImage: "mappin.slash")
            }
        }
    }

    /// A static preview; tapping it opens the full, interactive map.
    private func mapPreview(_ place: Place) -> some View {
        Button {
            showingMap = true
        } label: {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: place.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))) {
                Marker(place.name, systemImage: place.kind.symbolName, coordinate: place.coordinate)
            }
            .allowsHitTesting(false)  // the preview doesn't scroll; the whole card is the button
            .frame(height: 140)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.footnote.weight(.semibold))
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open map of \(place.name)")
        .padding(.horizontal)
    }

    private func header(_ place: Place) -> some View {
        HStack(alignment: .top, spacing: 14) {
            PlaceIconView(place: place, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(place.name).font(.title2.bold())
                    if place.isVerified {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint)
                    }
                }
                Text("\(place.kind.displayName) · \(place.locationLine)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(place.disciplines.map(\.displayName).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !place.about.isEmpty {
                    Text(place.about).font(.subheadline).padding(.top, 2)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func actionRow(_ place: Place) -> some View {
        VStack(spacing: 12) {
            HStack {
                StatView(value: store.followerCount(of: place.id), label: "Followers")
                StatView(value: store.postCount(at: place.id), label: "Sends")
                StatView(value: Set(store.posts(at: place.id).map(\.authorID)).count, label: "Climbers")
                if place.kind == .crag {
                    StatView(value: store.climbs(at: place.id).count, label: "Climbs")
                }
            }
            HStack {
                FollowButton(isFollowing: store.isFollowing(place: place.id)) {
                    store.toggleFollow(place: place.id)
                }
                Button {
                    composing = true
                } label: {
                    Label("Post a send", systemImage: "video.badge.plus")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func sends(_ place: Place) -> some View {
        let all = store.posts(at: place.id)
        let filtered = all.filter { discipline == nil || $0.discipline == discipline }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sends").font(.title3.bold())
                Spacer()
                Menu {
                    Picker("Discipline", selection: $discipline) {
                        Text("All").tag(ClimbDiscipline?.none)
                        ForEach(place.disciplines) { DisciplineLabel(discipline: $0).tag(ClimbDiscipline?.some($0)) }
                    }
                } label: {
                    Label(discipline?.displayName ?? "All", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal)

            if filtered.isEmpty {
                ContentUnavailableView(
                    "No sends yet",
                    systemImage: "figure.climbing",
                    description: Text("Be the first to post a send at \(place.name).")
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filtered) { post in
                        PostCardView(post: post)
                        Divider()
                    }
                }
            }
        }
    }

    /// Searchable list of the crag's climbs. While browsing, sorted by most sends, grouped by area
    /// (wall / boulder field), or by difficulty (hardest or easiest first); a search is best match first.
    @ViewBuilder
    private func climbList(_ place: Place) -> some View {
        let results = store.searchClimbs(climbQuery, at: place.id)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search climbs at \(place.name)", text: $climbQuery)
                    .autocorrectionDisabled()
                if !climbQuery.isEmpty {
                    Button {
                        climbQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal)

            if climbQuery.isEmpty && !results.isEmpty {
                sortControls
            }

            if results.isEmpty {
                ContentUnavailableView {
                    Label(climbQuery.isEmpty ? "No climbs listed yet" : "No climb matches “\(climbQuery)”",
                          systemImage: "mountain.2")
                } description: {
                    Text("Add it so everyone's videos of it end up in one place.")
                }
            } else if climbQuery.isEmpty {
                switch climbSort {
                case .popularity:
                    // `searchClimbs` with no query is already most-sent first.
                    VStack(spacing: 0) {
                        ForEach(results) { climb in climbLink(climb) }
                    }
                case .area:
                    let areas = Dictionary(grouping: results, by: \.area)
                    ForEach(areas.keys.sorted { areaSortKey($0) < areaSortKey($1) }, id: \.self) { area in
                        climbGroup(area.isEmpty ? "Other" : area,
                                   (areas[area] ?? []).sorted { $0.name < $1.name })
                    }
                case .difficulty:
                    ForEach(difficultyGroups(results), id: \.title) { group in
                        climbGroup(group.title, group.climbs)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(results) { climb in
                        climbLink(climb)
                    }
                }
            }

            Button {
                addingClimb = true
            } label: {
                Label(climbQuery.isEmpty ? "Add a climb" : "Add “\(climbQuery)”", systemImage: "plus.circle")
            }
            .padding(.horizontal)
        }
    }

    /// Sort picker, plus hardest / easiest first when sorting by difficulty.
    private var sortControls: some View {
        HStack {
            Menu {
                Picker("Sort climbs", selection: $climbSort) {
                    ForEach(ClimbSort.allCases) { sort in
                        Label(sort.rawValue, systemImage: sort.symbolName).tag(sort)
                    }
                }
            } label: {
                Label("Sort: \(climbSort.rawValue)", systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
            if climbSort == .difficulty {
                Picker("Order", selection: $hardestFirst) {
                    Text("Hardest first").tag(true)
                    Text("Easiest first").tag(false)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .padding(.horizontal)
        .animation(.easeOut(duration: 0.15), value: climbSort)
    }

    private func climbGroup(_ title: String, _ climbs: [Climb]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 4)
            ForEach(climbs) { climb in climbLink(climb) }
        }
    }

    /// Unnamed areas ("Other") go last.
    private func areaSortKey(_ area: String) -> String {
        area.isEmpty ? "\u{10FFFF}" : area.lowercased()
    }

    private struct ClimbGroup {
        let title: String
        let climbs: [Climb]
    }

    /// Climbs by grade, hardest or easiest first. Boulders, routes, ice and mixed are graded on
    /// different scales, so each gets its own group (Font is compared as V-scale, French as YDS).
    /// A climb's grade is the community average, falling back to the guidebook grade; climbs with
    /// no grade come last.
    private func difficultyGroups(_ climbs: [Climb]) -> [ClimbGroup] {
        var graded: [GradeSystem: [(climb: Climb, rank: Int)]] = [:]
        var ungraded: [Climb] = []
        for climb in climbs {
            let grade = store.averageGrade(forClimb: climb.id)?.grade ?? climb.grade
            // Convert to the category's common scale; mixed (M) grades stay as they are.
            guard let comparable = grade.map({ $0.canonical ?? $0 }), comparable.rank >= 0 else {
                ungraded.append(climb)
                continue
            }
            graded[comparable.system, default: []].append((climb: climb, rank: comparable.rank))
        }
        let order: [GradeSystem] = [.vScale, .yds, .waterIce, .mixed]
        var groups = order.compactMap { system -> ClimbGroup? in
            guard let entries = graded[system], !entries.isEmpty else { return nil }
            let sorted = entries.sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return hardestFirst ? lhs.rank > rhs.rank : lhs.rank < rhs.rank }
                return lhs.climb.name < rhs.climb.name
            }
            let title = system == .mixed ? "Mixed" : system.category.displayName
            return ClimbGroup(title: title, climbs: sorted.map { $0.climb })
        }
        if !ungraded.isEmpty {
            groups.append(ClimbGroup(title: "No grade yet", climbs: ungraded.sorted { $0.name < $1.name }))
        }
        return groups
    }

    private func climbLink(_ climb: Climb) -> some View {
        NavigationLink(value: Route.climb(climb.id)) {
            ClimbRow(climb: climb)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        PlaceDetailView(placeID: SampleData.brooklynGym)
            .withAppRoutes()
    }
    .environment(AppStore.preview)
}
