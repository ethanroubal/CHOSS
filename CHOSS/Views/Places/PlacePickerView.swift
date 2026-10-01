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

            // Like "Add a climb": anyone can add a missing gym or crag (drop a pin, pick the type).
            Section {
                Button {
                    addingPlace = true
                } label: {
                    Label(SearchResults.clean(query).isEmpty
                          ? "Add a new gym or crag"
                          : "Add “\(SearchResults.clean(query))” as a new gym or crag",
                          systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
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
    @Environment(\.dismiss) private var dismiss
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
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            if selection.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            // Picks apply as you tap; Done goes back to the profile with them.
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .bold()
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
/// Add a gym or crag that isn't listed yet: name it, choose gym or crag, and drop a pin where it
/// is (tap the map; search a town to get there quickly). The town / state / country fill in from
/// the pin. It shows as unverified until reviewed (see docs/PLACES_DATA_STRATEGY.md).
struct AddPlaceView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let onAdded: (Place.ID) -> Void

    @State private var name: String
    /// Must be chosen (no default), so nothing is filed as the wrong kind by accident.
    @State private var kind: PlaceKind?
    @State private var city = ""
    @State private var region = ""
    @State private var country = ""
    @State private var about = ""
    @State private var camera: MapCameraPosition = .region(Self.startRegion)
    @State private var pin: CLLocationCoordinate2D?
    @State private var locationQuery = ""
    @State private var isLocating = false
    @State private var isSaving = false

    /// The continental US (where the bundled directory is), until the climber searches or zooms.
    private static let startRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
        span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 50)
    )

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
                        ForEach(PlaceKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.symbolName).tag(Optional(kind))
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Gym or crag?")
                } footer: {
                    if kind == nil {
                        Text("Choose whether it's an indoor gym or an outdoor crag.")
                    }
                }

                locationSection

                Section {
                    TextField("About (optional)", text: $about, axis: .vertical)
                }

                Section {
                } footer: {
                    Text("New places are visible right away and marked unverified until a moderator or the owner confirms them.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add a gym or crag")
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

    /// Search to get near it, then tap the map to drop the pin exactly.
    private var locationSection: some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a town or address", text: $locationQuery)
                    .submitLabel(.search)
                    .onSubmit(findLocation)
                if isLocating { ProgressView() }
            }

            MapReader { proxy in
                Map(position: $camera) {
                    if let pin {
                        Marker(name.isEmpty ? "New \(kind?.displayName.lowercased() ?? "place")" : name,
                               systemImage: kind?.symbolName ?? "mappin",
                               coordinate: pin)
                            .tint(.red)
                    }
                }
                .onTapGesture { point in
                    guard let coordinate = proxy.convert(point, from: .local) else { return }
                    withAnimation(.snappy) { pin = coordinate }
                    fillAddress(from: coordinate)
                }
            }
            .frame(height: 300)
            .listRowInsets(EdgeInsets())

            if let pin {
                Label(String(format: "Pin at %.5f, %.5f. Tap the map again to move it.", pin.latitude, pin.longitude),
                      systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            TextField("City / nearest town", text: $city)
            TextField("State / region", text: $region)
            TextField("Country", text: $country)
        } header: {
            Text("Location")
        } footer: {
            if pin == nil {
                Text("Tap the map to drop a pin exactly where the \(kind?.displayName.lowercased() ?? "gym or crag") is. Zoom in for accuracy.")
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && kind != nil && pin != nil
    }

    /// Moves the map to a searched town / address (the pin is still dropped by hand).
    private func findLocation() {
        let query = locationQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isLocating = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        Task {
            let response = try? await MKLocalSearch(request: request).start()
            if let item = response?.mapItems.first {
                withAnimation {
                    camera = .region(MKCoordinateRegion(
                        center: item.placemark.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))
                }
            }
            isLocating = false
        }
    }

    /// Fills town / state / country from the pin (keeping anything already typed).
    private func fillAddress(from coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        Task {
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return }
            if city.isEmpty { city = placemark.locality ?? placemark.subAdministrativeArea ?? "" }
            if region.isEmpty { region = placemark.administrativeArea ?? "" }
            if country.isEmpty { country = placemark.isoCountryCode == "US" ? "US" : (placemark.country ?? "") }
        }
    }

    private func save() {
        guard let pin, let kind else { return }
        isSaving = true
        let place = Place(
            id: "p_\(UUID().uuidString)",
            name: name.trimmingCharacters(in: .whitespaces),
            kind: kind,
            city: city, region: region, country: country,
            latitude: pin.latitude, longitude: pin.longitude,
            // Not asked for: gym or crag is enough. An empty list means "any discipline"
            // (e.g. every discipline is offered when adding a climb there).
            disciplines: [],
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
