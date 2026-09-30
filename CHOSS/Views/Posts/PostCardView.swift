import SwiftUI

/// Instagram-style card for a send: header, video, actions, grade/route info, caption.
struct PostCardView: View {
    @Environment(AppStore.self) private var store
    let post: Post
    var reason: FeedReason? = nil

    @State private var showingComments = false
    /// Bumped on each like to play the bicep burst over the video.
    @State private var likeBurst = 0

    private var author: User? { store.user(post.authorID) }
    private var place: Place? { store.place(post.placeID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            reasonLabel

            header
            // Double-tap likes, or unlikes if already liked.
            SendVideoPlayer(post: post) {
                store.toggleLike(post.id)
            }
            .overlay { LikeBurst(trigger: likeBurst) }
            actions
            details
        }
        .padding(.vertical, 8)
        .onChange(of: store.isLiked(post.id)) { _, liked in
            if liked { likeBurst += 1 }
        }
        // A light tap on like; unliking is silent.
        .sensoryFeedback(trigger: store.isLiked(post.id)) { _, liked in
            liked ? SensoryFeedback.impact(weight: .light, intensity: 0.7) : nil
        }
        .sheet(isPresented: $showingComments) {
            CommentsView(postID: post.id)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var reasonLabel: some View {
        switch reason {
        case .followedPlace(let placeID):
            if let followed = store.place(placeID) {
                Label("Because you follow \(followed.name)", systemImage: followed.kind.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        case .repostedBy(let userID):
            NavigationLink(value: Route.user(userID)) {
                Label("\(store.user(userID)?.username ?? "Someone") reposted", systemImage: "arrow.2.squarepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        default:
            EmptyView()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            NavigationLink(value: Route.user(post.authorID)) {
                AvatarView(user: author)
            }
            VStack(alignment: .leading, spacing: 1) {
                NavigationLink(value: Route.user(post.authorID)) {
                    Text(author?.username ?? "unknown").font(.subheadline.bold())
                }
                if let place {
                    NavigationLink(value: Route.place(place.id)) {
                        Label(place.name, systemImage: place.kind.symbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Text(post.createdAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var actions: some View {
        HStack(spacing: 18) {
            Button {
                store.toggleLike(post.id)
            } label: {
                FlexIcon(filled: store.isLiked(post.id), size: 24)
                    .foregroundStyle(store.isLiked(post.id) ? Color.accentColor : Color.primary)
            }
            .accessibilityLabel(store.isLiked(post.id) ? "Unlike" : "Like")
            Button {
                showingComments = true
            } label: {
                Image(systemName: "bubble.right")
            }
            if store.canRepost(post) {
                Button {
                    store.toggleRepost(post.id)
                } label: {
                    Image(systemName: "arrow.2.squarepath")
                        .foregroundStyle(store.isReposted(post.id) ? Color.green : Color.primary)
                        .symbolEffect(.bounce, value: store.isReposted(post.id))
                }
                .accessibilityLabel(store.isReposted(post.id) ? "Undo repost" : "Repost")
            }
            Spacer()
            Label(post.sendStyle.displayName, systemImage: post.sendStyle.symbolName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .font(.title3)
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            let counts = [
                countText(post.likedBy.count, "like", "likes"),
                countText(store.repostCount(post.id), "repost", "reposts"),
            ].compactMap { $0 }
            // Likes and reposts, then views in grey (visible, but quieter).
            let views = Text("\(post.viewCount.formatted(.number.notation(.compactName))) \(post.viewCount == 1 ? "view" : "views")")
                .foregroundStyle(.secondary)
                .fontWeight(.regular)
            Group {
                if counts.isEmpty {
                    views
                } else {
                    Text(counts.joined(separator: " · ")) + Text("  ·  ").foregroundStyle(.secondary) + views
                }
            }
            .font(.subheadline.bold())

            HStack(spacing: 8) {
                if let grade = store.displayGrade(for: post) {
                    GradeBadge(grade: grade)
                }
                if let climb = store.climb(post.climbID) {
                    // Linked outdoor climb: tap for every video of it (beta).
                    NavigationLink(value: Route.climb(climb.id)) {
                        Label(climb.name, systemImage: "mountain.2")
                            .font(.subheadline.bold())
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                } else if !post.routeName.isEmpty {
                    Text(post.routeName)
                        .font(.subheadline.bold())
                }
                // Gym climbs don't have names, so the discipline stands alone there.
                Text(post.climbID == nil && post.routeName.isEmpty
                     ? post.discipline.displayName
                     : "· \(post.discipline.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            gradeExplanation


            if !post.caption.isEmpty {
                (Text(author?.username ?? "").bold() + Text(" ") + Text(post.caption))
                    .font(.subheadline)
            }

            if !post.comments.isEmpty {
                Button("View all \(post.comments.count) comments") { showingComments = true }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    /// "Proposed ~V7 · Grade is the average of 3 proposals" under the route line.
    @ViewBuilder
    private var gradeExplanation: some View {
        let average = store.averageGrade(for: post)
        if post.proposedGrade != nil || average != nil {
            HStack(spacing: 6) {
                if let proposed = post.proposedGrade {
                    Text("Proposed").font(.caption).foregroundStyle(.secondary)
                    GradeBadge(grade: proposed, isProposed: true)
                }
                if let average {
                    Text(average.count == 1
                         ? "· Grade from 1 proposal"
                         : "· Grade is the average of \(average.count) proposals")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func countText(_ count: Int, _ singular: String, _ plural: String) -> String? {
        count == 0 ? nil : "\(count) \(count == 1 ? singular : plural)"
    }
}

/// A list of posts opened from a grid or search result. It starts at the tapped post and
/// lets you keep scrolling through the rest (like tapping a post on an Instagram profile).
struct PostFeed: Hashable {
    var title: String
    var postIDs: [Post.ID]
    var startID: Post.ID
}

struct PostFeedView: View {
    @Environment(AppStore.self) private var store
    let feed: PostFeed

    @State private var position: Post.ID?

    init(feed: PostFeed) {
        self.feed = feed
        _position = State(initialValue: feed.startID)
    }

    var body: some View {
        let posts = feed.postIDs.compactMap { store.post($0) }

        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(posts) { post in
                    VStack(spacing: 12) {
                        PostCardView(post: post)
                        Divider()
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $position, anchor: .top)
        .overlay {
            if posts.isEmpty {
                ContentUnavailableView("Post not found", systemImage: "questionmark.video")
            }
        }
        .navigationTitle(feed.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A single post opened from a link (e.g. shared in a DM). Opens on that post, then keeps
/// going through the rest of the author's posts.
struct PostDetailView: View {
    @Environment(AppStore.self) private var store
    let postID: Post.ID

    var body: some View {
        PostFeedView(feed: feed)
    }

    private var feed: PostFeed {
        guard let post = store.post(postID) else {
            return PostFeed(title: "Send", postIDs: [], startID: postID)
        }
        var ids = store.posts(by: post.authorID).map(\.id)
        if !ids.contains(postID) { ids.insert(postID, at: 0) }
        let username = store.user(post.authorID)?.username ?? "Sends"
        return PostFeed(title: username, postIDs: ids, startID: postID)
    }
}

/// 3-column grid of video thumbnails, like an Instagram profile. Tapping one opens a
/// scrollable feed of this grid's posts, starting at the tapped one.
struct PostGrid: View {
    /// What each thumbnail shows in its corner.
    enum Badge {
        /// The climb's grade (top right), e.g. on profiles where climbs differ.
        case grade
        /// The like count (bottom left), e.g. on a climb page where every video is the same climb.
        case likes
    }

    let posts: [Post]
    /// Title for the feed opened from this grid, e.g. the username or "Trending".
    var title: String = "Sends"
    var badge: Badge = .grade

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        let ids = posts.map(\.id)

        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(posts) { post in
                NavigationLink(value: Route.feed(PostFeed(title: title, postIDs: ids, startID: post.id))) {
                    Color.clear
                        .aspectRatio(4 / 5, contentMode: .fit)
                        .overlay { VideoThumbnailView(post: post) }
                        .clipped()
                        .overlay(alignment: badge == .grade ? .topTrailing : .bottomLeading) {
                            switch badge {
                            case .grade:
                                // The climb's grade, when it has one.
                                PostGradeBadge(post: post).padding(5)
                            case .likes:
                                Label {
                                    Text("\(post.likedBy.count)")
                                } icon: {
                                    FlexIcon(filled: true, size: 12)
                                }
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.black.opacity(0.5), in: Capsule())
                                    .padding(5)
                                    .accessibilityLabel("\(post.likedBy.count) likes")
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
