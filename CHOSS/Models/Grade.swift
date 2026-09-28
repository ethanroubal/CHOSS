import Foundation

/// The style of climbing a send was done in.
enum ClimbDiscipline: String, Codable, CaseIterable, Identifiable, Hashable {
    case boulder
    case sport
    case trad
    case topRope

    var id: Self { self }

    var displayName: String {
        switch self {
        case .boulder: "Boulder"
        case .sport: "Sport"
        case .trad: "Trad"
        case .topRope: "Top Rope"
        }
    }

    var symbolName: String {
        switch self {
        case .boulder: "square.stack.3d.up.fill"
        case .sport: "link"
        case .trad: "gearshape.2.fill"
        case .topRope: "arrow.up.and.down"
        }
    }

    var isRoped: Bool { self != .boulder }

    /// Sensible default grading system; users can switch (e.g. Font in Europe).
    var defaultGradeSystem: GradeSystem { isRoped ? .yds : .vScale }

    var gradeSystems: [GradeSystem] { isRoped ? [.yds, .french] : [.vScale, .font] }
}

enum GradeSystem: String, Codable, CaseIterable, Identifiable, Hashable {
    case vScale
    case font
    case yds
    case french

    var id: Self { self }

    var displayName: String {
        switch self {
        case .vScale: "V-Scale"
        case .font: "Font"
        case .yds: "YDS"
        case .french: "French"
        }
    }

    /// Grades ordered easiest → hardest.
    var grades: [String] {
        switch self {
        case .vScale:
            return ["VB"] + (0...17).map { "V\($0)" }
        case .font:
            return ["3", "4", "4+", "5", "5+"]
                + ["6", "7", "8"].flatMap { n in ["A", "A+", "B", "B+", "C", "C+"].map { "\(n)\($0)" } }
                + ["9A"]
        case .yds:
            return (5...9).map { "5.\($0)" }
                + (10...15).flatMap { n in ["a", "b", "c", "d"].map { "5.\(n)\($0)" } }
        case .french:
            return ["4a", "4b", "4c", "5a", "5b", "5c"]
                + (6...9).flatMap { n in ["a", "a+", "b", "b+", "c", "c+"].map { "\(n)\($0)" } }
        }
    }
}

struct Grade: Codable, Hashable {
    var system: GradeSystem
    var value: String

    /// Position within its system; only comparable between grades of the same system.
    var rank: Int { system.grades.firstIndex(of: value) ?? -1 }

    static func defaultGrade(for discipline: ClimbDiscipline) -> Grade {
        defaultGrade(in: discipline.defaultGradeSystem)
    }

    /// A reasonable starting point for pickers (roughly a third of the way up the scale).
    static func defaultGrade(in system: GradeSystem) -> Grade {
        let grades = system.grades
        return Grade(system: system, value: grades[grades.count / 3])
    }
}

/// Boulders and routes are graded differently and can't be compared with each other.
enum GradeCategory: String, CaseIterable, Identifiable, Hashable {
    case boulder
    case route

    var id: Self { self }

    var displayName: String {
        switch self {
        case .boulder: "Boulders"
        case .route: "Routes"
        }
    }

    /// Every grade in the category is converted to this scale for comparison.
    var canonicalSystem: GradeSystem { self == .boulder ? .vScale : .yds }
}

extension GradeSystem {
    var category: GradeCategory { self == .vScale || self == .font ? .boulder : .route }
}

extension Grade {
    /// Approximate Font → V-scale conversion.
    private static let fontToV: [String: String] = [
        "3": "VB", "4": "V0", "4+": "V0", "5": "V1", "5+": "V2",
        "6A": "V3", "6A+": "V3", "6B": "V4", "6B+": "V4", "6C": "V5", "6C+": "V5",
        "7A": "V6", "7A+": "V7", "7B": "V8", "7B+": "V8", "7C": "V9", "7C+": "V10",
        "8A": "V11", "8A+": "V12", "8B": "V13", "8B+": "V14", "8C": "V15", "8C+": "V16", "9A": "V17",
    ]

    /// Approximate French sport → YDS conversion.
    private static let frenchToYDS: [String: String] = [
        "4a": "5.5", "4b": "5.6", "4c": "5.7", "5a": "5.8", "5b": "5.9", "5c": "5.10a",
        "6a": "5.10b", "6a+": "5.10d", "6b": "5.11a", "6b+": "5.11b", "6c": "5.11c", "6c+": "5.11d",
        "7a": "5.12a", "7a+": "5.12b", "7b": "5.12c", "7b+": "5.12d", "7c": "5.13a", "7c+": "5.13b",
        "8a": "5.13c", "8a+": "5.13d", "8b": "5.14a", "8b+": "5.14b", "8c": "5.14c", "8c+": "5.14d",
        "9a": "5.15a", "9a+": "5.15b", "9b": "5.15c", "9b+": "5.15d", "9c": "5.15d", "9c+": "5.15d",
    ]

    /// The same grade on its category's common scale (V-scale for boulders, YDS for routes),
    /// so grades from different systems can be compared. nil if it can't be converted.
    var canonical: Grade? {
        let converted: String?
        switch system {
        case .vScale, .yds: converted = value
        case .font: converted = Self.fontToV[value]
        case .french: converted = Self.frenchToYDS[value]
        }
        guard let converted else { return nil }
        let grade = Grade(system: system.category.canonicalSystem, value: converted)
        return grade.rank >= 0 ? grade : nil
    }
}

/// A climber's self-reported ability, e.g. "V4–V6" or just "5.11a".
struct GradeRange: Codable, Hashable {
    var system: GradeSystem
    var low: String
    /// nil (or equal to `low`) means a single grade rather than a range.
    var high: String?

    var display: String {
        guard let high, high != low else { return low }
        return "\(low)–\(high)"
    }
}

/// How the climb was sent.
enum SendStyle: String, Codable, CaseIterable, Identifiable, Hashable {
    case onsight
    case flash
    case redpoint
    case repeatSend
    /// Linked a section / moves of the climb, not a full send.
    case link

    var id: Self { self }

    var displayName: String {
        switch self {
        case .onsight: "Onsight"
        case .flash: "Flash"
        case .redpoint: "Send"
        case .repeatSend: "Repeat"
        case .link: "Link"
        }
    }

    var symbolName: String {
        switch self {
        case .onsight: "eye.fill"
        case .flash: "bolt.fill"
        case .redpoint: "checkmark.seal.fill"
        case .repeatSend: "arrow.clockwise"
        case .link: "point.3.connected.trianglepath.dotted"
        }
    }

    /// A link is a section of the climb, so it doesn't count as having sent it
    /// (leaderboards, hardest send).
    var countsAsSend: Bool { self != .link }
}
