import Foundation

/// In-memory backend seeded with sample data. State lives for the lifetime of the app process.
actor MockClimbingRepository: ClimbingRepository {
    private var snapshot: AppSnapshot

    init(snapshot: AppSnapshot = SampleData.snapshot) {
        self.snapshot = snapshot
    }

    func loadSnapshot() async throws -> AppSnapshot {
        snapshot
    }

    func setFollow(placeID: Place.ID, following: Bool, by userID: User.ID) async throws {
        if following {
            snapshot.followedPlaces[userID, default: []].insert(placeID)
        } else {
            snapshot.followedPlaces[userID, default: []].remove(placeID)
        }
    }

    func setFollow(userID: User.ID, following: Bool, by followerID: User.ID) async throws {
        if following {
            snapshot.followedUsers[followerID, default: []].insert(userID)
        } else {
            snapshot.followedUsers[followerID, default: []].remove(userID)
        }
    }

    func setLike(postID: Post.ID, liked: Bool, by userID: User.ID) async throws {
        guard let index = snapshot.posts.firstIndex(where: { $0.id == postID }) else { return }
        if liked {
            snapshot.posts[index].likedBy.insert(userID)
        } else {
            snapshot.posts[index].likedBy.remove(userID)
        }
    }

    func addComment(_ comment: Comment, to postID: Post.ID) async throws {
        guard let index = snapshot.posts.firstIndex(where: { $0.id == postID }) else { return }
        snapshot.posts[index].comments.append(comment)
    }

    func createPost(_ post: Post) async throws -> Post {
        snapshot.posts.insert(post, at: 0)
        return post
    }

    func addPlace(_ place: Place) async throws -> Place {
        snapshot.places.append(place)
        return place
    }
}
