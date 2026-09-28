import Foundation

/// A climb's grade as decided by the community: the average of everyone's proposed grades.
struct AverageGrade: Hashable {
    let grade: Grade
    /// How many proposals it's based on.
    let count: Int
}

extension AppStore {
    /// Identifies "the same climb" across posts: the linked outdoor climb, or (for gym climbs and
    /// unlinked sends) the same route name at the same place. nil if the post can't be grouped.
    func climbKey(for post: Post) -> String? {
        if let climbID = post.climbID { return "climb:\(climbID)" }
        let name = NameMatcher.normalize(post.routeName)
        guard !name.isEmpty else { return nil }
        // Without a place, only the poster's own posts of that name can be the same climb.
        let scope = post.placeID ?? "user:\(post.authorID)"
        return "route:\(scope):\(name)"
    }

    /// Every post of the same climb as `post` (including itself).
    func postsOfSameClimb(as post: Post) -> [Post] {
        guard let key = climbKey(for: post) else { return [post] }
        return posts.filter { climbKey(for: $0) == key }
    }

    /// Average of a set of proposed grades: the mean position on the scale, rounded to the nearest
    /// grade. Uses the scale most proposals were made in (so a Font crag stays in Font).
    static func average(of proposals: [Grade]) -> AverageGrade? {
        let valid = proposals.filter { $0.rank >= 0 }
        let bySystem = Dictionary(grouping: valid, by: \.system)
        guard let mostUsed = bySystem.max(by: { lhs, rhs in
            lhs.value.count != rhs.value.count
                ? lhs.value.count < rhs.value.count
                : lhs.key.rawValue > rhs.key.rawValue  // deterministic tie-break
        }) else { return nil }
        let system = mostUsed.key
        let grades = mostUsed.value
        let mean = Double(grades.map(\.rank).reduce(0, +)) / Double(grades.count)
        let index = min(max(Int(mean.rounded()), 0), system.grades.count - 1)
        return AverageGrade(grade: Grade(system: system, value: system.grades[index]), count: grades.count)
    }

    /// The climb's grade for a post: the average of all proposed grades for that climb.
    func averageGrade(for post: Post) -> AverageGrade? {
        Self.average(of: postsOfSameClimb(as: post).compactMap(\.proposedGrade))
    }

    /// Average proposed grade for an outdoor climb.
    func averageGrade(forClimb climbID: Climb.ID) -> AverageGrade? {
        Self.average(of: posts(ofClimb: climbID).compactMap(\.proposedGrade))
    }

    /// The grade to show and rank a post by: the climb's average proposed grade, falling back to
    /// the outdoor climb's guidebook grade when nobody has proposed one yet.
    func displayGrade(for post: Post) -> Grade? {
        averageGrade(for: post)?.grade ?? climb(post.climbID)?.grade
    }
}
