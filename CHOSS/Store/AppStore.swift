import Foundation
import Observation

/// Where a home-feed post came from, so the card can say "From Granite Works" vs. a followed climber.
enum FeedReason: Hashable {
    case followedPlace(Place.ID)
    case followedUser
    case own
}

struct FeedItem: Identifiable {
    let post: Post
    let reason: FeedReason
    var id: Post.ID { post.id }
}

enum HomeFeedFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case places = "Places"
    case climbers = "Climbers"

    var id: Self { self }
}

/// Single source of truth for the UI. Mutations are applied optimistically and then
/// sent to the repository; on failure they're rolled back by reloading.
@MainActor
@Observable
final class AppStore {
    private let repository: ClimbingRepository

    private(set) var isLoaded = false
    private(set) var lastError: String?
    var currentUserID: User.ID

    private(set) var users: [User.ID: User] = [:]
    private(set) var places: [Place.ID: Place] = [:]
    /// Newest first.
    private(set) var posts: [Post] = []
    private(set) var followedPlaces: [User.ID: Set<Place.ID>] = [:]
    private(set) var followedUsers: [User.ID: Set<User.ID>] = [:]

    init(repository: ClimbingRepository = MockClimbingRepository(),
         currentUserID: User.ID = SampleData.currentUserID) {
        self.repository = repository
        self.currentUserID = currentUserID
    }

    /// A store pre-filled with sample data, for SwiftUI previews.
    static var preview: AppStore {
        let store = AppStore()
        store.apply(SampleData.snapshot)
        return store
    }

    // MARK: - Loading

    func load() async {
        do {
            apply(try await repository.loadSnapshot())
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func apply(_ snapshot: AppSnapshot) {
        users = Dictionary(uniqueKeysWithValues: snapshot.users.map { ($0.id, $0) })
        places = Dictionary(uniqueKeysWithValues: snapshot.places.map { ($0.id, $0) })
        posts = snapshot.posts.sorted { $0.createdAt > $1.createdAt }
        followedPlaces = snapshot.followedPlaces
        followedUsers = snapshot.followedUsers
        isLoaded = true
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                lastError = error.localizedDescription
                await load()
            }
        }
    }

    // MARK: - Lookups

    var currentUser: User? { users[currentUserID] }

    func user(_ id: User.ID) -> User? { users[id] }
    func place(_ id: Place.ID?) -> Place? { id.flatMap { places[$0] } }
    func post(_ id: Post.ID) -> Post? { posts.first { $0.id == id } }

    var allPlaces: [Place] { places.values.sorted { $0.name < $1.name } }
    var allUsers: [User] { users.values.sorted { $0.displayName < $1.displayName } }

    // MARK: - Feeds

    /// The home feed: sends posted to places you follow, plus posts from climbers you follow.
    func homeFeed(filter: HomeFeedFilter) -> [FeedItem] {
        let myPlaces = followedPlaces[currentUserID] ?? []
        let myPeople = followedUsers[currentUserID] ?? []

        return posts.compactMap { post in
            let reason: FeedReason?
            if post.authorID == currentUserID {
                reason = filter == .places ? nil : .own
            } else if let placeID = post.placeID, myPlaces.contains(placeID), filter != .climbers {
                reason = .followedPlace(placeID)
            } else if myPeople.contains(post.authorID), filter != .places {
                reason = .followedUser
            } else {
                reason = nil
            }
            return reason.map { FeedItem(post: post, reason: $0) }
        }
    }

    func posts(at placeID: Place.ID) -> [Post] {
        posts.filter { $0.placeID == placeID }
    }

    func posts(by userID: User.ID) -> [Post] {
        posts.filter { $0.authorID == userID }
    }

    /// Most-liked recent sends for Explore.
    func trendingPosts(discipline: ClimbDiscipline? = nil) -> [Post] {
        posts
            .filter { discipline == nil || $0.discipline == discipline }
            .sorted { ($0.likedBy.count, $0.createdAt) > ($1.likedBy.count, $1.createdAt) }
    }

    func popularPlaces(kind: PlaceKind? = nil) -> [Place] {
        places.values
            .filter { kind == nil || $0.kind == kind }
            .sorted { followerCount(of: $0.id) > followerCount(of: $1.id) }
    }

    // MARK: - Follow graph

    func isFollowing(place placeID: Place.ID) -> Bool {
        followedPlaces[currentUserID]?.contains(placeID) ?? false
    }

