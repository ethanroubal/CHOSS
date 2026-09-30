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
/// Grids crop it to fill; the player shows the whole frame (`fits`) on black, like the video.
struct VideoThumbnailView: View {
    let post: Post
    var fits = false
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if fits && image != nil {
                Color.black
            } else {
                Rectangle().fill(Color.seeded(post.id).gradient)
            }
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fits ? .fit : .fill)
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

/// Where a video is, for the scrubber. Separate from `LoopingPlayback` so the frequent time
/// updates only redraw the scrubber, not the whole post.
@MainActor
final class PlaybackProgress: ObservableObject {
    @Published var current: Double = 0
    @Published var duration: Double = 0
}

/// Owns one looping player for a post. Created lazily when the post scrolls into view and
/// torn down when it leaves, so only on-screen posts hold video resources.
@MainActor
final class LoopingPlayback: ObservableObject {
    let player = AVQueuePlayer()
    let progress = PlaybackProgress()
    @Published private(set) var isReady = false
    private var looper: AVPlayerLooper?
    private var loadedURL: URL?
    private var statusObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    /// Where to start once the video can play (e.g. continuing inline playback full screen).
    private var pendingStart: Double?
    /// True while the scrubber is being dragged, so time updates don't fight the finger.
    var isScrubbing = false

    /// Current position in seconds.
    var currentSeconds: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    func load(_ url: URL, startAt start: Double? = nil) {
        guard loadedURL != url else { return }
        unload()
        loadedURL = url
        pendingStart = (start ?? 0) > 0.05 ? start : nil
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor in
                guard let self, playing, !self.isReady else { return }
                if let start = self.pendingStart {
                    // Jump to the start point before showing the video, so it doesn't flash frame 0.
                    self.pendingStart = nil
                    self.player.seek(to: CMTime(seconds: start, preferredTimescale: 600),
                                     toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        Task { @MainActor in self.isReady = true }
                    }
                } else {
                    self.isReady = true
                }
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isScrubbing else { return }
                let duration = self.player.currentItem?.duration.seconds ?? 0
                if duration.isFinite, duration > 0, self.progress.duration != duration {
                    self.progress.duration = duration
                }
                if time.seconds.isFinite { self.progress.current = time.seconds }
            }
        }
    }

    func play() { player.play() }
    func pause() { player.pause() }

    /// Jumps to `seconds` (frame-accurate, so scrubbing shows exactly where you are).
    func seek(to seconds: Double) {
        progress.current = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func unload() {
        player.pause()
        statusObservation = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        loadedURL = nil
        pendingStart = nil
        isReady = false
        progress.current = 0
        progress.duration = 0
    }
}

/// A thin timeline along the bottom of a video: shows how far in it is, and dragging (or
/// tapping) anywhere on it jumps there. It thickens while you drag.
struct VideoScrubber: View {
    @ObservedObject var progress: PlaybackProgress
    let onSeek: (Double) -> Void
    var onScrubbingChanged: (Bool) -> Void = { _ in }

    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = progress.duration > 0
                ? min(max((dragValue ?? progress.current) / progress.duration, 0), 1)
                : 0
            let isDragging = dragValue != nil
            let thumb: CGFloat = isDragging ? 16 : 10

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(height: isDragging ? 6 : 3)
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(width * fraction, 0), height: isDragging ? 6 : 3)
                Circle()
                    .fill(Color.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(x: width * fraction - thumb / 2)
            }
            .frame(width: width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard progress.duration > 0, width > 0 else { return }
                        if dragValue == nil { onScrubbingChanged(true) }
                        let seconds = min(max(value.location.x / width, 0), 1) * progress.duration
                        dragValue = seconds
                        onSeek(seconds)
                    }
                    .onEnded { _ in
                        if let dragValue { progress.current = dragValue }
                        withAnimation(.easeOut(duration: 0.15)) { dragValue = nil }
                        onScrubbingChanged(false)
                    }
            )
            .animation(.easeOut(duration: 0.15), value: isDragging)
        }
        .frame(height: 28)
        .opacity(progress.duration > 0 ? 1 : 0)
        .accessibilityElement()
        .accessibilityLabel("Video position")
        .accessibilityValue("\(Int(progress.current)) of \(Int(progress.duration)) seconds")
        .accessibilityAdjustableAction { direction in
            let step = max(progress.duration / 10, 1)
            let target = direction == .increment ? progress.current + step : progress.current - step
            onSeek(min(max(target, 0), progress.duration))
        }
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
/// the timeline along the bottom to jump around, and the corner button opens it full screen
/// (continuing from the same spot).
///
/// Every video sits in the same fixed-size black frame and keeps its shape: vertical videos get
/// bars on the sides, horizontal ones above and below. The frame is capped at about half the
/// screen's height so the author above and the likes / comments below stay visible.
struct SendVideoPlayer: View {
    @Environment(AppStore.self) private var store
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
    /// Where to pick up after full screen (used if the inline player was unloaded meanwhile).
    @State private var resumeAt: Double?
    @Environment(\.scenePhase) private var scenePhase

