import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

/// Post a send: pick/record a video, tag the gym or crag, add grade and description.
struct ComposeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PostDraft
    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoadingVideo = false
    @State private var isRecording = false
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var previewPlayer: AVPlayer?

    init(initialPlaceID: Place.ID? = nil) {
        var draft = PostDraft()
        draft.placeID = initialPlaceID
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                videoSection
                placeSection
                climbSection
                gradeSection
                Section("Description") {
                    TextField("How did it go? Beta, beta spray, celebrations…", text: $draft.caption, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("New Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView()
                    } else {
                        Button("Share", action: share)
                            .bold()
                            .disabled(!draft.isReady)
                    }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                loadVideo(from: item)
            }
            .onChange(of: draft.discipline) { _, discipline in
                if !discipline.gradeSystems.contains(draft.gradeSystem) {
                    draft.gradeSystem = discipline.defaultGradeSystem
                    draft.grade = nil
                    draft.proposedGrade = nil
                }
            }
            .onChange(of: draft.videoURL) { _, url in
                previewPlayer = url.map(AVPlayer.init(url:))
            }
            .fullScreenCover(isPresented: $isRecording) {
                VideoRecorder { url in
                    if let url { draft.videoURL = url }
                    isRecording = false
                }
                .ignoresSafeArea()
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Sections

    private var videoSection: some View {
        Section {
            if let previewPlayer {
                VideoPlayer(player: previewPlayer)
                    .frame(height: 320)
                    .listRowInsets(EdgeInsets())
            } else if isLoadingVideo {
                HStack {
                    ProgressView()
                    Text("Loading video…").foregroundStyle(.secondary)
                }
            }

            PhotosPicker(selection: $pickerItem, matching: .videos, preferredItemEncoding: .current) {
                Label(draft.videoURL == nil ? "Choose from library" : "Choose a different video",
                      systemImage: "photo.on.rectangle")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    isRecording = true
                } label: {
                    Label("Record a video", systemImage: "video.fill")
                }
            }
        } header: {
            Text("Video")
        } footer: {
            if draft.videoURL == nil {
                Text("A video is required to post a send.")
            }
        }
    }

    private var placeSection: some View {
        Section {
            NavigationLink {
                PlacePickerView(selection: $draft.placeID)
            } label: {
                if let place = store.place(draft.placeID) {
                    HStack {
                        PlaceIconView(place: place, size: 32)
                        VStack(alignment: .leading) {
                            Text(place.name)
                            Text(place.locationLine).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Label("Tag a gym or crag", systemImage: "mappin.and.ellipse")
                }
            }
        } header: {
            Text("Where")
        } footer: {
            if let place = store.place(draft.placeID) {
                Text("Everyone following \(place.name) will see this send.")
            } else {
                Text("Untagged sends are only shown to people who follow you.")
            }
        }
    }

    private var climbSection: some View {
        Section("Climb") {
            TextField("Route / problem name", text: $draft.routeName)

            Picker("Discipline", selection: $draft.discipline) {
                ForEach(ClimbDiscipline.allCases) { Text($0.displayName).tag($0) }
            }

            Picker("Style", selection: $draft.sendStyle) {
                ForEach(SendStyle.allCases) { Label($0.displayName, systemImage: $0.symbolName).tag($0) }
            }
        }
    }

    /// Both grades are optional: the official grade (from the gym/guidebook) and
    /// the poster's proposed grade ("feels like").
    private var gradeSection: some View {
        Section {
            if draft.discipline.gradeSystems.count > 1 {
                Picker("Scale", selection: gradeSystemBinding) {
                    ForEach(draft.discipline.gradeSystems) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            OptionalGradePicker(title: "Grade", system: draft.gradeSystem, grade: $draft.grade)
            OptionalGradePicker(title: "Proposed grade", system: draft.gradeSystem, grade: $draft.proposedGrade)
        } header: {
            Text("Grade")
        } footer: {
            Text("Grade is the official grade from the gym or guidebook. Proposed grade is what you think it really is. Both are optional.")
        }
    }

    /// Switching scales converts nothing; it just clears grades from the old scale.
    private var gradeSystemBinding: Binding<GradeSystem> {
        Binding {
            draft.gradeSystem
        } set: { system in
            draft.gradeSystem = system
            if draft.grade?.system != system { draft.grade = nil }
            if draft.proposedGrade?.system != system { draft.proposedGrade = nil }
        }
    }

    // MARK: Actions

    private func loadVideo(from item: PhotosPickerItem) {
        isLoadingVideo = true
        Task {
            defer { isLoadingVideo = false }
            do {
                if let movie = try await item.loadTransferable(type: PickedMovie.self) {
                    draft.videoURL = movie.url
                }
            } catch {
                errorMessage = "Couldn't load that video: \(error.localizedDescription)"
            }
        }
    }

    private func share() {
        isPosting = true
        Task {
            let success = await store.createPost(from: draft)
            isPosting = false
            if success {
                dismiss()
            } else {
                errorMessage = store.lastError ?? "Something went wrong."
            }
        }
    }
}

/// A grade that can be left blank: "Not set" or a value on the given scale.
private struct OptionalGradePicker: View {
    let title: String
    let system: GradeSystem
    @Binding var grade: Grade?

    var body: some View {
        Picker(title, selection: Binding(
            get: { grade?.value },
            set: { value in grade = value.map { Grade(system: system, value: $0) } }
        )) {
            Text("Not set").tag(String?.none)
            ForEach(system.grades, id: \.self) { Text($0).tag(String?.some($0)) }
        }
    }
}

// MARK: - Video import

enum SendVideoStorage {
    /// Copies a picked/recorded video into the app's Documents so it outlives the temp file.
    static func persist(_ source: URL) throws -> URL {
        let folder = URL.documentsDirectory.appending(path: "Sends", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let destination = folder.appending(path: "\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}

struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            PickedMovie(url: try SendVideoStorage.persist(received.file))
        }
    }
}

/// Wraps the system camera in video mode.
struct VideoRecorder: UIViewControllerRepresentable {
    /// Called with the saved video, or nil if the user cancelled.
    let onFinish: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 5 * 60
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: VideoRecorder

        init(parent: VideoRecorder) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let saved = (info[.mediaURL] as? URL).flatMap { try? SendVideoStorage.persist($0) }
            parent.onFinish(saved)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onFinish(nil)
        }
    }
}

#Preview {
    ComposeView(initialPlaceID: "p_granite_works").environment(AppStore.preview)
}
