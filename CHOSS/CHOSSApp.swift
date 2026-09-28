import SwiftUI

@main
struct CHOSSApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .task { await store.load() }
        }
    }
}
