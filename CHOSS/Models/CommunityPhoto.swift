import Foundation

/// What a community photo is of: a gym / crag, or an outdoor climb.
enum PhotoSubject: Codable, Hashable {
    case place(Place.ID)
    case climb(Climb.ID)
}

/// A picture anyone can add to a place's or climb's page. The most-liked one becomes the page's
/// profile picture (see `AppStore.coverPhoto(of:)`).
struct CommunityPhoto: Identifiable, Codable, Hashable {
    typealias ID = String

    let id: ID
    let subject: PhotoSubject
    let authorID: User.ID
    /// Where the image is stored (a local file today; a CDN URL with a real backend).
    let imageURL: URL
    var likedBy: Set<User.ID> = []
    var createdAt: Date
}
