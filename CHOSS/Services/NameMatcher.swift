import Foundation

/// Forgiving name matching for "send to…" search: prefix, word-prefix, substring,
/// abbreviation ("jo" → "Jess Okafor") and small typos ("alx" → "alexcrimps", "priay" → "Priya").
enum NameMatcher {
    /// Higher is better; nil means no match. An empty query matches everything with score 0.
    static func score(query: String, user: User) -> Double? {
        let q = normalize(query)
        guard !q.isEmpty else { return 0 }

        let name = normalize(user.displayName)
        let username = normalize(user.username)
        let words = name.split(separator: " ").map(String.init)
            + username.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)

        var best: Double?
        func consider(_ value: Double?) {
            if let value, value > (best ?? -1) { best = value }
        }

        for field in [name, username] {
            consider(field == q ? 100 : nil)
            consider(field.hasPrefix(q) ? 90 : nil)
            consider(field.contains(q) ? 70 : nil)
        }
        for word in words {
            consider(word.hasPrefix(q) ? 85 : nil)
        }
        // Initials: "jo" or "j o" → Jess Okafor.
        let initials = String(name.split(separator: " ").compactMap(\.first))
        let compactQuery = q.replacingOccurrences(of: " ", with: "")
        consider(compactQuery.count >= 2 && initials.hasPrefix(compactQuery) ? 75 : nil)

        // Typos: compare against same-length prefixes of each word / whole field.
        if q.count >= 3 {
            let allowed = q.count >= 6 ? 2 : 1
            for candidate in words + [name, username] {
                let prefix = String(candidate.prefix(q.count))
                let distance = editDistance(q, prefix)
                if distance <= allowed {
                    consider(60 - Double(distance) * 10)
                }
            }
        }

        // Letters in order, possibly with gaps ("alxc" → "alexcrimps").
        for field in [name, username] {
            if let compactness = subsequenceCompactness(q, in: field) {
                consider(30 + 20 * compactness)
            }
        }
        return best
    }

    /// Users that match `query`, best match first. Ties are broken alphabetically.
    static func rank(_ users: [User], query: String) -> [User] {
        users
            .compactMap { user in score(query: query, user: user).map { (user, $0) } }
            .sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.displayName < rhs.0.displayName
            }
            .map(\.0)
    }

    // MARK: - Helpers

    static func normalize(_ string: String) -> String {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { result, char in
                // Collapse runs of separators into one space.
                if char == " " && (result.isEmpty || result.last == " ") { return }
                result.append(char)
            }
            .trimmingCharacters(in: .whitespaces)
    }

    /// Edit distance where insertions, deletions, substitutions and swapped neighbours
    /// ("priay" → "priya") each cost 1 (optimal string alignment).
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }

    /// If `query`'s characters appear in order in `text`, returns 0...1 (1 = contiguous).
    static func subsequenceCompactness(_ query: String, in text: String) -> Double? {
        let q = Array(query.replacingOccurrences(of: " ", with: ""))
        guard !q.isEmpty else { return nil }
        var qi = 0
        var first: Int?
        var last = 0
        for (i, char) in text.enumerated() where qi < q.count && char == q[qi] {
            if first == nil { first = i }
            last = i
            qi += 1
        }
        guard qi == q.count, let first else { return nil }
        let span = last - first + 1
        return Double(q.count) / Double(span)
    }
}
