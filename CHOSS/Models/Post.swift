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
    var videoURL: URL?
    var thumbnailURL: URL? = nil
    var routeName: String
    var discipline: ClimbDiscipline
    var grade: Grade
    var sendStyle: SendStyle
    var caption: String
    var createdAt: Date
    var likedBy: Set<User.ID> = []
    var comments: [Comment] = []
}

/// Everything the user fills in on the composer before a `Post` is created.
struct PostDraft {
    var videoURL: URL?
    var placeID: Place.ID?
    var routeName = ""
    var discipline: ClimbDiscipline = .boulder
    var grade = Grade.defaultGrade(for: .boulder)
    var sendStyle: SendStyle = .redpoint
    var caption = ""

    var isReady: Bool { videoURL != nil }
}
