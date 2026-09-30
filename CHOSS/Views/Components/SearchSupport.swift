import SwiftUI

/// The ids from the most recent finished search, and the query they're for.
/// While a newer search is running the previous results stay on screen (no flicker).
struct SearchResults: Equatable {
    var query = ""
    var ids: [String] = []

    /// True once a search for `query` has finished with nothing found.
    func isEmpty(for query: String) -> Bool {
        ids.isEmpty && self.query == SearchResults.clean(query) && !self.query.isEmpty
    }

    static func clean(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Long lists (thousands of places, every send) show a page at a time; the next page loads
/// when the last row scrolls into view.
enum Paging {
    static let pageSize = 50

    /// `first`, then `rest` without the ids already in `first`, stopping after `limit + 1` ids
    /// (the extra one tells the caller there's more). Only walks as far as it needs to.
    static func page(_ first: [String], then rest: [String], limit: Int) -> [String] {
        let seen = Set(first)
        var result = Array(first.prefix(limit + 1))
        for id in rest where !seen.contains(id) {
            if result.count > limit { break }
            result.append(id)
        }
        return result
    }
}

/// A search box drawn in the page itself (not the navigation bar's search drawer, which can
/// misplace the list and stop taking taps on screens pushed from a scroll view).
struct InlineSearchField: View {
    let prompt: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .focused($isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }
}

/// Placed after the last shown row; asks for the next page when it appears.
struct LoadMoreRow: View {
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .listRowSeparator(.hidden)
        .onAppear(perform: action)
    }
}

private struct SearchTaskKey: Equatable {
    let query: String
    let context: String
    let version: Int
}

extension View {
    /// Runs `search` whenever `query` settles (after a short pause in typing) or the indexes
    /// change (`version`), cancelling the previous one, and stores the ids in `results`.
    /// The search itself runs off the main thread (see `AppStore.searchPlaceIDs` etc.), so typing
    /// stays smooth however large the lists are.
    /// `context` distinguishes searches over different lists (e.g. the Search tab's scopes).
    func runSearch(_ query: String, context: String = "", version: Int, into results: Binding<SearchResults>,
                   search: @escaping (String) async -> [String]) -> some View {
        task(id: SearchTaskKey(query: SearchResults.clean(query), context: context, version: version)) {
            let cleaned = SearchResults.clean(query)
            guard !cleaned.isEmpty else {
                results.wrappedValue = SearchResults()
                return
            }
            // Debounce: a new keystroke cancels this task before it searches.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let ids = await search(cleaned)
            guard !Task.isCancelled else { return }
            results.wrappedValue = SearchResults(query: cleaned, ids: ids)
        }
    }
}
