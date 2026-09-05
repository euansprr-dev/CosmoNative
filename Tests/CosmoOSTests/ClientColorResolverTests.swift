// Tests/CosmoOSTests/ClientColorResolverTests.swift
// A pinned swatch beats the hash; no pin (or a malformed one) falls back
// to the deterministic colour `DS.clientColor` has always produced.

import XCTest
import SwiftUI
import AppKit
@testable import CosmoOS

final class ClientColorResolverTests: XCTestCase {

    private let uuid = "client-color-test-\(UUID().uuidString)"

    override func tearDown() {
        ClientColorResolver.shared.refresh(with: [])
        super.tearDown()
    }

    // MARK: - Override map

    func testRefreshWithEntriesInstallsNormalisedOverrides() {
        let resolver = ClientColorResolver()
        resolver.refresh(with: [
            (uuid: "a", colorHex: "#2e86ab"),
            (uuid: "b", colorHex: nil),
            (uuid: "c", colorHex: "not-a-colour"),
            (uuid: "d", colorHex: "  A23B72 "),
        ])
        XCTAssertEqual(resolver.hex(for: "a"), "2E86AB")
        XCTAssertNil(resolver.hex(for: "b"))
        XCTAssertNil(resolver.hex(for: "c"), "garbage never becomes a colour")
        XCTAssertEqual(resolver.hex(for: "d"), "A23B72")
        XCTAssertNil(resolver.hex(for: "unknown"))
    }

    func testRefreshReplacesThePreviousMap() {
        let resolver = ClientColorResolver()
        resolver.refresh(with: [(uuid: "a", colorHex: "2E86AB")])
        resolver.refresh(with: [(uuid: "b", colorHex: "A23B72")])
        XCTAssertNil(resolver.hex(for: "a"), "a full pass is the truth — stale pins do not linger")
        XCTAssertEqual(resolver.hex(for: "b"), "A23B72")
    }

    func testHexGrammar() {
        XCTAssertEqual(ClientColorResolver.normalizedHex("#5e8c61"), "5E8C61")
        XCTAssertEqual(ClientColorResolver.normalizedHex("5E8C61"), "5E8C61")
        XCTAssertNil(ClientColorResolver.normalizedHex("5E8C6"))
        XCTAssertNil(ClientColorResolver.normalizedHex("#5E8C61FF"))
        XCTAssertNil(ClientColorResolver.normalizedHex("GGGGGG"))
        XCTAssertNil(ClientColorResolver.normalizedHex(""))
        XCTAssertNil(ClientColorResolver.normalizedHex(nil))
    }

    // MARK: - DS.clientColor(for:)

    func testOverrideBeatsHashAndNilFallsBack() {
        let hashed = components(DS.hashedClientColor(for: uuid))

        ClientColorResolver.shared.refresh(with: [(uuid: uuid, colorHex: "2E86AB")])
        XCTAssertEqual(components(DS.clientColor(for: uuid)), components(Color(hex: "2E86AB")))

        ClientColorResolver.shared.refresh(with: [(uuid: uuid, colorHex: nil)])
        XCTAssertEqual(components(DS.clientColor(for: uuid)), hashed, "no pin → the deterministic hash colour")
    }

    func testHashFallbackIsDeterministicAndInPalette() {
        let first = components(DS.hashedClientColor(for: "stable-uuid"))
        let second = components(DS.hashedClientColor(for: "stable-uuid"))
        XCTAssertEqual(first, second)
        XCTAssertTrue(DS.clientPalette.map(components).contains(first))
        XCTAssertEqual(DS.clientPalette.count, DS.clientPaletteHex.count)
    }

    private func components(_ color: Color) -> [Int] {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return [] }
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int(($0 * 255).rounded()) }
    }
}
