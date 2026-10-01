import SwiftUI

/// Comments on a crag's / gym's or climb's page (conditions, access, beta…): the latest two,
/// plus buttons to add one or see them all. Loads the page's comments when it appears.
struct PageCommentsSection: View {
    @Environment(AppStore.self) private var store
    let page: PhotoSubject
    /// The place or climb name, for the sheet's title.
    let title: String

    @State private var showingAll = false

    var body: some View {
        let comments = store.comments(on: page)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(comments.isEmpty ? "Comments" : "Comments · \(comments.count)")
                    .font(.title3.bold())
                Spacer()
                if comments.count > 2 {
                    Button("See all") { showingAll = true }
                        .font(.subheadline.weight(.semibold))
                }
            }

            if comments.isEmpty && store.isLoadingComments(on: page) {
                ProgressView().frame(maxWidth: .infinity)
            } else if comments.isEmpty {
                Text("No comments yet. Share conditions, access info or beta.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(comments.suffix(2)) { comment in
                    CommentLine(comment: comment)
                }
            }

            Button {
                showingAll = true
            } label: {
                HStack(spacing: 10) {
                    AvatarView(user: store.currentUser, size: 28)
                    Text("Add a comment…")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.subheadline)
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .task(id: page) { await store.loadComments(on: page) }
        .sheet(isPresented: $showingAll) {
            PageCommentsView(page: page, title: title)
        }
    }
}

/// Every comment on a page, with a box to add one. Swipe your own to delete it.
struct PageCommentsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let page: PhotoSubject
    let title: String

    @State private var draft = ""
    @FocusState private var isComposing: Bool

    var body: some View {
        NavigationStack {
            let comments = store.comments(on: page)
            ScrollViewReader { proxy in
                List {
                    if comments.isEmpty {
                        Text(store.isLoadingComments(on: page)
                             ? "Loading…" : "No comments yet. Share conditions, access info or beta.")
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(comments) { comment in
                        CommentLine(comment: comment)
                            .id(comment.id)
                            .swipeActions {
                                if comment.authorID == store.currentUserID {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        store.deleteComment(comment.id, on: page)
                                    }
                                }
                            }
                            .contextMenu {
                                if comment.authorID == store.currentUserID {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        store.deleteComment(comment.id, on: page)
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await store.loadComments(on: page, force: true) }
                .onChange(of: comments.count) { _, _ in
                    if let last = comments.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    AvatarView(user: store.currentUser, size: 32)
                    TextField("Add a comment…", text: $draft, axis: .vertical)
                        .focused($isComposing)
                        .lineLimit(1...4)
                    Button("Post") {
                        store.addComment(draft, on: page)
                        draft = ""
                    }
                    .bold()
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(.bar)
            }
            .task { await store.loadComments(on: page) }
        }
    }
}

/// One comment: avatar, username, when, and the text.
struct CommentLine: View {
    @Environment(AppStore.self) private var store
    let comment: Comment

    var body: some View {
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
            Spacer(minLength: 0)
        }
    }
}
