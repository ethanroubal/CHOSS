import Foundation

/// Everything the app needs to render for a signed-in user.
struct AppSnapshot {
    var users: [User]
    var places: [Place]
    var posts: [Post]
    /// userID → places that user follows.
    var followedPlaces: [User.ID: Set<Place.ID>]
    /// userID → users that user follows.
    var followedUsers: [User.ID: Set<User.ID>]
}

/// The backend boundary. `MockClimbingRepository` backs the app today; a real
/// implementation (Supabase / Firebase / custom API) can be dropped in without touching views.
protocol ClimbingRepository: Sendable {
    func loadSnapshot() async throws -> AppSnapshot
    func setFollow(placeID: Place.ID, following: Bool, by userID: User.ID) async throws
    func setFollow(userID: User.ID, following: Bool, by followerID: User.ID) async throws
    func setLike(postID: Post.ID, liked: Bool, by userID: User.ID) async throws
    func addComment(_ comment: Comment, to postID: Post.ID) async throws
    /// Uploads the video (in a real backend) and persists the post, returning the stored version.
    func createPost(_ post: Post) async throws -> Post
    func addPlace(_ place: Place) async throws -> Place
}
