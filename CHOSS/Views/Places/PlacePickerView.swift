import SwiftUI
import MapKit

/// Searchable gym/crag picker, used when tagging a send and when choosing a home gym/crag.
/// Falls back to adding a new place.
struct PlacePickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Place.ID?
    var title = "Tag a place"
    /// Label for clearing the selection.
    var noneLabel = "No place (followers only)"

    @State private var query = ""
    @State private var addingPlace = false

    var body: some View {
        List {
            if selection != nil {
                Button(noneLabel, role: .destructive) {
                    selection = nil
                    dismiss()
                }
            }

            Section(query.isEmpty ? "Your places" : "Results") {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, place in
                    Button {
                        selection = place.id
                        dismiss()
                    } label: {
                        HStack {
                            PlaceRow(place: place)
                            if index == 0 && !query.isEmpty {
                                Text("Best match")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.tint)
                            }
                            if selection == place.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button {
                    addingPlace = true
                } label: {
                    Label("Can't find it? Add a gym or crag", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search gyms and crags by name or town")
        .autocorrectionDisabled()
        .onSubmit(of: .search) {
            // Return picks the best match.
            if let best = results.first, !query.isEmpty {
                selection = best.id
                dismiss()
            }
        }
        .sheet(isPresented: $addingPlace) {
            AddPlaceView(suggestedName: query) { newID in
                selection = newID
                dismiss()
            }
        }
    }

    /// With no query, followed places come first so posting at your usual gym is one tap.
    private var results: [Place] {
        guard query.isEmpty else { return store.searchPlaces(query) }
        let followed = store.followedPlaces(of: store.currentUserID)
        let others = store.allPlaces.filter { !followed.contains($0) }
        return followed + others
    }
}

/// User-submitted place. Shows as unverified until reviewed (see docs/PLACES_DATA_STRATEGY.md).
struct AddPlaceView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let onAdded: (Place.ID) -> Void

    @State private var name: String
    @State private var kind: PlaceKind = .gym
    @State private var city = ""
    @State private var region = ""
    @State private var country = ""
    @State private var disciplines: Set<ClimbDiscipline> = [.boulder]
    @State private var about = ""
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var center: CLLocationCoordinate2D?
    @State private var isSaving = false

    init(suggestedName: String = "", onAdded: @escaping (Place.ID) -> Void) {
        _name = State(initialValue: suggestedName)
        self.onAdded = onAdded
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(PlaceKind.allCases) { Label($0.displayName, systemImage: $0.symbolName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Location") {
                    Map(position: $camera)
                        .overlay {
                            Image(systemName: "mappin")
                                .font(.title)
                                .foregroundStyle(.red)
                                .offset(y: -12)
                                .allowsHitTesting(false)
                        }
                        .onMapCameraChange(frequency: .onEnd) { context in
                            center = context.region.center
                        }
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                    TextField("City / nearest town", text: $city)
                    TextField("State / region", text: $region)
                    TextField("Country", text: $country)
                }

                Section("Climbing") {
                    ForEach(ClimbDiscipline.allCases) { d in
                        Toggle(d.displayName, isOn: Binding(
                            get: { disciplines.contains(d) },
                            set: { if $0 { disciplines.insert(d) } else { disciplines.remove(d) } }
                        ))
                    }
                    TextField("About (optional)", text: $about, axis: .vertical)
                }

                Section {
                } footer: {
                    Text("New places are visible right away and marked unverified until a moderator or the owner confirms them.")
                }
            }
            .navigationTitle("Add a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save)
                        .bold()
                        .disabled(!canSave || isSaving)
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && center != nil && !disciplines.isEmpty
    }

    private func save() {
        guard let center else { return }
        isSaving = true
        let place = Place(
            id: "p_\(UUID().uuidString)",
            name: name.trimmingCharacters(in: .whitespaces),
            kind: kind,
            city: city, region: region, country: country,
            latitude: center.latitude, longitude: center.longitude,
            disciplines: ClimbDiscipline.allCases.filter(disciplines.contains),
            about: about,
            source: .userSubmitted,
            isVerified: false,
            createdBy: store.currentUserID
        )
        Task {
            if let saved = await store.addPlace(place) {
                onAdded(saved.id)
                dismiss()
            }
            isSaving = false
        }
    }
}
