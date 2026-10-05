#if canImport(Supabase)
import Foundation
import UIKit
import Supabase

/// `ClimbingRepository` backed by Supabase (see supabase/migrations and docs/BACKEND_PLAN.md).
///
/// For now it loads one snapshot at launch, like the demo data, so every screen works
/// unchanged:
/// - all places;
/// - the climbs those need (in sends, projects and photos) plus the most filmed. A crag's other
///   climbs load when its page or the route picker opens (`climbs(at:)`), and climb search runs
///   on the server (`searchClimbs`): there are 200k+ outdoor climbs.
/// - the latest 400 sends plus your own;
/// - the people involved;
/// - follows, likes, comments, reposts, photos and projects.
///
/// That's fine for a beta. The next step is loading each screen a page at a time (home_feed,
/// search_* and places_in_box are ready on the server).
///
/// Writes go straight to their tables. Row Level Security on the server checks every one, so
/// the app can't change anything it shouldn't.
final class SupabaseClimbingRepository: ClimbingRepository, @unchecked Sendable {
    private let client: SupabaseClient
    private let userID: String
    private let pageSize = 1000
    private let recentPostLimit = 400
    private let popularClimbLimit = 200
    /// Local avatar file → its uploaded path, so later profile saves (e.g. adding a project)
    /// don't upload the same picture again.
    private var uploadedAvatars: [String: String] = [:]
    private let lock = NSLock()

    init(client: SupabaseClient, userID: String) {
        self.client = client
        self.userID = userID
    }

    // MARK: - Loading

