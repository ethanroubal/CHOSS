import Foundation

/// Forgiving name matching used by every search: prefix, word-prefix, substring,
/// initials ("jo" → "Jess Okafor", "ml" → "Midnight Lightning"), small typos ("priay" → "Priya",
/// "midnite" → "Midnight Lightning"), words in any order, and letters in order ("alxc" → "alexcrimps").
///
/// Names are normalized once into `Prepared` (the expensive part: accent folding, lowercasing,
/// splitting) and queries once into `Query`, so scoring a candidate is only cheap comparisons.
/// Large lists go through `SearchIndex`, which narrows candidates before scoring.
enum NameMatcher {
    /// A name (plus optional alternate names) normalized for matching. Build it once per item.
    struct Prepared: Sendable, Hashable {
        /// Normalized names, primary first.
        let fields: [String]
        /// Every word of every field.
        let words: [String]
        /// First letters of the primary name's words ("midnight lightning" → "ml").
        let initials: String

        init(names: [String]) {
            fields = names.map(NameMatcher.normalize).filter { !$0.isEmpty }
            words = fields.flatMap { $0.split(separator: " ").map(String.init) }
            initials = String((fields.first ?? "").split(separator: " ").compactMap(\.first))
        }

        var isEmpty: Bool { fields.isEmpty }
    }

    /// A normalized query. Build it once per search, not once per candidate.
    struct Query: Sendable {
        let text: String
        let words: [String]
        let compact: String
        let characters: [Character]

        init(_ raw: String) {
            text = NameMatcher.normalize(raw)
            words = text.split(separator: " ").map(String.init)
            compact = text.replacingOccurrences(of: " ", with: "")
            characters = Array(compact)
        }

        var isEmpty: Bool { text.isEmpty }
    }

    // MARK: - Scoring

    /// Higher is better; nil means no match. An empty query matches everything with score 0.
    static func score(_ query: Query, _ target: Prepared) -> Double? {
        let q = query.text
        guard !q.isEmpty else { return 0 }
        guard !target.isEmpty else { return nil }

        var best: Double?
        func consider(_ value: Double) {
            if value > (best ?? -1) { best = value }
        }

        for field in target.fields {
            if field == q { return 100 }
            if field.hasPrefix(q) { consider(90) } else if field.contains(q) { consider(70) }
        }
        if best ?? 0 < 85, target.words.contains(where: { $0.hasPrefix(q) }) {
            consider(85)
        }
        if best ?? 0 >= 85 { return best }

        // Every query word starts (or nearly starts) some word: "lightning midnight", "midnite light".
        if query.words.count > 1 {
            let allMatch = query.words.allSatisfy { qw in
                target.words.contains { w in
                    if w.hasPrefix(qw) { return true }
                    guard qw.count >= 4 else { return false }
                    let allowed = qw.count >= 6 ? 2 : 1
                    return editDistance(qw, String(w.prefix(qw.count)), max: allowed) <= allowed
                }
            }
            if allMatch { consider(80) }
        }

        // Initials: "jo" or "j o" → Jess Okafor.
        if query.compact.count >= 2 && target.initials.hasPrefix(query.compact) {
            consider(75)
        }

        // Typos: compare against same-length prefixes of each word / whole field.
        if (best ?? 0) < 60, q.count >= 3 {
            let allowed = q.count >= 6 ? 2 : 1
            for candidate in target.words + target.fields {
                let distance = editDistance(q, String(candidate.prefix(q.count)), max: allowed)
                if distance <= allowed {
                    consider(60 - Double(distance) * 10)
                }
            }
        }

        // Letters in order, possibly with gaps ("alxc" → "alexcrimps").
        if (best ?? 0) < 50 {
            for field in target.fields {
                if let compactness = subsequenceCompactness(query.characters, in: field) {
                    consider(30 + 20 * compactness)
                }
            }
        }
        return best
    }

    /// Convenience for one-off matching (small lists). Prefer `Prepared`/`Query` in loops.
    static func score(query: String, names: [String]) -> Double? {
        score(Query(query), Prepared(names: names))
    }

    static func score(query: String, user: User) -> Double? {
        score(query: query, names: [user.displayName, user.username])
    }

    static func score(query: String, climb: Climb) -> Double? {
        score(query: query, names: [climb.name])
    }

    /// Items that match `query`, best match first; everything (in the given order) when empty.
    /// For small lists (a crag's climbs, people you follow). Big lists use `SearchIndex`.
    static func rank<T>(_ items: [T], query: String, names: (T) -> [String], tieBreak: (T, T) -> Bool) -> [T] {
        let q = Query(query)
        guard !q.isEmpty else { return items }
        return items
            .compactMap { item in score(q, Prepared(names: names(item))).map { (item, $0) } }
            .sorted { lhs, rhs in lhs.1 != rhs.1 ? lhs.1 > rhs.1 : tieBreak(lhs.0, rhs.0) }
            .map { $0.0 }
    }

    static func rank(_ climbs: [Climb], query: String) -> [Climb] {
        rank(climbs, query: query, names: { [$0.name] }, tieBreak: { $0.name < $1.name })
    }

    static func rank(_ users: [User], query: String) -> [User] {
        rank(users, query: query, names: { [$0.displayName, $0.username] },
             tieBreak: { $0.displayName < $1.displayName })
    }

    // MARK: - Helpers

    static func normalize(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        var lastWasSpace = true
        for char in string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased() {
            if char.isLetter || char.isNumber {
                result.append(char)
                lastWasSpace = false
            } else if !lastWasSpace {
                // Collapse runs of separators into one space.
                result.append(" ")
                lastWasSpace = true
            }
        }
        if result.last == " " { result.removeLast() }
        return result
    }

    /// Edit distance where insertions, deletions, substitutions and swapped neighbours
    /// ("priay" → "priya") each cost 1 (optimal string alignment). Uses three rolling rows and
    /// stops early once the distance must exceed `max` (returns `max + 1` then).
    static func editDistance(_ a: String, _ b: String, max limit: Int = .max) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        if limit != .max, abs(a.count - b.count) > limit { return limit + 1 }

        var twoBack = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowMin = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = Swift.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = Swift.min(value, twoBack[j - 2] + 1)
                }
                current[j] = value
                rowMin = Swift.min(rowMin, value)
            }
            if limit != .max, rowMin > limit { return limit + 1 }
            (twoBack, previous, current) = (previous, current, twoBack)
        }
        return previous[b.count]
    }

    /// If the query's characters appear in order in `text`, returns 0...1 (1 = contiguous).
    static func subsequenceCompactness(_ query: [Character], in text: String) -> Double? {
        guard !query.isEmpty else { return nil }
        var qi = 0
        var first: Int?
        var last = 0
        for (i, char) in text.enumerated() where qi < query.count && char == query[qi] {
            if first == nil { first = i }
            last = i
            qi += 1
        }
        guard qi == query.count, let first else { return nil }
        return Double(query.count) / Double(last - first + 1)
    }
}
