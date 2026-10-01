import SwiftUI

/// One climb in a list: name, area, grade, and how many videos (beta) it has.
struct ClimbRow: View {
    @Environment(AppStore.self) private var store
    let climb: Climb
    var showsCrag = false
    var isBestMatch = false

    var body: some View {
        let videos = store.postCount(ofClimb: climb.id)

        HStack(spacing: 12) {
            DisciplineIcon(discipline: climb.discipline, size: 26)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(climb.name).font(.headline).lineLimit(1)
                    if isBestMatch {
                        Text("Best match")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                if let grade = store.averageGrade(forClimb: climb.id)?.grade ?? climb.grade {
                    GradeBadge(grade: grade)
                }
                Label("\(videos)", systemImage: "video")
                    .font(.caption)
                    .foregroundStyle(videos == 0 ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.secondary)
                    .accessibilityLabel("\(videos) videos")
            }
        }
    }

    private var subtitle: String {
        var parts = [climb.area, climb.discipline.displayName].filter { !$0.isEmpty }
        if showsCrag, let crag = store.place(climb.placeID) {
            parts.insert(crag.name, at: 0)
        }
        return parts.joined(separator: " · ")
    }
}

/// A climb's page: every video people have posted of it, so you can find beta.
struct ClimbDetailView: View {
    @Environment(AppStore.self) private var store
    let climbID: Climb.ID

    private enum Sort: String, CaseIterable, Identifiable {
        case newest = "Most recent"
        case mostLiked = "Most liked"
        var id: Self { self }
    }

    @State private var sort: Sort = .newest
    @State private var composing = false

    var body: some View {
        ScrollView {
            if let climb = store.climb(climbID) {
                VStack(alignment: .leading, spacing: 16) {
                    header(climb)
                    stats(climb)

                    Button {
                        composing = true
                    } label: {
                        Label("Post your send of \(climb.name)", systemImage: "video.badge.plus")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Brand.onAccent)
                    .padding(.horizontal)

                    // Save it to your profile's Projects.
                    Button {
                        withAnimation(.snappy) { store.toggleProject(climb.id) }
                    } label: {
                        Label(store.isProject(climb.id) ? "Your project · Remove" : "Add as project",
                              systemImage: store.isProject(climb.id) ? "bookmark.fill" : "bookmark")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .sensoryFeedback(.selection, trigger: store.isProject(climb.id))
                    .padding(.horizontal)

                    videos(climb)
                    BrandFooter()
                }
                .navigationTitle(climb.name)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $composing) {
                    ComposeView(initialPlaceID: climb.placeID, initialClimbID: climb.id)
                }
            } else {
                ContentUnavailableView("Climb not found", systemImage: "mountain.2")
            }
        }
        .defaultScrollAnchor(.top)
        // Pull down to load videos (and photos) posted since the page opened.
        .refreshable { await store.load() }
    }