    func loadSnapshot() async throws -> AppSnapshot {
        async let placeRows: [PlaceRecord] = allPages("places", columns: PlaceRecord.columns, order: "name")
        async let popularClimbRows: [ClimbRecord] = client.from("climbs").select(ClimbRecord.columns)
            .gt("post_count", value: 0).order("post_count", ascending: false).limit(popularClimbLimit)
            .execute().value
        async let recentRows: [PostRow] = client.from("posts").select(PostRow.columns)
            .order("created_at", ascending: false).limit(recentPostLimit).execute().value
        async let myRows: [PostRow] = client.from("posts").select(PostRow.columns)
            .eq("author_id", value: userID).order("created_at", ascending: false).execute().value
        async let userFollowRows: [UserFollowRow] = allPages("user_follows", columns: "follower_id,followee_id", order: "created_at")
        async let placeFollowRows: [PlaceFollowRow] = allPages("place_follows", columns: "user_id,place_id", order: "created_at")
        async let repostRows: [RepostRow] = client.from("reposts").select("user_id,post_id,created_at")
            .order("created_at", ascending: false).limit(2000).execute().value
        async let photoRows: [PhotoRow] = allPages("community_photos", columns: PhotoRow.columns, order: "created_at")

        var postsByID: [String: PostRow] = [:]
        for row in try await recentRows + myRows { postsByID[row.id] = row }
        let postIDs = Array(postsByID.keys)
        let userFollows = try await userFollowRows
        let placeFollows = try await placeFollowRows
        let reposts = try await repostRows
        let photos = try await photoRows

        async let likeRows: [PostLikeRow] = rows(in: "post_likes", columns: "post_id,user_id", key: "post_id", values: postIDs)
        async let commentRows: [CommentRow] = rows(in: "comments", columns: CommentRow.columns, key: "post_id", values: postIDs)
        async let photoLikeRows: [PhotoLikeRow] = rows(in: "photo_likes", columns: "photo_id,user_id",
                                                       key: "photo_id", values: photos.map(\.id))

        // Everyone who appears anywhere: authors, commenters, followers, reposters, you.
        let comments = try await commentRows
        var people = Set([userID])
        people.formUnion(postsByID.values.map(\.author_id))
        people.formUnion(comments.map(\.author_id))
        people.formUnion(userFollows.flatMap { [$0.follower_id, $0.followee_id] })
        people.formUnion(reposts.map(\.user_id))
        people.formUnion(photos.map(\.author_id))
        let peopleIDs = Array(people)

        async let profileRows: [ProfileRow] = rows(in: "profiles", columns: ProfileRow.columns, key: "id", values: peopleIDs)
        async let homeRows: [HomePlaceRow] = rows(in: "profile_home_places", columns: "user_id,place_id,position",
                                                  key: "user_id", values: peopleIDs)
        async let projectRows: [ProjectRow] = rows(in: "projects", columns: "user_id,climb_id,created_at",
                                                   key: "user_id", values: peopleIDs)

        let likes = try await likeRows
        let photoLikes = try await photoLikeRows
        let homes = Dictionary(grouping: try await homeRows, by: \.user_id)
        let likedBy = Dictionary(grouping: likes, by: \.post_id).mapValues { Set($0.map(\.user_id)) }
        let commentsByPost = Dictionary(grouping: comments, by: \.post_id)
        let photoLikedBy = Dictionary(grouping: photoLikes, by: \.photo_id).mapValues { Set($0.map(\.user_id)) }

        let projectsList = try await projectRows
        let projects = Dictionary(grouping: projectsList, by: \.user_id)
        // The climbs anything on screen points at.
        var climbIDs = Set(postsByID.values.compactMap(\.climb_id))
        climbIDs.formUnion(projectsList.map(\.climb_id))
        climbIDs.formUnion(photos.compactMap(\.climb_id))
        var climbsByID: [String: Climb] = [:]
        for row in try await popularClimbRows { climbsByID[row.id] = row.climb }
        climbIDs.subtract(climbsByID.keys)
        let referencedClimbs: [ClimbRecord] = try await rows(in: "climbs", columns: ClimbRecord.columns,
                                                             key: "id", values: Array(climbIDs))
        for row in referencedClimbs { climbsByID[row.id] = row.climb }

        let users = try await profileRows.map { row in
            row.user(
                homePlaceIDs: (homes[row.id] ?? []).sorted { $0.position < $1.position }.map(\.place_id),
                projectClimbIDs: (projects[row.id] ?? []).sorted { $0.created_at > $1.created_at }.map(\.climb_id),
                avatarURL: row.avatar_path.flatMap { publicURL(bucket: "avatars", path: $0) }
            )
        }
        let posts = postsByID.values.map { row in
            row.post(likedBy: likedBy[row.id] ?? [],
                     comments: (commentsByPost[row.id] ?? []).map(\.comment).sorted { $0.createdAt < $1.createdAt })
        }
        let communityPhotos = photos.compactMap { row in
            publicURL(bucket: "community-photos", path: row.storage_path).flatMap { url in
                row.photo(imageURL: url, likedBy: photoLikedBy[row.id] ?? [])
            }
        }

        return AppSnapshot(
            users: users,
            places: try await placeRows.map(\.place),
            climbs: Array(climbsByID.values),
            posts: posts,
            followedPlaces: Dictionary(grouping: placeFollows, by: \.user_id).mapValues { Set($0.map(\.place_id)) },
            followedUsers: Dictionary(grouping: userFollows, by: \.follower_id).mapValues { Set($0.map(\.followee_id)) },
            reposts: reposts.map(\.repost),
            communityPhotos: communityPhotos
        )
    }

    /// Every row of a table, `pageSize` at a time (the server returns at most 1000 per request).
    private func allPages<T: Decodable>(_ table: String, columns: String, order: String) async throws -> [T] {
        var all: [T] = []
        var from = 0
        while true {
            let page: [T] = try await client.from(table).select(columns)
                .order(order).range(from: from, to: from + pageSize - 1).execute().value
            all += page
            if page.count < pageSize { return all }
            from += pageSize
        }
    }

