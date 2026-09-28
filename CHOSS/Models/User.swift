import Foundation

struct User: Identifiable, Codable, Hashable {
    typealias ID = String

    let id: ID
    var username: String
    var displayName: String
    var bio: String
    var homePlaceID: Place.ID?
    var avatarURL: URL? = nil
    /// Self-reported bouldering level, e.g. V4–V6.
    var boulderRange: GradeRange? = nil
    /// Self-reported rope level (sport/trad/top rope), e.g. 5.11a–5.11c.
    var ropeRange: GradeRange? = nil
    /// Whether the grade ranges appear on the public profile.
    var showsGradeRange: Bool = true

    /// Ranges that should be shown to other people.
    var visibleGradeRanges: [GradeRange] {
        showsGradeRange ? [boulderRange, ropeRange].compactMap { $0 } : []
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? String(username.prefix(1)).uppercased() : letters.uppercased()
    }
}
