import SwiftUI
import MapKit

/// A gym or crag's page: follow it, see every send posted there, post your own.
struct PlaceDetailView: View {
    @Environment(AppStore.self) private var store
    let placeID: Place.ID

    @State private var discipline: ClimbDiscipline?
    @State private var composing = false

    var body: some View {
        ScrollView {
            if let place = store.place(placeID) {
                VStack(alignment: .leading, spacing: 14) {
                    header(place)
                    actionRow(place)
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: place.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))) {
                        Marker(place.name, systemImage: place.kind.symbolName, coordinate: place.coordinate)
                    }
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
                    .padding(.horizontal)

                    sends(place)
                    BrandFooter()
                }
                .navigationTitle(place.name)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $composing) {
                    ComposeView(initialPlaceID: place.id)
                }
            } else {
                ContentUnavailableView("Place not found", systemImage: "mappin.slash")
            }
        }
    }

    private func header(_ place: Place) -> some View {
        HStack(alignment: .top, spacing: 14) {
            PlaceIconView(place: place, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(place.name).font(.title2.bold())
                    if place.isVerified {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint)
                    }
                }
                Text("\(place.kind.displayName) · \(place.locationLine)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(place.disciplines.map(\.displayName).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !place.about.isEmpty {
                    Text(place.about).font(.subheadline).padding(.top, 2)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func actionRow(_ place: Place) -> some View {
        VStack(spacing: 12) {
            HStack {
                StatView(value: store.followerCount(of: place.id), label: "Followers")
                StatView(value: store.posts(at: place.id).count, label: "Sends")
                StatView(value: Set(store.posts(at: place.id).map(\.authorID)).count, label: "Climbers")
            }
            HStack {
                FollowButton(isFollowing: store.isFollowing(place: place.id)) {
                    store.toggleFollow(place: place.id)
                }
                Button {
                    composing = true
                } label: {
                    Label("Post a send", systemImage: "video.badge.plus")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func sends(_ place: Place) -> some View {
        let all = store.posts(at: place.id)
        let filtered = all.filter { discipline == nil || $0.discipline == discipline }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sends").font(.title3.bold())
                Spacer()
                Menu {
                    Picker("Discipline", selection: $discipline) {
                        Text("All").tag(ClimbDiscipline?.none)
                        ForEach(place.disciplines) { Text($0.displayName).tag(ClimbDiscipline?.some($0)) }
                    }
                } label: {
                    Label(discipline?.displayName ?? "All", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal)

            if filtered.isEmpty {
                ContentUnavailableView(
                    "No sends yet",
                    systemImage: "figure.climbing",
                    description: Text("Be the first to post a send at \(place.name).")
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filtered) { post in
                        PostCardView(post: post)
                        Divider()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PlaceDetailView(placeID: "p_granite_works")
            .withAppRoutes()
    }
    .environment(AppStore.preview)
}
