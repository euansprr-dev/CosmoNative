import XCTest
@testable import CosmoOS

/// Guards the invariants the swipe thumbnail prewarm rests on:
/// the prefetch band must strictly contain the mount band, and the key a
/// warmer computes must equal the key the card later asks for. If either
/// breaks, prewarming silently warms the wrong thing and cards go grey again.
final class SwipeThumbnailPrewarmTests: XCTestCase {

    // MARK: - Prefetch band

    func testPrefetchBandStrictlyContainsMountBand() {
        // Any offset, including negatives (rubber-band overscroll at the top).
        for offset in stride(from: -800.0, through: 12_000.0, by: 137.0) {
            let mount = SwipeMasonryVisibleBand.quantized(offsetInGrid: offset, viewportHeight: 900)
            let prefetch = SwipeMasonryVisibleBand.prefetchQuantized(offsetInGrid: offset, viewportHeight: 900)

            XCTAssertLessThanOrEqual(
                prefetch.minY, mount.minY,
                "prefetch band must reach at least as far above the mount band (offset \(offset))"
            )
            XCTAssertGreaterThanOrEqual(
                prefetch.maxY, mount.maxY,
                "prefetch band must reach at least as far below the mount band (offset \(offset))"
            )
        }
    }

    func testPrefetchBandReachesFurtherThanMountBandBelowTheFold() {
        let mount = SwipeMasonryVisibleBand.quantized(offsetInGrid: 2_000, viewportHeight: 900)
        let prefetch = SwipeMasonryVisibleBand.prefetchQuantized(offsetInGrid: 2_000, viewportHeight: 900)
        // Warming has to lead the mount window, not merely match it — otherwise
        // the image request still starts at mount time and a flick outruns it.
        XCTAssertGreaterThan(prefetch.maxY, mount.maxY)
        XCTAssertLessThan(prefetch.minY, mount.minY)
    }

    func testBothBandsQuantizeToTheScrollBucket() {
        let bucket = SwipeMasonryVisibleBand.bucket
        for offset in stride(from: 0.0, through: 4_000.0, by: 61.0) {
            let bands = SwipeMasonryScrollBands.quantized(offsetInGrid: offset, viewportHeight: 740)
            for band in [bands.mount, bands.prefetch] {
                XCTAssertEqual(band.minY.truncatingRemainder(dividingBy: bucket), 0, accuracy: 0.0001)
                XCTAssertEqual(band.maxY.truncatingRemainder(dividingBy: bucket), 0, accuracy: 0.0001)
            }
        }
    }

    /// Scrolling within one bucket must not churn state — the bands feed
    /// `onGeometryChange`, which fires per frame and is gated purely on equality.
    func testBandsAreStableWithinABucket() {
        let first = SwipeMasonryScrollBands.quantized(offsetInGrid: 1_000, viewportHeight: 800)
        let nudged = SwipeMasonryScrollBands.quantized(offsetInGrid: 1_012, viewportHeight: 800)
        XCTAssertEqual(first, nudged)
    }

    func testEverythingBandCoversAnyFrame() {
        let bands = SwipeMasonryScrollBands.everything
        let frame = CGRect(x: 0, y: 48_000, width: 208, height: 260)
        XCTAssertTrue(bands.mount.intersects(frame))
        XCTAssertTrue(bands.prefetch.intersects(frame))
    }

    // MARK: - Cache key agreement

    /// The premise of the whole prewarm: the warmer and the card must derive
    /// the SAME key from the same model, and an expiring CDN signature must not
    /// fragment it.
    func testExpiringQueryParametersDoNotChangeTheCacheKey() {
        let cache = ThumbnailCacheService.shared
        let fresh = URL(string: "https://scontent.cdninstagram.com/v/t51/abc123.jpg?stp=dst-jpg&_nc_ht=x&oe=6789")!
        let rotated = URL(string: "https://scontent.cdninstagram.com/v/t51/abc123.jpg?stp=dst-jpg&_nc_ht=y&oe=9999")!

        XCTAssertEqual(
            cache.cacheKey(for: fresh, stableKey: nil),
            cache.cacheKey(for: rotated, stableKey: nil)
        )
    }

    func testExplicitStableKeyWinsOverUrlDerivation() {
        let cache = ThumbnailCacheService.shared
        let url = URL(string: "https://scontent.cdninstagram.com/v/t51/abc123.jpg?oe=6789")!
        XCTAssertEqual(cache.cacheKey(for: url, stableKey: "ig-carousel-CxYz-0"), "ig-carousel-CxYz-0")
        // Empty is not a key — it must fall through to derivation.
        XCTAssertNotEqual(cache.cacheKey(for: url, stableKey: ""), "")
    }

    func testYouTubeThumbnailsShareOneKeyAcrossUrlShapes() {
        let cache = ThumbnailCacheService.shared
        let watch = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        let short = URL(string: "https://youtu.be/dQw4w9WgXcQ")!
        XCTAssertEqual(cache.cacheKey(for: watch, stableKey: nil), "yt-dQw4w9WgXcQ")
        XCTAssertEqual(cache.cacheKey(for: short, stableKey: nil), "yt-dQw4w9WgXcQ")
    }

    func testDistinctPathsGetDistinctKeys() {
        let cache = ThumbnailCacheService.shared
        let first = URL(string: "https://scontent.cdninstagram.com/v/t51/abc123.jpg")!
        let second = URL(string: "https://scontent.cdninstagram.com/v/t51/def456.jpg")!
        XCTAssertNotEqual(cache.cacheKey(for: first, stableKey: nil), cache.cacheKey(for: second, stableKey: nil))
    }

    // MARK: - Legacy fallback guard

    /// The cheap string guard must admit exactly the keys `fallbackImage` can
    /// resolve — a narrower guard would drop real legacy thumbnails, a wider
    /// one puts a pointless detached decode back on every cache miss.
    func testLegacyFallbackGuardAdmitsOnlyFirstCarouselSlideKeys() {
        XCTAssertTrue(InstagramCarouselImageCache.mayHaveLegacyFallback(forStableKey: "ig-carousel-CxYz123-0"))

        for rejected in [
            "ig-carousel-CxYz123-1",   // not slide 0
            "ig-carousel-CxYz123-10",  // trailing digit is not the index
            "yt-dQw4w9WgXcQ",
            "swipe-stage-2E1B0",
            "ig-img-deadbeef",
            "ig-carousel--0",          // empty shortcode
            ""
        ] {
            XCTAssertNil(
                InstagramCarouselImageCache.fallbackImage(forStableKey: rejected),
                "\(rejected) must not resolve a legacy fallback"
            )
        }

        // Every key the guard rejects must also be unresolvable — the guard may
        // never hide a file that exists.
        for rejected in ["ig-carousel-CxYz123-1", "yt-dQw4w9WgXcQ", "swipe-stage-2E1B0", ""] {
            XCTAssertFalse(InstagramCarouselImageCache.mayHaveLegacyFallback(forStableKey: rejected))
        }
    }
}
