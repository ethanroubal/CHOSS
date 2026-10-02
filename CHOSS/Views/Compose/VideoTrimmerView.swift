import SwiftUI
import AVKit

/// The part of a video to keep, in seconds from its start.
struct VideoTrim: Equatable {
    var start: Double
    var end: Double

    var duration: Double { end - start }

    var timeRange: CMTimeRange {
        CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                    end: CMTime(seconds: end, preferredTimescale: 600))
    }

    /// "0:03 – 0:21 · 18s"
    var label: String {
        "\(Self.clock(start)) – \(Self.clock(end)) · \(Int(duration.rounded()))s"
    }

    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Cuts a video down to a trim, writing a new file (the original is left alone).
enum VideoTrimExporter {
    enum ExportError: LocalizedError {
        case unavailable, failed(String?)
        var errorDescription: String? {
            switch self {
            case .unavailable: "This video can't be trimmed."
            case .failed(let reason): reason ?? "Couldn't trim the video."
            }
        }
    }

    static func export(_ source: URL, trim: VideoTrim) async throws -> URL {
        let asset = AVURLAsset(url: source)
        // Re-encoded (not passthrough) so the cut lands on the exact frame chosen.
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.unavailable
        }
        let folder = URL.documentsDirectory.appending(path: "Sends", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appending(path: "\(UUID().uuidString).mp4")
        session.outputURL = output
        session.outputFileType = .mp4
        session.timeRange = trim.timeRange
        session.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw ExportError.failed(session.error?.localizedDescription)
        }
        return output
    }
}

/// Pick where the video starts and ends: drag the handles on the filmstrip. The preview plays
/// just the kept part, on a loop.
struct VideoTrimmerView: View {
    let url: URL
    let initial: VideoTrim?
    /// Called with the chosen trim (nil: keep the whole video), or not at all on Cancel.
    let onDone: (VideoTrim?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var duration: Double = 0
    @State private var trim = VideoTrim(start: 0, end: 0)
    @State private var thumbnails: [UIImage] = []
    @State private var playhead: Double = 0
    @State private var timeObserver: Any?

    /// Shortest clip you can trim down to.
    private let minimumLength = 1.0

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)

                if duration > 0 {
                    VStack(spacing: 10) {
                        Text(trim.label)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                        TrimBar(duration: duration, trim: $trim, playhead: playhead,
                                thumbnails: thumbnails, minimumLength: minimumLength) { time in
                            // Show the frame under the handle being dragged.
                            player.pause()
                            player.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                                        toleranceBefore: .zero, toleranceAfter: .zero)
                        } onDragEnded: {
                            playFromStart()
                        }
                        .frame(height: 56)
                        Text("Drag the ends to choose where the video starts and stops.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                } else {
                    ProgressView().frame(height: 100)
                }
            }
            .padding(.bottom)
            .navigationTitle("Trim video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let isWhole = trim.start < 0.05 && trim.end > duration - 0.05
                        onDone(isWhole ? nil : trim)
                        dismiss()
                    }
                    .bold()
                    .disabled(duration == 0)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset") {
                        trim = VideoTrim(start: 0, end: duration)
                        playFromStart()
                    }
                    .disabled(duration == 0 || (trim.start == 0 && trim.end == duration))
                }
            }
        }
        .task { await load() }
        .onDisappear {
            player.pause()
            if let timeObserver { player.removeTimeObserver(timeObserver) }
        }
    }

    private func load() async {
        let asset = AVURLAsset(url: url)
        guard let length = try? await asset.load(.duration).seconds, length.isFinite, length > 0 else { return }
        duration = length
        if let initial, initial.end <= length {
            trim = initial
        } else {
            trim = VideoTrim(start: 0, end: length)
        }
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { time in
            MainActor.assumeIsolated {
                playhead = time.seconds
                // Loop the kept part.
                if time.seconds >= trim.end, player.rate > 0 { playFromStart() }
            }
        }
        playFromStart()
        thumbnails = await Self.filmstrip(for: asset, duration: length, count: 10)
    }

    private func playFromStart() {
        player.seek(to: CMTime(seconds: trim.start, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    private static func filmstrip(for asset: AVAsset, duration: Double, count: Int) async -> [UIImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        var images: [UIImage] = []
        for index in 0..<count {
            let time = CMTime(seconds: duration * (Double(index) + 0.5) / Double(count), preferredTimescale: 600)
            if let frame = try? await generator.image(at: time).image {
                images.append(UIImage(cgImage: frame))
            }
        }
        return images
    }
}

/// Filmstrip with a start and an end handle. Outside the kept part is dimmed.
private struct TrimBar: View {
    let duration: Double
    @Binding var trim: VideoTrim
    let playhead: Double
    let thumbnails: [UIImage]
    let minimumLength: Double
    let onScrub: (Double) -> Void
    let onDragEnded: () -> Void

    private let handleWidth: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - handleWidth * 2
            let startX = handleWidth + width * trim.start / duration
            let endX = handleWidth + width * trim.end / duration

            ZStack(alignment: .leading) {
                // Filmstrip.
                HStack(spacing: 0) {
                    ForEach(thumbnails.indices, id: \.self) { index in
                        Image(uiImage: thumbnails[index])
                            .resizable()
                            .scaledToFill()
                            .frame(width: width / CGFloat(max(thumbnails.count, 1)), height: proxy.size.height)
                            .clipped()
                    }
                }
                .frame(width: width, height: proxy.size.height)
                .background(Color(.tertiarySystemFill))
                .offset(x: handleWidth)

                // Dim what's cut off.
                Rectangle().fill(.black.opacity(0.55))
                    .frame(width: max(0, startX - handleWidth))
                    .offset(x: handleWidth)
                Rectangle().fill(.black.opacity(0.55))
                    .frame(width: max(0, handleWidth + width - endX))
                    .offset(x: endX)

                // Kept part: frame and handles.
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.yellow, lineWidth: 3)
                    .frame(width: endX - startX + handleWidth * 2)
                    .offset(x: startX - handleWidth)
                    .allowsHitTesting(false)

                // Playhead.
                if playhead >= trim.start, playhead <= trim.end {
                    Capsule().fill(.white)
                        .frame(width: 3, height: proxy.size.height + 8)
                        .offset(x: handleWidth + width * playhead / duration - 1.5)
                        .allowsHitTesting(false)
                }

                handle(systemName: "chevron.compact.left", height: proxy.size.height)
                    .offset(x: startX - handleWidth)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trimBar"))
                        .onChanged { value in
                            let time = (value.location.x - handleWidth) / width * duration
                            trim.start = min(max(0, time), trim.end - minimumLength)
                            onScrub(trim.start)
                        }
                        .onEnded { _ in onDragEnded() })
                    .accessibilityLabel("Start, \(VideoTrim.clock(trim.start))")

                handle(systemName: "chevron.compact.right", height: proxy.size.height)
                    .offset(x: endX)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trimBar"))
                        .onChanged { value in
                            let time = (value.location.x - handleWidth) / width * duration
                            trim.end = max(min(duration, time), trim.start + minimumLength)
                            onScrub(trim.end)
                        }
                        .onEnded { _ in onDragEnded() })
                    .accessibilityLabel("End, \(VideoTrim.clock(trim.end))")
            }
            .coordinateSpace(.named("trimBar"))
        }
    }

    private func handle(systemName: String, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.yellow)
            .frame(width: handleWidth, height: height)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
            }
            .contentShape(Rectangle().inset(by: -12))
    }
}
