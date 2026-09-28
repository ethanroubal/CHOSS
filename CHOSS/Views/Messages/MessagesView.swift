import SwiftUI

/// DM inbox, opened from the paper-plane button on Home.
struct InboxView: View {
    @Environment(AppStore.self) private var store
    @State private var composing = false
    @State private var openConversation: Conversation.ID?

    var body: some View {
        List {
            if store.myConversations.isEmpty {
                ContentUnavailableView(
                    "No messages yet",
                    systemImage: "paperplane",
                    description: Text("Send a video to someone you follow with the paper plane on any post.")
                )
            }
            ForEach(store.myConversations) { conversation in
                NavigationLink(value: conversation.id) {
                    ConversationRow(conversation: conversation)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Messages")
        .navigationDestination(for: Conversation.ID.self) { id in
            ConversationView(conversationID: id)
        }
        .navigationDestination(item: $openConversation) { id in
            ConversationView(conversationID: id)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    composing = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New message")
            }
        }
        .sheet(isPresented: $composing) {
            NewMessageView { userID in
                openConversation = store.directConversation(with: userID).id
            }
        }
    }
}

private struct ConversationRow: View {
    @Environment(AppStore.self) private var store
    let conversation: Conversation

    var body: some View {
        let others = store.otherParticipants(in: conversation)
        let last = store.lastMessage(in: conversation.id)

        HStack(spacing: 12) {
            AvatarView(user: others.first, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(others.map(\.displayName).joined(separator: ", ")).font(.headline)
                if let last {
                    Text(preview(of: last))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let last {
                Text(last.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func preview(of message: Message) -> String {
        let sender = message.senderID == store.currentUserID ? "You" : (store.user(message.senderID)?.displayName ?? "")
        if message.sharedPostID != nil {
            return message.text.isEmpty ? "\(sender) sent a video" : "\(sender) sent a video: \(message.text)"
        }
        return message.senderID == store.currentUserID ? "You: \(message.text)" : message.text
    }
}

struct ConversationView: View {
    @Environment(AppStore.self) private var store
    let conversationID: Conversation.ID
    @State private var draft = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.messages(in: conversationID)) { message in
                        MessageBubble(message: message, isMine: message.senderID == store.currentUserID)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onAppear { scrollToBottom(proxy) }
            .onChange(of: store.messages(in: conversationID).count) { _, _ in scrollToBottom(proxy) }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("Message…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                Button {
                    store.sendMessage(draft, in: conversationID)
                    draft = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        guard let conversation = store.conversations.first(where: { $0.id == conversationID }) else { return "Chat" }
        return store.otherParticipants(in: conversation).map(\.displayName).joined(separator: ", ")
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = store.messages(in: conversationID).last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

private struct MessageBubble: View {
    @Environment(AppStore.self) private var store
    let message: Message
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 50) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                if let postID = message.sharedPostID, let post = store.post(postID) {
                    NavigationLink(value: Route.post(post.id)) {
                        SharedPostPreview(post: post)
                    }
                    .buttonStyle(.plain)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isMine ? Color.accentColor : Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(isMine ? Color.white : Color.primary)
                }
            }
            if !isMine { Spacer(minLength: 50) }
        }
    }
}

/// A shared send inside a DM: thumbnail with grade, route and place.
private struct SharedPostPreview: View {
    @Environment(AppStore.self) private var store
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(width: 200, height: 250)
                .overlay { VideoThumbnailView(post: post) }
                .overlay {
                    Image(systemName: "play.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .overlay(alignment: .topTrailing) {
                    PostGradeBadge(post: post).padding(6)
                }
                .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(store.user(post.authorID)?.username ?? "").font(.caption.bold())
                Text([post.routeName, store.place(post.placeID)?.name ?? ""].filter { !$0.isEmpty }
                        .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(width: 200, alignment: .leading)
            .background(Color(.secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Pick someone you follow to start a new thread (same fuzzy search as sharing).
private struct NewMessageView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onPick: (User.ID) -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(NameMatcher.rank(store.followedUsers(of: store.currentUserID), query: query)) { user in
                Button {
                    onPick(user.id)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(user: user, size: 40)
                        VStack(alignment: .leading) {
                            Text(user.displayName).font(.headline)
                            Text("@\(user.username)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search people you follow")
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