    /// Rows whose `key` is one of `values`, asked for in small batches (keeps URLs short).
    private func rows<T: Decodable>(in table: String, columns: String, key: String, values: [String]) async throws -> [T] {
        var all: [T] = []
        for start in stride(from: 0, to: values.count, by: 100) {
            let batch = Array(values[start..<min(start + 100, values.count)])
            let page: [T] = try await client.from(table).select(columns).in(key, values: batch).execute().value
            all += page
        }
        return all
    }

    private func publicURL(bucket: String, path: String) -> URL? {
        try? client.storage.from(bucket).getPublicURL(path: path)
    }

    // MARK: - Follows, likes, views

    func setFollow(placeID: Place.ID, following: Bool, by userID: User.ID) async throws {
        if following {
            try await client.from("place_follows").insert(["user_id": userID, "place_id": placeID]).execute()
        } else {
            try await client.from("place_follows").delete()
                .eq("user_id", value: userID).eq("place_id", value: placeID).execute()
        }
    }

    func setFollow(userID: User.ID, following: Bool, by followerID: User.ID) async throws {
        if following {
            try await client.from("user_follows").insert(["follower_id": followerID, "followee_id": userID]).execute()
        } else {
            try await client.from("user_follows").delete()
                .eq("follower_id", value: followerID).eq("followee_id", value: userID).execute()
        }
    }

    func setLike(postID: Post.ID, liked: Bool, by userID: User.ID) async throws {
        if liked {
            try await client.from("post_likes").insert(["post_id": postID, "user_id": userID]).execute()
        } else {
            try await client.from("post_likes").delete()
                .eq("post_id", value: postID).eq("user_id", value: userID).execute()
        }
    }

    func recordView(postID: Post.ID, by userID: User.ID) async throws -> Int? {
        try await client.rpc("record_view", params: ["p_post": postID]).execute().value
    }

    // MARK: - Comments, reposts

    func addComment(_ comment: Comment, to postID: Post.ID) async throws {
        try await client.from("comments").insert([
            "id": comment.id, "post_id": postID, "author_id": comment.authorID, "body": comment.text,
        ]).execute()
    }

    func deleteComment(_ commentID: Comment.ID, from postID: Post.ID) async throws {
        try await client.from("comments").delete().eq("id", value: commentID).execute()
    }

    func addRepost(_ repost: Repost) async throws {
        try await client.from("reposts").insert(["user_id": repost.userID, "post_id": repost.postID]).execute()
    }

    func removeRepost(postID: Post.ID, by userID: User.ID) async throws {
        try await client.from("reposts").delete()
            .eq("user_id", value: userID).eq("post_id", value: postID).execute()
    }

    // MARK: - Posting

    /// Creates the post on the server (hidden until its video is processed) and uploads the
    /// video straight to Mux. Returns the post with its server id; the poster sees it at once,
    /// everyone else once Mux has finished (usually under a minute).
    func createPost(_ post: Post) async throws -> Post {
        guard let videoURL = post.videoURL else { throw BackendError.missingVideo }
        let request = CreateVideoUploadRequest(
            placeId: post.placeID, climbId: post.climbID, routeName: post.routeName,
            discipline: post.discipline.rawValue, sendStyle: post.sendStyle.rawValue,
            proposedGradeSystem: post.proposedGrade?.system.rawValue,
            proposedGradeValue: post.proposedGrade?.value, caption: post.caption
        )
        let upload: CreateVideoUploadResponse = try await client.functions.invoke(
            "create-video-upload", options: FunctionInvokeOptions(body: request)
        )
        guard let uploadURL = URL(string: upload.uploadUrl) else { throw BackendError.badResponse }
        var put = URLRequest(url: uploadURL)
        put.httpMethod = "PUT"
        put.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        // Ask iOS for extra time so leaving the app mid-upload doesn't cut it off (a few minutes
        // at most; an upload that never finishes is cleaned up on the server after a day).
        let backgroundTask = await MainActor.run { () -> UIBackgroundTaskIdentifier in
            var id = UIBackgroundTaskIdentifier.invalid
            // If time runs out, end the task (iOS stops the app otherwise); the upload just stops.
            id = UIApplication.shared.beginBackgroundTask(withName: "Upload video") {
                UIApplication.shared.endBackgroundTask(id)
            }
            return id
        }
        defer {
            Task { @MainActor in UIApplication.shared.endBackgroundTask(backgroundTask) }
        }
        let (_, response) = try await URLSession.shared.upload(for: put, fromFile: videoURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BackendError.uploadFailed
        }
        return Post(id: upload.postId, authorID: post.authorID, placeID: post.placeID, climbID: post.climbID,
                    videoURL: videoURL, routeName: post.routeName, discipline: post.discipline,
                    grade: nil, proposedGrade: post.proposedGrade, sendStyle: post.sendStyle,
                    caption: post.caption, createdAt: post.createdAt)
    }

