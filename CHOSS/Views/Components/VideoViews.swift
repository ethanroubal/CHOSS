import SwiftUI
import AVKit

/// Generates and caches poster frames for send videos.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, UIImage>()

    func thumbnail(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        guard let frame = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)) else {
            return nil
        }
        let image = UIImage(cgImage: frame.image)
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// Poster frame for a post, falling back to a colored placeholder while loading / if unavailable.
struct VideoThumbnailView: View {
    let post: Post
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.seeded(post.id).gradient)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: post.discipline.symbolName)
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .clipped()
        .task(id: post.videoURL) {
            guard let url = post.videoURL else { return }
            image = await ThumbnailCache.shared.thumbnail(for: url)
        }
    }
}

/// Tap-to-play inline video. Keeps only one AVPlayer alive per visible card.
struct SendVideoPlayer: View {
    let post: Post
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .onDisappear {
                        player.pause()
                        self.player = nil
                    }
            } else {
                VideoThumbnailView(post: post)
                    .overlay {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 6)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(perform: play)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Play video")
            }
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .clipped()
    }

    private func play() {
        guard let url = post.videoURL else { return }
        let player = AVPlayer(url: url)
        self.player = player
        player.play()
    }
}
