import SwiftUI
import PhotosUI

/// Used both for first-time profile setup and for editing later.
struct EditProfileView: View {
    enum Mode {
        case setup
        case edit
    }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    @State private var user: User
    @State private var isSaving = false
    @State private var error: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var photoToFrame: PhotoToFrame?
    @State private var isLoadingPhoto = false

    /// A picked photo waiting to be framed.
    private struct PhotoToFrame: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    /// Edit an existing profile.
    init(user: User) {
        mode = .edit
        _user = State(initialValue: user)
    }

    /// Set up a brand-new profile.
    init() {
        mode = .setup
        _user = State(initialValue: User(id: "u_\(UUID().uuidString)", username: "", displayName: "",
                                         bio: "", homePlaceID: nil))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        if mode == .setup {
                            WordmarkView(height: 36)
                            Text("Welcome! Set up your climber profile.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        photoPicker
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Profile") {
                    TextField("Name", text: $user.displayName)
                        .textContentType(.name)
                    TextField("Username", text: $user.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    TextField("Bio", text: $user.bio, axis: .vertical)
                        .lineLimit(2...4)
                    NavigationLink {
                        PlacePickerView(selection: $user.homePlaceID,
                                        title: "Home gym / crag",
                                        noneLabel: "No home gym / crag")
                    } label: {
                        LabeledContent("Home gym / crag") {
                            Text(store.place(user.homePlaceID)?.name ?? "Choose")
                                .foregroundStyle(user.homePlaceID == nil ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                        }
                    }
                }

                GradeRangeSection(
                    title: "Bouldering grade",
                    systems: ClimbDiscipline.boulder.gradeSystems,
                    range: $user.boulderRange
                )
                GradeRangeSection(
                    title: "Rope grade",
                    systems: ClimbDiscipline.sport.gradeSystems,
                    range: $user.ropeRange
                )

                Section {
                    Toggle("Show my grade on my profile", isOn: $user.showsGradeRange)
                } footer: {
                    Text("Your grade tells people what kind of climber you are. Hide it any time; it's still used to suggest climbs and places.")
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                loadPhoto(item)
            }
            .fullScreenCover(item: $photoToFrame) { photo in
                AvatarCropView(image: photo.image) {
                    photoToFrame = nil
                } onDone: { framed in
                    savePhoto(framed)
                    photoToFrame = nil
                }
            }
            .navigationTitle(mode == .setup ? "Set up your profile" : "Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .setup ? "Create" : "Save", action: save)
                        .bold()
                        .disabled(!isValid || isSaving)
                }
            }
            .alert("Couldn't save", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    /// Tap the avatar (or "Add photo") to pick a picture, then frame it.
    private var photoPicker: some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: $photoItem, matching: .images, preferredItemEncoding: .current) {
                AvatarView(user: user, size: 96)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: isLoadingPhoto ? "hourglass" : "camera.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Brand.onAccent)
                            .frame(width: 28, height: 28)
                            .background(Color.accentColor, in: Circle())
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(user.avatarURL == nil ? "Add profile photo" : "Change profile photo")

            HStack(spacing: 16) {
                PhotosPicker(user.avatarURL == nil ? "Add photo" : "Change photo",
                             selection: $photoItem, matching: .images, preferredItemEncoding: .current)
                    .font(.subheadline.bold())
                if user.avatarURL != nil {
                    Button("Remove", role: .destructive) {
                        user.avatarURL = nil
                    }
                    .font(.subheadline)
                }
            }
            // Separate tap targets inside a Form row (otherwise a tap triggers every button).
            .buttonStyle(.borderless)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            defer {
                isLoadingPhoto = false
                photoItem = nil  // so picking the same photo again still triggers
            }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let original = UIImage(data: data) else {
                error = "Couldn't load that photo."
                return
            }
            // Keep framing smooth with huge camera photos: 2048px on the long side is plenty
            // for a 600px avatar.
            let longSide = max(original.size.width, original.size.height)
            let target = longSide > 2048
                ? CGSize(width: original.size.width * 2048 / longSide, height: original.size.height * 2048 / longSide)
                : original.size
            let prepared = await original.byPreparingThumbnail(ofSize: target) ?? original
            photoToFrame = PhotoToFrame(image: prepared)
        }
    }

    private func savePhoto(_ image: UIImage) {
        do {
            let url = try AvatarStorage.save(image)
            AvatarImageCache.shared.store(image, for: url)
            user.avatarURL = url
        } catch {
            self.error = "Couldn't save the photo: \(error.localizedDescription)"
        }
    }

    private var cleanUsername: String {
        user.username.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var isValid: Bool {
        !user.displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && cleanUsername.count >= 3
            && cleanUsername.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
    }

    private func save() {
        var saved = user
        saved.username = cleanUsername
        saved.displayName = user.displayName.trimmingCharacters(in: .whitespaces)
        guard store.isUsernameAvailable(saved.username, excluding: saved.id) else {
            error = "@\(saved.username) is taken. Try another username."
            return
        }
        switch mode {
        case .edit:
            store.updateProfile(saved)
            dismiss()
        case .setup:
            isSaving = true
            Task {
                if await store.createAccount(saved) {
                    dismiss()
                } else {
                    error = store.lastError ?? "Something went wrong."
                }
                isSaving = false
            }
        }
    }
}

/// Optional grade or grade range: off, a single grade, or low–high.
private struct GradeRangeSection: View {
    let title: String
    let systems: [GradeSystem]
    @Binding var range: GradeRange?

    var body: some View {
        Section(title) {
            Toggle("Add \(title.lowercased())", isOn: Binding(
                get: { range != nil },
                set: { enabled in
                    if enabled {
                        let start = Grade.defaultGrade(in: systems[0]).value
                        range = GradeRange(system: systems[0], low: start, high: nil)
                    } else {
                        range = nil
                    }
                }
            ))

            if let current = range {
                Picker("Scale", selection: systemBinding(current)) {
                    ForEach(systems) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle("It's a range", isOn: Binding(
                    get: { current.high != nil },
                    set: { isRange in
                        range?.high = isRange ? nextGrade(after: current.low, in: current.system) : nil
                    }
                ))

                Picker(current.high == nil ? "Grade" : "From", selection: Binding(
                    get: { current.low },
                    set: { newLow in
                        range?.low = newLow
                        // Keep low ≤ high.
                        if let high = range?.high, rank(high, current.system) < rank(newLow, current.system) {
                            range?.high = newLow
                        }
                    }
                )) {
                    ForEach(current.system.grades, id: \.self) { Text($0).tag($0) }
                }

                if let high = current.high {
                    Picker("To", selection: Binding(
                        get: { high },
                        set: { range?.high = $0 }
                    )) {
                        ForEach(current.system.grades.filter { rank($0, current.system) >= rank(current.low, current.system) },
                                id: \.self) { Text($0).tag($0) }
                    }
                }

                LabeledContent("Shows as", value: current.display)
            }
        }
    }

    private func rank(_ grade: String, _ system: GradeSystem) -> Int {
        system.grades.firstIndex(of: grade) ?? 0
    }

    private func nextGrade(after grade: String, in system: GradeSystem) -> String {
        let grades = system.grades
        let index = min(rank(grade, system) + 1, grades.count - 1)
        return grades[index]
    }

    /// Changing the scale resets the grades to that scale's default.
    private func systemBinding(_ current: GradeRange) -> Binding<GradeSystem> {
        Binding(
            get: { current.system },
            set: { system in
                let start = Grade.defaultGrade(in: system).value
                range = GradeRange(system: system, low: start,
                                   high: current.high == nil ? nil : nextGrade(after: start, in: system))
            }
        )
    }
}

#Preview("Edit") {
    EditProfileView(user: SampleData.users[0]).environment(AppStore.preview)
}

#Preview("Setup") {
    EditProfileView().environment(AppStore.preview)
}