    /// 4:5 at full width, but never more than about half the screen's height.
    static var height: CGFloat {
        let screen = UIScreen.main.bounds
        return min(screen.width * 5 / 4, screen.height * 0.55)
    }

    var body: some View {
        // A fixed-size frame with the video fitted inside it (the frame never takes the video's shape).
        Color.black
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .overlay {
                ZStack {
                    VideoThumbnailView(post: post, fits: true)
                    if post.videoURL != nil {
                        PlayerSurface(player: playback.player, gravity: .resizeAspect)
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
            .contentShape(Rectangle())
            // Double-tap is declared first so a single tap waits to see if a second one follows.
            .onTapGesture(count: 2) { onDoubleTap() }
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { isPausedByUser.toggle() }
                updatePlayback()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isPausedByUser ? "Play video" : "Pause video")
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
                    .padding(.trailing, 10)
                    .padding(.bottom, 30)  // above the timeline
                    .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                }
            }
            .overlay(alignment: .bottom) {
                if post.videoURL != nil {
                    VideoScrubber(progress: playback.progress) { seconds in
                        playback.seek(to: seconds)
                    } onScrubbingChanged: { scrubbing in
                        playback.isScrubbing = scrubbing
                        if scrubbing { playback.pause() } else { updatePlayback() }
                    }
                    .padding(.horizontal, 10)
                }
            }
            .fullScreenCover(isPresented: $isFullScreen, onDismiss: updatePlayback) {
                FullScreenVideoView(post: post, startAt: playback.currentSeconds,
                                    onDoubleTap: onDoubleTap) { seconds in
                    // Carry on inline from where full screen left off.
                    resumeAt = seconds
                    playback.seek(to: seconds)
                }
            }
            .onChange(of: isFullScreen) { _, _ in updatePlayback() }
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
            // A view counts once the video has really been on screen (mostly visible, app in the
            // foreground, not covered) for a moment, so scrolling straight past doesn't count.
            .task(id: isViewable) {
                guard isViewable else { return }
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled && isViewable { store.recordView(post.id) }
            }
            .onAppear {
                isAppeared = true
                updatePlayback()
            }
            .onDisappear {
                isAppeared = false
                playback.unload()
            }
    }

    /// Physically on the user's screen right now.
    private var isViewable: Bool {
        isOnScreen && isAppeared && !isFullScreen && scenePhase == .active
    }

    private func updatePlayback() {
        guard let url = post.videoURL else { return }
        if isOnScreen && isAppeared && !isFullScreen && !playback.isScrubbing && scenePhase == .active {
            playback.load(url, startAt: resumeAt)  // no-op (keeps position) if already loaded
            resumeAt = nil
            playback.player.isMuted = isMuted
            if isPausedByUser { playback.pause() } else { playback.play() }
        } else {
            playback.pause()
        }
    }
}

