import SwiftUI

/// A crag's leaderboards: most different climbs sent, and hardest send (boulders or routes).
/// Ties share a podium place and collapse into a dropdown of usernames.
struct LeaderboardView: View {
    @Environment(AppStore.self) private var store
    let placeID: Place.ID

    @State private var category: GradeCategory?

    var body: some View {
        let categories = store.leaderboardCategories(at: placeID)
        let selected = category.flatMap { categories.contains($0) ? $0 : nil } ?? categories.first

        VStack(alignment: .leading, spacing: 24) {
            board(
                title: "Most climbs sent",
                subtitle: "Different climbs posted here. Repeats count once.",
                systemImage: "list.number",
                tiers: store.mostSendsLeaderboard(at: placeID)
            )

            VStack(alignment: .leading, spacing: 10) {
                if categories.count > 1 {
                    Picker("Category", selection: Binding(
                        get: { selected ?? .boulder },
                        set: { category = $0 }
                    )) {
                        ForEach(categories) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                if let selected {
                    board(
                        title: "Hardest send",
                        subtitle: selected == .boulder
                            ? "Font grades are converted to V-scale to compare."
                            : "French grades are converted to YDS to compare.",
                        systemImage: "flame",
                        tiers: store.hardestSendLeaderboard(at: placeID, category: selected)
                    )
                } else {
                    board(title: "Hardest send", subtitle: nil, systemImage: "flame", tiers: [])
                }
            }
        }
    }

    private func board(title: String, subtitle: String?, systemImage: String, tiers: [LeaderboardTier]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage).font(.title3.bold())
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            if tiers.isEmpty {
                Text("No graded sends yet. Post one to claim first place!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(tiers) { tier in
                        TierRow(tier: tier)
                        if tier.id != tiers.last?.id {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal)
            }
        }
    }
}

/// One podium place. A single climber shows inline; a tie becomes a dropdown of usernames.
private struct TierRow: View {
    @Environment(AppStore.self) private var store
    let tier: LeaderboardTier

    @State private var isExpanded = false

    var body: some View {
        if tier.isTie, !tier.entries.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(spacing: 0) {
                    ForEach(tier.entries) { entry in
                        entryLink(entry, avatarSize: 28)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.leading, 44)
            } label: {
                HStack(spacing: 12) {
                    Medal(place: tier.place)
                    AvatarStack(userIDs: tier.entries.map(\.userID))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(tier.entries.count) climbers tied")
                            .font(.subheadline.bold())
                        Text(isExpanded ? "Hide names" : "Show names")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(tier.scoreLabel).font(.headline.monospacedDigit())
                }
                .foregroundStyle(Color.primary)
            }
            .padding(12)
            .accessibilityLabel("Place \(tier.place): \(tier.entries.count) climbers tied at \(tier.scoreLabel)")
        } else if let entry = tier.entries.first {
            HStack(spacing: 12) {
                Medal(place: tier.place)
                entryLink(entry, avatarSize: 36)
                Text(tier.scoreLabel).font(.headline.monospacedDigit())
            }
            .padding(12)
        }
    }

    private func entryLink(_ entry: LeaderboardEntry, avatarSize: CGFloat) -> some View {
        NavigationLink(value: Route.user(entry.userID)) {
            HStack(spacing: 10) {
                AvatarView(user: store.user(entry.userID), size: avatarSize)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.user(entry.userID)?.username ?? "unknown")
                        .font(.subheadline.bold())
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct Medal: View {
    let place: Int

    var body: some View {
        ZStack {
            Circle().fill(color.gradient)
            Text("\(place)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
        }
        .frame(width: 32, height: 32)
        .accessibilityLabel(["1st", "2nd", "3rd"][min(max(place - 1, 0), 2)] + " place")
    }

    private var color: Color {
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

    var body: some View {
        HStack(spacing: -10) {
            ForEach(userIDs.prefix(3), id: \.self) { id in
                AvatarView(user: store.user(id), size: 28)
                    .overlay(Circle().stroke(Color(.secondarySystemBackground), lineWidth: 2))
            }
            if userIDs.count > 3 {
                Text("+\(userIDs.count - 3)")
                    .font(.caption2.bold())
                    .frame(width: 28, height: 28)
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
