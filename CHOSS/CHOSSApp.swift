import SwiftUI
import AVFoundation

@main
struct CHOSSApp: App {
    init() {
        // Video app audio: play sound even when the ring/silent switch is on silent
        // (the default "ambient" category mutes it), and duck other audio instead of stopping it.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        // Start loading the ad shown when the app opens (see AppOpenAdManager).
        AppOpenAdManager.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
    }
}
