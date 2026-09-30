import SwiftUI
import PhotosUI

/// Loads community photos from disk off the main thread and keeps recent ones in memory.
@MainActor
final class PhotoImageCache {
    static let shared = PhotoImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            return image.preparingForDisplay() ?? image
        }.value
        if let loaded { cache.setObject(loaded, forKey: url as NSURL) }
        return loaded
    }
}

/// A community photo, filling its frame (cropped). Shows a soft placeholder while loading.
struct CommunityPhotoImage: View {
    let photo: CommunityPhoto
    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemFill)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: photo.imageURL) {
                image = await PhotoImageCache.shared.image(for: photo.imageURL)
            }
    }
}

/// A climb's profile picture: its most-liked community photo, or a mountain placeholder.
struct ClimbIconView: View {
    @Environment(AppStore.self) private var store
    let climb: Climb
    var size: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        Group {
            if let cover = store.coverPhoto(of: .climb(climb.id)) {
                CommunityPhotoImage(photo: cover)
            } else {
                shape
                    .fill(Color.seeded(climb.id).gradient)
                    .overlay {
                        Image(systemName: "mountain.2.fill")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }
}

/// Under a place's or climb's name: add a community photo, and see them all.
struct CommunityPhotosBar: View {
    @Environment(AppStore.self) private var store
    let subject: PhotoSubject
    /// The place or climb name, for titles.
    let title: String

    var body: some View {
        let count = store.communityPhotos(of: subject).count
        HStack(spacing: 8) {
            AddCommunityPhotoButton(subject: subject)
                .buttonStyle(.bordered)
            NavigationLink {
                CommunityPhotosView(subject: subject, title: title)
            } label: {
                Label(count == 0 ? "Photos" : "Photos · \(count)", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Picks a photo from the library and adds it (with a spinner while it's saved).
struct AddCommunityPhotoButton: View {
    @Environment(AppStore.self) private var store
    let subject: PhotoSubject
    var label = "Add photo"

    @State private var item: PhotosPickerItem?
    @State private var isAdding = false

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            if isAdding {
                ProgressView().controlSize(.small)
            } else {
                Label(label, systemImage: "camera")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .disabled(isAdding)
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            isAdding = true
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await store.addCommunityPhoto(data, to: subject)
                }
                item = nil
                isAdding = false
            }
        }
    }
}

/// Every community photo of a place or climb in a grid, most liked first. The first one is the
/// page's profile picture. Like photos with the bicep; tap one to see it large.
struct CommunityPhotosView: View {
    @Environment(AppStore.self) private var store
    let subject: PhotoSubject
    let title: String

    @State private var viewing: CommunityPhoto.ID?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        let photos = store.communityPhotos(of: subject)
        ScrollView {
            if photos.isEmpty {
                ContentUnavailableView {
                    Label("No photos yet", systemImage: "photo.on.rectangle")
                } description: {
                    Text("Add the first photo of \(title). The most-liked photo becomes its profile picture.")
                } actions: {
                    AddCommunityPhotoButton(subject: subject)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 60)
            } else {
                Text("The most-liked photo is \(title)'s profile picture.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        PhotoTile(photo: photo, isCover: index == 0) { viewing = photo.id }
                    }
                }
            }
        }
        .navigationTitle("\(title) photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AddCommunityPhotoButton(subject: subject, label: "Add")
            }
        }
        .sheet(item: Binding(
            get: { viewing.map { PhotoSelection(id: $0) } },
            set: { viewing = $0?.id }
        )) { selection in
            PhotoViewer(photoID: selection.id)
        }
    }
}

private struct PhotoSelection: Identifiable {
    let id: CommunityPhoto.ID
}

/// A square tile with the like button and count; a crown marks the profile picture.
private struct PhotoTile: View {
    @Environment(AppStore.self) private var store
    let photo: CommunityPhoto
    let isCover: Bool
    let onOpen: () -> Void

    var body: some View {
        let liked = store.isPhotoLiked(photo.id)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { CommunityPhotoImage(photo: photo) }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .overlay(alignment: .topLeading) {
                if isCover {
                    Label("Profile", systemImage: "crown.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Button {
                    store.togglePhotoLike(photo.id)
                } label: {
                    HStack(spacing: 3) {
                        FlexIcon(filled: liked, size: 14)
                        Text("\(photo.likedBy.count)").monospacedDigit()
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(liked ? Color.accentColor : Color.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(liked ? "Unlike photo" : "Like photo")
                .sensoryFeedback(trigger: liked) { _, isLiked in
                    isLiked ? SensoryFeedback.impact(weight: .light, intensity: 0.7) : nil
                }
            }
            .contextMenu {
                if photo.authorID == store.currentUserID {
                    Button("Delete photo", systemImage: "trash", role: .destructive) {
                        store.deleteCommunityPhoto(photo.id)
                    }
                }
            }
    }
}

/// One photo, large: who added it, likes (button or double-tap), and delete for your own.
private struct PhotoViewer: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let photoID: CommunityPhoto.ID

    @State private var image: UIImage?
    @State private var likeBurst = 0

    var body: some View {
        NavigationStack {
            if let photo = store.communityPhotos.first(where: { $0.id == photoID }) {
                let liked = store.isPhotoLiked(photo.id)
                VStack(spacing: 12) {
                    ZStack {
                        Color.black
                        if let image {
                            Image(uiImage: image).resizable().scaledToFit()
                        } else {
                            ProgressView().tint(.white)
                        }
                        LikeBurst(trigger: likeBurst)
                    }
                    .onTapGesture(count: 2) { store.togglePhotoLike(photo.id) }

                    HStack {
                        Button {
                            store.togglePhotoLike(photo.id)
                        } label: {
                            HStack(spacing: 6) {
                                FlexIcon(filled: liked, size: 24)
                                Text("\(photo.likedBy.count) \(photo.likedBy.count == 1 ? "like" : "likes")")
                                    .font(.subheadline.bold())
                            }
                            .foregroundStyle(liked ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("Added by @\(store.user(photo.authorID)?.username ?? "unknown")")
                                .font(.caption.bold())
                            Text(photo.createdAt, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
                .task(id: photo.imageURL) {
                    image = await PhotoImageCache.shared.image(for: photo.imageURL)
                }
                .onChange(of: liked) { _, isLiked in
                    if isLiked { likeBurst += 1 }
                }
                .sensoryFeedback(trigger: liked) { _, isLiked in
                    isLiked ? SensoryFeedback.impact(weight: .light, intensity: 0.7) : nil
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                    if photo.authorID == store.currentUserID {
                        ToolbarItem(placement: .destructiveAction) {
                            Button("Delete", role: .destructive) {
                                store.deleteCommunityPhoto(photo.id)
                                dismiss()
                            }
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Photo removed", systemImage: "photo")
            }
        }
    }
}
