import SwiftUI
import MapKit

struct ExploreView: View {
    @Environment(AppStore.self) private var store

    private enum Mode: String, CaseIterable, Identifiable {
        case sends = "Sends"
        case map = "Map"
        var id: Self { self }
    }

    @State private var mode: Mode = .sends
    /// A Recent climbs video was tapped: feed mode opens on it.
    @State private var feedModeStart: FeedModeStart?
    @State private var discipline: ClimbDiscipline?
    @State private var selectedPlaceID: Place.ID?
    /// Starts over the continental US; updated as you pan / zoom.
    @State private var mapCamera: MapCameraPosition = .region(Self.continentalUS)
    @State private var visibleRegion: MKCoordinateRegion = Self.continentalUS

    private static let continentalUS = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
        span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 60)
    )
    /// Drawing ~1,500 markers at once makes the map sluggish, so only the most-followed places
    /// in view are drawn; zoom in to see the rest.
    private static let maxMarkers = 250

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .sends: sendsView
                case .map: mapView
                }
            }
            // The Sends / Map switch sits just under the bar, not in the bar's title slot: custom
            // views there can leave the bar mis-sized on pages opened from here (their tops
            // ended up hidden under it).
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .padding(.horizontal)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .withAppRoutes()
        }
    }

    // MARK: Sends

    private var sendsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                disciplineChips

                placeCarousel(title: "Popular gyms", places: store.popularPlaceIDs(kind: .gym).prefix(15).compactMap { store.place($0) })
                recentClimbsCarousel
                climbCarousel
                trendingCarousel
                placeCarousel(title: "Popular crags", places: store.popularPlaceIDs(kind: .crag).prefix(15).compactMap { store.place($0) })
                BrandFooter()
            }
        }
        .fullScreenCover(item: $feedModeStart) { start in feedMode(start) }
    }

    private var disciplineChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                chip("All", isOn: discipline == nil) {
                    Image(systemName: "square.grid.2x2")
                } action: { discipline = nil }
                ForEach(ClimbDiscipline.allCases) { d in
                    chip(d.displayName, isOn: discipline == d) {
                        DisciplineIcon(discipline: d, size: 18)
                    } action: { discipline = d }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip<Icon: View>(_ title: String, isOn: Bool, @ViewBuilder icon: () -> Icon,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(title) } icon: { icon() }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isOn ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(isOn ? Brand.onAccent : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func placeCarousel(title: String, places: [Place]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(places) { place in
                        NavigationLink(value: Route.place(place.id)) {
                            PlaceCard(place: place)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    /// Videos shown in each Explore video row (feed mode carries on through all of them).
    private static let rowLimit = 6

    /// The newest videos (for the selected discipline). Tapping one opens feed mode on the
    /// Recents tab at that video, where you can keep going through every recent video.
    @ViewBuilder
    private var recentClimbsCarousel: some View {
        let posts: [Post] = Array(store.posts.lazy
            .filter { $0.videoURL != nil && (discipline == nil || $0.discipline == discipline) }
            .prefix(Self.rowLimit))
        videoRow(title: "Recent climbs", posts: posts) { post in
            FeedModeStart(postID: post.id, recents: true)
        }
    }

    /// Trending videos (for the selected discipline): six here; tapping one opens feed mode
    /// through all of them.
    @ViewBuilder
    private var trendingCarousel: some View {
        let all = store.trendingPosts(discipline: discipline).filter { $0.videoURL != nil }
        videoRow(title: discipline.map { "Trending \($0.displayName)" } ?? "Trending sends",
                 posts: Array(all.prefix(Self.rowLimit))) { post in
            FeedModeStart(postID: post.id, postIDs: all.map(\.id))
        }
    }

    @ViewBuilder
    private func videoRow(title: String, posts: [Post], open: @escaping (Post) -> FeedModeStart) -> some View {
        if !posts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title3.bold()).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(posts) { post in
                            Button {
                                feedModeStart = open(post)
                            } label: {
                                RecentClimbCard(post: post)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder
    private func feedMode(_ start: FeedModeStart) -> some View {
        if start.recents {
            // Recents tab at the tapped video; Following (the home feed) a swipe away.
            let following = store.homeFeed().map(\.post.id)
            FeedModeView(postIDs: following, startID: following.first ?? start.postID,
                         showsHomeTabs: true, initialTab: .recents, recentsStartID: start.postID)
        } else {
            FeedModeView(postIDs: start.postIDs, startID: start.postID)
        }
    }

    /// Outdoor climbs with the most videos (beta), for the selected discipline.
    @ViewBuilder
    private var climbCarousel: some View {
        // Walks the cached ranking lazily and stops after 15 matches.
        let climbs: [Climb] = Array(store.mostFilmedClimbIDs()
            .lazy
            .compactMap { store.climb($0) }
            .filter { discipline == nil || $0.discipline == discipline }
            .prefix(15))
        if !climbs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Popular climbs").font(.title3.bold()).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(climbs) { climb in
                            NavigationLink(value: Route.climb(climb.id)) {
                                ClimbCard(climb: climb)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: Map

    private var mapView: some View {
        Map(position: $mapCamera, selection: $selectedPlaceID) {
            ForEach(placesOnMap) { place in
                Marker(place.name, systemImage: place.kind.symbolName, coordinate: place.coordinate)
                    .tint(place.kind == .gym ? Color.accentColor : Color.green)
                    .tag(place.id)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
        .safeAreaInset(edge: .bottom) {
            if let place = store.place(selectedPlaceID) {
                NavigationLink(value: Route.place(place.id)) {
                    PlaceRow(place: place)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding()
            }
        }
    }
}

extension ExploreView {
    /// Places inside the visible map area, most-followed first, capped at `maxMarkers`.
    /// The selected place is always kept so its card doesn't disappear.
    fileprivate var placesOnMap: [Place] {
        let region = visibleRegion
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        // Walks the (cached) popularity order and stops once the marker cap is reached.
        var shown: [Place] = []
        for id in store.popularPlaceIDs() {
            if shown.count >= Self.maxMarkers { break }
            guard let place = store.place(id),
                  place.latitude >= minLat, place.latitude <= maxLat,
                  place.longitude >= minLon, place.longitude <= maxLon else { continue }
            shown.append(place)
        }
        if let selected = store.place(selectedPlaceID), !shown.contains(selected) {
            shown.append(selected)
        }
        return shown
    }
}

private struct PlaceCard: View {
    @Environment(AppStore.self) private var store
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The place's profile picture (its most-liked community photo), else the placeholder.
            Group {
                if let cover = store.coverPhoto(of: .place(place.id)) {
                    CommunityPhotoImage(photo: cover)
                } else {
                    Rectangle()
                        .fill(Color.seeded(place.id).gradient)
                        .overlay {
                            Image(systemName: place.kind.symbolName)
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                }
            }
            .frame(width: 180, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(place.name).font(.subheadline.bold()).lineLimit(1)
            Text(place.locationLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text("\(store.followerCount(of: place.id)) followers")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 180)
    }
}

/// A climb in the Popular climbs row: its profile picture, name, crag, grade and video count.
private struct ClimbCard: View {
    @Environment(AppStore.self) private var store
    let climb: Climb

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let cover = store.coverPhoto(of: .climb(climb.id)) {
                    CommunityPhotoImage(photo: cover)
                } else {
                    Rectangle()
                        .fill(Color.seeded(climb.id).gradient)
                        .overlay {
                            DisciplineIcon(discipline: climb.discipline, size: 40)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                }
            }
            .frame(width: 180, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if let grade = store.averageGrade(forClimb: climb.id)?.grade ?? climb.grade {
                    GradeBadge(grade: grade).padding(6)
                }
            }
            Text(climb.name).font(.subheadline.bold()).lineLimit(1)
            Text(store.place(climb.placeID)?.name ?? climb.area)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            let videos = store.postCount(ofClimb: climb.id)
            Text("\(videos) \(videos == 1 ? "video" : "videos")")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 180)
    }
}

#Preview {
    ExploreView().environment(AppStore.preview)
}

/// Which video to open feed mode on from Explore, and through what.
private struct FeedModeStart: Identifiable {
    let postID: Post.ID
    /// Open on the Recents tab (else swipe through `postIDs`).
    var recents = false
    var postIDs: [Post.ID] = []
    var id: Post.ID { postID }
}

/// A video in the Recent climbs row: its poster frame with the climb, grade and who posted it.
private struct RecentClimbCard: View {
    @Environment(AppStore.self) private var store
    let post: Post

    var body: some View {
        VideoThumbnailView(post: post)
            .frame(width: 120, height: 170)
            // Darken the bottom so the text stays readable.
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    if let grade = store.displayGrade(for: post) {
                        GradeBadge(grade: grade)
                    }
                    Text(store.climb(post.climbID)?.name
                         ?? (post.routeName.isEmpty ? post.discipline.displayName : post.routeName))
                        .font(.caption.bold())
                        .lineLimit(2)
                    Text(store.user(post.authorID)?.username ?? "")
                        .font(.caption2)
                        .opacity(0.85)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3)
                .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
