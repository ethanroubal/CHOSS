import Foundation

/// The US climbing gym list shipped with the app (CHOSS/Resources/us_climbing_gyms.json),
/// generated from data/US_Climbing_Gyms_Simple.xlsx by scripts/import_gyms_xlsx.py.
/// With a real backend this becomes a one-time database import instead.
enum BundledGyms {
    static let places: [Place] = load()

    private static func load() -> [Place] {
        guard let url = Bundle.main.url(forResource: "us_climbing_gyms", withExtension: "json") else {
            assertionFailure("us_climbing_gyms.json is missing from the app bundle")
            return []
        }
        do {
            return try JSONDecoder().decode([Place].self, from: Data(contentsOf: url))
        } catch {
            assertionFailure("Couldn't decode us_climbing_gyms.json: \(error)")
            return []
        }
    }
}
