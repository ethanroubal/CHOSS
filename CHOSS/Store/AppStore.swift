import Foundation
import Observation

/// Where a home-feed post came from, so the card can say "From Granite Works" vs. a followed climber.
enum FeedReason: Hashable {
    case followedPlace(Place.ID)
    case followedUser
    case repostedBy(User.ID)
    case own
}

struct FeedItem: Identifiable {
    let post: Post
    let reason: FeedReason
    /// When it entered the feed: the post date, or the repost date for reposts.
    let date: Date
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
    private(set) var climbs: [Climb.ID: Climb] = [:]
    /// Newest first.
    private(set) var posts: [Post] = []
    private(set) var followedPlaces: [User.ID: Set<Place.ID>] = [:]
    private(set) var followedUsers: [User.ID: Set<User.ID>] = [:]
    private(set) var reposts: [Repost] = []
    private(set) var conversations: [Conversation] = []
    private(set) var messages: [Message] = []

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
        climbs = Dictionary(uniqueKeysWithValues: snapshot.climbs.map { ($0.id, $0) })
        posts = snapshot.posts.sorted { $0.createdAt > $1.createdAt }
        followedPlaces = snapshot.followedPlaces
        followedUsers = snapshot.followedUsers
        reposts = snapshot.reposts
        conversations = snapshot.conversations
        messages = snapshot.messages.sorted { $0.createdAt < $1.createdAt }
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
    func climb(_ id: Climb.ID?) -> Climb? { id.flatMap { climbs[$0] } }

    var allPlaces: [Place] { places.values.sorted { $0.name < $1.name } }
    var allUsers: [User] { users.values.sorted { $0.displayName < $1.displayName } }

    // MARK: - Feeds

    /// The home feed: sends posted to places you follow, posts from climbers you follow,
    /// and posts those climbers reposted. Each post appears once.
    func homeFeed(filter: HomeFeedFilter) -> [FeedItem] {
        let myPlaces = followedPlaces[currentUserID] ?? []
        let myPeople = followedUsers[currentUserID] ?? []

        var items: [Post.ID: FeedItem] = [:]
        for post in posts {
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
            if let reason {
                items[post.id] = FeedItem(post: post, reason: reason, date: post.createdAt)
            }
        }

        if filter != .places {
            // A post already in the feed keeps its original reason; among reposts, the newest wins.
            for repost in reposts where myPeople.contains(repost.userID) {
                guard let post = self.post(repost.postID) else { continue }
                if let existing = items[post.id] {
                    guard case .repostedBy = existing.reason, repost.createdAt > existing.date else { continue }
                }
                items[post.id] = FeedItem(post: post, reason: .repostedBy(repost.userID), date: repost.createdAt)
            }
        }

        return items.values.sorted { $0.date > $1.date }
    }

    func posts(at placeID: Place.ID) -> [Post] {
        posts.filter { $0.placeID == placeID }
    }

    func posts(by userID: User.ID) -> [Post] {
        posts.filter { $0.authorID == userID }
    }

