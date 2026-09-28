import SwiftUI

extension Color {
    /// Stable, pleasant color derived from an ID (Swift's `hashValue` is randomized per launch).
    static func seeded(_ seed: String) -> Color {
        let value = seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hue: Double(value % 360) / 360, saturation: 0.55, brightness: 0.8)
    }
}

struct AvatarView: View {
    let user: User?
    var size: CGFloat = 36

    var body: some View {
        Circle()
            .fill(Color.seeded(user?.id ?? "?").gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(user?.initials ?? "?")
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(user?.displayName ?? "Unknown climber")
    }
}

struct PlaceIconView: View {
    let place: Place
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(Color.seeded(place.id).gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: place.kind.symbolName)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.white)
            }
    }
}

struct GradeBadge: View {
    let grade: Grade
    var prominent = false

    var body: some View {
        Text(grade.value)
            .font(prominent ? .headline.monospacedDigit() : .caption.bold().monospacedDigit())
            .padding(.horizontal, prominent ? 10 : 7)
            .padding(.vertical, prominent ? 5 : 3)
            .background(.tint, in: Capsule())
            .foregroundStyle(.white)
    }
}

struct FollowButton: View {
    let isFollowing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isFollowing ? "Following" : "Follow")
                .font(.subheadline.bold())
                .frame(minWidth: 90)
        }
        .buttonStyle(.borderedProminent)
        .tint(isFollowing ? Color(.systemGray5) : .accentColor)
        .foregroundStyle(isFollowing ? Color.primary : Color.white)
        .animation(.snappy, value: isFollowing)
    }
}

struct StatView: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value, format: .number).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PlaceRow: View {
    @Environment(AppStore.self) private var store
    let place: Place

    var body: some View {
        HStack(spacing: 12) {
            PlaceIconView(place: place)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(place.name).font(.headline).lineLimit(1)
                    if place.isVerified {
                        Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.tint)
                    }
                }
                Text("\(place.kind.displayName) · \(place.locationLine)")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text("\(store.followerCount(of: place.id)) followers · \(store.posts(at: place.id).count) sends")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct UserRow: View {
    @Environment(AppStore.self) private var store
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(user: user, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.username).font(.headline)
                Text(user.displayName).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if user.id != store.currentUserID {
                FollowButton(isFollowing: store.isFollowing(user: user.id)) {
                    store.toggleFollow(user: user.id)
                }
            }
        }
    }
}

/// Navigation targets shared across tabs.
enum Route: Hashable {
    case place(Place.ID)
    case user(User.ID)
    case post(Post.ID)
}

extension View {
    /// Registers destinations for `Route` so any tab's NavigationStack can push places, profiles and posts.
    func withAppRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .place(let id): PlaceDetailView(placeID: id)
            case .user(let id): ProfileView(userID: id)
            case .post(let id): PostDetailView(postID: id)
            }
        }
    }
}
