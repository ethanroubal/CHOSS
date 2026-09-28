import SwiftUI

/// One climb in a list: name, area, grade, and how many videos (beta) it has.
struct ClimbRow: View {
    @Environment(AppStore.self) private var store
    let climb: Climb
    var showsCrag = false
    var isBestMatch = false

    var body: some View {
        let videos = store.posts(ofClimb: climb.id).count

        HStack(spacing: 12) {
            Image(systemName: climb.discipline.symbolName)
                .font(.title3)
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
                if let grade = climb.grade {
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
        case newest = "Newest"
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
    }

    private func header(_ climb: Climb) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(climb.name).font(.title.bold())
                if let grade = climb.grade {
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
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func stats(_ climb: Climb) -> some View {
        let sends = store.posts(ofClimb: climb.id)
        let flashes = sends.filter { $0.sendStyle == .flash || $0.sendStyle == .onsight }.count

        return VStack(spacing: 10) {
            HStack {
                StatView(value: sends.count, label: "Videos")
                StatView(value: Set(sends.map(\.authorID)).count, label: "Climbers")
                StatView(value: flashes, label: "Flashes")
            }
            if let community = store.communityGrade(for: climb.id) {
                HStack(spacing: 6) {
                    Text("Climbers say it feels like")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    GradeBadge(grade: community, isProposed: true)
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func videos(_ climb: Climb) -> some View {
        let sends = store.posts(ofClimb: climb.id)
        let sorted = sort == .newest
            ? sends
            : sends.sorted { $0.likedBy.count > $1.likedBy.count }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Beta videos").font(.title3.bold())
                Spacer()
                Picker("Sort", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)

            if sorted.isEmpty {
                ContentUnavailableView(
                    "No beta yet",
                    systemImage: "video.slash",
                    description: Text("Nobody has posted a video of \(climb.name) yet. Be the first!")
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(sorted) { post in
                        PostCardView(post: post)
                        Divider()
                    }
                }
            }
        }
    }
}

/// Composer step for outdoor sends: search the crag's climbs by name and pick the best match.
struct ClimbPickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let placeID: Place.ID
    let onPick: (Climb) -> Void

    @State private var query = ""
    @State private var addingClimb = false

    var body: some View {
        let results = store.searchClimbs(query, at: placeID)

        List {
            Section {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, climb in
                    Button {
                        pick(climb)
                    } label: {
                        ClimbRow(climb: climb, isBestMatch: index == 0 && !query.isEmpty)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                if !results.isEmpty {
                    Text(query.isEmpty ? "Climbs at \(store.place(placeID)?.name ?? "this crag")" : "Matches")
                }
            } footer: {
                if !query.isEmpty && !results.isEmpty {
                    Text("Tip: press return to pick the best match.")
                }
            }

            Section {
                Button {
                    addingClimb = true
                } label: {
                    Label(query.isEmpty ? "Can't find it? Add a climb" : "Add “\(query)” as a new climb",
                          systemImage: "plus.circle")
                }
            } footer: {
                Text("Linking your video to the climb puts it on that climb's page, so people looking for beta can find it.")
            }
        }
        .navigationTitle("Which climb?")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search climb names")
        .autocorrectionDisabled()
        .onSubmit(of: .search) {
            if let best = results.first, !query.isEmpty { pick(best) }
        }
        .sheet(isPresented: $addingClimb) {
            AddClimbView(placeID: placeID, suggestedName: query) { climb in
                pick(climb)
            }
        }
    }

    private func pick(_ climb: Climb) {
        onPick(climb)
        dismiss()
    }
}

/// Add a climb that isn't listed yet. Warns about likely duplicates first.
struct AddClimbView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let placeID: Place.ID
    let onAdded: (Climb) -> Void

    @State private var name: String
    @State private var area = ""
    @State private var discipline: ClimbDiscipline
    @State private var gradeSystem: GradeSystem
    @State private var grade: Grade?
    @State private var about = ""
    @State private var isSaving = false

    init(placeID: Place.ID, suggestedName: String = "", onAdded: @escaping (Climb) -> Void) {
        self.placeID = placeID
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
                    TextField("Climb name", text: $name)
                        .autocorrectionDisabled()
                    TextField("Area / wall / boulder (optional)", text: $area)
                    if !knownAreas.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(knownAreas, id: \.self) { known in
                                    Button(known) { area = known }
                                        .buttonStyle(.bordered)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }

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
                        ForEach(disciplines) { Text($0.displayName).tag($0) }
                    }
                    if discipline.gradeSystems.count > 1 {
                        Picker("Scale", selection: $gradeSystem) {
                            ForEach(discipline.gradeSystems) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
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
                        .disabled(trimmedName.isEmpty || isSaving)
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

    /// The crag's disciplines (all of them if the crag doesn't say).
    private var disciplines: [ClimbDiscipline] {
        let listed = store.place(placeID)?.disciplines ?? []
        return listed.isEmpty ? ClimbDiscipline.allCases : listed
    }

    private var knownAreas: [String] {
        Array(Set(store.climbs(at: placeID).map(\.area).filter { !$0.isEmpty })).sorted()
    }

    /// An existing climb here with a very similar name.
    private var likelyDuplicate: Climb? {
        guard trimmedName.count >= 3 else { return nil }
        return store.climbs(at: placeID).first { climb in
            (NameMatcher.score(query: trimmedName, climb: climb) ?? 0) >= 80
        }
    }

    private func save() {
        isSaving = true
        let climb = Climb(
            id: "c_\(UUID().uuidString)",
            placeID: placeID,
            name: trimmedName,
            area: area.trimmingCharacters(in: .whitespacesAndNewlines),
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

#Preview("Climb") {
    NavigationStack {
        ClimbDetailView(climbID: "c_midnight_lightning").withAppRoutes()
    }
    .environment(AppStore.preview)
}
