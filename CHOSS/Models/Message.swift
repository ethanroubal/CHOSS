import Foundation

/// A direct-message thread between two or more climbers.
struct Conversation: Identifiable, Codable, Hashable {
    typealias ID = String

    let id: ID
    var participantIDs: Set<User.ID>
}

struct Message: Identifiable, Codable, Hashable {
    typealias ID = String

    let id: ID
    let conversationID: Conversation.ID
    let senderID: User.ID
    var text: String
    /// Set when the message shares a send video.
    var sharedPostID: Post.ID?
    var createdAt: Date
}
