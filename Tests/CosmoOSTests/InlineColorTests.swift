// Tests/CosmoOSTests/InlineColorTests.swift
// Inline ink / highlight / link (Notes 3.0 §2.5 + §6): the palette
// guard-twin, the import matcher, the serializer round trip, the command
// bus contract the TextKit coordinator observes, and the quill bar's
// source-level laws (no NSPopover; every swatch goes through the bus).

import SwiftUI
import XCTest
import AppKit
@testable import CosmoOS

@MainActor
final class InlineColorTests: XCTestCase {

    // MARK: - (a) Palette guard-twin

    /// `RichInlineColor.toneInks` is the pure (UI-free, twin-file) mirror of
    /// `NoteInkPalette`. Ids in order and light hexes must agree, or imports
    /// map colours to tones the editor cannot render.
    func testToneInksMirrorNoteInkPalette() {
        XCTAssertEqual(RichInlineColor.toneInks.map(\.id), NoteInkPalette.tones.map(\.id))
        XCTAssertEqual(RichInlineColor.toneIDs, ["moss", "clay", "gilt", "slate", "plum", "rose"])
        for (mirror, tone) in zip(RichInlineColor.toneInks, NoteInkPalette.tones) {
            XCTAssertEqual(
                hex(of: tone.ink(darkMode: false)), mirror.hex.uppercased(),
                "light ink for \(tone.id) drifted from RichInlineColor.toneInks"
            )
        }
    }

