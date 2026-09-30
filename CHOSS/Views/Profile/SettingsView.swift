import SwiftUI

/// The gear on your profile: your activity and account settings.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var editingProfile = false

    var body: some View {
        List {
            Section("Your activity") {
                NavigationLink {
                    LikedVideosView()
                } label: {
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
            }
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
