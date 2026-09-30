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

    func recordView(postID: Post.ID, by userID: User.ID) async throws {
        guard let index = snapshot.posts.firstIndex(where: { $0.id == postID }) else { return }
        snapshot.posts[index].viewCount += 1
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

    func deleteComment(_ commentID: Comment.ID, from postID: Post.ID) async throws {
        guard let index = snapshot.posts.firstIndex(where: { $0.id == postID }) else { return }
        snapshot.posts[index].comments.removeAll { $0.id == commentID }
    }

    func createPost(_ post: Post) async throws -> Post {
        snapshot.posts.insert(post, at: 0)
        return post
    }

    func addPlace(_ place: Place) async throws -> Place {
        snapshot.places.append(place)
        return place
    }

    func addClimb(_ climb: Climb) async throws -> Climb {
        snapshot.climbs.append(climb)
        return climb
    }

    func saveUser(_ user: User) async throws {
        if let index = snapshot.users.firstIndex(where: { $0.id == user.id }) {
            snapshot.users[index] = user
        } else {
            snapshot.users.append(user)
        }
    }

    func addRepost(_ repost: Repost) async throws {
        snapshot.reposts.append(repost)
    }

    func removeRepost(postID: Post.ID, by userID: User.ID) async throws {
        snapshot.reposts.removeAll { $0.postID == postID && $0.userID == userID }
    }

    func addCommunityPhoto(_ photo: CommunityPhoto) async throws {
        snapshot.communityPhotos.append(photo)
    }

    func deleteCommunityPhoto(_ photoID: CommunityPhoto.ID, by userID: User.ID) async throws {
        guard let photo = snapshot.communityPhotos.first(where: { $0.id == photoID }) else { return }
        guard photo.authorID == userID else { throw RepositoryError.notAllowed }
        snapshot.communityPhotos.removeAll { $0.id == photoID }
    }

    func setPhotoLike(photoID: CommunityPhoto.ID, liked: Bool, by userID: User.ID) async throws {
        guard let index = snapshot.communityPhotos.firstIndex(where: { $0.id == photoID }) else { return }
        if liked {
            snapshot.communityPhotos[index].likedBy.insert(userID)
        } else {
            snapshot.communityPhotos[index].likedBy.remove(userID)
        }
    }
}
