import Foundation
import CoreLocation

enum PlaceKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case gym
    case crag

    var id: Self { self }

    var displayName: String {
        switch self {
        case .gym: "Gym"
        case .crag: "Crag"
        }
    }

    var symbolName: String {
        switch self {
        case .gym: "building.2.fill"
        case .crag: "mountain.2.fill"
        }
    }
}

/// Where a place record came from. Lets us mix imported and community data
/// (see docs/PLACES_DATA_STRATEGY.md).
enum PlaceSource: String, Codable, Hashable {
    case curated
    case openStreetMap
    case openBeta
    case userSubmitted
}

/// A climbing gym or outdoor crag that users can follow and post sends to.
struct Place: Identifiable, Codable, Hashable {
    typealias ID = String

    let id: ID
    var name: String
    var kind: PlaceKind
    var city: String
    var region: String
    var country: String
    var latitude: Double
    var longitude: Double
    var disciplines: [ClimbDiscipline]
    var about: String
    var source: PlaceSource = .curated
    /// ID in the source dataset (OSM element, OpenBeta area UUID) for de-duplication on re-import.
    var externalID: String? = nil
    var isVerified: Bool = true
    var createdBy: User.ID? = nil

    var locationLine: String {
        [city, region, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
