import SwiftUI

/// "Legends": a place's leaderboards as podiums, under the map on its page, in a section that
/// folds away (tap the header). 1st stands in the middle on the tallest step, 2nd on the left,
/// 3rd on the right. Ties share a step: stacked avatars that open a list of usernames.
///
/// - Crags: most climbs sent, plus a hardest-send podium for each discipline that has graded
///   sends there (boulder, sport, trad, ice…). Disciplines nobody has sent aren't shown.
/// - Gyms: just most climbs sent (gym grades vary by gym).
///
/// Podiums sit two to a row; an odd one out spans the full width.
struct LeaderboardView: View {
    @Environment(AppStore.self) private var store
    let placeID: Place.ID
    /// Crags only: gym grades are set by each gym, so a hardest-send ranking isn't meaningful.
    var showsHardest = true

    @State private var isExpanded = false
    /// A climber tapped on a podium (pushed via `navigationDestination`).
    @State private var openUserID: User.ID?

    private enum Board: Hashable {
        case mostSends
        case hardest(ClimbDiscipline)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Label("Legends", systemImage: "trophy")
                        .font(.headline)
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .accessibilityLabel("Legends")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows the leaderboards")

            if isExpanded {
                let rows = boards.chunked(into: 2)
                VStack(spacing: 10) {
                    ForEach(rows, id: \.self) { row in
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(row, id: \.self) { board in card(board) }
                        }
                    }
                }
                .padding(.horizontal)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .navigationDestination(item: $openUserID) { userID in
            ProfileView(userID: userID)
        }
    }

    /// Most sends first, then one hardest board per discipline with graded sends here.
    private var boards: [Board] {
        let hardest = showsHardest ? store.leaderboardDisciplines(at: placeID).map(Board.hardest) : []
        return [.mostSends] + hardest
    }

    @ViewBuilder
    private func card(_ board: Board) -> some View {
        switch board {
        case .mostSends:
            PodiumCard(
                title: showsHardest ? "Most sends" : "Most climbs sent",
                icon: Image(systemName: "list.number"),
                tiers: store.mostSendsLeaderboard(at: placeID),
                emptyText: "No sends yet",
                openUserID: $openUserID
            ) {
                EmptyView()
            }
        case .hardest(let discipline):
            PodiumCard(
                title: "Hardest \(discipline.displayName.lowercased())",
                icon: discipline.iconImage(),
                tiers: store.hardestSendLeaderboard(at: placeID, discipline: discipline),
                emptyText: "No graded sends yet",
                openUserID: $openUserID
            ) {
                EmptyView()
            }
        }
    }
}

private extension Array {
    /// Splits into consecutive groups of `size` (the last may be shorter).
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

/// One leaderboard as a three-step podium in a card.
private struct PodiumCard<Accessory: View>: View {
    let title: String
    let icon: Image
    let tiers: [LeaderboardTier]
    let emptyText: String
    @Binding var openUserID: User.ID?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Label {
                    Text(title)
                } icon: {
                    icon
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                }
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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

    @State private var showingTie = false

    var body: some View {
        if tier.isTie {
            Button {
                showingTie = true
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
            .buttonStyle(.plain)
            // A small bubble next to the step (not a full sheet) listing everyone tied.
            .popover(isPresented: $showingTie) {
                TieList(tier: tier) { userID in
                    showingTie = false
                    openUserID = userID
                }
                .presentationCompactAdaptation(.popover)
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

/// Everyone sharing a podium step: profile picture, username, name and what earned the spot.
/// Tapping someone opens their profile.
private struct TieList: View {
    @Environment(AppStore.self) private var store
    let tier: LeaderboardTier
    let onSelect: (User.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Medal.color(for: tier.place)).frame(width: 10, height: 10)
                Text("\(tier.entries.count) tied at \(tier.scoreLabel)")
                    .font(.subheadline.bold())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(tier.entries) { entry in
                        let user = store.user(entry.userID)
                        Button {
                            onSelect(entry.userID)
                        } label: {
                            HStack(spacing: 10) {
                                AvatarView(user: user, size: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(user?.username ?? "unknown")
                                        .font(.subheadline.bold())
                                    Text(entry.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 12)
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(minWidth: 240)
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
