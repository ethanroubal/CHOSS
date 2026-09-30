import Foundation
import Observation

/// Where a home-feed post came from, so the card can say "Because you follow Movement Gowanus" vs. a followed climber.
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

    // MARK: Derived lookups
    // Kept in sync by `rebuildLookups()` (on load) and by each mutation, so reads are
    // dictionary lookups instead of scans over every post / follow. See docs/SEARCH_AND_SCALE.md.

    /// Post id → insertion counter; its position in `posts` is `posts.count - 1 - key`
    /// (new posts go to the front, so existing keys never change).
    @ObservationIgnored private var postAgeKeys: [Post.ID: Int] = [:]
    @ObservationIgnored private var nextPostAgeKey = 0
    /// Newest first.
    private(set) var postIDsByPlace: [Place.ID: [Post.ID]] = [:]
    private(set) var postIDsByAuthor: [User.ID: [Post.ID]] = [:]
    private(set) var postIDsByClimb: [Climb.ID: [Post.ID]] = [:]
    /// "Same climb" groups (see `climbKey(for:)`), newest first.
    private(set) var postIDsByClimbKey: [String: [Post.ID]] = [:]
    @ObservationIgnored private(set) var climbKeyByPost: [Post.ID: String] = [:]
    /// Alphabetical.
    private(set) var climbIDsByPlace: [Place.ID: [Climb.ID]] = [:]
    private(set) var placeFollowerCounts: [Place.ID: Int] = [:]
    private(set) var followerIDsByUser: [User.ID: Set<User.ID>] = [:]
    private(set) var repostCounts: [Post.ID: Int] = [:]
    /// Bumped when follows / posts / places change, so cached rankings are recomputed once.
    private(set) var popularityVersion = 0
    /// Bumped when likes or posts change (trending).
    private(set) var engagementVersion = 0
    @ObservationIgnored private var popularPlacesCache: [String: [Place.ID]] = [:]
    @ObservationIgnored private var popularPlacesCacheVersion = -1
    @ObservationIgnored private var trendingCache: [String: [Post.ID]] = [:]
    @ObservationIgnored private var trendingCacheVersion = -1
    @ObservationIgnored private var mostFilmedClimbsCache: [Climb.ID] = []
    @ObservationIgnored private var mostFilmedClimbsCacheVersion = -1
    @ObservationIgnored private var popularUsersCache: [User.ID] = []
    @ObservationIgnored private var popularUsersCacheVersion = -1

    // MARK: Search indexes
    // Built off the main thread after loading; items added later are upserted in place.
    @ObservationIgnored private var placeIndex = SearchIndex()
    @ObservationIgnored private var climbIndex = SearchIndex()
    @ObservationIgnored private var userIndex = SearchIndex()
    @ObservationIgnored private var postIndex = SearchIndex()
    @ObservationIgnored private var indexGeneration = 0
    /// Bumped whenever the indexes change, so open searches re-run.
    private(set) var searchIndexVersion = 0

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
        rebuildLookups()
        rebuildSearchIndexes()
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
    func post(_ id: Post.ID) -> Post? { postPosition(id).map { posts[$0] } }
    func climb(_ id: Climb.ID?) -> Climb? { id.flatMap { climbs[$0] } }

    var allUsers: [User] { users.values.sorted { $0.displayName < $1.displayName } }

    // MARK: - Feeds

    /// The home feed: your own posts, sends posted to places you follow, posts from climbers you
    /// follow, and posts those climbers reposted. Each post appears once.
    func homeFeed() -> [FeedItem] {
        let myPlaces = followedPlaces[currentUserID] ?? []
        let myPeople = followedUsers[currentUserID] ?? []

        var items: [Post.ID: FeedItem] = [:]
        for post in posts {
            let reason: FeedReason?
            if post.authorID == currentUserID {
                reason = .own
            } else if let placeID = post.placeID, myPlaces.contains(placeID) {
                reason = .followedPlace(placeID)
            } else if myPeople.contains(post.authorID) {
                reason = .followedUser
            } else {
                reason = nil
            }
            if let reason {
                items[post.id] = FeedItem(post: post, reason: reason, date: post.createdAt)
            }
        }

        // A post already in the feed keeps its original reason; among reposts, the newest wins.
        for repost in reposts where myPeople.contains(repost.userID) {
            guard let post = self.post(repost.postID) else { continue }
            if let existing = items[post.id] {
                guard case .repostedBy = existing.reason, repost.createdAt > existing.date else { continue }
            }
            items[post.id] = FeedItem(post: post, reason: .repostedBy(repost.userID), date: repost.createdAt)
        }

        return items.values.sorted { $0.date > $1.date }
    }

    func posts(at placeID: Place.ID) -> [Post] {
        (postIDsByPlace[placeID] ?? []).compactMap { post($0) }
    }

    /// Counts without building the post arrays (for list rows).
    func postCount(at placeID: Place.ID) -> Int { postIDsByPlace[placeID]?.count ?? 0 }
    func postCount(by userID: User.ID) -> Int { postIDsByAuthor[userID]?.count ?? 0 }
    func postCount(ofClimb climbID: Climb.ID) -> Int { postIDsByClimb[climbID]?.count ?? 0 }

    func posts(by userID: User.ID) -> [Post] {
        (postIDsByAuthor[userID] ?? []).compactMap { post($0) }
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
        trendingPostIDs(discipline: discipline).compactMap { post($0) }
    }

    /// Cached; re-sorted only after likes or posts change.
    func trendingPostIDs(discipline: ClimbDiscipline? = nil) -> [Post.ID] {
        if trendingCacheVersion != engagementVersion {
            trendingCache = [:]
            trendingCacheVersion = engagementVersion
        }
        let key = discipline?.rawValue ?? "all"
        if let cached = trendingCache[key] { return cached }
        let ids = posts
            .filter { discipline == nil || $0.discipline == discipline }
            .sorted { ($0.likedBy.count, $0.createdAt) > ($1.likedBy.count, $1.createdAt) }
            .map(\.id)
        trendingCache[key] = ids
        return ids
    }

    /// Most-followed first, then most sends, then alphabetical (most imported places have neither yet).
    func popularPlaces(kind: PlaceKind? = nil) -> [Place] {
        popularPlaceIDs(kind: kind).compactMap { places[$0] }
    }

    /// Cached; re-sorted only after follows, posts or places change (not on every screen redraw).
    func popularPlaceIDs(kind: PlaceKind? = nil) -> [Place.ID] {
        if popularPlacesCacheVersion != popularityVersion {
            popularPlacesCache = [:]
            popularPlacesCacheVersion = popularityVersion
        }
        let key = kind?.rawValue ?? "all"
        if let cached = popularPlacesCache[key] { return cached }
        let ranked = places.values
            .filter { kind == nil || $0.kind == kind }
            .map { place in
                (id: place.id, followers: placeFollowerCounts[place.id] ?? 0,
                 sends: postIDsByPlace[place.id]?.count ?? 0, name: place.name.lowercased())
            }
            .sorted { lhs, rhs in
                if lhs.followers != rhs.followers { return lhs.followers > rhs.followers }
                if lhs.sends != rhs.sends { return lhs.sends > rhs.sends }
                return lhs.name < rhs.name
            }
            .map { $0.id }
        popularPlacesCache[key] = ranked
        return ranked
    }

    /// Climbers by follower count (suggestions when nothing is typed). Cached like places.
    func popularUserIDs() -> [User.ID] {
        if popularUsersCacheVersion != popularityVersion {
            popularUsersCache = users.values
                .sorted { lhs, rhs in
                    let l = followerIDsByUser[lhs.id]?.count ?? 0, r = followerIDsByUser[rhs.id]?.count ?? 0
                    return l != r ? l > r : lhs.displayName < rhs.displayName
                }
                .map(\.id)
            popularUsersCacheVersion = popularityVersion
        }
        return popularUsersCache
    }

    // MARK: - Follow graph

    func isFollowing(place placeID: Place.ID) -> Bool {
        followedPlaces[currentUserID]?.contains(placeID) ?? false
    }

    func isFollowing(user userID: User.ID) -> Bool {
        followedUsers[currentUserID]?.contains(userID) ?? false
    }

    func followerCount(of placeID: Place.ID) -> Int {
        placeFollowerCounts[placeID] ?? 0
    }

    func followerCount(ofUser userID: User.ID) -> Int {
        followerIDsByUser[userID]?.count ?? 0
    }

    /// Climbers who follow `userID`, alphabetically.
    func followers(of userID: User.ID) -> [User] {
        (followerIDsByUser[userID] ?? [])
            .compactMap { users[$0] }
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
            placeFollowerCounts[placeID, default: 0] += 1
        } else {
            followedPlaces[me, default: []].remove(placeID)
            placeFollowerCounts[placeID] = max((placeFollowerCounts[placeID] ?? 1) - 1, 0)
        }
        popularityVersion += 1
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
            followerIDsByUser[userID, default: []].insert(me)
        } else {
            followedUsers[me, default: []].remove(userID)
            followerIDsByUser[userID]?.remove(me)
        }
        popularityVersion += 1
        perform { [repository] in
            try await repository.setFollow(userID: userID, following: follow, by: me)
        }
    }

    // MARK: - Engagement

    func isLiked(_ postID: Post.ID) -> Bool {
        post(postID)?.likedBy.contains(currentUserID) ?? false
    }

    func toggleLike(_ postID: Post.ID) {
        guard let index = postPosition(postID) else { return }
        defer { engagementVersion += 1 }
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
        guard !trimmed.isEmpty, let index = postPosition(postID) else { return }
        let comment = Comment(id: UUID().uuidString, authorID: currentUserID, text: trimmed, createdAt: .now)
        posts[index].comments.append(comment)
        perform { [repository] in
            try await repository.addComment(comment, to: postID)
        }
    }

    func deleteComment(_ commentID: Comment.ID, from postID: Post.ID) {
        guard let index = postPosition(postID),
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
        repostCounts[postID] ?? 0
    }

    /// Reposting your own post isn't allowed (same as Instagram).
    func canRepost(_ post: Post) -> Bool { post.authorID != currentUserID }

    func toggleRepost(_ postID: Post.ID) {
        guard let post = post(postID), canRepost(post) else { return }
        let me = currentUserID
        if isReposted(postID) {
            reposts.removeAll { $0.postID == postID && $0.userID == me }
            repostCounts[postID] = max((repostCounts[postID] ?? 1) - 1, 0)
            perform { [repository] in
                try await repository.removeRepost(postID: postID, by: me)
            }
        } else {
            let repost = Repost(id: UUID().uuidString, userID: me, postID: postID, createdAt: .now)
            reposts.append(repost)
            repostCounts[postID, default: 0] += 1
            perform { [repository] in
                try await repository.addRepost(repost)
            }
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
        userIndex.upsert(searchItem(for: user))
        searchIndexVersion += 1
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
            userIndex.upsert(searchItem(for: user))
            searchIndexVersion += 1
            popularityVersion += 1
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
            indexNewPost(saved)
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
            placeIndex.upsert(searchItem(for: saved))
            searchIndexVersion += 1
            popularityVersion += 1
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
        (climbIDsByPlace[placeID] ?? []).compactMap { climbs[$0] }
    }

    /// Every send video of a climb (its beta), newest first.
    func posts(ofClimb climbID: Climb.ID) -> [Post] {
        (postIDsByClimb[climbID] ?? []).compactMap { post($0) }
    }

    /// Fuzzy climb-name search within one crag (a crag has a manageable number of climbs).
    /// Searching every climb everywhere goes through `searchClimbIDs(_:)` instead.
    func searchClimbs(_ query: String, at placeID: Place.ID) -> [Climb] {
        let pool = climbs(at: placeID)
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            // No query: most-filmed climbs first, handy for finding beta.
            return pool.sorted { postCount(ofClimb: $0.id) > postCount(ofClimb: $1.id) }
        }
        return NameMatcher.rank(pool, query: query)
    }

    /// Climbs with the most videos first (only climbs that have any). Cached until posts change.
    func mostFilmedClimbIDs() -> [Climb.ID] {
        if mostFilmedClimbsCacheVersion != engagementVersion {
            mostFilmedClimbsCache = postIDsByClimb
                .filter { climbs[$0.key] != nil }
                .sorted { lhs, rhs in
                    lhs.value.count != rhs.value.count ? lhs.value.count > rhs.value.count : lhs.key < rhs.key
                }
                .map { $0.key }
            mostFilmedClimbsCacheVersion = engagementVersion
        }
        return mostFilmedClimbsCache
    }

    /// Adds a climb that isn't in the database yet (shown as unverified).
    func addClimb(_ climb: Climb) async -> Climb? {
        do {
            let saved = try await repository.addClimb(climb)
            climbs[saved.id] = saved
            climbIDsByPlace[saved.placeID, default: []].append(saved.id)
            climbIDsByPlace[saved.placeID]?.sort { (climbs[$0]?.name ?? "") < (climbs[$1]?.name ?? "") }
            climbIndex.upsert(searchItem(for: saved))
            searchIndexVersion += 1
            return saved
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Search
    // Every search runs on a snapshot of an index, off the main thread, and returns ids (best
    // match first). Cost stays roughly flat as the number of places / climbs / people / sends grows.

    func searchPlaceIDs(_ query: String, kind: PlaceKind? = nil, limit: Int = 100) async -> [Place.ID] {
        let index = placeIndex
        return await Task.detached(priority: .userInitiated) {
            index.search(query, tag: kind?.rawValue, limit: limit)
        }.value
    }

    func searchClimbIDs(_ query: String, limit: Int = 100) async -> [Climb.ID] {
        let index = climbIndex
        return await Task.detached(priority: .userInitiated) { index.search(query, limit: limit) }.value
    }

    func searchUserIDs(_ query: String, limit: Int = 100) async -> [User.ID] {
        let index = userIndex
        return await Task.detached(priority: .userInitiated) { index.search(query, limit: limit) }.value
    }

    /// Sends by climb name, caption, place or climber. A query that is exactly a grade ("v5",
    /// "5.11a") also finds recent sends at that grade.
    func searchPostIDs(_ query: String, limit: Int = 100) async -> [Post.ID] {
        let index = postIndex
        let byText = await Task.detached(priority: .userInitiated) { index.search(query, limit: limit) }.value
        let wanted = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard GradeSystem.allCases.contains(where: { $0.grades.contains { $0.lowercased() == wanted } }) else {
            return byText
        }
        // Grades are community averages that change as people post, so they aren't indexed;
        // check the most recent sends only, which keeps this bounded.
        let byGrade = posts.prefix(2_000)
            .filter { displayGrade(for: $0)?.value.lowercased() == wanted }
            .prefix(limit)
            .map(\.id)
        var seen = Set(byGrade)
        return Array((byGrade + byText.filter { seen.insert($0).inserted }).prefix(limit))
    }

    // MARK: - Lookup maintenance

    private func postPosition(_ id: Post.ID) -> Int? {
        guard let key = postAgeKeys[id] else { return nil }
        let position = posts.count - 1 - key
        guard posts.indices.contains(position), posts[position].id == id else { return nil }
        return position
    }

    /// Recomputes every derived lookup from scratch (on load).
    private func rebuildLookups() {
        var ageKeys: [Post.ID: Int] = [:]
        var byPlace: [Place.ID: [Post.ID]] = [:]
        var byAuthor: [User.ID: [Post.ID]] = [:]
        var byClimb: [Climb.ID: [Post.ID]] = [:]
        var byKey: [String: [Post.ID]] = [:]
        var keys: [Post.ID: String] = [:]
        ageKeys.reserveCapacity(posts.count)
        for (position, post) in posts.enumerated() {  // newest first, so appends stay newest first
            ageKeys[post.id] = posts.count - 1 - position
            if let placeID = post.placeID { byPlace[placeID, default: []].append(post.id) }
            byAuthor[post.authorID, default: []].append(post.id)
            if let climbID = post.climbID { byClimb[climbID, default: []].append(post.id) }
            if let key = computeClimbKey(for: post) {
                keys[post.id] = key
                byKey[key, default: []].append(post.id)
            }
        }
        postAgeKeys = ageKeys
        nextPostAgeKey = posts.count
        postIDsByPlace = byPlace
        postIDsByAuthor = byAuthor
        postIDsByClimb = byClimb
        postIDsByClimbKey = byKey
        climbKeyByPost = keys

        climbIDsByPlace = Dictionary(grouping: climbs.values, by: \.placeID)
            .mapValues { $0.sorted { $0.name < $1.name }.map(\.id) }

        var placeCounts: [Place.ID: Int] = [:]
        for followed in followedPlaces.values {
            for id in followed { placeCounts[id, default: 0] += 1 }
        }
        placeFollowerCounts = placeCounts

        var followers: [User.ID: Set<User.ID>] = [:]
        for (follower, followed) in followedUsers {
            for id in followed { followers[id, default: []].insert(follower) }
        }
        followerIDsByUser = followers

        var reposted: [Post.ID: Int] = [:]
        for repost in reposts { reposted[repost.postID, default: 0] += 1 }
        repostCounts = reposted

        popularityVersion += 1
        engagementVersion += 1
    }

    /// Adds a just-created post (already inserted at the front of `posts`) to every lookup.
    private func indexNewPost(_ post: Post) {
        postAgeKeys[post.id] = nextPostAgeKey
        nextPostAgeKey += 1
        if let placeID = post.placeID { postIDsByPlace[placeID, default: []].insert(post.id, at: 0) }
        postIDsByAuthor[post.authorID, default: []].insert(post.id, at: 0)
        if let climbID = post.climbID { postIDsByClimb[climbID, default: []].insert(post.id, at: 0) }
        if let key = computeClimbKey(for: post) {
            climbKeyByPost[post.id] = key
            postIDsByClimbKey[key, default: []].insert(post.id, at: 0)
        }
        postIndex.upsert(searchItem(for: post))
        searchIndexVersion += 1
        popularityVersion += 1
        engagementVersion += 1
    }

    // MARK: - Search index building

    private func searchItem(for place: Place) -> SearchIndex.Item {
        SearchIndex.Item(id: place.id, names: [place.name], secondary: [place.city, place.region],
                         tag: place.kind.rawValue,
                         boost: Double(placeFollowerCounts[place.id] ?? 0) + Double(postIDsByPlace[place.id]?.count ?? 0) / 100)
    }

    private func searchItem(for climb: Climb) -> SearchIndex.Item {
        SearchIndex.Item(id: climb.id, names: [climb.name],
                         secondary: [climb.area, places[climb.placeID]?.name ?? ""],
                         boost: Double(postIDsByClimb[climb.id]?.count ?? 0))
    }

    private func searchItem(for user: User) -> SearchIndex.Item {
        SearchIndex.Item(id: user.id, names: [user.displayName, user.username],
                         boost: Double(followerIDsByUser[user.id]?.count ?? 0))
    }

    private func searchItem(for post: Post) -> SearchIndex.Item {
        SearchIndex.Item(id: post.id, names: [climbs[post.climbID ?? ""]?.name ?? post.routeName],
                         secondary: [post.caption, places[post.placeID ?? ""]?.name ?? "",
                                     users[post.authorID]?.username ?? ""],
                         boost: Double(post.likedBy.count))
    }

    /// Builds the search indexes in the background. Gathering the items is a quick pass here;
    /// the expensive part (normalizing every name, building the trigram tables) runs off the
    /// main thread, and results are swapped in when ready.
    private func rebuildSearchIndexes() {
        indexGeneration += 1
        let generation = indexGeneration
        let placeItems = places.values.map { searchItem(for: $0) }
        let climbItems = climbs.values.map { searchItem(for: $0) }
        let userItems = users.values.map { searchItem(for: $0) }
        let postItems = posts.map { searchItem(for: $0) }
        Task.detached(priority: .userInitiated) { [weak self] in
            let places = SearchIndex(placeItems)
            let climbs = SearchIndex(climbItems)
            let users = SearchIndex(userItems)
            let posts = SearchIndex(postItems)
            await self?.installIndexes(generation: generation, places: places, climbs: climbs,
                                       users: users, posts: posts)
        }
    }

    private func installIndexes(generation: Int, places: SearchIndex, climbs: SearchIndex,
                                users: SearchIndex, posts: SearchIndex) {
        guard generation == indexGeneration else { return }  // a newer rebuild is on its way
        placeIndex = places
        climbIndex = climbs
        userIndex = users
        postIndex = posts
        searchIndexVersion += 1
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
