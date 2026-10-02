import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// Sponsored posts in the home feed (Google AdMob native ads): one after every
/// `FeedAds.interval` posts, styled like a post and labelled "Sponsored". A slot whose ad hasn't
/// loaded (or never does, e.g. with an ad blocker) takes up no space, so the feed never waits.
///
/// The ad unit comes from the ADMOB_FEED_NATIVE_AD_UNIT_ID build setting (CHOSS-Info.plist);
/// Debug builds always use Google's test unit.
enum FeedAds {
    /// Posts between ads.
    static let interval = 5
}

#if canImport(GoogleMobileAds)
/// Loads native ads a few at a time and hands each feed slot its own ad, kept for the session so
/// scrolling back shows the same one.
@MainActor
@Observable
final class FeedAdStore: NSObject {
    static let shared = FeedAdStore()

    /// slot number → its ad.
    private(set) var adsBySlot: [Int: NativeAd] = [:]
    @ObservationIgnored private var spare: [NativeAd] = []
    @ObservationIgnored private var waitingSlots: [Int] = []
    @ObservationIgnored private var loader: AdLoader?
    @ObservationIgnored private var failures = 0

    /// Google's published test unit for native ads.
    private static let testAdUnitID = "ca-app-pub-3940256099942544/3986624511"

    private static var adUnitID: String? {
        #if DEBUG
        return testAdUnitID
        #else
        let raw = Bundle.main.object(forInfoDictionaryKey: "CHOSSFeedNativeAdUnitID") as? String
        let id = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id, !id.isEmpty, !id.hasPrefix("$(") else { return nil }
        return id
        #endif
    }

    func ad(forSlot slot: Int) -> NativeAd? { adsBySlot[slot] }

    /// A slot came into view: give it an ad (now if one is spare, else when the next loads).
    func request(slot: Int) {
        guard adsBySlot[slot] == nil, !waitingSlots.contains(slot) else { return }
        if !spare.isEmpty {
            adsBySlot[slot] = spare.removeFirst()
        } else {
            waitingSlots.append(slot)
        }
        loadMoreIfNeeded()
    }

    private func loadMoreIfNeeded() {
        // Keep one spare ready; stop retrying after a few failures (ad blocker, no fill…).
        guard loader == nil, !waitingSlots.isEmpty || spare.isEmpty, failures < 3,
              let unitID = Self.adUnitID else { return }
        let options = MultipleAdsAdLoaderOptions()
        options.numberOfAds = 3
        let loader = AdLoader(adUnitID: unitID, rootViewController: nil, adTypes: [.native], options: [options])
        loader.delegate = self
        self.loader = loader
        loader.load(Request())
    }

    private func received(_ ad: NativeAd) {
        failures = 0
        if !waitingSlots.isEmpty {
            adsBySlot[waitingSlots.removeFirst()] = ad
        } else {
            spare.append(ad)
        }
    }

    private func finished() {
        loader = nil
        if !waitingSlots.isEmpty { loadMoreIfNeeded() }
    }

    private func failed(_ error: Error) {
        failures += 1
        print("[Ads] Feed ad failed to load: \(error.localizedDescription)")
        loader = nil
        if !waitingSlots.isEmpty { loadMoreIfNeeded() }
    }
}

extension FeedAdStore: NativeAdLoaderDelegate {
    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor in self.received(nativeAd) }
    }

    nonisolated func adLoaderDidFinishLoading(_ adLoader: AdLoader) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        Task { @MainActor in self.failed(error) }
    }
}
#endif

/// A sponsored post in the feed, followed by a divider. Empty until (unless) its ad loads.
struct FeedAdSlot: View {
    /// 0 for the first ad in the feed, 1 for the second…
    let slot: Int

