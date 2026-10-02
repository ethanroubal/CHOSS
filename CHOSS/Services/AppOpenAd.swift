import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// A full-screen ad shown once when the app is opened (Google AdMob "app open" ad). It helps
/// pay for the servers. The ad starts loading at launch; if it's ready within a few seconds it
/// is shown, otherwise the app just carries on (nobody waits on a slow ad). It's shown at most
/// once per launch, never when coming back from the background.
///
/// IDs live in the project's build settings (ADMOB_APP_ID, ADMOB_APP_OPEN_AD_UNIT_ID), which
/// fill in CHOSS-Info.plist. They're Google's test IDs until real ones are set: test ads are
/// labelled "Test Ad" and earn nothing.
@MainActor
final class AppOpenAdManager: NSObject {
    static let shared = AppOpenAdManager()

    /// How long launch waits for an ad that's still loading (the first load after install,
    /// while the SDK starts up, can take several seconds).
    private let loadTimeout: Duration = .seconds(8)
    /// Only on opening the app: if the main screen first appears later than this (signing in,
    /// setting up a new profile), no ad, so new climbers aren't greeted by one.
    private let launchWindow: TimeInterval = 15
    private var hasShownThisLaunch = false
    private var isStarted = false
    private var launchedAt = Date()

    #if canImport(GoogleMobileAds)
    private var ad: AppOpenAd?
    private var loadTask: Task<AppOpenAd?, Never>?
    #endif

    /// Starts the ads SDK and begins loading the launch ad. Call once, early.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        launchedAt = .now
        #if canImport(GoogleMobileAds)
        guard let unitID = Self.adUnitID else {
            print("[Ads] No app-open ad unit id in Info.plist (CHOSSAppOpenAdUnitID); no launch ad.")
            return
        }
        MobileAds.shared.start(completionHandler: nil)
        loadTask = Task {
            do {
                let ad = try await AppOpenAd.load(with: unitID, request: Request())
                print("[Ads] Launch ad loaded.")
                return ad
            } catch {
                print("[Ads] Launch ad failed to load: \(error.localizedDescription)")
                return nil
            }
        }
        #else
        print("[Ads] GoogleMobileAds isn't linked into the app; no launch ad.")
        #endif
    }

    /// Shows the launch ad if it loads in time. Call when the app's first screen is up.
    func showOnLaunchIfReady() async {
        guard !hasShownThisLaunch else { return }
        hasShownThisLaunch = true
        guard Date.now.timeIntervalSince(launchedAt) < launchWindow else {
            print("[Ads] Main screen appeared too long after launch (sign-in / setup); no launch ad.")
            return
        }
        #if canImport(GoogleMobileAds)
        guard let loadTask else { return }
        // Wait for the ad, but no longer than the timeout.
        let loaded = await withTaskGroup(of: AppOpenAd?.self) { group in
            group.addTask { await loadTask.value }
            group.addTask { [loadTimeout] in
                try? await Task.sleep(for: loadTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let loaded else {
            print("[Ads] Launch ad wasn't ready in time; skipped.")
            return
        }
        guard let root = Self.topViewController() else {
            print("[Ads] Nowhere to show the launch ad from; skipped.")
            return
        }
        ad = loaded
        loaded.fullScreenContentDelegate = self
        loaded.present(from: root)
        #endif
    }

    #if canImport(GoogleMobileAds)
    private static var adUnitID: String? {
        let id = Bundle.main.object(forInfoDictionaryKey: "CHOSSAppOpenAdUnitID") as? String
        guard let id, !id.isEmpty, !id.hasPrefix("$(") else { return nil }
        return id
    }
    #endif

    /// The view controller currently on top, to present the ad from.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

#if canImport(GoogleMobileAds)
extension AppOpenAdManager: FullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.ad = nil }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("[Ads] Launch ad couldn't be shown: \(error.localizedDescription)")
        Task { @MainActor in self.ad = nil }
    }
}
#endif