    func addPlace(_ place: Place) async throws -> Place {
        let row: PlaceRecord = try await client.from("places").insert(PlaceInsert(place, createdBy: userID))
            .select(PlaceRecord.columns).single().execute().value
        return row.place
    }

    func addClimb(_ climb: Climb) async throws -> Climb {
        let row: ClimbRecord = try await client.from("climbs").insert(ClimbInsert(climb, createdBy: userID))
            .select(ClimbRecord.columns).single().execute().value
        return row.climb
    }

    // MARK: - Climbs

    func climbs(at placeID: Place.ID) async throws -> [Climb]? {
        var all: [Climb] = []
        var from = 0
        while true {
            let page: [ClimbRecord] = try await client.from("climbs").select(ClimbRecord.columns)
                .eq("place_id", value: placeID).order("name").order("id")
                .range(from: from, to: from + pageSize - 1).execute().value
            all += page.map(\.climb)
            if page.count < pageSize { return all }
            from += pageSize
        }
    }

    func searchClimbs(_ query: String, limit: Int) async throws -> [Climb]? {
        let rows: [ClimbRecord] = try await client
            .rpc("search_climbs", params: SearchClimbsParams(q: query, max_results: min(limit, 100)))
            .select(ClimbRecord.columns).execute().value
        return rows.map(\.climb)
    }

    // MARK: - Profiles

    /// The username column is case-insensitive (citext), so this finds "Sam" for "sam".
    func isUsernameTaken(_ username: String, excluding userID: User.ID) async throws -> Bool {
        let matches: [IDRow] = try await client.from("profiles").select("id")
            .eq("username", value: username).limit(2).execute().value
        return matches.contains { $0.id.lowercased() != userID.lowercased() }
    }

    /// Creates or updates your profile, then its home places and projects. A new profile
    /// picture (a local file) is uploaded first. The database's unique username rule is the
    /// final check: losing a race for a name becomes `RepositoryError.usernameTaken`.
    func saveUser(_ user: User) async throws {
        do {
            try await saveUserRows(user)
        } catch let error as PostgrestError where error.code == "23505" {  // unique violation
            throw RepositoryError.usernameTaken(user.username)
        }
    }

