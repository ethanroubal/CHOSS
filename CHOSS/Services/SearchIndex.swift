import Foundation

/// A fuzzy search index over a large list (places, climbs, climbers, sends).
///
/// Cost per search does not grow with the number of items the way scanning does:
/// 1. Each item's names are normalized once, when it's added (`NameMatcher.Prepared`).
/// 2. A query first gathers a bounded set of candidates:
///    - words (and initials) starting with what's being typed, via binary search in a sorted
///      word list, and
///    - items sharing 3-letter chunks ("trigrams") with the query, which also catches typos
///      ("priay" shares "pri" with "priya"), rarest chunks first.
/// 3. Only those candidates (at most `candidateLimit`) get the full typo-tolerant score.
///
/// It's an immutable-by-default value type (`Sendable`), so searches run off the main thread
/// on a snapshot while the app keeps working. Items can be added or replaced in place.
struct SearchIndex: Sendable {
    struct Item: Sendable {
        let id: String
        /// Primary names (e.g. a place's name). Matches here rank highest.
        let names: [String]
        /// Secondary names (e.g. town / state, author). Matches here rank a little lower.
        var secondary: [String] = []
        /// Optional category used to filter results (e.g. "gym" / "crag").
        var tag: String? = nil
        /// Tie-breaker between equally good matches (e.g. popularity).
        var boost: Double = 0
    }

    private struct Entry: Sendable {
        let id: String
        let primary: NameMatcher.Prepared
        let secondary: NameMatcher.Prepared?
        let tag: String?
        let boost: Double
        let sortName: String
    }

    /// Candidates scored per query. Bounds the cost of a search regardless of index size.
    var candidateLimit = 600
    /// Most entries read from one trigram's posting list. A chunk shared by a huge number of
    /// items ("ock") says little on its own; this keeps its cost bounded.
    var postingScanLimit = 20_000

    private var entries: [Entry] = []
    /// id → position in `entries` (replaced items leave a stale entry behind that is skipped).
    private var positions: [String: Int] = [:]
    private var trigrams: [String: [Int32]] = [:]
    /// Every word (and multi-word initials) with its entry, sorted by word, for prefix lookups.
    private var sortedWords: [(word: String, entry: Int32)] = []
    private var pendingWords: [(word: String, entry: Int32)] = []

    init(_ items: [Item] = []) {
        entries.reserveCapacity(items.count)
        for item in items { insert(item, sortWords: false) }
        sortedWords.append(contentsOf: pendingWords)
        pendingWords.removeAll()
        sortedWords.sort { $0.word < $1.word }
    }

    var count: Int { positions.count }

    /// Adds an item, or replaces it if its id is already indexed.
    mutating func upsert(_ item: Item) {
        insert(item, sortWords: true)
    }

    // MARK: - Search

    /// IDs matching `query`, best first (score, then boost, then name). Empty for an empty query.
    func search(_ rawQuery: String, tag: String? = nil, limit: Int = 100) -> [String] {
        let query = NameMatcher.Query(rawQuery)
        guard !query.isEmpty, !entries.isEmpty else { return [] }

        var hits: [Int32: Int] = [:]

        // 1. Word prefixes: the word being typed (last word) and initials ("ml").
        var prefixes = [query.words.last ?? query.text]
        if query.compact.count >= 2 { prefixes.append(query.compact) }
        for prefix in prefixes {
            for entry in entriesWithWord(prefix: prefix, cap: candidateLimit) {
                hits[entry, default: 0] += 3  // prefix matches are strong signals
            }
        }

        // 2. Trigrams, rarest first; very common chunks are skipped once we have enough.
        let queryGrams = Set(query.words.flatMap { Self.trigrams(of: $0, isPrefix: $0 == query.words.last) })
        let postings = queryGrams.compactMap { trigrams[$0] }.sorted { $0.count < $1.count }
        for list in postings {
            if hits.count >= candidateLimit * 4 && list.count > candidateLimit { break }
            for entry in list.prefix(postingScanLimit) { hits[entry, default: 0] += 1 }
        }

        // 3. Score the best candidates only.
        let candidates = hits
            .sorted { $0.value > $1.value }
            .prefix(candidateLimit)
            .map { Int($0.key) }

        var scored: [(entry: Entry, score: Double)] = []
        scored.reserveCapacity(candidates.count)
        for position in candidates {
            let entry = entries[position]
            guard positions[entry.id] == position else { continue }  // replaced item
            if let tag, entry.tag != tag { continue }
            let primary = NameMatcher.score(query, entry.primary)
            let secondary = entry.secondary.flatMap { NameMatcher.score(query, $0) }.map { $0 - 5 }
            guard let score = [primary, secondary].compactMap({ $0 }).max() else { continue }
            scored.append((entry, score))
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.entry.boost != rhs.entry.boost { return lhs.entry.boost > rhs.entry.boost }
                return lhs.entry.sortName < rhs.entry.sortName
            }
            .prefix(limit)
            .map { $0.entry.id }
    }

    // MARK: - Building

    private mutating func insert(_ item: Item, sortWords: Bool) {
        let primary = NameMatcher.Prepared(names: item.names)
        let secondaryNames = item.secondary.filter { !$0.isEmpty }
        let secondary = secondaryNames.isEmpty ? nil : NameMatcher.Prepared(names: secondaryNames)
        let position = entries.count
        entries.append(Entry(id: item.id, primary: primary, secondary: secondary, tag: item.tag,
                             boost: item.boost, sortName: primary.fields.first ?? ""))
        positions[item.id] = position

        let entry = Int32(position)
        var words = Set(primary.words + (secondary?.words ?? []))
        if primary.initials.count >= 2 { words.insert(primary.initials) }
        for word in words {
            for gram in Self.trigrams(of: word, isPrefix: false) {
                trigrams[gram, default: []].append(entry)
            }
        }
        let wordEntries = words.map { (word: $0, entry: entry) }
        if sortWords {
            for pair in wordEntries {
                let index = insertionIndex(for: pair.word)
                sortedWords.insert(pair, at: index)
            }
        } else {
            pendingWords.append(contentsOf: wordEntries)
        }
    }

    /// Chunks of 3 letters, padded with a leading space so word starts count.
    /// A word still being typed isn't padded at the end (it may continue).
    private static func trigrams(of word: String, isPrefix: Bool) -> [String] {
        let chars = Array(" " + word + (isPrefix ? "" : " "))
        guard chars.count >= 3 else { return chars.count == 2 ? [String(chars) + " "] : [] }
        return (0...(chars.count - 3)).map { String(chars[$0..<$0 + 3]) }
    }

    private func insertionIndex(for word: String) -> Int {
        var low = 0, high = sortedWords.count
        while low < high {
            let mid = (low + high) / 2
            if sortedWords[mid].word < word { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Entries with a word starting with `prefix` (binary search, then a bounded scan).
    private func entriesWithWord(prefix: String, cap: Int) -> [Int32] {
        var result: [Int32] = []
        var index = insertionIndex(for: prefix)
        while index < sortedWords.count, result.count < cap, sortedWords[index].word.hasPrefix(prefix) {
            result.append(sortedWords[index].entry)
            index += 1
        }
        return result
    }
}
