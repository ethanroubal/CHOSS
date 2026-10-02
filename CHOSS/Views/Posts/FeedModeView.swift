import SwiftUI

/// The posts a tapped video belongs to (e.g. the home feed), so feed mode can carry on through
/// them. Set by lists of posts; without it, feed mode shows just the tapped video.
private struct VideoFeedPostIDsKey: EnvironmentKey {
    static let defaultValue: [Post.ID]? = nil
}

extension EnvironmentValues {
    var videoFeedPostIDs: [Post.ID]? {
        get { self[VideoFeedPostIDsKey.self] }
        set { self[VideoFeedPostIDsKey.self] = newValue }
    }
}

/// "Feed mode", like Instagram Reels: each video fills the screen, with who posted it, the
/// climb and caption along the bottom and like / comment / repost / sound down the right. Swipe
/// up for the next video; every few videos there's a sponsored page. The back arrow (top left)
/// returns to where you were.
struct FeedModeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let postIDs: [Post.ID]
    let startID: Post.ID

    @State private var currentID: String?
    @State private var isPositioned = false
    @State private var isAppeared = false
    @State private var focusID = UUID()
    /// This session's ad slots in `FeedAdStore`: a fresh range each time feed mode opens, apart
    /// from the home feed's (0, 1, 2…), since one ad can't show in two places at once.
    @State private var adSlotBase = Int.random(in: 1...1_000_000) * 1_000

    init(postIDs: [Post.ID], startID: Post.ID) {
        self.postIDs = postIDs.contains(startID) ? postIDs : [startID]
        self.startID = startID
        _currentID = State(initialValue: Page.post(startID).id)
    }

    private enum Page: Identifiable, Hashable {
        case post(Post.ID)
        case ad(slot: Int)

        var id: String {
            switch self {
            case .post(let id): "post:\(id)"
            case .ad(let slot): "ad:\(slot)"
            }
        }
    }

    /// Posts, with a sponsored page after every `FeedAds.interval` posts once its ad is ready.
    private var pages: [Page] {
        let posts = postIDs.filter { store.post($0) != nil }
        var pages: [Page] = []
        for (index, id) in posts.enumerated() {
            pages.append(.post(id))
            if (index + 1) % FeedAds.interval == 0, index < posts.count - 1 {
                let slot = adSlotBase + (index + 1) / FeedAds.interval - 1
                if FeedAds.hasAd(slot: slot) { pages.append(.ad(slot: slot)) }
            }
        }
        return pages
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let insets = geometry.safeAreaInsets
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(pages) { page in
                                pageView(page, insets: insets)
                                    .containerRelativeFrame([.horizontal, .vertical])
                                    .id(page.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $currentID)
                    .scrollIndicators(.hidden)
                    .ignoresSafeArea()
                    .opacity(isPositioned ? 1 : 0)
                    .task {
                        // Start on the tapped video (belt and braces: the lazy stack can ignore
                        // the initial scroll position).
                        guard !isPositioned else { return }
                        await Task.yield()
                        proxy.scrollTo(Page.post(startID).id, anchor: .top)
                        isPositioned = true
                    }
                }
            }
            .background(Color.black)
            .overlay(alignment: .topLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                }
                .padding(.leading, 8)
                .accessibilityLabel("Back")
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                isAppeared = true
                VideoFocus.shared.beginExclusive(focusID)  // inline videos behind stay paused
                pageChanged()
            }
            .onDisappear {
                isAppeared = false
                VideoFocus.shared.endExclusive(focusID)
            }
            .onChange(of: currentID) { _, _ in pageChanged() }
            .withAppRoutes()
        }
        .environment(\.colorScheme, .dark)
        .onDisappear { FeedAds.releaseFeedModeSlots(from: adSlotBase) }
    }

    @ViewBuilder
    private func pageView(_ page: Page, insets: EdgeInsets) -> some View {
        switch page {
        case .post(let id):
            if let post = store.post(id) {
                FeedModePostPage(post: post, isCurrent: isAppeared && currentID == page.id, insets: insets)
            }
        case .ad(let slot):
            FeedModeAdPage(slot: slot, insets: insets)
        }
    }

    /// Ads: ask for the next one a few videos ahead; a slot passed without an ad stays empty
    /// (so a page never appears above the one you're on).
    private func pageChanged() {
        let posts = postIDs.filter { store.post($0) != nil }
        guard let currentID, currentID.hasPrefix("post:"),
              let index = posts.firstIndex(where: { Page.post($0).id == currentID }) else { return }
        let upcoming = (index + FeedAds.lookahead) / FeedAds.interval - 1
        if upcoming >= 0 { FeedAds.prepare(slot: adSlotBase + upcoming) }
        // Slots before this video have been passed.
        let passed = index / FeedAds.interval
        for slot in 0..<passed { FeedAds.slotReachedScreen(adSlotBase + slot) }
    }
}