    private func saveUserRows(_ user: User) async throws {
        var avatarPath: String?? = .none   // .none: leave as is; .some(nil): remove
        if let url = user.avatarURL {
            let local = AvatarStorage.resolve(url)
            let alreadyUploaded = lock.withLock { uploadedAvatars[local.path] }
            if let alreadyUploaded {
                avatarPath = .some(alreadyUploaded)
            } else if local.isFileURL, let data = try? Data(contentsOf: local) {
                let path = "\(userID)/\(UUID().uuidString.lowercased()).jpg"
                try await client.storage.from("avatars")
                    .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
                lock.withLock { uploadedAvatars[local.path] = path }
                avatarPath = .some(path)
            }
        } else {
            avatarPath = .some(nil)
        }

        // Update if the profile exists, otherwise create it (id can only be set on create).
        let updated: [IDRow] = try await client.from("profiles").update(ProfileFields(user, avatarPath: avatarPath))
            .eq("id", value: userID).select("id").execute().value
        if updated.isEmpty {
            try await client.from("profiles")
                .insert(ProfileFields(user, avatarPath: avatarPath, id: userID)).execute()
        }

        try await client.from("profile_home_places").delete().eq("user_id", value: userID).execute()
        let homes = user.homePlaceIDs.prefix(User.maxHomePlaces).enumerated().map { index, placeID in
            HomePlaceRow(user_id: userID, place_id: placeID, position: index)
        }
        if !homes.isEmpty {
            try await client.from("profile_home_places").insert(Array(homes)).execute()
        }

        // Projects keep their order (newest first) through their timestamps.
        try await client.from("projects").delete().eq("user_id", value: userID).execute()
        let now = Date.now
        let projects = user.projectClimbIDs.enumerated().map { index, climbID in
            ProjectRow(user_id: userID, climb_id: climbID, created_at: now.addingTimeInterval(-Double(index)))
        }
        if !projects.isEmpty {
            try await client.from("projects").insert(projects).execute()
        }
    }

    // MARK: - Community photos

    func addCommunityPhoto(_ photo: CommunityPhoto) async throws {
        let data = try Data(contentsOf: photo.imageURL)
        let path = "\(userID)/\(photo.id.lowercased()).jpg"
        try await client.storage.from("community-photos")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        let subject: (place: String?, climb: String?) = switch photo.subject {
        case .place(let id): (id, nil)
        case .climb(let id): (nil, id)
        }
        do {
            try await client.from("community_photos").insert(PhotoInsert(
                id: photo.id, place_id: subject.place, climb_id: subject.climb,
                author_id: userID, storage_path: path
            )).execute()
        } catch {
            // Don't leave the uploaded file behind if the photo couldn't be saved.
            _ = try? await client.storage.from("community-photos").remove(paths: [path])
            throw error
        }
    }

    func deleteCommunityPhoto(_ photoID: CommunityPhoto.ID, by userID: User.ID) async throws {
        // The server only deletes it if you added it; nothing comes back otherwise.
        let deleted: [PhotoPathRow] = try await client.from("community_photos").delete()
            .eq("id", value: photoID).select("storage_path").execute().value
        guard let path = deleted.first?.storage_path else { throw RepositoryError.notAllowed }
        _ = try? await client.storage.from("community-photos").remove(paths: [path])
    }

    // MARK: - Page comments

    func pageComments(on page: PhotoSubject) async throws -> PageComments? {
        let (column, id) = page.columnAndID
        let commentRows: [PageCommentRow] = try await client.from("page_comments").select(PageCommentRow.columns)
            .eq(column, value: id).order("created_at", ascending: false).limit(500).execute().value  // newest 500
        let authorIDs = Array(Set(commentRows.map(\.author_id)))
        let profiles: [ProfileRow] = try await rows(in: "profiles", columns: ProfileRow.columns,
                                                    key: "id", values: authorIDs)
        return PageComments(
            comments: commentRows.map(\.comment),
            authors: profiles.map { row in
                row.user(homePlaceIDs: [], projectClimbIDs: [],
                         avatarURL: row.avatar_path.flatMap { publicURL(bucket: "avatars", path: $0) })
            }
        )
    }

    func addPageComment(_ comment: Comment, on page: PhotoSubject) async throws {
        let (column, id) = page.columnAndID
        try await client.from("page_comments").insert([
            "id": comment.id, column: id, "author_id": comment.authorID, "body": comment.text,
        ]).execute()
    }

    func deletePageComment(_ commentID: Comment.ID) async throws {
        // The server only deletes your own; nothing comes back otherwise.
        let deleted: [IDRow] = try await client.from("page_comments").delete()
            .eq("id", value: commentID).select("id").execute().value
        if deleted.isEmpty { throw RepositoryError.notAllowed }
    }

