import SwiftUI

/// "Send to…" sheet: search the climbers you follow (fuzzy name matching), pick one or more,
/// add an optional note, and the video is delivered to each as a DM.
struct ShareToFollowersView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let post: Post

    @State private var query = ""
    @State private var selected: Set<User.ID> = []
    @State private var note = ""
    @State private var sent = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField

                List {
                    if following.isEmpty {
                        ContentUnavailableView(
                            "You're not following anyone yet",
                            systemImage: "person.2",
                            description: Text("Follow climbers to send them videos.")
                        )
                    } else if matches.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, user in
                            RecipientRow(
                                user: user,
                                isSelected: selected.contains(user.id),
                                isBestMatch: index == 0 && !query.isEmpty
                            ) {
                                toggle(user.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)

                if !selected.isEmpty {
                    sendBar
                }
            }
            .navigationTitle("Send to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if let url = post.videoURL {
                    ToolbarItem(placement: .primaryAction) {
                        // Fallback to the system share sheet (Messages, AirDrop…).
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .sensoryFeedback(.success, trigger: sent)
        }
    }

    private var following: [User] {
        store.followedUsers(of: store.currentUserID)
    }

    /// People you follow, best match first.
    private var matches: [User] {
        NameMatcher.rank(following, query: query)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search people you follow", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit {
                    // Pressing return picks the best match, like autocomplete.
                    if let best = matches.first, !query.isEmpty {
                        selected.insert(best.id)
                        query = ""
                    }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding()
    }

    private var sendBar: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(selected.compactMap { store.user($0) }.sorted { $0.displayName < $1.displayName }) { user in
                        Button {
                            toggle(user.id)
                        } label: {
                            HStack(spacing: 4) {
                                Text(user.displayName)
                                Image(systemName: "xmark")
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                TextField("Add a message…", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                Button {
                    store.share(post.id, with: selected, note: note)
                    sent.toggle()
                    dismiss()
                } label: {
                    Text(selected.count == 1 ? "Send" : "Send (\(selected.count))")
                        .bold()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.bar)
    }

    private func toggle(_ id: User.ID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }
}

private struct RecipientRow: View {
    let user: User
    let isSelected: Bool
    let isBestMatch: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AvatarView(user: user, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(user.displayName).font(.headline)
                        if isBestMatch {
                            Text("Best match")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(.tint)
                        }
                    }
                    Text("@\(user.username)").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
