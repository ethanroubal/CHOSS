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
        let system = discipline.defaultGradeSystem
        let value = system == .vScale ? "V3" : "5.10a"
        return Grade(system: system, value: value)
    }
}

/// How the climb was sent.
enum SendStyle: String, Codable, CaseIterable, Identifiable, Hashable {
    case onsight
    case flash
    case redpoint
    case repeatSend

    var id: Self { self }

    var displayName: String {
        switch self {
        case .onsight: "Onsight"
        case .flash: "Flash"
        case .redpoint: "Send"
        case .repeatSend: "Repeat"
        }
    }

    var symbolName: String {
        switch self {
        case .onsight: "eye.fill"
        case .flash: "bolt.fill"
        case .redpoint: "checkmark.seal.fill"
        case .repeatSend: "arrow.clockwise"
        }
    }
}
