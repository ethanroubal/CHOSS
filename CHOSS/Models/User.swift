import Foundation

struct User: Identifiable, Codable, Hashable {
    typealias ID = String

    let id: ID
    var username: String
    var displayName: String
    var bio: String
    var homePlaceID: Place.ID?
    var avatarURL: URL? = nil

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? String(username.prefix(1)).uppercased() : letters.uppercased()
    }
}
