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
                        CommentLine(comment: comment)
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
}
