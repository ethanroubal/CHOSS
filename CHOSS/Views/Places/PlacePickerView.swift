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
    @State private var search = SearchResults()
    @State private var pageLimit = Paging.pageSize

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
                if resultIDs.count > pageLimit {
                    LoadMoreRow { pageLimit += Paging.pageSize }
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
        .runSearch(query, version: store.searchIndexVersion, into: $search) { [store] text in
            await store.searchPlaceIDs(text)
        }
        .onChange(of: query) { pageLimit = Paging.pageSize }
        .onSubmit(of: .search) {
            // Return picks the best match (searched now, in case the typed results haven't landed yet).
            let text = query
            guard !SearchResults.clean(text).isEmpty else { return }
            Task {
                if let best = await store.searchPlaceIDs(text, limit: 1).first {
                    selection = best
                    dismiss()
                }
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
    private var resultIDs: [Place.ID] {
        guard SearchResults.clean(query).isEmpty else { return Array(search.ids.prefix(pageLimit + 1)) }
        let followed = store.followedPlaces(of: store.currentUserID).map(\.id)
        return Paging.page(followed, then: store.popularPlaceIDs(), limit: pageLimit)
    }

    private var results: [Place] {
        resultIDs.prefix(pageLimit).compactMap { store.place($0) }
    }
}

/// Pick up to `User.maxHomePlaces` home gyms / crags. Tap to toggle; once the limit is reached,
/// other places are disabled until one is removed.
struct HomePlacesPickerView: View {
    @Environment(AppStore.self) private var store
    @Binding var selection: [Place.ID]

    @State private var query = ""
    @State private var addingPlace = false
    @State private var search = SearchResults()
    @State private var pageLimit = Paging.pageSize

    private let limit = User.maxHomePlaces
    private var isFull: Bool { selection.count >= limit }

    var body: some View {
        List {
            Section {
                if selection.isEmpty {
                    Text("None yet. Pick from the list below.")
                        .foregroundStyle(.secondary)
                }
                ForEach(selection, id: \.self) { id in
                    if let place = store.place(id) {
                        PlaceRow(place: place)
                    }
                }
                .onDelete { selection.remove(atOffsets: $0) }
                .onMove { selection.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Your home spots (\(selection.count)/\(limit))")
            } footer: {
                Text(isFull
                     ? "That's the maximum. Swipe one away to pick another."
                     : "Pick up to \(limit). Swipe to remove, drag to reorder.")
            }

            Section(query.isEmpty ? "Your places" : "Results") {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, place in
                    let isSelected = selection.contains(place.id)
                    Button {
                        toggle(place.id)
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
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isFull && !isSelected)
                    .opacity(isFull && !isSelected ? 0.4 : 1)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
                if resultIDs.count > pageLimit {
                    LoadMoreRow { pageLimit += Paging.pageSize }
                }
            }

            Section {
                Button {
                    addingPlace = true
                } label: {
                    Label("Can't find it? Add a gym or crag", systemImage: "plus.circle")
                }
                .disabled(isFull)
            }
        }
        .navigationTitle("Home gyms / crags")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if selection.count > 1 {
                EditButton()
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search gyms and crags by name or town")
        .autocorrectionDisabled()
        .runSearch(query, version: store.searchIndexVersion, into: $search) { [store] text in
            await store.searchPlaceIDs(text)
        }
        .onChange(of: query) { pageLimit = Paging.pageSize }
        .onSubmit(of: .search) {
            // Return adds the best match.
            let text = query
            guard !SearchResults.clean(text).isEmpty, !isFull else { return }
            Task {
                if let best = await store.searchPlaceIDs(text, limit: 1).first, !selection.contains(best), !isFull {
                    selection.append(best)
                    query = ""
                }
            }
        }
        .sheet(isPresented: $addingPlace) {
            AddPlaceView(suggestedName: query) { newID in
                if !isFull && !selection.contains(newID) { selection.append(newID) }
            }
        }
    }

    private func toggle(_ id: Place.ID) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else if !isFull {
            selection.append(id)
        }
    }

    /// With no query, followed places come first.
    private var resultIDs: [Place.ID] {
        guard SearchResults.clean(query).isEmpty else { return Array(search.ids.prefix(pageLimit + 1)) }
        let followed = store.followedPlaces(of: store.currentUserID).map(\.id)
        return Paging.page(followed, then: store.popularPlaceIDs(), limit: pageLimit)
    }

    private var results: [Place] {
        resultIDs.prefix(pageLimit).compactMap { store.place($0) }
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
