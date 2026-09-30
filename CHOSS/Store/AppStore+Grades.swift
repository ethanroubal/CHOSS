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
        climbKeyByPost[post.id] ?? computeClimbKey(for: post)
    }

    /// Uncached `climbKey(for:)`, used when building the lookups.
    func computeClimbKey(for post: Post) -> String? {
        if let climbID = post.climbID { return "climb:\(climbID)" }
        let name = NameMatcher.normalize(post.routeName)
        guard !name.isEmpty else { return nil }
        // Without a place, only the poster's own posts of that name can be the same climb.
        let scope = post.placeID ?? "user:\(post.authorID)"
        return "route:\(scope):\(name)"
    }

    /// Every post of the same climb as `post` (including itself).
    func postsOfSameClimb(as post: Post) -> [Post] {
        guard let key = climbKey(for: post), let ids = postIDsByClimbKey[key] else { return [post] }
        return ids.compactMap { self.post($0) }
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

/// A route people have posted at a gym (or you've posted without a place). Gym climbs aren't a
/// fixed list like outdoor climbs, so "the same climb" is the same route name at the same place.
struct KnownRoute: Identifiable, Hashable {
    let name: String
    let discipline: ClimbDiscipline
    let postCount: Int
    let grade: Grade?
    /// The gym it's at (nil for your own untagged routes).
    var placeID: Place.ID? = nil
    /// Identifies it everywhere (see `AppStore.climbKey(for:)`).
    var climbKey: String = ""
    /// Unique within one place's list.
    var id: String { NameMatcher.normalize(name) }
}

extension AppStore {
    /// Routes already posted at a place (not linked to an outdoor climb), most-posted first.
    /// With no place, it's the current user's own untagged routes.
    func knownRoutes(at placeID: Place.ID?) -> [KnownRoute] {
        // Only this place's posts (or your own), not every post.
        let pool = placeID.map { posts(at: $0) } ?? posts(by: currentUserID)
        let candidates = pool.filter { post in
            post.climbID == nil && !post.routeName.trimmingCharacters(in: .whitespaces).isEmpty
                && post.placeID == placeID
        }
        let groups = Dictionary(grouping: candidates) { NameMatcher.normalize($0.routeName) }
        return groups.values.compactMap { knownRoute(from: $0) }
        .sorted { lhs, rhs in
            lhs.postCount != rhs.postCount ? lhs.postCount > rhs.postCount : lhs.name < rhs.name
        }
    }

    /// A gym route (or untagged route) by its climb key, e.g. from `searchRouteKeys(_:)`.
    func knownRoute(forKey key: String) -> KnownRoute? {
        knownRoute(from: (postIDsByClimbKey[key] ?? []).compactMap { post($0) })
    }

    /// Summarizes the posts of one route (newest first).
    private func knownRoute(from group: [Post]) -> KnownRoute? {
        guard let latest = group.first, latest.climbID == nil else { return nil }
        let disciplines = Dictionary(grouping: group, by: \.discipline)
        let discipline = disciplines.max { $0.value.count < $1.value.count }?.key ?? latest.discipline
        return KnownRoute(name: latest.routeName, discipline: discipline,
                          postCount: group.count, grade: displayGrade(for: latest),
                          placeID: latest.placeID, climbKey: climbKey(for: latest) ?? "")
    }

    /// Whether the current user has already posted a full send of the same climb as `post`.
    func hasSent(sameClimbAs post: Post) -> Bool {
        postsOfSameClimb(as: post).contains {
            $0.id != post.id && $0.authorID == currentUserID && $0.sendStyle.countsAsSend
        }
    }
}
