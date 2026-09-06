import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CosmoOS

/// The filename + type rules behind every image save (twinned on iOS).
struct ImageSaveNamingTests {

    // MARK: - Stem choice

    @Test func storedNameWinsWhenMeaningful() {
        #expect(ImageSaveNaming.stem(preferred: "IMG_1234", title: "Notes") == "IMG_1234")
        #expect(ImageSaveNaming.stem(preferred: "hero-banner", title: nil) == "hero-banner")
    }

    @Test func uuidAndCacheNamesFallThroughToTitle() {
        let uuid = UUID().uuidString
        #expect(ImageSaveNaming.stem(preferred: uuid, title: "Meeting notes") == "Meeting notes")
        #expect(ImageSaveNaming.stem(preferred: "thumb-abc123", title: "Swipe") == "Swipe")
        #expect(ImageSaveNaming.stem(preferred: "ig-img-0f3a9c2b1d", title: "Swipe") == "Swipe")
        #expect(ImageSaveNaming.stem(preferred: "4823950128_3849201", title: "Reel") == "Reel")
        #expect(ImageSaveNaming.stem(preferred: "3f2a9c0e1b7d4a6c", title: "Digest") == "Digest")
    }

    @Test func dateStampWhenNothingElseMeansAnything() {
        let now = Date(timeIntervalSince1970: 1_757_142_312) // 2026-09-06 06:25:12 UTC
        let stem = ImageSaveNaming.stem(preferred: UUID().uuidString, title: "   ", now: now)
        #expect(stem.hasPrefix("Cosmo Image "))
        #expect(stem.contains(" at "))
    }

    // MARK: - Sanitizing

    @Test func sanitizedIsFinderSafe() {
        #expect(ImageSaveNaming.sanitized("A/B: C\nD") == "A-B- C D")
        #expect(ImageSaveNaming.sanitized("  many   spaces  ") == "many spaces")
        #expect(ImageSaveNaming.sanitized("trailing dot.") == "trailing dot")
        #expect(ImageSaveNaming.sanitized(String(repeating: "x", count: 200)).count == 80)
    }

    // MARK: - Unique names

    @Test func uniqueFilenameFollowsSafari() {
        var taken: Set<String> = ["Image.png", "Image-1.png"]
        #expect(ImageSaveNaming.uniqueFilename("Image.png") { taken.contains($0) } == "Image-2.png")
        taken = []
        #expect(ImageSaveNaming.uniqueFilename("Image.png") { taken.contains($0) } == "Image.png")
        taken = ["README"]
        #expect(ImageSaveNaming.uniqueFilename("README") { taken.contains($0) } == "README-1")
    }

    // MARK: - Type sniffing

    @Test func sniffsRealTypeFromBytes() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + pngBody
        #expect(ImageSaveNaming.imageType(of: png) == .png)
        #expect(ImageSaveNaming.imageType(of: Data("not an image".utf8)) == nil)
    }

    /// The smallest valid 1×1 PNG after the signature.
    private var pngBody: Data {
        Data([
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
        ])
    }
}