    func setPhotoLike(photoID: CommunityPhoto.ID, liked: Bool, by userID: User.ID) async throws {
        if liked {
            try await client.from("photo_likes").insert(["photo_id": photoID, "user_id": userID]).execute()
        } else {
            try await client.from("photo_likes").delete()
                .eq("photo_id", value: photoID).eq("user_id", value: userID).execute()
        }
    }
}

enum BackendError: LocalizedError {
    case missingVideo
    case badResponse
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .missingVideo: "Pick a video first."
        case .badResponse: "The server sent something unexpected. Try again."
        case .uploadFailed: "The video didn't upload. Check your connection and try again."
        }
    }
}

// MARK: - Rows (column names match the database)

private struct IDRow: Decodable { let id: String }
private struct PhotoPathRow: Decodable { let storage_path: String }

private struct PlaceRecord: Decodable {
    static let columns = "id,external_id,name,kind,city,region,country,latitude,longitude,disciplines,about,source,is_verified,created_by"
    let id: String
    let external_id: String?
    let name: String
    let kind: PlaceKind
    let city: String
    let region: String
    let country: String
    let latitude: Double
    let longitude: Double
    let disciplines: [ClimbDiscipline]
    let about: String
    let source: String
    let is_verified: Bool
    let created_by: String?

    var place: Place {
        Place(id: id, name: name, kind: kind, city: city, region: region, country: country,
              latitude: latitude, longitude: longitude, disciplines: disciplines, about: about,
              source: PlaceSource(rawValue: source) ?? .curated, externalID: external_id,
              isVerified: is_verified, createdBy: created_by)
    }
}

private struct PlaceInsert: Encodable {
    let name: String, kind: String, city: String, region: String, country: String
    let latitude: Double, longitude: Double
    let disciplines: [String]
    let about: String
    let source = "userSubmitted"
    let is_verified = false
    let created_by: String

    init(_ place: Place, createdBy: String) {
        name = place.name; kind = place.kind.rawValue
        city = place.city; region = place.region; country = place.country
        latitude = place.latitude; longitude = place.longitude
        disciplines = place.disciplines.map(\.rawValue); about = place.about
        created_by = createdBy
    }
}

private struct ClimbRecord: Decodable {
    static let columns = "id,place_id,name,area,discipline,grade_system,grade_value,about,is_verified,created_by,latitude,longitude"
    let id: String
    let place_id: String
    let name: String
    let area: String
    let discipline: ClimbDiscipline
    let grade_system: GradeSystem?
    let grade_value: String?
    let about: String
    let is_verified: Bool
    let created_by: String?
    let latitude: Double?
    let longitude: Double?

    var climb: Climb {
        var grade: Grade?
        if let grade_system, let grade_value { grade = Grade(system: grade_system, value: grade_value) }
        return Climb(id: id, placeID: place_id, name: name, area: area, discipline: discipline, grade: grade,
                     about: about, source: .curated, isVerified: is_verified, createdBy: created_by,
                     latitude: latitude, longitude: longitude)
    }
}

private struct SearchClimbsParams: Encodable {
    let q: String
    let max_results: Int
}

private struct ClimbInsert: Encodable {
    let place_id: String, name: String, area: String, discipline: String
    let grade_system: String?, grade_value: String?
    let about: String
    let is_verified = false
    let created_by: String

    init(_ climb: Climb, createdBy: String) {
        place_id = climb.placeID; name = climb.name; area = climb.area
        discipline = climb.discipline.rawValue
        grade_system = climb.grade?.system.rawValue; grade_value = climb.grade?.value
        about = climb.about; created_by = createdBy
    }
}