    private func header(_ climb: Climb) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Profile picture: the most-liked community photo (mountain placeholder until then).
            ClimbIconView(climb: climb, size: 72)
            HStack(alignment: .firstTextBaseline) {
                Text(climb.name).font(.title.bold())
                if let grade = store.averageGrade(forClimb: climb.id)?.grade ?? climb.grade {
                    GradeBadge(grade: grade, prominent: true)
                }
                if !climb.isVerified {
                    Text("Unverified")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            if let crag = store.place(climb.placeID) {
                NavigationLink(value: Route.place(crag.id)) {
                    Label(climb.area.isEmpty ? crag.name : "\(climb.area) · \(crag.name)",
                          systemImage: crag.kind.symbolName)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            Text(climb.discipline.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !climb.about.isEmpty {
                Text(climb.about).font(.subheadline)
            }
            CommunityPhotosBar(subject: .climb(climb.id), title: climb.name)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func stats(_ climb: Climb) -> some View {
        let sends = store.posts(ofClimb: climb.id)
        // Onsights and flashes are sends like any other: no separate stat.
        let sendCount = sends.filter { $0.sendStyle.countsAsSend }.count
        let average = store.averageGrade(forClimb: climb.id)

        return VStack(spacing: 10) {
            HStack {
                StatView(value: sends.count, label: "Videos")
                StatView(value: Set(sends.map(\.authorID)).count, label: "Climbers")
                StatView(value: sendCount, label: "Sends")
            }
            // The climb's grade is the community's: the average of everyone's proposed grades.
            Group {
                if let average {
                    Text(average.count == 1
                         ? "Grade from 1 climber's proposal"
                         : "Grade is the average of \(average.count) climbers' proposals")
                } else {
                    Text("No proposed grades yet. Post a send to propose one.")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let guidebook = climb.grade, guidebook != average?.grade {
                HStack(spacing: 6) {
                    Text("Guidebook grade")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    GradeBadge(grade: guidebook, isProposed: true)
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func videos(_ climb: Climb) -> some View {
        let sends = store.posts(ofClimb: climb.id)  // newest first
        let sorted = sort == .newest
            ? sends
            : sends.sorted { lhs, rhs in
                lhs.likedBy.count != rhs.likedBy.count
                    ? lhs.likedBy.count > rhs.likedBy.count
                    : lhs.createdAt > rhs.createdAt
            }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Beta videos").font(.title3.bold())
                Spacer()
                Picker("Sort", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .padding(.horizontal)

            if sorted.isEmpty {
                ContentUnavailableView(
                    "No beta yet",
                    systemImage: "video.slash",
                    description: Text("Nobody has posted a video of \(climb.name) yet. Be the first!")
                )
            } else {
                // Grid like a profile; tapping opens a scrollable feed in this order,
                // starting at the tapped video.
                PostGrid(posts: sorted, title: "\(climb.name) · \(sort.rawValue)", badge: .likes)
            }
        }
    }
}

/// Add a climb that isn't listed yet. The crag is picked from the crag directory (searchable),
/// pre-filled when opened from a crag. Warns about likely duplicates first.
struct AddClimbView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onAdded: (Climb) -> Void

    @State private var cragID: Place.ID?
    @State private var name: String
    @State private var area = ""
    @State private var discipline: ClimbDiscipline
    @State private var gradeSystem: GradeSystem
    @State private var grade: Grade?
    @State private var about = ""
    @State private var isSaving = false

    /// - Parameter placeID: the crag to pre-select (e.g. when adding from a crag's page), or nil
    ///   to let the climber choose.
    init(placeID: Place.ID? = nil, suggestedName: String = "", onAdded: @escaping (Climb) -> Void) {
        _cragID = State(initialValue: placeID)
        self.onAdded = onAdded
        _name = State(initialValue: suggestedName)
        let discipline = ClimbDiscipline.boulder
        _discipline = State(initialValue: discipline)
        _gradeSystem = State(initialValue: discipline.defaultGradeSystem)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        CragPickerView(selection: $cragID)
                    } label: {
                        if let crag = store.place(cragID) {
                            HStack(spacing: 12) {
                                PlaceIconView(place: crag, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(crag.name).font(.headline)
                                    Text(crag.locationLine).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Label("Choose the crag", systemImage: "mountain.2")
                                .foregroundStyle(.tint)
                        }
                    }
                } header: {
                    Text("Crag")
                } footer: {
                    if cragID == nil {
                        Text("Search the crag directory so the climb lands on the right crag's page.")
                    }
                }

                Section {
                    TextField("Climb name", text: $name)
                        .autocorrectionDisabled()
                }

                areaSection

                if let duplicate = likelyDuplicate {
                    Section {
                        Button {
                            onAdded(duplicate)
                            dismiss()
                        } label: {
                            Label("Did you mean \(duplicate.name)? Use that instead", systemImage: "exclamationmark.triangle")
                        }
                    } footer: {
                        Text("Using the existing climb keeps all the beta for it in one place.")
                    }
                }

                Section("Climb") {
                    Picker("Discipline", selection: $discipline) {
                        ForEach(disciplines) { DisciplineLabel(discipline: $0).tag($0) }
                    }
                    if discipline.gradeSystems.count > 1 {
                        GradeScalePicker(selection: $gradeSystem, systems: discipline.gradeSystems)
                    }
                    OptionalGradePicker(title: "Guidebook grade", system: gradeSystem, grade: $grade)
                    TextField("Description (optional)", text: $about, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Add a climb")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save)
                        .bold()
                        .disabled(trimmedName.isEmpty || cragID == nil || isSaving)
                }
            }
            // The crag's climbs (for area suggestions and "Did you mean…?").
            .task(id: cragID) {
                if let cragID { await store.loadClimbs(at: cragID) }
            }
            .onChange(of: cragID) { _, _ in
                // Areas and disciplines belong to the crag; reset what no longer fits.
                if !knownAreas.contains(area) { area = "" }
                if let first = disciplines.first, !disciplines.contains(discipline) {
                    discipline = first
                }
            }
            .onChange(of: discipline) { _, newValue in
                if !newValue.gradeSystems.contains(gradeSystem) {
                    gradeSystem = newValue.defaultGradeSystem
                }
            }
            .onChange(of: gradeSystem) { _, newValue in
                if grade?.system != newValue { grade = nil }
            }
            .onAppear {
                if let first = disciplines.first, !disciplines.contains(discipline) {
                    discipline = first
                    gradeSystem = first.defaultGradeSystem
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every discipline: a crag's listed disciplines are incomplete (ice in winter, a boulder
    /// under a sport wall…), so they don't limit what a new climb can be.
    private var disciplines: [ClimbDiscipline] { ClimbDiscipline.allCases }

    private var knownAreas: [String] {
        guard let cragID else { return [] }
        return Array(Set(store.climbs(at: cragID).map(\.area).filter { !$0.isEmpty })).sorted()
    }

    /// Climbs per area at the crag (for ordering suggestions and showing counts).
    private var areaCounts: [String: Int] {
        guard let cragID else { return [:] }
        return Dictionary(grouping: store.climbs(at: cragID).filter { !$0.area.isEmpty }, by: \.area)
            .mapValues(\.count)
    }

    private var trimmedArea: String {
        area.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The existing area the typed text is (same name ignoring case, accents and punctuation).
    private var exactArea: String? {
        let typed = NameMatcher.normalize(trimmedArea)
        guard !typed.isEmpty else { return nil }
        return knownAreas.first { NameMatcher.normalize($0) == typed }
    }

    /// Existing areas that match what's typed, best first (typos, initials and word order are
    /// forgiven, like every search); the busiest areas when nothing is typed.
    private var suggestedAreas: [String] {
        let counts = areaCounts
        let ranked = NameMatcher.rank(knownAreas, query: trimmedArea, names: { [$0] }) { lhs, rhs in
            (counts[lhs] ?? 0) != (counts[rhs] ?? 0) ? (counts[lhs] ?? 0) > (counts[rhs] ?? 0) : lhs < rhs
        }
        let ordered = trimmedArea.isEmpty
            ? knownAreas.sorted { (counts[$0] ?? 0) != (counts[$1] ?? 0) ? (counts[$0] ?? 0) > (counts[$1] ?? 0) : $0 < $1 }
            : ranked
        return Array(ordered.filter { $0 != exactArea }.prefix(5))
    }

    /// Area / wall / boulder: type to search the crag's existing areas and tap one, so climbs on
    /// the same wall are grouped together; a name that matches nothing becomes a new area.
    private var areaSection: some View {
        Section {
            HStack {
                TextField("Area / wall / boulder (optional)", text: $area)
                    .autocorrectionDisabled()
                if exactArea != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Existing area")
                }
            }
            ForEach(Array(suggestedAreas.enumerated()), id: \.element) { index, known in
                Button {
                    area = known
                } label: {
                    HStack {
                        Label(known, systemImage: "mappin.and.ellipse")
                            .foregroundStyle(Color.primary)
                        if index == 0 && !trimmedArea.isEmpty {
                            Text("Best match")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(.tint)
                        }
                        Spacer()
                        let count = areaCounts[known] ?? 0
                        Text("\(count) \(count == 1 ? "climb" : "climbs")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Area")
        } footer: {
            if let exactArea {
                Text("Adding to \(exactArea), with the other climbs there.")
            } else if !trimmedArea.isEmpty {
                Text(suggestedAreas.isEmpty
                     ? "“\(trimmedArea)” will be a new area at this crag."
                     : "Tap an existing area if it's one of these, or keep “\(trimmedArea)” as a new area.")
            } else if !knownAreas.isEmpty {
                Text("Start typing to find the wall or boulder, or pick one of the busiest areas.")
            }
        }
    }

    /// An existing climb here with a very similar name.
    private var likelyDuplicate: Climb? {
        guard trimmedName.count >= 3, let cragID else { return nil }
        return store.climbs(at: cragID).first { climb in
            (NameMatcher.score(query: trimmedName, climb: climb) ?? 0) >= 80
        }
    }

    private func save() {
        guard let cragID else { return }
        isSaving = true
        let climb = Climb(
            id: "c_\(UUID().uuidString)",
            placeID: cragID,
            name: trimmedName,
            area: exactArea ?? trimmedArea,  // an existing area keeps its exact spelling
            discipline: discipline,
            grade: grade,
            about: about.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .userSubmitted,
            isVerified: false,
            createdBy: store.currentUserID
        )
        Task {
            if let saved = await store.addClimb(climb) {
                onAdded(saved)
                dismiss()
            }
            isSaving = false
        }
    }
}

/// Search the crag directory (crags only): typo-tolerant, by name or nearby town,
/// best match first; return picks it. Followed crags come first before you type.
struct CragPickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Place.ID?

    @State private var query = ""
    @State private var search = SearchResults()
    @State private var pageLimit = Paging.pageSize

    var body: some View {
        let results = crags

        List {
            Section(query.isEmpty ? "Crags" : "Results") {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, crag in
                    Button {
                        selection = crag.id
                        dismiss()
                    } label: {
                        HStack {
                            PlaceRow(place: crag)
                            if index == 0 && !query.isEmpty {
                                Text("Best match")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.tint)
                            }
                            if selection == crag.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if cragIDs.count > pageLimit {
                    LoadMoreRow { pageLimit += Paging.pageSize }
                }
            }
        }
        .overlay {
            if search.isEmpty(for: query) {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Choose a crag")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search crags by name or town")
        .autocorrectionDisabled()
        .runSearch(query, version: store.searchIndexVersion, into: $search) { [store] text in
            await store.searchPlaceIDs(text, kind: .crag)
        }
        .onChange(of: query) { pageLimit = Paging.pageSize }
        .onSubmit(of: .search) {
            let text = query
            guard !SearchResults.clean(text).isEmpty else { return }
            Task {
                if let best = await store.searchPlaceIDs(text, kind: .crag, limit: 1).first {
                    selection = best
                    dismiss()
                }
            }
        }
    }

    private var cragIDs: [Place.ID] {
        guard SearchResults.clean(query).isEmpty else { return Array(search.ids.prefix(pageLimit + 1)) }
        let followed = store.followedPlaces(of: store.currentUserID).filter { $0.kind == .crag }.map(\.id)
        return Paging.page(followed, then: store.popularPlaceIDs(kind: .crag), limit: pageLimit)
    }

    private var crags: [Place] {
        cragIDs.prefix(pageLimit).compactMap { store.place($0) }
    }
}

#Preview("Climb") {
    NavigationStack {
        ClimbDetailView(climbID: "c_midnight_lightning").withAppRoutes()
    }
    .environment(AppStore.preview)
}
