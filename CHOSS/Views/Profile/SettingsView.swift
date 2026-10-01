import SwiftUI

/// The gear on your profile: your activity and account settings.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    /// Sign out / delete account (nil with demo data, where there's no account).
    @Environment(\.accountActions) private var accountActions
    @State private var editingProfile = false
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteFailed = false

    var body: some View {
        List {
            Section("Your activity") {
                NavigationLink(value: Route.likedVideos) {
                    LabeledContent {
                        Text(store.likedPosts(by: store.currentUserID).count, format: .number)
                    } label: {
                        Label {
                            Text("Liked videos")
                        } icon: {
                            FlexIcon(filled: true, size: 20)
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }

            Section("Account") {
                Button {
                    editingProfile = true
                } label: {
                    Label("Edit profile", systemImage: "person.crop.circle")
                }
                if let accountActions {
                    if let email = accountActions.email {
                        LabeledContent("Signed in as", value: email)
                    }
                    Button {
                        Task { await accountActions.signOut() }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }

            if let accountActions {
                Section {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Label("Delete account", systemImage: "trash")
                        }
                    }
                    .disabled(isDeleting)
                } footer: {
                    Text("Permanently deletes your profile, sends, comments, photos and likes.")
                }
                .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete account and everything in it", role: .destructive) {
                        isDeleting = true
                        Task {
                            deleteFailed = !(await accountActions.deleteAccount())
                            isDeleting = false
                        }
                    }
                } message: {
                    Text("This can't be undone.")
                }
            }

            Section {
            } footer: {
                Text("Data: \(BackendEnvironment.current.displayName)")
            }
        }
        .alert("Couldn't delete your account", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again.")
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editingProfile) {
            if let user = store.currentUser {
                EditProfileView(user: user)
            }
        }
    }
}

/// Every video you've liked, as a grid like a profile. Tap one to scroll through them from there.
struct LikedVideosView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let liked = store.likedPosts(by: store.currentUserID)
        ScrollView {
            if liked.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No liked videos yet")
                    } icon: {
                        FlexIcon(filled: false, size: 44)
                    }
                } description: {
                    Text("Tap the bicep (or double-tap a video) to like it. Liked videos show up here.")
                }
                .padding(.top, 60)
            } else {
                PostGrid(posts: liked, title: "Liked videos", badge: .grade)
            }
        }
        .navigationTitle("Liked videos")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView().withAppRoutes()
    }
    .environment(AppStore.preview)
}
