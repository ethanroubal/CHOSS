import SwiftUI

/// Everyone who liked a post, opened by tapping "N likes". Searchable (forgiving, like the
/// other people lists) once there are more than a handful; tap someone for their profile.
struct LikesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let postID: Post.ID

    @State private var query = ""

    var body: some View {
        let likers = (store.post(postID)?.likedBy ?? [])
            .compactMap { store.user($0) }
            .sorted { $0.displayName < $1.displayName }
        let shown = NameMatcher.rank(likers, query: query)

        NavigationStack {
            List {
                ForEach(shown) { user in
                    NavigationLink(value: Route.user(user.id)) {
                        UserRow(user: user)
                    }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .top, spacing: 0) {
                if likers.count > 8 {
                    InlineSearchField(prompt: "Search likes", text: $query)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.bar)
                }
            }
            .overlay {
                if likers.isEmpty {
                    ContentUnavailableView("No likes yet", systemImage: "hand.thumbsup")
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Likes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .withAppRoutes()
        }
    }
}