    /// Posts a user has reposted, most recent repost first.
    func repostedPosts(by userID: User.ID) -> [Post] {
        reposts
            .filter { $0.userID == userID }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { post($0.postID) }
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

    /// Climbers who follow `userID`, alphabetically.
    func followers(of userID: User.ID) -> [User] {
        followedUsers
            .filter { $0.value.contains(userID) }
            .compactMap { users[$0.key] }
            .sorted { $0.displayName < $1.displayName }
    }

    func followingCount(ofUser userID: User.ID) -> Int {
        followedUsers[userID]?.count ?? 0
    }

    /// Climbers `userID` follows, alphabetically.
    func followedUsers(of userID: User.ID) -> [User] {
        (followedUsers[userID] ?? []).compactMap { users[$0] }.sorted { $0.displayName < $1.displayName }
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

    func deleteComment(_ commentID: Comment.ID, from postID: Post.ID) {
        guard let index = posts.firstIndex(where: { $0.id == postID }),
              posts[index].comments.contains(where: { $0.id == commentID && $0.authorID == currentUserID })
        else { return }
        posts[index].comments.removeAll { $0.id == commentID }
        perform { [repository] in
            try await repository.deleteComment(commentID, from: postID)
        }
    }

    // MARK: - Reposts

    func isReposted(_ postID: Post.ID) -> Bool {
        reposts.contains { $0.postID == postID && $0.userID == currentUserID }
    }

    func repostCount(_ postID: Post.ID) -> Int {
        reposts.filter { $0.postID == postID }.count
    }

    /// Reposting your own post isn't allowed (same as Instagram).
    func canRepost(_ post: Post) -> Bool { post.authorID != currentUserID }

    func toggleRepost(_ postID: Post.ID) {
        guard let post = post(postID), canRepost(post) else { return }
        let me = currentUserID
        if isReposted(postID) {
            reposts.removeAll { $0.postID == postID && $0.userID == me }
            perform { [repository] in
                try await repository.removeRepost(postID: postID, by: me)
            }
        } else {
            let repost = Repost(id: UUID().uuidString, userID: me, postID: postID, createdAt: .now)
            reposts.append(repost)
            perform { [repository] in
                try await repository.addRepost(repost)
            }
        }
    }

    // MARK: - Direct messages

    /// The current user's threads, most recently active first.
    var myConversations: [Conversation] {
        conversations
            .filter { $0.participantIDs.contains(currentUserID) }
            .sorted { (lastMessage(in: $0.id)?.createdAt ?? .distantPast) > (lastMessage(in: $1.id)?.createdAt ?? .distantPast) }
    }

    func messages(in conversationID: Conversation.ID) -> [Message] {
        messages.filter { $0.conversationID == conversationID }
    }

    func lastMessage(in conversationID: Conversation.ID) -> Message? {
        messages.last { $0.conversationID == conversationID }
    }

    /// The other people in a thread (everyone but the current user).
    func otherParticipants(in conversation: Conversation) -> [User] {
        conversation.participantIDs.subtracting([currentUserID]).compactMap { users[$0] }
    }

    /// Finds the 1:1 thread with `userID`, creating it if needed.
    @discardableResult
    func directConversation(with userID: User.ID) -> Conversation {
        let participants: Set<User.ID> = [currentUserID, userID]
        if let existing = conversations.first(where: { $0.participantIDs == participants }) {
            return existing
        }
        let conversation = Conversation(id: UUID().uuidString, participantIDs: participants)
        conversations.append(conversation)
        perform { [repository] in
            try await repository.saveConversation(conversation)
        }
        return conversation
    }

    func sendMessage(_ text: String, sharing postID: Post.ID? = nil, in conversationID: Conversation.ID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || postID != nil else { return }
        let message = Message(id: UUID().uuidString, conversationID: conversationID, senderID: currentUserID,
                              text: trimmed, sharedPostID: postID, createdAt: .now)
        messages.append(message)
        perform { [repository] in
            try await repository.sendMessage(message)
        }
    }

    /// Sends a post to each recipient in their own 1:1 thread, with an optional note.
    func share(_ postID: Post.ID, with recipientIDs: Set<User.ID>, note: String) {
        for recipient in recipientIDs {
            let conversation = directConversation(with: recipient)
            sendMessage(note, sharing: postID, in: conversation.id)
        }
    }

    // MARK: - Profiles

    func isUsernameAvailable(_ username: String, excluding userID: User.ID? = nil) -> Bool {
        let wanted = username.lowercased()
        return !users.values.contains { $0.username.lowercased() == wanted && $0.id != userID }
    }

    /// Saves edits to the current user's profile.
    func updateProfile(_ user: User) {
        guard user.id == currentUserID else { return }
        users[user.id] = user
        followHomePlaces(of: user)
        perform { [repository] in
            try await repository.saveUser(user)
        }
    }

    /// Your home gyms / crags are always in your feed.
    private func followHomePlaces(of user: User) {
        for home in user.homePlaceIDs where !isFollowing(place: home) {
            toggleFollow(place: home)
        }
    }

    /// Profile setup for a new account; signs in as the new user.
    func createAccount(_ user: User) async -> Bool {
        guard isUsernameAvailable(user.username) else {
            lastError = "That username is taken."
            return false
        }
        do {
            try await repository.saveUser(user)
            users[user.id] = user
            currentUserID = user.id
            followHomePlaces(of: user)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
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
            climbID: draft.climbID,
            videoURL: draft.videoURL,
            routeName: draft.routeName.trimmingCharacters(in: .whitespacesAndNewlines),
            discipline: draft.discipline,
            grade: nil,  // the climb's grade is the average of proposed grades
            proposedGrade: draft.proposedGrade,
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

    // MARK: - Outdoor climbs

    /// Every climb at a crag, alphabetically.
    func climbs(at placeID: Place.ID) -> [Climb] {
        climbs.values.filter { $0.placeID == placeID }.sorted { $0.name < $1.name }
    }

    /// Every send video of a climb (its beta), newest first.
    func posts(ofClimb climbID: Climb.ID) -> [Post] {
        posts.filter { $0.climbID == climbID }
    }

    /// Fuzzy climb-name search, best match first, optionally limited to one crag.
    func searchClimbs(_ query: String, at placeID: Place.ID? = nil) -> [Climb] {
        let pool = placeID.map { climbs(at: $0) } ?? climbs.values.sorted { $0.name < $1.name }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            // No query: most-filmed climbs first, handy for finding beta.
            return pool.sorted { posts(ofClimb: $0.id).count > posts(ofClimb: $1.id).count }
        }
        return NameMatcher.rank(pool, query: query)
    }

    /// Adds a climb that isn't in the database yet (shown as unverified).
    func addClimb(_ climb: Climb) async -> Climb? {
        do {
            let saved = try await repository.addClimb(climb)
            climbs[saved.id] = saved
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
        // Typo-tolerant, by name first, then town/region ("granit", "bishop", "font").
        return allPlaces
            .compactMap { place -> (Place, Double)? in
                let byName = NameMatcher.score(query: q, names: [place.name])
                let byLocation = NameMatcher.score(query: q, names: [place.city, place.region, place.country])
                    .map { $0 - 5 }  // a name match beats a same-quality location match
                guard let score = [byName, byLocation].compactMap({ $0 }).max() else { return nil }
                return (place, score)
            }
            .sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 > rhs.1 : followerCount(of: lhs.0.id) > followerCount(of: rhs.0.id)
            }
            .map { $0.0 }
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
                || (displayGrade(for: post)?.value.localizedCaseInsensitiveContains(q) ?? false)
                || (place(post.placeID)?.name.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    // MARK: - Stats

    /// Hardest send per grading system, e.g. [V7, 5.12a], using each climb's average grade.
    /// Links (sections, not full sends) don't count.
    func hardestGrades(for userID: User.ID) -> [Grade] {
        let sends = posts(by: userID).filter { $0.sendStyle.countsAsSend }
        let grouped = Dictionary(grouping: sends.compactMap { displayGrade(for: $0) }, by: \.system)
        return GradeSystem.allCases.compactMap { system in
            grouped[system]?.max { $0.rank < $1.rank }
        }
    }
}
