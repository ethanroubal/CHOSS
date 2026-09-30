import SwiftUI
import MapKit

/// Full-screen, interactive map of one place: pan, zoom, rotate, switch to satellite
/// (handy for finding a crag's approach), jump back to the place, or get directions in Maps.
struct PlaceMapView: View {
    @Environment(\.dismiss) private var dismiss
    let place: Place

    @State private var position: MapCameraPosition
    @State private var style: Style = .standard

    enum Style: String, CaseIterable, Identifiable {
        case standard = "Map"
        case hybrid = "Satellite"
        var id: Self { self }
    }

    init(place: Place) {
        self.place = place
        _position = State(initialValue: Self.home(for: place))
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                Marker(place.name, systemImage: place.kind.symbolName, coordinate: place.coordinate)
            }
            .mapStyle(style == .hybrid ? MapStyle.hybrid(elevation: .realistic) : MapStyle.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
                MapPitchToggle()
            }
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Map style", selection: $style) {
                ForEach(Style.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)

            Spacer()

            Button {
                withAnimation { position = Self.home(for: place) }
            } label: {
                Image(systemName: "scope")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Center on \(place.name)")

            Button {
                openDirections()
            } label: {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(height: 36)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private static func home(for place: Place) -> MapCameraPosition {
        .region(MKCoordinateRegion(center: place.coordinate,
                                   span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
    }

    /// Opens Apple Maps with directions to the place.
    private func openDirections() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}

#Preview {
    if let place = AppStore.preview.place(SampleData.bishop) {
        PlaceMapView(place: place)
    }
}
