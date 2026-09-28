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

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .sends: sendsView
                case .map: mapView
                }
            }
            .navigationTitle("Explore")
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

                placeCarousel(title: "Popular gyms", places: store.popularPlaces(kind: .gym))
                placeCarousel(title: "Popular crags", places: store.popularPlaces(kind: .crag))

                Text("Trending sends")
                    .font(.title3.bold())
                    .padding(.horizontal)
                PostGrid(posts: store.trendingPosts(discipline: discipline))
                BrandFooter()
            }
        }
    }

    private var disciplineChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                chip("All", systemImage: "square.grid.2x2", isOn: discipline == nil) { discipline = nil }
                ForEach(ClimbDiscipline.allCases) { d in
                    chip(d.displayName, systemImage: d.symbolName, isOn: discipline == d) { discipline = d }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
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
        Map(selection: $selectedPlaceID) {
            ForEach(store.allPlaces) { place in
                Marker(place.name, systemImage: place.kind.symbolName, coordinate: place.coordinate)
                    .tint(place.kind == .gym ? Color.accentColor : Color.green)
                    .tag(place.id)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
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
