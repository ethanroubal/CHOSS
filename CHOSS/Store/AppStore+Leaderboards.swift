import Foundation

/// One climber on a leaderboard.
struct LeaderboardEntry: Identifiable, Hashable {
    let userID: User.ID
    /// Supporting detail, e.g. the climb that earned the spot.
    let detail: String
    var id: User.ID { userID }
}

/// A podium place (1st, 2nd, 3rd). Everyone with the same score shares the place.
struct LeaderboardTier: Identifiable, Hashable {
    let place: Int
    /// The shared score, e.g. "12 climbs" or "V8".
    let scoreLabel: String
    let entries: [LeaderboardEntry]
    var id: Int { place }
    var isTie: Bool { entries.count > 1 }
}

extension AppStore {
    /// Top 3 places for the most different climbs sent at a place (crag or gym). Repeats of the
    /// same climb count once; unlinked posts count by route name (board problems), and unnamed
    /// gym sends each count as their own climb.
    func mostSendsLeaderboard(at placeID: Place.ID) -> [LeaderboardTier] {
        let byUser = Dictionary(grouping: sends(at: placeID), by: \.authorID)
        let scores = byUser.map { userID, posts -> (userID: User.ID, score: Int, detail: String) in
            let distinct = Set(posts.map { post in
                post.climbID ?? "name:" + NameMatcher.normalize(post.routeName.isEmpty ? post.id : post.routeName)
            })
            return (userID: userID, score: distinct.count, detail: "\(posts.count) \(posts.count == 1 ? "video" : "videos")")
        }
        return podium(scores) { "\($0) \($0 == 1 ? "climb" : "climbs")" }
    }

    /// Top 3 places for the hardest send at a place, within one category (boulders or routes).
    /// A send counts at the climb's grade (the average of everyone's proposed grades).
    /// Grades from other scales are converted (Font → V, French → YDS) so everyone is comparable.
    func hardestSendLeaderboard(at placeID: Place.ID, category: GradeCategory) -> [LeaderboardTier] {
        var best: [User.ID: (grade: Grade, post: Post)] = [:]
        for post in sends(at: placeID) {
            guard let grade = displayGrade(for: post)?.canonical, grade.system.category == category else { continue }
            if let current = best[post.authorID], current.grade.rank >= grade.rank { continue }
            best[post.authorID] = (grade, post)
        }
        let scores = best.map { userID, value in
            (userID: userID, score: value.grade.rank, detail: climbName(value.post))
        }
        let system = category.canonicalSystem
        return podium(scores) { rank in system.grades.indices.contains(rank) ? system.grades[rank] : "?" }
    }

    /// Top 3 places for the hardest send of one discipline at a place (e.g. hardest trad send).
    /// Grades are compared on the discipline's common scale (Font → V, French / British → YDS);
    /// if a discipline's sends span kinds (e.g. "Other"), the scale most of them use is ranked.
    /// Empty if nobody has a graded send of that discipline there.
    func hardestSendLeaderboard(at placeID: Place.ID, discipline: ClimbDiscipline) -> [LeaderboardTier] {
        let graded = sends(at: placeID)
            .filter { $0.discipline == discipline }
            .compactMap { post in displayGrade(for: post)?.comparable.map { (post: post, grade: $0) } }
        let bySystem = Dictionary(grouping: graded, by: { $0.grade.system })
        guard let system = bySystem.max(by: { $0.value.count < $1.value.count })?.key else { return [] }
        var best: [User.ID: (grade: Grade, post: Post)] = [:]
        for entry in bySystem[system] ?? [] {
            if let current = best[entry.post.authorID], current.grade.rank >= entry.grade.rank { continue }
            best[entry.post.authorID] = (entry.grade, entry.post)
        }
        let scores = best.map { userID, value in
            (userID: userID, score: value.grade.rank, detail: climbName(value.post))
        }
        return podium(scores) { rank in system.grades.indices.contains(rank) ? system.grades[rank] : "?" }
    }

    /// Disciplines with at least one graded send at a place, in the usual discipline order.
    func leaderboardDisciplines(at placeID: Place.ID) -> [ClimbDiscipline] {
        let present = Set(sends(at: placeID)
            .filter { displayGrade(for: $0)?.comparable != nil }
            .map(\.discipline))
        return ClimbDiscipline.allCases.filter(present.contains)
    }

    /// Which categories have graded sends at a place, for the Boulders / Routes switch.
    func leaderboardCategories(at placeID: Place.ID) -> [GradeCategory] {
        let present = Set(sends(at: placeID).compactMap { displayGrade(for: $0)?.canonical?.system.category })
        return GradeCategory.allCases.filter(present.contains)
    }

    // MARK: - Helpers

    /// Full sends at a place. Links (sections of a climb) don't count toward leaderboards.
    private func sends(at placeID: Place.ID) -> [Post] {
        posts(at: placeID).filter { $0.sendStyle.countsAsSend }
    }

    private func climbName(_ post: Post) -> String {
        climb(post.climbID)?.name ?? (post.routeName.isEmpty ? "Unnamed route" : post.routeName)
    }

    /// Groups scores into the top 3 distinct values (ties share a place), highest first.
    /// Within a tie, climbers are listed alphabetically by username.
    private func podium<Score: Comparable & Hashable>(
        _ scores: [(userID: User.ID, score: Score, detail: String)],
        label: (Score) -> String
    ) -> [LeaderboardTier] {
        let grouped = Dictionary(grouping: scores, by: { $0.score })
        return grouped.keys.sorted(by: >).prefix(3).enumerated().map { index, score -> LeaderboardTier in
            let entries = (grouped[score] ?? [])
                .sorted { (user($0.userID)?.username ?? "") < (user($1.userID)?.username ?? "") }
                .map { LeaderboardEntry(userID: $0.userID, detail: $0.detail) }
            return LeaderboardTier(place: index + 1, scoreLabel: label(score), entries: entries)
        }
    }
}
