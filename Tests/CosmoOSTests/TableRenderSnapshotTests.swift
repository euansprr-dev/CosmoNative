import AppKit
import SwiftUI
import XCTest
@testable import CosmoOS

/// Renders a note with a table, a section and inked text through the REAL
/// block editor offscreen and writes PNGs to the scratch directory named by
/// `COSMO_SNAPSHOT_DIR` — the eyeball pass for surfaces that cannot be
/// screenshotted while the machine is locked. Skipped unless the variable
/// is set, so the suite stays hermetic.
@MainActor
final class TableRenderSnapshotTests: XCTestCase {

    @Observable
    final class Model {
        var document: RichDocument
        init(document: RichDocument) { self.document = document }
    }

    struct Body: View {
        let model: Model
        let focusCoordinator: BlockFocusCoordinator
        let darkMode: Bool

        var body: some View {
            ScrollView(.vertical, showsIndicators: false) {
                BlockListView(
                    document: Binding(get: { model.document }, set: { model.document = $0 }),
                    fontSize: 17,
                    placeholder: "",
                    darkMode: darkMode,
                    overrideTextColor: darkMode ? NSColor.white : nil,
                    allowSlashCommands: true,
                    allowMentions: true,
                    allowSelectionMenu: true,
                    allowImages: true,
                    typewriterMode: false,
                    scrollsInternally: false,
                    editorTargetID: "test:snapshot",
                    focusCoordinator: focusCoordinator
                )
                .frame(width: 640, alignment: .topLeading)
                .padding(24)
            }
            .background(darkMode ? Color(red: 0.11, green: 0.11, blue: 0.12) : DS.bg)
        }
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func sampleDocument() -> RichDocument {
        var table = RichTable(strings: [
            ["Hook", "Why it works", "Score"],
            ["Specificity beats cleverness", "Names a tension the reader already feels", "9"],
            ["One idea per piece", "The reader lends you two seconds", "8"],
            ["Open on motion", "A verb in the first beat", "7"],
        ], hasHeaderRow: true)
        table.columns[2].alignment = .trailing
        table.columns[1].weight = 1.6
        table.rows[1].cells[0].toneID = "moss"
        table.rows[3].cells[2].inlines = [RichInlineNode(kind: .text, text: "7", marks: [.bold], inkID: "clay")]
        return RichDocument(blocks: [
            RichBlock(kind: .heading2, inlines: [.text("Hooks, compared")]),
            RichBlock.paragraph("A comparison table in the note's own voice."),
            .table(table),
            RichBlock.section(
                title: "Section 1 — Change begins with clarity",
                style: RichSectionStyle(toneID: "plum", appearance: .wash, icon: "sparkles"),
                children: [
                    .paragraph("Name the tension before the promise."),
                    RichBlock(kind: .bulletList, inlines: [
                        .text("Ink and "),
                        RichInlineNode(kind: .text, text: "highlight", highlightID: "gilt"),
                        .text(" travel with the text — "),
                        RichInlineNode(kind: .text, text: "plum ink", marks: [.bold], inkID: "plum"),
                        .text("."),
                    ]),
                ]
            ),
            RichBlock.section(
                title: "Outline box",
                style: RichSectionStyle(toneID: "slate", appearance: .bar, icon: nil),
                children: [.paragraph("A bar-style section.")]
            ),
        ])
    }

    func testRenderTableAndSectionSnapshots() throws {
        guard let directory = ProcessInfo.processInfo.environment["COSMO_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set COSMO_SNAPSHOT_DIR to render snapshots")
        }
        for darkMode in [false, true] {
            let model = Model(document: Self.sampleDocument())
            let coordinator = BlockFocusCoordinator()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 760),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            let hosting = NSHostingView(rootView: Body(model: model, focusCoordinator: coordinator, darkMode: darkMode))
            hosting.frame = NSRect(x: 0, y: 0, width: 700, height: 760)
            window.contentView = hosting
            window.appearance = NSAppearance(named: darkMode ? .darkAqua : .aqua)
            hosting.layoutSubtreeIfNeeded()
            pump(1.5)

            let bounds = hosting.bounds
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else {
                XCTFail("no bitmap rep"); continue
            }
            hosting.cacheDisplay(in: bounds, to: rep)
            let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory).appendingPathComponent("table-section-\(darkMode ? "dark" : "light").png")
            try data.write(to: url)
            print("[SNAPSHOT] wrote \(url.path)")
            window.contentView = nil
        }
    }
}