    func isFollowing(user userID: User.ID) -> Bool {
        followedUsers[currentUserID]?.contains(userID) ?? false
    }

    func followerCount(of placeID: Place.ID) -> Int {
        followedPlaces.values.filter { $0.contains(placeID) }.count
    }

    func followerCount(ofUser userID: User.ID) -> Int {
        followedUsers.values.filter { $0.contains(userID) }.count
    }

    func followingCount(ofUser userID: User.ID) -> Int {
        followedUsers[userID]?.count ?? 0
    }

    func followedPlaces(of userID: User.ID) -> [Place] {
        (followedPlaces[userID] ?? []).compactMap { places[$0] }.sorted { $0.name < $1.name }
    }

    func toggleFollow(place placeID: Place.ID) {
        let follow = !isFollowing(place: placeID)
        let me = currentUserID
        if follow {
            followedPlaces[me, default: []].insert(placeID)
        } else {
            followedPlaces[me, default: []].remove(placeID)
        }
        perform { [repository] in
            try await repository.setFollow(placeID: placeID, following: follow, by: me)
        }
    }

    func toggleFollow(user userID: User.ID) {
        guard userID != currentUserID else { return }
        let follow = !isFollowing(user: userID)
        let me = currentUserID
        if follow {
            followedUsers[me, default: []].insert(userID)
        } else {
            followedUsers[me, default: []].remove(userID)
        }
        perform { [repository] in
            try await repository.setFollow(userID: userID, following: follow, by: me)
        }
    }

    // MARK: - Engagement

    func isLiked(_ postID: Post.ID) -> Bool {
        post(postID)?.likedBy.contains(currentUserID) ?? false
    }

    func toggleLike(_ postID: Post.ID) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        let me = currentUserID
        let like = !posts[index].likedBy.contains(me)
        if like {
            posts[index].likedBy.insert(me)
        } else {
            posts[index].likedBy.remove(me)
        }
        perform { [repository] in
            try await repository.setLike(postID: postID, liked: like, by: me)
        }
    }

    func addComment(_ text: String, to postID: Post.ID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        let comment = Comment(id: UUID().uuidString, authorID: currentUserID, text: trimmed, createdAt: .now)
        posts[index].comments.append(comment)
        perform { [repository] in
            try await repository.addComment(comment, to: postID)
        }
    }

    // MARK: - Creating content

    @discardableResult
    func createPost(from draft: PostDraft) async -> Bool {
        guard draft.isReady else { return false }
        let post = Post(
            id: UUID().uuidString,
            authorID: currentUserID,
            placeID: draft.placeID,
            videoURL: draft.videoURL,
            routeName: draft.routeName.trimmingCharacters(in: .whitespacesAndNewlines),
            discipline: draft.discipline,
            grade: draft.grade,
            sendStyle: draft.sendStyle,
            caption: draft.caption.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: .now
        )
        do {
            let saved = try await repository.createPost(post)
            posts.insert(saved, at: 0)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Adds a user-submitted place and follows it for the submitter.
    func addPlace(_ place: Place) async -> Place? {
        do {
            let saved = try await repository.addPlace(place)
            places[saved.id] = saved
            if !isFollowing(place: saved.id) { toggleFollow(place: saved.id) }
            return saved
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Search

    func searchPlaces(_ query: String) -> [Place] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return popularPlaces() }
        return allPlaces.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.locationLine.localizedCaseInsensitiveContains(q)
        }
    }

    func searchUsers(_ query: String) -> [User] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return allUsers.filter { $0.id != currentUserID } }
        return allUsers.filter {
            $0.username.localizedCaseInsensitiveContains(q) || $0.displayName.localizedCaseInsensitiveContains(q)
        }
    }

    func searchPosts(_ query: String) -> [Post] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return trendingPosts() }
        return posts.filter { post in
            post.routeName.localizedCaseInsensitiveContains(q)
                || post.caption.localizedCaseInsensitiveContains(q)
                || post.grade.value.localizedCaseInsensitiveContains(q)
                || (place(post.placeID)?.name.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    // MARK: - Stats

    /// Hardest send per grading system, e.g. [V7, 5.12a].
    func hardestGrades(for userID: User.ID) -> [Grade] {
        let grouped = Dictionary(grouping: posts(by: userID).map(\.grade), by: \.system)
        return GradeSystem.allCases.compactMap { system in
            grouped[system]?.max { $0.rank < $1.rank }
        }
    }
}
