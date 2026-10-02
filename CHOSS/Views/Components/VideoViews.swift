import SwiftUI
import AVKit
import Observation

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

    /// A poster image downloaded from a URL (e.g. Mux's thumbnail), cached like grabbed frames.
    func image(at url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
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
                    // When filled, the image overflows its frame (cropped by the parent); the
                    // hidden part must not catch taps meant for neighbouring views.
                    .allowsHitTesting(false)
            } else {
                DisciplineIcon(discipline: post.discipline, size: 40)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .clipped()
        .task(id: post.videoURL) {
            // Server videos come with a poster image (Mux); local ones get a frame grabbed.
            if let poster = post.thumbnailURL {
                image = await ThumbnailCache.shared.image(at: poster)
            } else if let url = post.videoURL {
                image = await ThumbnailCache.shared.thumbnail(for: url)
            }
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

/// Decides which single video plays. Every inline player that's mostly on screen reports where
/// it is; the one showing the most of itself (nearest the middle on a tie) is the active one and
/// the rest stay paused. A full-screen video takes over while it's open.
@MainActor
@Observable
final class VideoFocus {
    static let shared = VideoFocus()

    /// The player allowed to play (and count a view) right now.
    private(set) var activeID: UUID?
    @ObservationIgnored private var frames: [UUID: CGRect] = [:]
    @ObservationIgnored private var exclusive: [UUID] = []

    /// A player's on-screen frame, or nil when it's not a candidate (off screen, covered…).
    func report(_ id: UUID, frame: CGRect?) {
        frames[id] = frame
        choose()
    }

    /// A full-screen player: only it plays until `endExclusive`.
    func beginExclusive(_ id: UUID) {
        exclusive.append(id)
        choose()
    }

    func endExclusive(_ id: UUID) {
        exclusive.removeAll { $0 == id }
        choose()
    }

    private func choose() {
        let next: UUID?
        if let top = exclusive.last {
            next = top
        } else {
            let screen = UIScreen.main.bounds
            next = frames.max { lhs, rhs in
                let left = lhs.value.intersection(screen).height
                let right = rhs.value.intersection(screen).height
                if abs(left - right) > 1 { return left < right }
                // Same amount showing: the higher one (the one you reached first) wins.
                return lhs.value.minY > rhs.value.minY
            }?.key
        }
        if next != activeID { activeID = next }
    }
}

/// Plain video surface with no system controls (taps are handled by `SendVideoPlayer`).
struct PlayerSurface: UIViewRepresentable {
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
    /// This player's id for `VideoFocus` (only the focused video plays).
    @State private var focusID = UUID()
    @State private var screenFrame: CGRect = .zero
    /// False while another screen is pushed on top (the view stays in the hierarchy but hidden).
    @State private var isAppeared = false
    @State private var isPausedByUser = false
    /// Feed mode (full-screen, swipe-through videos) is open from this video.
    @State private var isFullScreen = false
    /// Where to pick up after full screen (used if the inline player was unloaded meanwhile).
    @State private var resumeAt: Double?
    /// The list this video is in, for feed mode to carry on through.
    @Environment(\.videoFeedPostIDs) private var feedPostIDs
    /// From the home feed: feed mode gets the Following / Recents tabs.
    @Environment(\.videoFeedShowsHomeTabs) private var showsHomeTabs
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
            // A tap opens feed mode: this video full screen, then swipe through the rest.
            .onTapGesture {
                guard post.videoURL != nil else { return }
                rememberPosition()  // feed mode carries on from here
                isFullScreen = true
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Open video full screen")
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
            .fullScreenCover(isPresented: $isFullScreen, onDismiss: {
                // Carry on inline from where feed mode left this video.
                if let seconds = store.playbackPosition(of: post.id), playback.isReady {
                    playback.seek(to: seconds)
                }
                updatePlayback()
            }) {
                FeedModeView(postIDs: feedPostIDs ?? [post.id], startID: post.id,
                             showsHomeTabs: showsHomeTabs)
            }
            .onChange(of: isFullScreen) { _, _ in
                reportFocus()
                updatePlayback()
            }
            // A candidate to autoplay when at least 60% of the video is on screen; of those, only
            // the one `VideoFocus` picks plays.
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                screenFrame = frame
                let visible = frame.intersection(UIScreen.main.bounds)
                let onScreen = !visible.isNull && frame.height > 0 && visible.height / frame.height >= 0.6
                if onScreen != isOnScreen {
                    isOnScreen = onScreen
                    if !onScreen { isPausedByUser = false }
                }
                reportFocus()
            }
            .onChange(of: isActive) { _, _ in updatePlayback() }
            .onChange(of: isOnScreen) { _, _ in updatePlayback() }
            .onChange(of: isMuted) { _, muted in playback.player.isMuted = muted }
            .onChange(of: scenePhase) { _, _ in
                reportFocus()
                updatePlayback()
            }
            // Leaving the screen (scrolled away, covered, full screen…) remembers where the video
            // was, so coming back carries on from there.
            .onChange(of: isViewable) { _, viewable in
                if !viewable { rememberPosition() }
            }
            // A view counts once the video has really been on screen (mostly visible, app in the
            // foreground, not covered) for a moment, so scrolling straight past doesn't count.
            // Coming back to a video you'd left partway through carries on the same view.
            .task(id: isViewable) {
                guard isViewable else { return }
                let isResuming = resumeAt != nil || store.playbackPosition(of: post.id) != nil
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled && isViewable && !isResuming { store.recordView(post.id) }
            }
            .onAppear {
                isAppeared = true
                reportFocus()
                updatePlayback()
            }
            .onDisappear {
                isAppeared = false
                VideoFocus.shared.report(focusID, frame: nil)
                rememberPosition()
                playback.unload()
            }
    }

    /// The one video allowed to play right now.
    private var isActive: Bool { VideoFocus.shared.activeID == focusID }

    /// Mostly on screen, not covered, app in the foreground.
    private var isCandidate: Bool {
        isOnScreen && isAppeared && !isFullScreen && scenePhase == .active
    }

    /// Physically on the user's screen and the video being played.
    private var isViewable: Bool { isCandidate && isActive }

    private func reportFocus() {
        VideoFocus.shared.report(focusID, frame: isCandidate ? screenFrame : nil)
    }

    /// Saves where the video is (if it has started playing) for when it comes back on screen.
    private func rememberPosition() {
        guard playback.isReady else { return }
        store.setPlaybackPosition(playback.currentSeconds, of: post.id)
    }

    private func updatePlayback() {
        guard let url = post.videoURL else { return }
        if isViewable && !playback.isScrubbing {
            // No-op (keeps position) if already loaded; otherwise carries on where it was left.
            playback.load(url, startAt: resumeAt ?? store.playbackPosition(of: post.id))
            resumeAt = nil
            playback.player.isMuted = isMuted
            if isPausedByUser { playback.pause() } else { playback.play() }
        } else {
            playback.pause()
        }
    }
}
