import SwiftUI

extension Color {
    /// Stable, pleasant color derived from an ID (Swift's `hashValue` is randomized per launch).
    static func seeded(_ seed: String) -> Color {
        let value = seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hue: Double(value % 360) / 360, saturation: 0.55, brightness: 0.8)
    }
}

/// Profile picture, or colored initials when there's no photo (or while it loads).
struct AvatarView: View {
    let user: User?
    var size: CGFloat = 36

    @State private var image: UIImage?

    var body: some View {
        Circle()
            .fill(Color.seeded(user?.id ?? "?").gradient)
            .frame(width: size, height: size)
            .overlay {
                if let photo = image ?? user?.avatarURL.flatMap({ AvatarImageCache.shared.cachedImage(for: $0) }) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    Text(user?.initials ?? "?")
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .task(id: user?.avatarURL) {
                guard let url = user?.avatarURL else {
                    image = nil
                    return
                }
                image = await AvatarImageCache.shared.image(for: url)
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

/// A filled pill for an official grade; an outlined "~V6" pill for a proposed grade.
struct GradeBadge: View {
    let grade: Grade
    var isProposed = false
    var prominent = false

    var body: some View {
        Text(isProposed ? "~\(grade.value)" : grade.value)
            .font(prominent ? .headline.monospacedDigit() : .caption.bold().monospacedDigit())
            .padding(.horizontal, prominent ? 10 : 7)
            .padding(.vertical, prominent ? 5 : 3)
            .background {
                if isProposed {
                    Capsule().fill(.black.opacity(0.45))
                    Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5)
                } else {
                    Capsule().fill(Color.accentColor)
                }
            }
            .foregroundStyle(isProposed ? Color.white : Brand.onAccent)
            .accessibilityLabel(isProposed ? "Proposed grade \(grade.value)" : "Grade \(grade.value)")
    }
}

/// The grade to show on a thumbnail: the climb's grade (average of proposed grades, or the
/// guidebook grade if nobody has proposed one). Nothing if the climb has no grade at all.
struct PostGradeBadge: View {
    @Environment(AppStore.self) private var store
    let post: Post

    var body: some View {
        if let grade = store.displayGrade(for: post) {
            GradeBadge(grade: grade)
        }
    }
}

/// A discipline's icon (hold / quickdraw / cam / top-rope anchor), tinted by the foreground style.
struct DisciplineIcon: View {
    let discipline: ClimbDiscipline
    var size: CGFloat = 20

    var body: some View {
        Image(size > 28 ? discipline.iconName + "Large" : discipline.iconName)
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(discipline.displayName)
    }
}

/// Text with the discipline's icon, for pickers and menus.
struct DisciplineLabel: View {
    let discipline: ClimbDiscipline

    var body: some View {
        Label {
            Text(discipline.displayName)
        } icon: {
            Image(discipline.iconName)
        }
    }
}

/// "V4–V6 · 5.11b–5.11d" chips for a climber's self-reported level.
struct GradeRangeChips: View {
    let ranges: [GradeRange]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ranges, id: \.self) { range in
                Label {
                    Text(range.display)
                } icon: {
                    DisciplineIcon(discipline: range.system.category.iconDiscipline, size: 14)
                }
                    .font(.caption.bold().monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(.tint)
            }
        }
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
        .foregroundStyle(isFollowing ? Color.primary : Brand.onAccent)
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
                Text("\(store.followerCount(of: place.id)) followers · \(store.postCount(at: place.id)) sends")
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
    case climb(Climb.ID)
    /// A gym route (or untagged route), by its climb key.
    case route(String)
    /// A scrollable list of posts starting at one of them.
    case feed(PostFeed)
    /// A profile's followers / following / followed places.
    case connections(User.ID, ConnectionsTab)
}

extension View {
    /// Registers destinations for `Route` so any tab's NavigationStack can push places, profiles and posts.
    func withAppRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .place(let id): PlaceDetailView(placeID: id)
            case .user(let id): ProfileView(userID: id)
            case .post(let id): PostDetailView(postID: id)
            case .climb(let id): ClimbDetailView(climbID: id)
            case .route(let key): RouteDetailView(climbKey: key)
            case .feed(let feed): PostFeedView(feed: feed)
            case .connections(let userID, let tab): ConnectionsView(userID: userID, tab: tab)
            }
        }
    }
}
