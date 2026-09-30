import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let feed = store.homeFeed()

        NavigationStack {
            ScrollView {
                followedPlacesStrip

                if feed.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("Nothing here yet")
                        } icon: {
                            HoldMarkView(size: 56).foregroundStyle(.tint)
                        }
                    } description: {
                        Text("Follow gyms, crags and climbers in Explore to fill your feed.")
                    }
                    .padding(.top, 60)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(feed) { item in
                            PostCardView(post: item.post, reason: item.reason)
                            Divider()
                        }
                    }
                    BrandFooter(message: "You're all caught up")
                }
            }
            .refreshable { await store.load() }
            // "Home" is what the back button says on pushed screens; the header shows the wordmark.
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WordmarkView(height: 24)
                }
            }
            .withAppRoutes()
        }
    }

    /// Story-style row of the places you follow, like Instagram's stories tray.
    @ViewBuilder
    private var followedPlacesStrip: some View {
        let places = store.followedPlaces(of: store.currentUserID)
        if !places.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(places) { place in
                        NavigationLink(value: Route.place(place.id)) {
                            VStack(spacing: 4) {
                                PlaceIconView(place: place, size: 58)
                                    .padding(3)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(Color.accentColor, lineWidth: 2)
                                    )
                                Text(place.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(width: 70)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }
}

#Preview {
    HomeView().environment(AppStore.preview)
}
