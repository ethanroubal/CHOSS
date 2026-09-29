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
            .navigationTitle("Explore")
            // Compact bar: a large title that collapses on scroll fights the switcher in the
            // title slot and makes the page jump around when you scroll back to the top.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            .withAppRoutes()
        }
    }

    // MARK: Sends

    private var sendsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                disciplineChips

                placeCarousel(title: "Popular gyms", places: Array(store.popularPlaces(kind: .gym).prefix(15)))
                placeCarousel(title: "Popular crags", places: Array(store.popularPlaces(kind: .crag).prefix(15)))

                Text("Trending sends")
                    .font(.title3.bold())
                    .padding(.horizontal)
                PostGrid(posts: store.trendingPosts(discipline: discipline),
                         title: discipline.map { "Trending \($0.displayName)" } ?? "Trending")
                BrandFooter()
            }
        }
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
        var shown = Array(
            store.popularPlaces()
                .filter { $0.latitude >= minLat && $0.latitude <= maxLat && $0.longitude >= minLon && $0.longitude <= maxLon }
                .prefix(Self.maxMarkers)
        )
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
            Rectangle()
                .fill(Color.seeded(place.id).gradient)
                .frame(width: 180, height: 100)
                .overlay {
                    Image(systemName: place.kind.symbolName)
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(place.name).font(.subheadline.bold()).lineLimit(1)
            Text(place.locationLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text("\(store.followerCount(of: place.id)) followers")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 180)
    }
}

#Preview {
    ExploreView().environment(AppStore.preview)
}
