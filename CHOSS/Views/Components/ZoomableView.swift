import SwiftUI

/// Pinch to zoom (up to `maxZoom`) around your fingers and drag to look around, like Photos.
/// Letting go below 1× springs back, and the content never pans past its edges. Dragging only
/// pans while zoomed in, so at 1× drags pass through (e.g. to swipe a sheet down). A "1×" button
/// appears in the corner while zoomed.
///
/// Gestures apply per-frame changes (not totals), so fingers landing or lifting mid-gesture
/// don't make the content jump.
struct ZoomableView<Content: View>: View {
    var maxZoom: CGFloat = 6
    @ViewBuilder let content: Content

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1
    @State private var lastDrag: CGSize = .zero
    @State private var size: CGSize = .zero

    private var isZoomed: Bool { zoom > 1.01 }

    var body: some View {
        content
            .scaleEffect(zoom)
            .offset(pan)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .clipped()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .simultaneousGesture(pinch)
            .gesture(drag, including: isZoomed ? GestureMask.all : GestureMask.subviews)
            .overlay(alignment: .topLeading) {
                if isZoomed {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            zoom = 1
                            pan = .zero
                        }
                    } label: {
                        Text("1×")
                            .font(.footnote.bold())
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .padding(10)
                    .accessibilityLabel("Reset zoom")
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isZoomed)
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let factor = value.magnification / lastMagnification
                lastMagnification = value.magnification
                let newZoom = min(max(zoom * factor, 0.8), maxZoom)
                let applied = newZoom / zoom
                // Keep the point under the fingers where it is.
                let anchor = CGSize(width: value.startLocation.x - size.width / 2,
                                    height: value.startLocation.y - size.height / 2)
                pan = CGSize(width: anchor.width - (anchor.width - pan.width) * applied,
                             height: anchor.height - (anchor.height - pan.height) * applied)
                zoom = newZoom
            }
            .onEnded { _ in
                lastMagnification = 1
                settle()
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                let delta = CGSize(width: value.translation.width - lastDrag.width,
                                   height: value.translation.height - lastDrag.height)
                lastDrag = value.translation
                pan = CGSize(width: pan.width + delta.width, height: pan.height + delta.height)
            }
            .onEnded { _ in
                lastDrag = .zero
                settle()
            }
    }

    private func settle() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if zoom <= 1.01 {
                zoom = 1
                pan = .zero
            } else {
                let maxX = size.width * (zoom - 1) / 2
                let maxY = size.height * (zoom - 1) / 2
                pan = CGSize(width: min(max(pan.width, -maxX), maxX),
                             height: min(max(pan.height, -maxY), maxY))
            }
        }
    }
}