/// One full-screen video in feed mode.
private struct FeedModePostPage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    let post: Post
    /// The page on screen (only it plays).
    let isCurrent: Bool
    let insets: EdgeInsets

    @AppStorage("videosMuted") private var isMuted = false
    @StateObject private var playback = LoopingPlayback()
    @State private var isPaused = false
    @State private var likeBurst = 0
    @State private var showingComments = false
    @State private var showingLikes = false
    @State private var captionExpanded = false

    private var author: User? { store.user(post.authorID) }
    private var isPlaying: Bool { isCurrent && scenePhase == .active }

    var body: some View {
        ZStack {
            Color.black
            VideoThumbnailView(post: post, fits: true)
            if post.videoURL != nil {
                PlayerSurface(player: playback.player, gravity: .resizeAspect)
                    .opacity(playback.isReady ? 1 : 0)
            }
            // Darken the bottom so the text over the video stays readable.
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
            if isPaused {
                Image(systemName: "play.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 6)
                    .allowsHitTesting(false)
            }
            LikeBurst(trigger: likeBurst)
        }
        .contentShape(Rectangle())
        // Double-tap likes (or unlikes); a single tap pauses / plays.
        .onTapGesture(count: 2) { store.toggleLike(post.id) }
        .onTapGesture {
            isPaused.toggle()
            updatePlayback()
        }
        .overlay(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 12) {
                info
                Spacer(minLength: 0)
                actions
            }
            .padding(.horizontal, 14)
            .padding(.bottom, insets.bottom + 26)
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
                .padding(.bottom, insets.bottom - 4)
            }
        }
        .onAppear { updatePlayback() }
        .onDisappear {
            rememberPosition()
            playback.unload()
        }
        .onChange(of: isPlaying) { _, playing in
            if !playing { rememberPosition() }
            if !isCurrent { isPaused = false }
            updatePlayback()
        }
        .onChange(of: isMuted) { _, muted in playback.player.isMuted = muted }
        // A view counts after a moment on screen, unless it carries on a view already counted
        // (e.g. the video you tapped, which was playing in the feed).
        .task(id: isPlaying) {
            guard isPlaying else { return }
            let isResuming = store.playbackPosition(of: post.id) != nil
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled && isPlaying && !isResuming { store.recordView(post.id) }
        }
        .onChange(of: store.isLiked(post.id)) { _, liked in
            if liked { likeBurst += 1 }
        }
        .sensoryFeedback(trigger: store.isLiked(post.id)) { _, liked in
            liked ? SensoryFeedback.impact(weight: .light, intensity: 0.7) : nil
        }
        .sheet(isPresented: $showingComments) {
            CommentsView(postID: post.id)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingLikes) {
            LikesView(postID: post.id)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Overlays

    /// Who, where, what, and the caption: bottom left.
    private var info: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: Route.user(post.authorID)) {
                HStack(spacing: 8) {
                    AvatarView(user: author, size: 32)
                    Text(author?.username ?? "unknown").font(.subheadline.bold())
                }
            }
            if let place = store.place(post.placeID) {
                NavigationLink(value: Route.place(place.id)) {
                    Label(place.name, systemImage: place.kind.symbolName)
                        .font(.caption.weight(.semibold))
                }
            }
            HStack(spacing: 6) {
                if let grade = store.displayGrade(for: post) {
                    GradeBadge(grade: grade)
                }
                if let climb = store.climb(post.climbID) {
                    NavigationLink(value: Route.climb(climb.id)) {
                        Label(climb.name, systemImage: "mountain.2").font(.subheadline.bold())
                    }
                } else if !post.routeName.isEmpty {
                    Text(post.routeName).font(.subheadline.bold())
                }
                Text(post.discipline.displayName).font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                Label(post.sendStyle.displayName, systemImage: post.sendStyle.symbolName)
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.8))
            }
            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(.subheadline)
                    .lineLimit(captionExpanded ? 8 : 2)
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { captionExpanded.toggle() } }
            }
            Text("\(post.viewCount.formatted(.number.notation(.compactName))) \(post.viewCount == 1 ? "view" : "views") · \(post.createdAt.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 3)
        .multilineTextAlignment(.leading)
    }

    /// Like, comment, repost, sound: down the right edge.
    private var actions: some View {
        VStack(spacing: 18) {
            VStack(spacing: 2) {
                Button {
                    store.toggleLike(post.id)
                } label: {
                    FlexIcon(filled: store.isLiked(post.id), size: 30)
                        .foregroundStyle(store.isLiked(post.id) ? Color.accentColor : .white)
                }
                .accessibilityLabel(store.isLiked(post.id) ? "Unlike" : "Like")
                Button(countLabel(post.likedBy.count)) { showingLikes = true }
                    .font(.caption.bold())
                    .accessibilityLabel("\(post.likedBy.count) likes")
                    .accessibilityHint("Shows who liked this")
            }
            VStack(spacing: 2) {
                Button {
                    showingComments = true
                } label: {
                    Image(systemName: "bubble.right").font(.title2)
                }
                .accessibilityLabel("Comments")
                Text(countLabel(post.comments.count)).font(.caption.bold())
            }
            if store.canRepost(post) {
                VStack(spacing: 2) {
                    Button {
                        store.toggleRepost(post.id)
                    } label: {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.title2)
                            .foregroundStyle(store.isReposted(post.id) ? Color.green : .white)
                            .symbolEffect(.bounce, value: store.isReposted(post.id))
                    }
                    .accessibilityLabel(store.isReposted(post.id) ? "Undo repost" : "Repost")
                    Text(countLabel(store.repostCount(post.id))).font(.caption.bold())
                }
            }
            Button {
                isMuted.toggle()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.body.bold())
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel(isMuted ? "Unmute" : "Mute")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 3)
    }

    private func countLabel(_ count: Int) -> String {
        count == 0 ? " " : count.formatted(.number.notation(.compactName))
    }

    // MARK: Playback

    private func updatePlayback() {
        guard let url = post.videoURL else { return }
        if isPlaying && !playback.isScrubbing {
            // Carries on where it was left (in the feed, or earlier in feed mode).
            playback.load(url, startAt: store.playbackPosition(of: post.id))
            playback.player.isMuted = isMuted
            if isPaused { playback.pause() } else { playback.play() }
        } else {
            playback.pause()
        }
    }

    private func rememberPosition() {
        guard playback.isReady else { return }
        store.setPlaybackPosition(playback.currentSeconds, of: post.id)
    }
}
