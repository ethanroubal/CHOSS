import SwiftUI
import UIKit

/// Frame a profile picture: drag to position yourself and pinch to zoom inside the circle.
/// When you stop moving, a "Use this photo" bar pops up to confirm the framing.
struct AvatarCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onDone: (UIImage) -> Void

    /// Zoom on top of "fill the circle" (1 = just fills it).
    @State private var zoom: CGFloat = 1
    /// Offset of the photo's center from the circle's center, in points.
    @State private var offset: CGSize = .zero
    /// Zoom and offset when the current gesture began. Every frame is computed from these
    /// (not from the previous frame), so small errors can't accumulate into jitter.
    @State private var gestureStart: (zoom: CGFloat, offset: CGSize)?
    /// Diameter of the framing circle, measured from the crop area.
    @State private var circleSide: CGFloat = 0
    @State private var showsConfirm = true
    @State private var confirmTask: Task<Void, Never>?

    private let maxZoom: CGFloat = 5
    private let outputSide: CGFloat = 600
    private let circleInset: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            topBar
            cropArea
            confirmBar
        }
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: - Parts

    private var topBar: some View {
        HStack {
            Button("Cancel", action: onCancel)
            Spacer()
            Text("Move and scale").font(.headline)
            Spacer()
            Button("Reset") {
                withAnimation(.snappy) {
                    zoom = 1
                    offset = .zero
                }
            }
            .disabled(zoom == 1 && offset == .zero)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var cropArea: some View {
        let scale = displayScale

        return ZStack {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: image.size.width * scale, height: image.size.height * scale)
                .offset(offset)

            // Dim everything outside the circle, and outline it.
            Rectangle()
                .fill(.black.opacity(0.6))
                .mask {
                    Rectangle()
                        .overlay {
                            Circle()
                                .frame(width: circleSide, height: circleSide)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
                .allowsHitTesting(false)
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: circleSide, height: circleSide)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Keep the (large) photo inside this area so it never covers the buttons.
        .clipped()
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { proxy in
            max(min(proxy.size.width, proxy.size.height) - circleInset * 2, 0)
        } action: { side in
            circleSide = side
            offset = clamped(offset, zoom: zoom)
        }
        .gesture(frameGesture)
        .onTapGesture(count: 2) {
            // Double-tap toggles between filling the circle and 2x.
            withAnimation(.snappy) {
                if zoom > 1.01 {
                    zoom = 1
                    offset = .zero
                } else {
                    zoom = 2
                    offset = clamped(CGSize(width: offset.width * 2, height: offset.height * 2), zoom: 2)
                }
            }
            scheduleConfirm()
        }
    }

    /// Pops up when you stop moving the photo.
    private var confirmBar: some View {
        ZStack {
            if showsConfirm {
                VStack(spacing: 10) {
                    Text("Happy with this framing?")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    Button {
                        onDone(croppedImage())
                    } label: {
                        Label("Use this photo", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.cream)
                    .foregroundStyle(Brand.green)
                    .disabled(circleSide <= 0)
                }
                .padding(.horizontal, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Drag to move · Pinch to zoom")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .transition(.opacity)
            }
        }
        .frame(height: 110)
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(weight: .light), trigger: showsConfirm) { _, shown in shown }
    }

    // MARK: - Gesture

    /// Pinch and drag handled as one gesture, so they can't fight each other.
    private var frameGesture: some Gesture {
        SimultaneousGesture(MagnifyGesture(), DragGesture(minimumDistance: 2))
            .onChanged { value in
                if gestureStart == nil {
                    gestureStart = (zoom, offset)
                    hideConfirm()
                }
                guard let start = gestureStart else { return }

                let magnification = value.first?.magnification ?? 1
                let newZoom = min(max(start.zoom * magnification, 1), maxZoom)
                // Scale the offset with the zoom so whatever is in the middle of the circle
                // stays put while pinching, then add the finger movement.
                let ratio = newZoom / start.zoom
                let translation = value.second?.translation ?? .zero
                let proposed = CGSize(width: start.offset.width * ratio + translation.width,
                                      height: start.offset.height * ratio + translation.height)

                zoom = newZoom
                offset = clamped(proposed, zoom: newZoom)
            }
            .onEnded { _ in
                gestureStart = nil
                scheduleConfirm()
            }
    }

    private func hideConfirm() {
        confirmTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { showsConfirm = false }
    }

    /// Show the confirm bar shortly after you stop moving.
    private func scheduleConfirm() {
        confirmTask?.cancel()
        confirmTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, gestureStart == nil else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showsConfirm = true }
        }
    }

    // MARK: - Geometry

    /// Points per image point: fill the circle, then apply the zoom.
    private var displayScale: CGFloat {
        fillScale * zoom
    }

    private var fillScale: CGFloat {
        guard image.size.width > 0, image.size.height > 0, circleSide > 0 else { return 1 }
        return max(circleSide / image.size.width, circleSide / image.size.height)
    }

    /// Keep the photo covering the whole circle.
    private func clamped(_ proposed: CGSize, zoom: CGFloat) -> CGSize {
        let scale = fillScale * zoom
        let maxX = max((image.size.width * scale - circleSide) / 2, 0)
        let maxY = max((image.size.height * scale - circleSide) / 2, 0)
        return CGSize(width: min(max(proposed.width, -maxX), maxX),
                      height: min(max(proposed.height, -maxY), maxY))
    }

    /// Renders what's inside the circle as a square image.
    private func croppedImage() -> UIImage {
        let scale = displayScale
        // The circle's center, in image coordinates (image center shifted opposite the drag).
        let centerX = image.size.width / 2 - offset.width / scale
        let centerY = image.size.height / 2 - offset.height / scale
        let cropSide = circleSide / scale
        let factor = outputSide / cropSide

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSide, height: outputSide), format: format)
        return renderer.image { _ in
            // `draw(in:)` respects the photo's orientation (image.size is already upright).
            image.draw(in: CGRect(
                x: -(centerX - cropSide / 2) * factor,
                y: -(centerY - cropSide / 2) * factor,
                width: image.size.width * factor,
                height: image.size.height * factor
            ))
        }
    }
}

#Preview {
    AvatarCropView(
        image: UIImage(systemName: "person.crop.square.fill") ?? UIImage(),
        onCancel: {},
        onDone: { _ in }
    )
}
