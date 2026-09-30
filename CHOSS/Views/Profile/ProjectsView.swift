import SwiftUI

/// A climber's projects: climbs they've saved with "Add as project", most recent first.
/// On your own list you can swipe to remove one; climbs you've since sent are marked.
struct ProjectsView: View {
    @Environment(AppStore.self) private var store
    let userID: User.ID

    private var isMe: Bool { userID == store.currentUserID }

    var body: some View {
        let projects = store.projects(of: userID)
        List {
            if isMe, store.currentUser?.showsProjects == false {
                Label("Only seen by you. Turn on \"Show my projects\" in Edit profile to share them.",
                      systemImage: "eye.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(projects) { climb in
                NavigationLink(value: Route.climb(climb.id)) {
                    HStack {
                        ClimbRow(climb: climb, showsCrag: true)
                        if store.hasSent(climb: climb.id, by: userID) {
                            Label("Sent", systemImage: "checkmark.seal.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
                .swipeActions {
                    if isMe {
                        Button("Remove", role: .destructive) { store.toggleProject(climb.id) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if projects.isEmpty {
                ContentUnavailableView {
                    Label("No projects yet", systemImage: "bookmark")
                } description: {
                    Text(isMe
                         ? "Open a climb and tap \"Add as project\" to save it here."
                         : "\(store.user(userID)?.username ?? "This climber") hasn't added any projects.")
                }
            }
        }
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.inline)
    }
}
