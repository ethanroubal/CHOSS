import SwiftUI
import UIKit

/// Saves and loads profile pictures. Until there's a backend they live in the app's Documents
/// folder; a real backend would upload the JPEG and store its remote URL in `User.avatarURL`.
enum AvatarStorage {
    private static var folder: URL {
        URL.documentsDirectory.appending(path: "Avatars", directoryHint: .isDirectory)
    }

    /// Writes a cropped avatar and returns its file URL.
    static func save(_ image: UIImage) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(UUID().uuidString).jpg")
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Local files: the app's container path changes between installs, so fall back to looking
    /// the file up by name in the current Avatars folder.
    static func resolve(_ url: URL) -> URL {
        guard url.isFileURL, !FileManager.default.fileExists(atPath: url.path) else { return url }
        return folder.appending(path: url.lastPathComponent)
    }
}

/// Loads and caches avatar images (local files now, remote URLs later).
@MainActor
final class AvatarImageCache {
    static let shared = AvatarImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        let resolved = AvatarStorage.resolve(url)
        let image: UIImage?
        if resolved.isFileURL {
            image = UIImage(contentsOfFile: resolved.path)
        } else if let response = try? await URLSession.shared.data(from: resolved) {
            image = UIImage(data: response.0)
        } else {
            image = nil
        }
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }

    /// Put a freshly cropped image in the cache so it shows instantly everywhere.
    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}
