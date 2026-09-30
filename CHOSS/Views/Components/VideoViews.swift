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
                DisciplineIcon(discipline: post.discipline, size: 40)
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

/// Owns one looping player for a post. Created lazily when the post scrolls into view and
/// torn down when it leaves, so only on-screen posts hold video resources.
@MainActor
final class LoopingPlayback: ObservableObject {
    let player = AVQueuePlayer()
    @Published private(set) var isReady = false
    private var looper: AVPlayerLooper?
    private var loadedURL: URL?
    private var statusObservation: NSKeyValueObservation?

    func load(_ url: URL) {
        guard loadedURL != url else { return }
        unload()
        loadedURL = url
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor in
                if playing { self?.isReady = true }
            }
        }
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func unload() {
        player.pause()
        statusObservation = nil
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        loadedURL = nil
        isReady = false
    }
}

/// Plain video surface with no system controls (taps are handled by `SendVideoPlayer`).
private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    /// Fill (crop) inline; fit (whole frame, letterboxed) full screen.
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
        view.playerLayer.videoGravity = gravity
    }
}

/// Instagram-style inline video: plays automatically (looping) while mostly on screen, pauses when
/// scrolled away. Tap to pause/resume, double-tap to like / unlike, speaker button to mute/unmute,
/// and the corner button opens it full screen.
///
/// Its height is capped so a vertical video never fills the screen: the author above it and the
/// likes / comments below stay visible while scrolling. Taller videos are cropped to fit.
struct SendVideoPlayer: View {
    let post: Post
    var onDoubleTap: () -> Void = {}

    /// Shared across all videos, like Instagram's sound toggle.
    @AppStorage("videosMuted") private var isMuted = false
    @StateObject private var playback = LoopingPlayback()
    @State private var isOnScreen = false
    /// False while another screen is pushed on top (the view stays in the hierarchy but hidden).
    @State private var isAppeared = false
    @State private var isPausedByUser = false
    @State private var isFullScreen = false
    @Environment(\.scenePhase) private var scenePhase

    /// 4:5 at full width, but never more than about half the screen's height.
    static var height: CGFloat {
        let screen = UIScreen.main.bounds
        return min(screen.width * 5 / 4, screen.height * 0.55)
    }

    var body: some View {
        // A fixed-size frame with the video laid over it: fill-scaled content (a tall video's
        // poster or player) can't grow the frame, it's cropped instead.
        Color.clear
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .overlay {
            ZStack {
                VideoThumbnailView(post: post)
                if post.videoURL != nil {
                    PlayerSurface(player: playback.player)
                        .opacity(playback.isReady ? 1 : 0)
                }
                if isPausedByUser {
                    Image(systemName: "play.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 6)
                        .transition(.opacity)
                }
            }
        }
        .clipped()
        .overlay(alignment: .topTrailing) {
            if post.videoURL != nil {
                Button {
                    isFullScreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .padding(10)
                .accessibilityLabel("Full screen")
            }
        }
        .fullScreenCover(isPresented: $isFullScreen, onDismiss: updatePlayback) {
            FullScreenVideoView(post: post, onDoubleTap: onDoubleTap)
        }
        .onChange(of: isFullScreen) { _, _ in updatePlayback() }
        .overlay(alignment: .bottomTrailing) {
            if post.videoURL != nil {
                Button {
                    isMuted.toggle()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .padding(10)
                .accessibilityLabel(isMuted ? "Unmute" : "Mute")
            }
        }
        .contentShape(Rectangle())
        // Double-tap is declared first so a single tap waits to see if a second one follows.
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) { isPausedByUser.toggle() }
            updatePlayback()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isPausedByUser ? "Play video" : "Pause video")
        // Autoplay when at least 60% of the video is on screen.
        .onGeometryChange(for: Bool.self) { proxy in
            let frame = proxy.frame(in: .global)
            let screen = UIScreen.main.bounds
            let visible = frame.intersection(screen)
            guard !visible.isNull, frame.height > 0 else { return false }
            return visible.height / frame.height >= 0.6
        } action: { onScreen in
            isOnScreen = onScreen
            if !onScreen { isPausedByUser = false }
            updatePlayback()
        }
        .onChange(of: isMuted) { _, muted in playback.player.isMuted = muted }
        .onChange(of: scenePhase) { _, _ in updatePlayback() }
        .onAppear {
            isAppeared = true
            updatePlayback()
        }
        .onDisappear {
            isAppeared = false
            playback.unload()
        }
    }

    private func updatePlayback() {
        guard let url = post.videoURL else { return }
        if isOnScreen && isAppeared && !isFullScreen && scenePhase == .active {
            playback.load(url)
            playback.player.isMuted = isMuted
            if isPausedByUser { playback.pause() } else { playback.play() }
        } else {
            playback.pause()
        }
    }
}

/// A send video full screen: the whole frame (letterboxed, not cropped), looping with sound.
/// Tap to pause, double-tap to like / unlike, swipe down or tap the X to close.
struct FullScreenVideoView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let post: Post
    var onDoubleTap: () -> Void = {}

    @AppStorage("videosMuted") private var isMuted = false
    @StateObject private var playback = LoopingPlayback()
    @State private var isPaused = false
    @State private var dragOffset: CGFloat = 0
    @State private var likeBurst = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerSurface(player: playback.player, gravity: .resizeAspect)
                .ignoresSafeArea()
            if isPaused {
                Image(systemName: "play.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 6)
            }
            LikeBurst(trigger: likeBurst)
        }
        .offset(y: dragOffset)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture {
            isPaused.toggle()
            if isPaused { playback.pause() } else { playback.play() }
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in dragOffset = max(value.translation.height, 0) }
                .onEnded { value in
                    if value.translation.height > 120 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                    }
                }
        )
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .padding()
            .accessibilityLabel("Close")
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                isMuted.toggle()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .padding()
            .accessibilityLabel(isMuted ? "Unmute" : "Mute")
        }
        .statusBarHidden()
        .onAppear {
            guard let url = post.videoURL else { return }
            playback.load(url)
            playback.player.isMuted = isMuted
            playback.play()
        }
        .onDisappear { playback.unload() }
        .onChange(of: isMuted) { _, muted in playback.player.isMuted = muted }
        .onChange(of: store.isLiked(post.id)) { _, liked in
            if liked { likeBurst += 1 }
        }
    }
}
