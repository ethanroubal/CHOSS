import SwiftUI
import UIKit

/// Frame a profile picture: drag to position yourself and pinch to zoom inside the circle.
/// The photo always fills the circle (no empty edges), and the result is a square image.
struct AvatarCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onDone: (UIImage) -> Void

    /// Zoom on top of "fill the circle" (1 = just fills it).
    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat?
    /// Offset of the photo's center from the circle's center, in points.
    @State private var offset: CGSize = .zero
    @State private var offsetAtGestureStart: CGSize?

    private let maxZoom: CGFloat = 5
    private let outputSide: CGFloat = 600

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height) - 32
            let scale = displayScale(circle: side)

            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .frame(width: image.size.width * scale, height: image.size.height * scale)
                    .offset(offset)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                // Dim everything outside the circle, and outline it.
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .mask {
                        Rectangle()
                            .overlay {
                                Circle()
                                    .frame(width: side, height: side)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }
                    .allowsHitTesting(false)
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 1.5)
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let start = offsetAtGestureStart ?? offset
                        offsetAtGestureStart = start
                        offset = clamped(CGSize(width: start.width + value.translation.width,
                                                height: start.height + value.translation.height),
                                         circle: side, zoom: zoom)
                    }
                    .onEnded { _ in offsetAtGestureStart = nil }
                    .simultaneously(with:
                        MagnifyGesture()
                            .onChanged { value in
                                let start = zoomAtGestureStart ?? zoom
                                zoomAtGestureStart = start
                                zoom = min(max(start * value.magnification, 1), maxZoom)
                                offset = clamped(offset, circle: side, zoom: zoom)
                            }
                            .onEnded { _ in zoomAtGestureStart = nil }
                    )
            )
            .onTapGesture(count: 2) {
                // Double-tap resets the framing.
                withAnimation(.snappy) {
                    zoom = 1
                    offset = .zero
                }
            }
            .safeAreaInset(edge: .top) {
                Text("Drag and pinch to frame yourself")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 12)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Cancel", action: onCancel)
                    Spacer()
                    Button("Choose") { onDone(cropped(circle: side)) }
                        .bold()
                }
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .statusBarHidden()
    }

    // MARK: - Geometry

    /// Points per image point: fill the circle, then apply the zoom.
    private func displayScale(circle side: CGFloat) -> CGFloat {
        guard image.size.width > 0, image.size.height > 0 else { return 1 }
        let fill = max(side / image.size.width, side / image.size.height)
        return fill * zoom
    }

    /// Keep the photo covering the whole circle.
    private func clamped(_ proposed: CGSize, circle side: CGFloat, zoom: CGFloat) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else { return .zero }
        let fill = max(side / image.size.width, side / image.size.height)
        let scale = fill * zoom
        let maxX = max((image.size.width * scale - side) / 2, 0)
        let maxY = max((image.size.height * scale - side) / 2, 0)
        return CGSize(width: min(max(proposed.width, -maxX), maxX),
                      height: min(max(proposed.height, -maxY), maxY))
    }

    /// Renders what's inside the circle as a square image.
    private func cropped(circle side: CGFloat) -> UIImage {
        let scale = displayScale(circle: side)
        // The circle's center, in image coordinates (image center shifted opposite the drag).
        let centerX = image.size.width / 2 - offset.width / scale
        let centerY = image.size.height / 2 - offset.height / scale
        let cropSide = side / scale
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