private struct PostRow: Decodable {
    static let columns = "id,author_id,place_id,climb_id,route_name,discipline,send_style,proposed_grade_system,proposed_grade_value,caption,video_status,mux_playback_id,view_count,created_at"
    let id: String
    let author_id: String
    let place_id: String?
    let climb_id: String?
    let route_name: String
    let discipline: ClimbDiscipline
    let send_style: SendStyle
    let proposed_grade_system: GradeSystem?
    let proposed_grade_value: String?
    let caption: String
    let video_status: String
    let mux_playback_id: String?
    let view_count: Int
    let created_at: Date

    func post(likedBy: Set<String>, comments: [Comment]) -> Post {
        var proposed: Grade?
        if let proposed_grade_system, let proposed_grade_value {
            proposed = Grade(system: proposed_grade_system, value: proposed_grade_value)
        }
        // Mux: adaptive stream + poster image, only once processing is done.
        let playback = video_status == "ready" ? mux_playback_id : nil
        var post = Post(id: id, authorID: author_id, placeID: place_id, climbID: climb_id,
                        videoURL: playback.flatMap { URL(string: "https://stream.mux.com/\($0).m3u8") },
                        thumbnailURL: playback.flatMap { URL(string: "https://image.mux.com/\($0)/thumbnail.jpg?width=600") },
                        routeName: route_name, discipline: discipline, grade: nil, proposedGrade: proposed,
                        sendStyle: send_style, caption: caption, createdAt: created_at)
        post.likedBy = likedBy
        post.comments = comments
        post.viewCount = view_count
        return post
    }
}

private struct CreateVideoUploadRequest: Encodable {
    let placeId: String?, climbId: String?, routeName: String
    let discipline: String, sendStyle: String
    let proposedGradeSystem: String?, proposedGradeValue: String?
    let caption: String
}

private struct CreateVideoUploadResponse: Decodable {
    let postId: String
    let uploadUrl: String
}

private struct ProfileRow: Decodable {
    static let columns = "id,username,display_name,bio,avatar_path,boulder_system,boulder_low,boulder_high,rope_system,rope_low,rope_high,shows_grade_range,shows_hardest_send,shows_projects"
    let id: String
    let username: String
    let display_name: String
    let bio: String
    let avatar_path: String?
    let boulder_system: GradeSystem?
    let boulder_low: String?
    let boulder_high: String?
    let rope_system: GradeSystem?
    let rope_low: String?
    let rope_high: String?
    let shows_grade_range: Bool
    let shows_hardest_send: Bool
    let shows_projects: Bool

    func user(homePlaceIDs: [String], projectClimbIDs: [String], avatarURL: URL?) -> User {
        var user = User(id: id, username: username, displayName: display_name, bio: bio)
        user.homePlaceIDs = homePlaceIDs
        user.avatarURL = avatarURL
        if let boulder_system, let boulder_low {
            user.boulderRange = GradeRange(system: boulder_system, low: boulder_low, high: boulder_high)
        }
        if let rope_system, let rope_low {
            user.ropeRange = GradeRange(system: rope_system, low: rope_low, high: rope_high)
        }
        user.showsGradeRange = shows_grade_range
        user.showsHardestSend = shows_hardest_send
        user.projectClimbIDs = projectClimbIDs
        user.showsProjects = shows_projects
        return user
    }
}

/// The profile columns you can write (the server ignores / refuses anything else).
private struct ProfileFields: Encodable {
    let username: String
    let display_name: String
    let bio: String
    let boulder_system: String?, boulder_low: String?, boulder_high: String?
    let rope_system: String?, rope_low: String?, rope_high: String?
    let shows_grade_range: Bool, shows_hardest_send: Bool, shows_projects: Bool
    /// .none: don't touch; .some(nil): clear; .some(path): set.
    let avatarPath: String??
    /// Only when creating the profile.
    let id: String?

    init(_ user: User, avatarPath: String??, id: String? = nil) {
        self.id = id
        username = user.username; display_name = user.displayName; bio = user.bio
        boulder_system = user.boulderRange?.system.rawValue
        boulder_low = user.boulderRange?.low; boulder_high = user.boulderRange?.high
        rope_system = user.ropeRange?.system.rawValue
        rope_low = user.ropeRange?.low; rope_high = user.ropeRange?.high
        shows_grade_range = user.showsGradeRange
        shows_hardest_send = user.showsHardestSend
        shows_projects = user.showsProjects
        self.avatarPath = avatarPath
    }