    var body: some View {
        #if canImport(GoogleMobileAds)
        Group {
            if let ad = FeedAdStore.shared.ad(forSlot: slot) {
                VStack(spacing: 12) {
                    NativeAdCard(ad: ad)
                    Divider()
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .onAppear { FeedAdStore.shared.request(slot: slot) }
        #else
        EmptyView()
        #endif
    }
}

#if canImport(GoogleMobileAds)
/// Google's native ad view laid out like a post: advertiser row, media, text, button.
/// Google draws its AdChoices icon in a corner; the "Sponsored" label is required.
private struct NativeAdCard: UIViewRepresentable {
    let ad: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()

        let icon = UIImageView()
        icon.contentMode = .scaleAspectFill
        icon.clipsToBounds = true
        icon.layer.cornerRadius = 8
        icon.backgroundColor = .secondarySystemFill
        icon.widthAnchor.constraint(equalToConstant: 36).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let headline = UILabel()
        headline.font = .preferredFont(forTextStyle: .subheadline).bold
        headline.numberOfLines = 1

        let sponsored = UILabel()
        sponsored.font = .preferredFont(forTextStyle: .caption1)
        sponsored.textColor = .secondaryLabel

        let titles = UIStackView(arrangedSubviews: [headline, sponsored])
        titles.axis = .vertical
        titles.spacing = 1

        let header = UIStackView(arrangedSubviews: [icon, titles])
        header.spacing = 10
        header.alignment = .center
        header.isLayoutMarginsRelativeArrangement = true
        header.directionalLayoutMargins = .init(top: 0, leading: 16, bottom: 0, trailing: 16)

        let media = MediaView()
        media.contentMode = .scaleAspectFit
        media.backgroundColor = .black
        let aspect = ad.mediaContent.aspectRatio > 0 ? ad.mediaContent.aspectRatio : 16.0 / 9.0
        let mediaHeight = min(UIScreen.main.bounds.width / aspect, SendVideoPlayer.height)
        media.heightAnchor.constraint(equalToConstant: mediaHeight).isActive = true

        let body = UILabel()
        body.font = .preferredFont(forTextStyle: .subheadline)
        body.numberOfLines = 2

        let button = UIButton(configuration: .filled())
        button.configuration?.baseBackgroundColor = UIColor(named: "AccentColor")
        button.configuration?.baseForegroundColor = UIColor(named: "OnAccent")
        button.configuration?.cornerStyle = .medium
        // Google handles the tap on the whole ad; the button is only a label.
        button.isUserInteractionEnabled = false

        let footer = UIStackView(arrangedSubviews: [body, button])
        footer.axis = .vertical
        footer.spacing = 10
        footer.isLayoutMarginsRelativeArrangement = true
        footer.directionalLayoutMargins = .init(top: 0, leading: 16, bottom: 0, trailing: 16)

        let stack = UIStackView(arrangedSubviews: [header, media, footer])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: adView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: adView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
        ])

        adView.iconView = icon
        adView.headlineView = headline
        adView.advertiserView = sponsored
        adView.mediaView = media
        adView.bodyView = body
        adView.callToActionView = button
        configure(adView)
        return adView
    }

    func updateUIView(_ adView: NativeAdView, context: Context) {
        if adView.nativeAd !== ad { configure(adView) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NativeAdView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let size = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: size.height)
    }

    private func configure(_ adView: NativeAdView) {
        (adView.headlineView as? UILabel)?.text = ad.headline
        (adView.advertiserView as? UILabel)?.text = ["Sponsored", ad.advertiser].compactMap { $0 }.joined(separator: " · ")
        (adView.iconView as? UIImageView)?.image = ad.icon?.image
        adView.iconView?.isHidden = ad.icon == nil
        adView.mediaView?.mediaContent = ad.mediaContent
        (adView.bodyView as? UILabel)?.text = ad.body
        adView.bodyView?.isHidden = ad.body == nil
        (adView.callToActionView as? UIButton)?.configuration?.title = ad.callToAction ?? "Learn more"
        // Last, so the SDK sees the filled-in views (it tracks impressions and clicks on them).
        adView.nativeAd = ad
    }
}

private extension UIFont {
    var bold: UIFont {
        fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: 0) } ?? self
    }
}
#endif
