import SwiftUI

/// A place's leaderboards as podiums, shown under the map on its page: most different climbs
/// sent, and (crags only) hardest send (boulders / routes / ice, switchable when the crag has
/// more than one), side by side. Gyms show just most climbs sent, full width. 1st stands in the middle on the tallest step, 2nd on the left,
/// 3rd on the right. Ties share a step: stacked avatars that open a list of usernames.
struct LeaderboardView: View {
    @Environment(AppStore.self) private var store
    let placeID: Place.ID
    /// Crags only: gym grades are set by each gym, so a hardest-send ranking isn't meaningful.
    var showsHardest = true

    @State private var category: GradeCategory?
    /// A climber tapped on a podium (pushed via `navigationDestination`).
    @State private var openUserID: User.ID?

    var body: some View {
        let categories = store.leaderboardCategories(at: placeID)
        let selected = category.flatMap { categories.contains($0) ? $0 : nil } ?? categories.first

        VStack(alignment: .leading, spacing: 8) {
            Label("Leaderboard", systemImage: "trophy")
                .font(.headline)
                .padding(.horizontal)

            HStack(alignment: .top, spacing: 10) {
                PodiumCard(
                    title: showsHardest ? "Most sends" : "Most climbs sent",
                    systemImage: "list.number",
                    tiers: store.mostSendsLeaderboard(at: placeID),
                    emptyText: "No sends yet",
                    openUserID: $openUserID
                ) {
                    EmptyView()
                }

                if showsHardest {
                    PodiumCard(
                        title: "Hardest",
                        systemImage: "flame",
                        tiers: selected.map { store.hardestSendLeaderboard(at: placeID, category: $0) } ?? [],
                        emptyText: "No graded sends yet",
                        openUserID: $openUserID
                    ) {
                        if categories.count > 1, let selected {
                            Menu {
                                Picker("Category", selection: Binding(
                                    get: { selected },
                                    set: { category = $0 }
                                )) {
                                    ForEach(categories) { Text($0.displayName).tag($0) }
                                }
                            } label: {
                                HStack(spacing: 2) {
                                    Text(selected.displayName)
                                    Image(systemName: "chevron.down").imageScale(.small)
                                }
                                .font(.caption.weight(.semibold))
                            }
                        } else if let selected {
                            Text(selected.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .navigationDestination(item: $openUserID) { userID in
            ProfileView(userID: userID)
        }
    }
}

/// One leaderboard as a three-step podium in a card.
private struct PodiumCard<Accessory: View>: View {
    let title: String
    let systemImage: String
    let tiers: [LeaderboardTier]
    let emptyText: String
    @Binding var openUserID: User.ID?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer(minLength: 0)
                accessory
            }

            if tiers.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                // 2nd | 1st | 3rd, standing on steps of different heights.
                HStack(alignment: .bottom, spacing: 4) {
                    step(place: 2)
                    step(place: 1)
                    step(place: 3)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func step(place: Int) -> some View {
        let tier = tiers.first { $0.place == place }
        VStack(spacing: 4) {
            if let tier {
                PodiumOccupant(tier: tier, openUserID: $openUserID)
            } else {
                Spacer(minLength: 0)
            }
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6, style: .continuous)
                    .fill(Medal.color(for: place).gradient.opacity(tier == nil ? 0.25 : 1))
                VStack(spacing: 1) {
                    Text("\(place)")
                        .font(.headline.bold())
                    if let tier {
                        Text(tier.scoreLabel)
                            .font(.caption2.bold().monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .foregroundStyle(.white)
                .padding(.top, 4)
                .padding(.horizontal, 2)
            }
            .frame(height: stepHeight(place))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func stepHeight(_ place: Int) -> CGFloat {
        switch place {
        case 1: 64
        case 2: 48
        default: 36
        }
    }
}

/// Who stands on a step: one climber (avatar + username), or a tie (stacked avatars + "N tied")
/// that opens a menu of their usernames.
private struct PodiumOccupant: View {
    @Environment(AppStore.self) private var store
    let tier: LeaderboardTier
    @Binding var openUserID: User.ID?

    var body: some View {
        if tier.isTie {
            Menu {
                Section("\(tier.entries.count) tied at \(tier.scoreLabel)") {
                    ForEach(tier.entries) { entry in
                        Button("@\(store.user(entry.userID)?.username ?? "unknown")") {
                            openUserID = entry.userID
                        }
                    }
                }
            } label: {
                VStack(spacing: 3) {
                    AvatarStack(userIDs: tier.entries.map(\.userID), size: 24)
                    HStack(spacing: 1) {
                        Text("\(tier.entries.count) tied")
                        Image(systemName: "chevron.down").imageScale(.small)
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                }
            }
            .accessibilityLabel("Place \(tier.place): \(tier.entries.count) climbers tied at \(tier.scoreLabel)")
        } else if let entry = tier.entries.first {
            Button {
                openUserID = entry.userID
            } label: {
                VStack(spacing: 3) {
                    AvatarView(user: store.user(entry.userID), size: tier.place == 1 ? 36 : 30)
                    Text(store.user(entry.userID)?.username ?? "unknown")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Place \(tier.place): \(store.user(entry.userID)?.username ?? "unknown"), \(tier.scoreLabel)")
        }
    }
}

enum Medal {
    static func color(for place: Int) -> Color {
        switch place {
        case 1: Color(red: 0.85, green: 0.65, blue: 0.13)   // gold
        case 2: Color(red: 0.62, green: 0.64, blue: 0.67)   // silver
        default: Color(red: 0.72, green: 0.45, blue: 0.20)  // bronze
        }
    }
}

/// Up to three overlapping avatars for a tie, with "+N" for the rest.
private struct AvatarStack: View {
    @Environment(AppStore.self) private var store
    let userIDs: [User.ID]
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -size / 3) {
            ForEach(userIDs.prefix(3), id: \.self) { id in
                AvatarView(user: store.user(id), size: size)
                    .overlay(Circle().stroke(Color(.secondarySystemBackground), lineWidth: 2))
            }
            if userIDs.count > 3 {
                Text("+\(userIDs.count - 3)")
                    .font(.caption2.bold())
                    .frame(width: size, height: size)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            LeaderboardView(placeID: SampleData.yosemite)
        }
        .withAppRoutes()
    }
    .environment(AppStore.preview)
}
