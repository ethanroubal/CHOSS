import SwiftUI
import AVFoundation

@main
struct CHOSSApp: App {
    init() {
        // Video app audio: play sound even when the ring/silent switch is on silent
        // (the default "ambient" category mutes it), and duck other audio instead of stopping it.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
    }
}
