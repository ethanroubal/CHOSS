import Foundation

struct User: Identifiable, Codable, Hashable {
    typealias ID = String

    let id: ID
    var username: String
    var displayName: String
    var bio: String
    /// Up to `maxHomePlaces` home gyms / crags, in the order the climber picked them.
    var homePlaceIDs: [Place.ID] = []
    var avatarURL: URL? = nil
    /// Self-reported bouldering level, e.g. V4–V6.
    var boulderRange: GradeRange? = nil
    /// Self-reported rope level (sport/trad/top rope), e.g. 5.11a–5.11c.
    var ropeRange: GradeRange? = nil
    /// Whether the grade ranges appear on the public profile.
    var showsGradeRange: Bool = true
    /// Whether "Hardest send" (worked out from your posts) appears on your profile.
    var showsHardestSend: Bool = true
    /// Climbs you're working on ("projects"), most recently added first.
    var projectClimbIDs: [Climb.ID] = []
    /// Whether other people can see your projects (you always can, on your own profile).
    var showsProjects: Bool = true

    /// Ranges that should be shown to other people.
    var visibleGradeRanges: [GradeRange] {
        showsGradeRange ? [boulderRange, ropeRange].compactMap { $0 } : []
    }

    static let maxHomePlaces = 3

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? String(username.prefix(1)).uppercased() : letters.uppercased()
    }
}
