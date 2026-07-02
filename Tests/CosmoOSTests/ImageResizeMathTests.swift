import AppKit
import XCTest
@testable import CosmoOS

final class ImageResizeMathTests: XCTestCase {

    // MARK: - aspectRatio

    func testAspectRatioGuardsAgainstZero() {
        XCTAssertEqual(ImageResizeMath.aspectRatio(intrinsic: CGSize(width: 0, height: 100)), 1)
        XCTAssertEqual(ImageResizeMath.aspectRatio(intrinsic: CGSize(width: 100, height: 0)), 1)
        XCTAssertEqual(ImageResizeMath.aspectRatio(intrinsic: CGSize(width: 200, height: 100)), 2, accuracy: 0.0001)
    }

    // MARK: - defaultDisplayWidth (reproduces the historical min(680, w) x 420 fit)

    func testDefaultDisplayWidthWideImageCapsAt680() {
        let width = ImageResizeMath.defaultDisplayWidth(intrinsic: CGSize(width: 2000, height: 1000))
        XCTAssertEqual(width, 680, accuracy: 0.5)
    }

    func testDefaultDisplayWidthTallImageRespects420HeightCap() {
        // 1000x2000: width limited so height stays <= 420 -> 210 wide (height 420).
        let width = ImageResizeMath.defaultDisplayWidth(intrinsic: CGSize(width: 1000, height: 2000))
        XCTAssertEqual(width, 210, accuracy: 0.5)
    }

    func testDefaultDisplayWidthSmallImageIsNotUpscaled() {
        let width = ImageResizeMath.defaultDisplayWidth(intrinsic: CGSize(width: 300, height: 200))
        XCTAssertEqual(width, 300, accuracy: 0.5)
    }

    // MARK: - resolvedSize

    func testResolvedSizeUsesDefaultWhenNoDisplayWidth() {
        let size = ImageResizeMath.resolvedSize(displayWidth: nil, intrinsic: CGSize(width: 2000, height: 1000), maxWidth: 680)
        XCTAssertEqual(size.width, 680, accuracy: 0.5)
        XCTAssertEqual(size.height, 340, accuracy: 0.5)
    }

    func testResolvedSizeDerivesHeightFromAspect() {
        let size = ImageResizeMath.resolvedSize(displayWidth: 100, intrinsic: CGSize(width: 200, height: 100), maxWidth: 680)
        XCTAssertEqual(size.width, 100, accuracy: 0.5)
        XCTAssertEqual(size.height, 50, accuracy: 0.5)
    }

    func testResolvedSizeClampsToMaxWidth() {
        let size = ImageResizeMath.resolvedSize(displayWidth: 5000, intrinsic: CGSize(width: 200, height: 100), maxWidth: 680)
        XCTAssertEqual(size.width, 680, accuracy: 0.5)
    }

    func testResolvedSizeClampsToMinWidth() {
        let size = ImageResizeMath.resolvedSize(displayWidth: 10, intrinsic: CGSize(width: 200, height: 100), maxWidth: 680)
        XCTAssertEqual(size.width, ImageResizeMath.minWidth, accuracy: 0.5)
    }

    // MARK: - cornerResizedWidth (proportional / aspect-locked)

    func testCornerResizeRightCornerGrowsOnPositiveDelta() {
        let width = ImageResizeMath.cornerResizedWidth(startWidth: 200, deltaX: 50, growsRight: true, maxWidth: 680)
        XCTAssertEqual(width, 250, accuracy: 0.5)
    }

    func testCornerResizeRightCornerShrinksOnNegativeDelta() {
        let width = ImageResizeMath.cornerResizedWidth(startWidth: 200, deltaX: -50, growsRight: true, maxWidth: 680)
        XCTAssertEqual(width, 150, accuracy: 0.5)
    }

    func testCornerResizeLeftCornerGrowsOnNegativeDelta() {
        let width = ImageResizeMath.cornerResizedWidth(startWidth: 200, deltaX: -50, growsRight: false, maxWidth: 680)
        XCTAssertEqual(width, 250, accuracy: 0.5)
    }

    func testCornerResizeClampsToMaxAndMin() {
        XCTAssertEqual(ImageResizeMath.cornerResizedWidth(startWidth: 650, deltaX: 200, growsRight: true, maxWidth: 680), 680, accuracy: 0.5)
        XCTAssertEqual(ImageResizeMath.cornerResizedWidth(startWidth: 80, deltaX: -200, growsRight: true, maxWidth: 680), ImageResizeMath.minWidth, accuracy: 0.5)
    }

    // MARK: - format

    func testFormatRoundsToIntegers() {
        XCTAssertEqual(ImageResizeMath.format(size: CGSize(width: 648.4, height: 432.1)), "648 × 432")
    }

    // MARK: - serializer round-trip (displayWidth survives attributedString <-> document)

    func testDisplayWidthSurvivesSerializerRoundTrip() throws {
        let nsImage = NSImage(size: NSSize(width: 200, height: 100))
        nsImage.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 100).fill()
        nsImage.unlockFocus()
        let data = try XCTUnwrap(nsImage.tiffRepresentation)
        let saved = try ImageStore.save(data, originalFilename: "resize-test.tiff")
        defer { ImageStore.delete(path: saved.path) }

        var imageRef = RichImageReference(path: saved.path, width: saved.width, height: saved.height)
        imageRef.displayWidth = 320
        let document = RichDocument(blocks: [RichBlock(kind: .image, inlines: [.image(imageRef)])])

        let attributed = RichDocumentSerializer.attributedString(from: document, fontSize: 17)
        let restored = RichDocumentSerializer.document(from: attributed)

        let restoredImage = try XCTUnwrap(
            restored.blocks.compactMap { $0.inlines.compactMap(\.image).first }.first
        )
        XCTAssertEqual(restoredImage.displayWidth ?? -1, 320, accuracy: 0.5)
    }

    func testMissingDisplayWidthDecodesAsNilForBackwardCompatibility() throws {
        // Older documents serialized without the field must decode to displayWidth == nil.
        let legacyJSON = #"{"path":"/tmp/x.png","width":200,"height":100}"#
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(RichImageReference.self, from: data)
        XCTAssertNil(decoded.displayWidth)
        XCTAssertEqual(decoded.width, 200, accuracy: 0.5)
    }
}
