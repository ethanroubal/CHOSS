import Foundation

struct Comment: Identifiable, Codable, Hashable {
    typealias ID = String

    let id: ID
    let authorID: User.ID
    var text: String
    var createdAt: Date
}

/// A send: a video of a climb, tagged with its grade and (optionally) the gym/crag it was sent at.
/// Posts tagged with a place show up in the feed of everyone who follows that place.
struct Post: Identifiable, Codable, Hashable {
    typealias ID = String

    let id: ID
    let authorID: User.ID
    var placeID: Place.ID?
    /// The outdoor climb this is a send of (crags only), so it shows up as beta on that climb.
    var climbID: Climb.ID? = nil
    var videoURL: URL?
    var thumbnailURL: URL? = nil
    var routeName: String
    var discipline: ClimbDiscipline
    /// Legacy per-post official grade. No longer set when posting: a climb's grade is now the
    /// average of everyone's proposed grades (see `AppStore.displayGrade(for:)`).
    var grade: Grade?
    /// What the poster thinks the climb actually is ("soft for V5, feels V4").
    var proposedGrade: Grade? = nil
    var sendStyle: SendStyle
    var caption: String
    var createdAt: Date
    var likedBy: Set<User.ID> = []
    var comments: [Comment] = []
}

/// Someone re-sharing a post to their own followers.
struct Repost: Identifiable, Codable, Hashable {
    typealias ID = String

    let id: ID
    let userID: User.ID
    let postID: Post.ID
    var createdAt: Date
}

/// Everything the user fills in on the composer before a `Post` is created.
struct PostDraft {
    var videoURL: URL?
    var placeID: Place.ID?
    var climbID: Climb.ID?
    var routeName = ""
    var discipline: ClimbDiscipline = .boulder
    var gradeSystem: GradeSystem = .vScale
    var proposedGrade: Grade?
    var sendStyle: SendStyle = .redpoint
    var caption = ""

    var isReady: Bool { videoURL != nil }
}
