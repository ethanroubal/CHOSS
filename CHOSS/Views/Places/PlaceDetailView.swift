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
        var id: Self { self }
    }

    @State private var tab: Tab = .sends
    @State private var discipline: ClimbDiscipline?
    @State private var climbQuery = ""
    @State private var composing = false
    @State private var addingClimb = false

    var body: some View {
        ScrollView {
            if let place = store.place(placeID) {
                VStack(alignment: .leading, spacing: 14) {
                    header(place)
                    actionRow(place)
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: place.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))) {
                        Marker(place.name, systemImage: place.kind.symbolName, coordinate: place.coordinate)
                    }
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
                    .padding(.horizontal)

                    if place.kind == .crag {
                        Picker("Section", selection: $tab) {
                            ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }

                    if place.kind == .crag && tab == .climbs {
                        climbList(place)
                    } else {
                        sends(place)
                    }
                    BrandFooter()
                }
                .navigationTitle(place.name)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $composing) {
                    ComposeView(initialPlaceID: place.id)
                }
                .sheet(isPresented: $addingClimb) {
                    AddClimbView(placeID: place.id, suggestedName: climbQuery) { _ in }
                }
            } else {
                ContentUnavailableView("Place not found", systemImage: "mappin.slash")
            }
        }
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
                StatView(value: store.posts(at: place.id).count, label: "Sends")
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
                        ForEach(place.disciplines) { Text($0.displayName).tag(ClimbDiscipline?.some($0)) }
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

    /// Searchable list of the crag's climbs. With no query, grouped by area (wall / boulder field).
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

            if results.isEmpty {
                ContentUnavailableView {
                    Label(climbQuery.isEmpty ? "No climbs listed yet" : "No climb matches “\(climbQuery)”",
                          systemImage: "mountain.2")
                } description: {
                    Text("Add it so everyone's videos of it end up in one place.")
                }
            } else if climbQuery.isEmpty {
                let areas = Dictionary(grouping: results, by: \.area)
                ForEach(areas.keys.sorted(), id: \.self) { area in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(area.isEmpty ? "Other" : area)
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.bottom, 4)
                        ForEach(areas[area] ?? []) { climb in
                            climbLink(climb)
                        }
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
        PlaceDetailView(placeID: "p_granite_works")
            .withAppRoutes()
    }
    .environment(AppStore.preview)
}
