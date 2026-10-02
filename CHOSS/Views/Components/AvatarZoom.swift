import SwiftUI

extension View {
    /// Tapping shows the person's profile picture large, still a circle, in the middle of the
    /// screen with everything behind it blurred. Tap anywhere to close it.
    func enlargesAvatarOnTap(_ user: User?) -> some View {
        modifier(AvatarZoomModifier(user: user))
    }
}

private struct AvatarZoomModifier: ViewModifier {
    let user: User?
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .contentShape(Circle())
            .onTapGesture {
                // No slide-up: the overlay fades and grows in by itself.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { isPresented = true }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows the profile picture larger")
            .fullScreenCover(isPresented: $isPresented) {
                AvatarZoomView(user: user) {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { isPresented = false }
                }
            }
    }
}

private struct AvatarZoomView: View {
    let user: User?
    let close: () -> Void
    @State private var isShown = false

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width - 64, proxy.size.height - 64, 360)
            ZStack {
                Color.clear
                AvatarView(user: user, size: size)
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                    .scaleEffect(isShown ? 1 : 0.3)
                    .opacity(isShown ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .presentationBackground {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isShown ? 1 : 0)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { dismiss() }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isShown = true }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.18)) { isShown = false } completion: { close() }
    }
}
