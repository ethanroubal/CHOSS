import Foundation

/// The gym and crag directories shipped with the app, generated from the spreadsheets in data/:
/// - CHOSS/Resources/us_climbing_gyms.json  ← scripts/import_gyms_xlsx.py
/// - CHOSS/Resources/us_climbing_areas.json ← scripts/import_crags_xlsx.py
/// With a real backend these become a one-time database import instead.
enum BundledPlaces {
    static let gyms: [Place] = load("us_climbing_gyms")
    static let crags: [Place] = load("us_climbing_areas")
    static var all: [Place] { gyms + crags }

    private static func load(_ resource: String) -> [Place] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            assertionFailure("\(resource).json is missing from the app bundle")
            return []
        }
        do {
            return try JSONDecoder().decode([Place].self, from: Data(contentsOf: url))
        } catch {
            assertionFailure("Couldn't decode \(resource).json: \(error)")
            return []
        }
    }
}
