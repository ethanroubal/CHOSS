import Foundation

/// A permanent outdoor route or boulder problem at a crag. Unlike gym climbs (reset every few
/// weeks), these don't change, so every send video of one is linked to it and becomes beta.
struct Climb: Identifiable, Codable, Hashable {
    typealias ID = String

    let id: ID
    /// The crag it belongs to.
    let placeID: Place.ID
    var name: String
    /// Sub-area or wall within the crag, e.g. "Camp 4" or "Motherlode".
    var area: String
    var discipline: ClimbDiscipline
    /// Guidebook grade, if known.
    var grade: Grade?
    var about: String = ""
    var source: PlaceSource = .curated
    /// ID in the source dataset (OpenBeta climb UUID) for de-duplication on re-import.
    var externalID: String? = nil
    var isVerified: Bool = true
    var createdBy: User.ID? = nil
    /// The climb's own location. nil when unknown (the source only had the crag's point).
    var latitude: Double? = nil
    var longitude: Double? = nil
}