    enum CodingKeys: String, CodingKey {
        case username, display_name, bio, boulder_system, boulder_low, boulder_high
        case rope_system, rope_low, rope_high, shows_grade_range, shows_hardest_send, shows_projects
        case avatar_path, id
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(username, forKey: .username)
        try c.encode(display_name, forKey: .display_name)
        try c.encode(bio, forKey: .bio)
        // Explicit nulls, so clearing a grade range clears it on the server too.
        try c.encode(boulder_system, forKey: .boulder_system)
        try c.encode(boulder_low, forKey: .boulder_low)
        try c.encode(boulder_high, forKey: .boulder_high)
        try c.encode(rope_system, forKey: .rope_system)
        try c.encode(rope_low, forKey: .rope_low)
        try c.encode(rope_high, forKey: .rope_high)
        try c.encode(shows_grade_range, forKey: .shows_grade_range)
        try c.encode(shows_hardest_send, forKey: .shows_hardest_send)
        try c.encode(shows_projects, forKey: .shows_projects)
        if case .some(let path) = avatarPath { try c.encode(path, forKey: .avatar_path) }
        if let id { try c.encode(id, forKey: .id) }
    }
}

private struct HomePlaceRow: Codable {
    let user_id: String
    let place_id: String
    let position: Int
}

private struct ProjectRow: Codable {
    let user_id: String
    let climb_id: String
    let created_at: Date
}

private struct UserFollowRow: Decodable { let follower_id: String; let followee_id: String }
private struct PlaceFollowRow: Decodable { let user_id: String; let place_id: String }
private struct PostLikeRow: Decodable { let post_id: String; let user_id: String }
private struct PhotoLikeRow: Decodable { let photo_id: String; let user_id: String }

private struct RepostRow: Decodable {
    let user_id: String
    let post_id: String
    let created_at: Date

    var repost: Repost { Repost(id: "\(user_id)-\(post_id)", userID: user_id, postID: post_id, createdAt: created_at) }
}

private struct CommentRow: Decodable {
    static let columns = "id,post_id,author_id,body,created_at"
    let id: String
    let post_id: String
    let author_id: String
    let body: String
    let created_at: Date

    var comment: Comment { Comment(id: id, authorID: author_id, text: body, createdAt: created_at) }
}

private struct PageCommentRow: Decodable {
    static let columns = "id,author_id,body,created_at"
    let id: String
    let author_id: String
    let body: String
    let created_at: Date

    var comment: Comment { Comment(id: id, authorID: author_id, text: body, createdAt: created_at) }
}

private extension PhotoSubject {
    /// The page_comments column for this page, and its id.
    var columnAndID: (String, String) {
        switch self {
        case .place(let id): ("place_id", id)
        case .climb(let id): ("climb_id", id)
        }
    }
}

private struct PhotoRow: Decodable {
    static let columns = "id,place_id,climb_id,author_id,storage_path,created_at"
    let id: String
    let place_id: String?
    let climb_id: String?
    let author_id: String
    let storage_path: String
    let created_at: Date

    func photo(imageURL: URL, likedBy: Set<String>) -> CommunityPhoto? {
        let subject: PhotoSubject
        if let place_id { subject = .place(place_id) } else if let climb_id { subject = .climb(climb_id) } else { return nil }
        return CommunityPhoto(id: id, subject: subject, authorID: author_id, imageURL: imageURL,
                              likedBy: likedBy, createdAt: created_at)
    }
}

private struct PhotoInsert: Encodable {
    let id: String
    let place_id: String?
    let climb_id: String?
    let author_id: String
    let storage_path: String
}
#endif
