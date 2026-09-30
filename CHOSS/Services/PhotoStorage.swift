import UIKit

/// Saves community photos as JPEGs on the device (a real backend would upload them instead),
/// downscaled so a photo is at most 1600 px on its longest side.
enum PhotoStorage {
    static let maxDimension: CGFloat = 1600

    /// Writes the image and returns its file URL, or nil if the data isn't an image.
    static func save(_ data: Data) -> URL? {
        guard let image = UIImage(data: data), let jpeg = downscaled(image).jpegData(compressionQuality: 0.85)
        else { return nil }
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        do {
            try jpeg.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("CommunityPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
