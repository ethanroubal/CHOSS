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
/// Loads native ads ahead of time and hands each feed slot its own ad, kept for the session so
/// scrolling back shows the same one.
///
/// Ads are loaded before they're needed (when the feed opens, then topping up), and a slot gets
/// its ad a few posts before you reach it. A slot that reaches the screen without an ad stays
/// empty for the session: an ad never pops in under your finger and shifts the feed.
@MainActor
@Observable
final class FeedAdStore: NSObject {
    static let shared = FeedAdStore()

    /// slot number → its ad.
    private(set) var adsBySlot: [Int: NativeAd] = [:]
    /// Loaded ads not given to a slot yet.
    @ObservationIgnored private var spare: [NativeAd] = []
    /// Slots coming up that still need an ad (given one as soon as it loads).
    @ObservationIgnored private var pendingSlots: [Int] = []
    /// Slots that reached the screen without an ad: left empty.
    @ObservationIgnored private var skippedSlots: Set<Int> = []
    @ObservationIgnored private var loader: AdLoader?
    @ObservationIgnored private var failures = 0
    /// Ads kept loaded and ready.
    private let spareTarget = 2

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

    /// Starts loading ads so the first slots have one ready (call when the feed opens).
    func preload() {
        loadMoreIfNeeded()
    }

    /// The feed is a few posts away from this slot: give it an ad now if one is ready, otherwise
    /// as soon as one loads (while it's still off screen).
    func prepare(slot: Int) {
        guard adsBySlot[slot] == nil, !skippedSlots.contains(slot), !pendingSlots.contains(slot) else { return }
        if !spare.isEmpty {
            adsBySlot[slot] = spare.removeFirst()
        } else {
            pendingSlots.append(slot)
            pendingSlots.sort()
        }
        loadMoreIfNeeded()
    }

    /// The slot has scrolled onto the screen. Without an ad by now, it stays empty.
    func slotReachedScreen(_ slot: Int) {
        guard adsBySlot[slot] == nil else { return }
        skippedSlots.insert(slot)
        pendingSlots.removeAll { $0 == slot }
    }

    private func loadMoreIfNeeded() {
        // Keep a couple of ads ready; stop retrying after a few failures (ad blocker, no fill…).
        guard loader == nil, spare.count < spareTarget || !pendingSlots.isEmpty, failures < 3,
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
        if !pendingSlots.isEmpty {
            adsBySlot[pendingSlots.removeFirst()] = ad
        } else {
            spare.append(ad)
        }
    }

    private func finished() {
        loader = nil
        loadMoreIfNeeded()
    }

    private func failed(_ error: Error) {
        failures += 1
        print("[Ads] Feed ad failed to load: \(error.localizedDescription)")
        loader = nil
        loadMoreIfNeeded()
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

/// A sponsored post in the feed, followed by a divider. Its ad is usually ready before it's
/// reached (see `FeedAdStore`); if not, the slot takes no space.
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
        // The lazy feed builds rows a little ahead of the screen: ask for an ad then too.
        .onAppear { FeedAdStore.shared.prepare(slot: slot) }
        // Once its top is on screen, it keeps whatever it has (no late pop-in).
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.frame(in: .global).minY < UIScreen.main.bounds.maxY
        } action: { onScreen in
            if onScreen { FeedAdStore.shared.slotReachedScreen(slot) }
        }
        #else
        EmptyView()
        #endif
    }
}

/// Feed hooks for loading ads early: when the feed opens, and a few posts before each slot.
extension FeedAds {
    /// How many posts ahead of a slot its ad is requested.
    static let lookahead = 3

    @MainActor static func feedAppeared() {
        #if canImport(GoogleMobileAds)
        FeedAdStore.shared.preload()
        #endif
    }

    /// Call when the post at `index` appears.
    @MainActor static func postAppeared(at index: Int) {
        #if canImport(GoogleMobileAds)
        // The next slot comes after post number (slot + 1) * interval.
        let nextSlot = (index + lookahead) / interval - 1
        if nextSlot >= 0 { FeedAdStore.shared.prepare(slot: nextSlot) }
        #endif
    }
}

#if canImport(GoogleMobileAds)
/// Google's native ad view laid out like a post: advertiser row, media, text, button.
/// Google draws its AdChoices icon in a corner; the "Sponsored" badge is required. Asset views
/// show the ad's own text exactly, and are hidden when the ad has none.
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

        // The ad badge is our own label, not an asset view: asset views must show exactly the
        // ad's text (Google's native ad validator flags anything added to them).
        let badge = UILabel()
        badge.text = "Sponsored"
        badge.font = .preferredFont(forTextStyle: .caption1).bold
        badge.textColor = .secondaryLabel
        badge.setContentHuggingPriority(.required, for: .horizontal)

        let advertiser = UILabel()
        advertiser.font = .preferredFont(forTextStyle: .caption1)
        advertiser.textColor = .secondaryLabel
        advertiser.numberOfLines = 1

        let subtitle = UIStackView(arrangedSubviews: [badge, advertiser])
        subtitle.spacing = 6

        let titles = UIStackView(arrangedSubviews: [headline, subtitle])
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
            // A little room top and bottom so rounding never puts an asset on (or past) the edge.
            stack.topAnchor.constraint(equalTo: adView.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
        ])

        adView.iconView = icon
        adView.headlineView = headline
        adView.advertiserView = advertiser
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
        let width = proposal.width.flatMap { $0 > 0 ? $0 : nil } ?? UIScreen.main.bounds.width
        // Tell the wrapping labels how wide they'll be, so a two-line description is measured
        // as two lines. If the card were sized too short, its contents would spill past the
        // ad view's edges, which Google's validator reports ("assets outside native ad view").
        let textWidth = width - 32
        (uiView.bodyView as? UILabel)?.preferredMaxLayoutWidth = textWidth
        (uiView.headlineView as? UILabel)?.preferredMaxLayoutWidth = textWidth - 46  // minus the icon
        let size = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: ceil(size.height))
    }

    private func configure(_ adView: NativeAdView) {
        (adView.headlineView as? UILabel)?.text = ad.headline
        (adView.advertiserView as? UILabel)?.text = ad.advertiser
        adView.advertiserView?.isHidden = ad.advertiser == nil
        (adView.iconView as? UIImageView)?.image = ad.icon?.image
        adView.iconView?.isHidden = ad.icon == nil
        adView.mediaView?.mediaContent = ad.mediaContent
        (adView.bodyView as? UILabel)?.text = ad.body
        adView.bodyView?.isHidden = ad.body == nil
        (adView.callToActionView as? UIButton)?.configuration?.title = ad.callToAction
        adView.callToActionView?.isHidden = ad.callToAction == nil
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