    private func hex(of color: Color) -> String {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return "?" }
        let channel = { (value: CGFloat) in Int((value * 255).rounded()) }
        return String(
            format: "%02X%02X%02X",
            channel(srgb.redComponent), channel(srgb.greenComponent), channel(srgb.blueComponent)
        )
    }

    // MARK: - (b) Nearest-tone matching

    func testNearestInkToneMapsSaturatedColoursAndDropsDefaultInk() {
        let red = RichInlineColor.nearestInkTone(for: "#cc0000")
        XCTAssertNotNil(red)
        XCTAssertTrue(["rose", "clay"].contains(red ?? ""), "pure red should land on rose or clay, got \(red ?? "nil")")

        XCTAssertNil(RichInlineColor.nearestInkTone(for: "#000000"), "black is default ink")
        XCTAssertNil(RichInlineColor.nearestInkTone(for: "#222222"), "near-black is default ink")
        XCTAssertNil(RichInlineColor.nearestInkTone(for: "#777777"), "grey is default ink")

        XCTAssertEqual(RichInlineColor.nearestInkTone(for: "rgb(74,124,89)"), "moss")
        XCTAssertEqual(RichInlineColor.nearestInkTone(for: "#5b7288"), "slate")
    }

    func testNearestHighlightToneDropsPaperAndMapsWashes() {
        XCTAssertNil(RichInlineColor.nearestHighlightTone(for: "#ffffff"))
        XCTAssertNil(RichInlineColor.nearestHighlightTone(for: "transparent"))
        XCTAssertNil(RichInlineColor.nearestHighlightTone(for: "#fafafa"))

        XCTAssertEqual(RichInlineColor.nearestHighlightTone(for: "#d9ead3"), "moss")
        XCTAssertEqual(RichInlineColor.nearestHighlightTone(for: "#fff2cc"), "gilt")
    }

    // MARK: - (c) Serializer round trip

    private struct RunShape: Equatable {
        var text: String?
        var marks: Set<RichTextMark>
        var inkID: String?
        var highlightID: String?
        var href: String?

        init(_ node: RichInlineNode) {
            text = node.text
            marks = node.marks
            inkID = node.inkID
            highlightID = node.highlightID
            href = node.href
        }
    }

    private func roundTrip(_ document: RichDocument) -> RichDocument {
        RichDocumentSerializer.document(from: RichDocumentSerializer.attributedString(from: document))
    }

    func testInkHighlightAndLinkSurviveTheAttributedStringRoundTrip() {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [
                .text("Plain "),
                RichInlineNode(
                    kind: .text, text: "coloured", marks: [.bold],
                    inkID: "plum", highlightID: "gilt", href: "https://example.com"
                ),
                .text(" tail")
            ])
        ])

        let parsed = roundTrip(document)
        XCTAssertEqual(parsed.blocks.count, 1)
        XCTAssertEqual(
            parsed.blocks[0].inlines.map(RunShape.init),
            document.blocks[0].inlines.map(RunShape.init)
        )
    }

    func testAdjacentRunsWithDifferentInkDoNotMerge() {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [
                RichInlineNode(kind: .text, text: "moss", inkID: "moss"),
                RichInlineNode(kind: .text, text: "clay", inkID: "clay"),
                RichInlineNode(kind: .text, text: "clay again", inkID: "clay")
            ])
        ])

        let runs = roundTrip(document).blocks[0].inlines.map(RunShape.init)
        XCTAssertEqual(runs.map(\.text), ["moss", "clayclay again"], "same styling merges; different ink never does")
        XCTAssertEqual(runs.map(\.inkID), ["moss", "clay"])
    }

    func testMentionLinkIsNeverReadBackAsHref() {
        let mention = RichMention(entityUUID: "0000-mention", entityID: 42, entityType: .note, titleSnapshot: "Alpha")
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("see "), .mention(mention)])
        ])

        let attributed = RichDocumentSerializer.attributedString(from: document)
        let mentionRange = (attributed.string as NSString).range(of: "@Alpha")
        XCTAssertNotEqual(mentionRange.location, NSNotFound)
        let link = attributed.attribute(.link, at: mentionRange.location, effectiveRange: nil)
        XCTAssertTrue(((link as? String) ?? "").hasPrefix("cosmo://"), "mentions carry a cosmo:// link attribute")

        let parsed = RichDocumentSerializer.document(from: attributed)
        let mentionNode = parsed.blocks[0].inlines.first { $0.kind == .mention }
        XCTAssertNotNil(mentionNode)
        XCTAssertNil(mentionNode?.href, "a cosmo:// mention link must stay a mention, not become href")
        XCTAssertEqual(mentionNode?.mention?.entityUUID, "0000-mention")
    }

    // MARK: - (d) Command bus contract

    private func observeInlineStyle(_ body: () -> Void) -> [[String: Any]] {
        var payloads: [[String: Any]] = []
        let token = NotificationCenter.default.addObserver(
            forName: .applyEditorInlineStyle, object: nil, queue: nil
        ) { note in
            payloads.append((note.userInfo as? [String: Any]) ?? [:])
        }
        body()
        NotificationCenter.default.removeObserver(token)
        return payloads
    }

    func testBusPostsExactlyOneStyleKeyPerNotification() {
        let memory = InlineStyleMemory.shared
        let restore = (ink: memory.lastInkTone, highlight: memory.lastHighlightTone)
        defer {
            memory.lastInkTone = restore.ink
            memory.lastHighlightTone = restore.highlight
        }

        let payloads = observeInlineStyle {
            EditorCommandBus.shared.applyInk("plum", targetEditorID: "note:abc:body")
            EditorCommandBus.shared.applyHighlight(nil)
            EditorCommandBus.shared.applyLink("https://example.com")
            EditorCommandBus.shared.applyLink(nil, targetEditorID: "")
        }

        XCTAssertEqual(payloads.count, 4)
        XCTAssertEqual(payloads[0]["ink"] as? String, "plum")
        XCTAssertEqual(payloads[0]["targetEditorID"] as? String, "note:abc:body")
        XCTAssertNil(payloads[0]["highlight"])
        XCTAssertNil(payloads[0]["link"])

        XCTAssertEqual(payloads[1]["highlight"] as? String, "", "nil clears as an empty string")
        XCTAssertNil(payloads[1]["ink"])
        XCTAssertNil(payloads[1]["targetEditorID"])

        XCTAssertEqual(payloads[2]["link"] as? String, "https://example.com")
        XCTAssertEqual(payloads[3]["link"] as? String, "")
        XCTAssertNil(payloads[3]["targetEditorID"], "an empty target is omitted, never sent as \"\"")

        XCTAssertEqual(memory.lastInkTone, "plum", "a chosen ink is remembered")
    }

    func testToggleLastHighlightPostsTheRememberedTone() {
        let memory = InlineStyleMemory.shared
        let restore = memory.lastHighlightTone
        defer { memory.lastHighlightTone = restore }

        memory.lastHighlightTone = "rose"
        let payloads = observeInlineStyle {
            EditorCommandBus.shared.toggleLastHighlight()
        }
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads[0]["highlight"] as? String, "rose")
        XCTAssertNil(payloads[0]["ink"])
        XCTAssertNil(payloads[0]["link"])
    }

    func testInlineStyleMemoryDefaultsAndRejectsUnknownTones() throws {
        let suite = "InlineColorTests.memory.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = InlineStyleMemory(defaults: defaults)

        XCTAssertEqual(memory.lastHighlightTone, "gilt")
        XCTAssertEqual(memory.lastInkTone, "clay")

        memory.lastHighlightTone = "moss"
        memory.lastInkTone = "slate"
        XCTAssertEqual(defaults.string(forKey: InlineStyleMemory.highlightKey), "moss")
        XCTAssertEqual(defaults.string(forKey: InlineStyleMemory.inkKey), "slate")

        memory.lastHighlightTone = "neon"
        XCTAssertEqual(memory.lastHighlightTone, "moss", "unknown tones never persist")

        defaults.set("bogus", forKey: InlineStyleMemory.inkKey)
        XCTAssertEqual(memory.lastInkTone, "clay", "a foreign stored id falls back to the default")
    }

    func testLinkFieldNormalisation() {
        XCTAssertNil(QuillLinkField.normalized("   "))
        XCTAssertEqual(QuillLinkField.normalized("example.com/path"), "https://example.com/path")
        XCTAssertEqual(QuillLinkField.normalized(" http://example.com "), "http://example.com")
        XCTAssertEqual(QuillLinkField.normalized("mailto:hi@example.com"), "mailto:hi@example.com")
    }

    // MARK: - (e) Quill bar source laws

    private var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            let candidate = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("CosmoOS.xcodeproj").path) {
                return candidate
            }
            url = candidate
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private func source(_ repoRelativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(repoRelativePath), encoding: .utf8)
    }

    /// The colour panel attaches the way the Aa panel does. An NSPopover
    /// would take first responder from the text view and drop the very
    /// selection the colour is meant for (quiet-margins quill-bar law).
    func testQuillBarAttachesColourPanelWithoutNSPopover() throws {
        let bar = try source("Editor/SelectionFormattingMenu.swift")
        XCTAssertFalse(bar.contains("NSPopover"))
        XCTAssertTrue(bar.contains("applyInk("))
        XCTAssertTrue(bar.contains("applyHighlight("))
        XCTAssertTrue(bar.contains("applyLink("))
        XCTAssertTrue(bar.contains(".help(\"Text colour\")"))
        XCTAssertTrue(bar.contains("cosmoMenuChrome(cornerRadius: 14"), "colour panel wears the attached-panel chrome")
    }

    func testBusDeclaresTheInlineStyleNotificationAndShortcutEntry() throws {
        let bus = try source("Editor/EditorCommandBus.swift")
        XCTAssertTrue(bus.contains("static let applyEditorInlineStyle = Notification.Name(\"ApplyEditorInlineStyle\")"))
        XCTAssertTrue(bus.contains("func toggleLastHighlight("))
    }
}
