import SwiftUI

struct RootTabView: View {
    @Environment(AppStore.self) private var store

    private enum Tab: Hashable {
        case home, explore, post, search, profile
    }

    @State private var selection: Tab = .home
    @State private var lastContentTab: Tab = .home
    @State private var composing = false

    var body: some View {
        if store.isLoaded {
            TabView(selection: $selection) {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(Tab.home)
                ExploreView()
                    .tabItem { Label("Explore", systemImage: "safari") }
                    .tag(Tab.explore)
                Color.clear
                    .tabItem { Label("Post", systemImage: "plus.app") }
                    .tag(Tab.post)
                SearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(Tab.search)
                MyProfileTab()
                    .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                    .tag(Tab.profile)
            }
            // The Post tab opens the composer instead of switching tabs, like Instagram.
            .onChange(of: selection) { _, newValue in
                if newValue == .post {
                    selection = lastContentTab
                    composing = true
                } else {
                    lastContentTab = newValue
                }
            }
            .sheet(isPresented: $composing) {
                ComposeView()
            }
        } else {
            ProgressView("Loading…")
        }
    }
}

#Preview {
    RootTabView().environment(AppStore.preview)
}
