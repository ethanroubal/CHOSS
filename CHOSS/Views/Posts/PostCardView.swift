import SwiftUI

/// Instagram-style card for a send: header, video, actions, grade/route info, caption.
struct PostCardView: View {
    @Environment(AppStore.self) private var store
    let post: Post
    var reason: FeedReason? = nil

    @State private var showingComments = false
    @State private var showingShare = false

    private var author: User? { store.user(post.authorID) }
    private var place: Place? { store.place(post.placeID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            reasonLabel

            header
            SendVideoPlayer(post: post)
                .onTapGesture(count: 2) {
                    if !store.isLiked(post.id) { store.toggleLike(post.id) }
                }
            actions
            details
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showingComments) {
            CommentsView(postID: post.id)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingShare) {
            ShareToFollowersView(post: post)
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
                Image(systemName: store.isLiked(post.id) ? "heart.fill" : "heart")
                    .foregroundStyle(store.isLiked(post.id) ? Color.red : Color.primary)
                    .symbolEffect(.bounce, value: store.isLiked(post.id))
            }
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
            Button {
                showingShare = true
            } label: {
                Image(systemName: "paperplane")
            }
            .accessibilityLabel("Send to a friend")
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
            if !counts.isEmpty {
                Text(counts.joined(separator: " · "))
                    .font(.subheadline.bold())
            }

            HStack(spacing: 8) {
                if let grade = post.grade {
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
                } else {
                    Text(post.routeName.isEmpty ? "Unnamed route" : post.routeName)
                        .font(.subheadline.bold())
                }
                Text("· \(post.discipline.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let proposed = post.proposedGrade {
                HStack(spacing: 6) {
                    GradeBadge(grade: proposed, isProposed: true)
                    Text("Proposed grade")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

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

    private func countText(_ count: Int, _ singular: String, _ plural: String) -> String? {
        count == 0 ? nil : "\(count) \(count == 1 ? singular : plural)"
    }
}

struct PostDetailView: View {
    @Environment(AppStore.self) private var store
    let postID: Post.ID

    var body: some View {
        ScrollView {
            if let post = store.post(postID) {
                PostCardView(post: post)
            } else {
                ContentUnavailableView("Post not found", systemImage: "questionmark.video")
            }
        }
        .navigationTitle("Send")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 3-column grid of video thumbnails, like an Instagram profile.
struct PostGrid: View {
    let posts: [Post]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(posts) { post in
                NavigationLink(value: Route.post(post.id)) {
                    Color.clear
                        .aspectRatio(4 / 5, contentMode: .fit)
                        .overlay { VideoThumbnailView(post: post) }
                        .clipped()
                        // Grade in the corner, only when the poster set one.
                        .overlay(alignment: .topTrailing) {
                            PostGradeBadge(post: post).padding(5)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