/// A send video full screen: the whole frame on black, looping with sound, starting where the
/// inline video was. Tap to pause, double-tap to like / unlike, drag the timeline at the bottom
/// to jump around, swipe down or tap the X to close.
///
/// Pinch to zoom (up to 6×) around your fingers and drag to look around, like Photos. Letting go
/// below 1× springs back; the view never pans past the video's edges. Swipe-down-to-close only
/// works when not zoomed in, so dragging a zoomed video doesn't close it.
struct FullScreenVideoView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let post: Post
    /// Seconds into the video to start at.
    var startAt: Double = 0
    var onDoubleTap: () -> Void = {}
    /// Called on close with where the video got to.
    var onClose: (Double) -> Void = { _ in }

    @AppStorage("videosMuted") private var isMuted = false
    @StateObject private var playback = LoopingPlayback()
    @State private var isPaused = false
    @State private var dragOffset: CGFloat = 0
    @State private var likeBurst = 0

    // Zoom: the committed state, plus the last gesture values so each frame applies only the
    // change since the previous one (no jumps when a finger lifts or lands mid-gesture).
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1
    @State private var lastDrag: CGSize = .zero
    @State private var containerSize: CGSize = .zero

    private static let maxZoom: CGFloat = 6
    private var isZoomed: Bool { zoom > 1.01 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerSurface(player: playback.player, gravity: .resizeAspect)
                .opacity(playback.isReady ? 1 : 0)
                .ignoresSafeArea()
                .scaleEffect(zoom)
                .offset(pan)
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
        .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture {
            isPaused.toggle()
            if isPaused { playback.pause() } else { playback.play() }
        }
        .gesture(SimultaneousGesture(pinchGesture, dragGesture))
        .overlay(alignment: .topLeading) {
            if isZoomed {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        zoom = 1
                        pan = .zero
                    }
                } label: {
                    Text("1×")
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .padding()
                .accessibilityLabel("Reset zoom")
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isZoomed)
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
        .overlay(alignment: .bottom) {
            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    isMuted.toggle()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .accessibilityLabel(isMuted ? "Unmute" : "Mute")

                VideoScrubber(progress: playback.progress) { seconds in
                    playback.seek(to: seconds)
                } onScrubbingChanged: { scrubbing in
                    playback.isScrubbing = scrubbing
                    if scrubbing {
                        playback.pause()
                    } else if !isPaused {
                        playback.play()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
        .statusBarHidden()
        .onAppear {
            guard let url = post.videoURL else { return }
            playback.load(url, startAt: startAt)
            playback.player.isMuted = isMuted
            playback.play()
        }
        .onDisappear {
            onClose(playback.currentSeconds)
            playback.unload()
        }
        .onChange(of: isMuted) { _, muted in playback.player.isMuted = muted }
        .task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { store.recordView(post.id) }
        }
        .onChange(of: store.isLiked(post.id)) { _, liked in
            if liked { likeBurst += 1 }
        }
    }

    // MARK: Zoom

    /// Pinch: zoom around the point between your fingers (it stays under them).
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let factor = value.magnification / lastMagnification
                lastMagnification = value.magnification
                let newZoom = min(max(zoom * factor, 0.8), Self.maxZoom)
                let applied = newZoom / zoom
                // Pinch point relative to the center; keep the video point under it fixed.
                let anchor = CGSize(width: value.startLocation.x - containerSize.width / 2,
                                    height: value.startLocation.y - containerSize.height / 2)
                pan = CGSize(width: anchor.width - (anchor.width - pan.width) * applied,
                             height: anchor.height - (anchor.height - pan.height) * applied)
                zoom = newZoom
            }
            .onEnded { _ in
                lastMagnification = 1
                settleZoom()
            }
    }

    /// Drag: look around when zoomed in; otherwise swipe down to close.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let delta = CGSize(width: value.translation.width - lastDrag.width,
                                   height: value.translation.height - lastDrag.height)
                lastDrag = value.translation
                if isZoomed {
                    dragOffset = 0  // a pinch that started at 1× may have nudged it
                    pan = CGSize(width: pan.width + delta.width, height: pan.height + delta.height)
                } else {
                    dragOffset = max(value.translation.height, 0)
                }
            }
            .onEnded { value in
                lastDrag = .zero
                if isZoomed {
                    settleZoom()
                } else if value.translation.height > 120 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                }
            }
    }

    /// Springs back to 1× if zoomed out too far, and keeps the zoomed video covering the screen
    /// (no panning past its edges).
    private func settleZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            dragOffset = 0
            if zoom <= 1.01 {
                zoom = 1
                pan = .zero
            } else {
                let maxX = containerSize.width * (zoom - 1) / 2
                let maxY = containerSize.height * (zoom - 1) / 2
                pan = CGSize(width: min(max(pan.width, -maxX), maxX),
                             height: min(max(pan.height, -maxY), maxY))
            }
        }
    }
}
