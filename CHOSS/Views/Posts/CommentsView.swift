import SwiftUI

struct CommentsView: View {
    @Environment(AppStore.self) private var store
    let postID: Post.ID

    @State private var draft = ""
    @FocusState private var isComposing: Bool

    var body: some View {
        NavigationStack {
            List {
                if let post = store.post(postID) {
                    if post.comments.isEmpty {
                        Text("No comments yet. Give them some beta!")
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(post.comments) { comment in
                        commentRow(comment)
                            .swipeActions {
                                if comment.authorID == store.currentUserID {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        store.deleteComment(comment.id, from: postID)
                                    }
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    AvatarView(user: store.currentUser, size: 32)
                    TextField("Add a comment…", text: $draft, axis: .vertical)
                        .focused($isComposing)
                        .lineLimit(1...4)
                    Button("Post") {
                        store.addComment(draft, to: postID)
                        draft = ""
                    }
                    .bold()
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
                .background(.bar)
            }
        }
    }

    private func commentRow(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(user: store.user(comment.authorID), size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(store.user(comment.authorID)?.username ?? "unknown").bold()
                    Text(comment.createdAt, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                Text(comment.text).font(.subheadline)
            }
        }
    }
}
