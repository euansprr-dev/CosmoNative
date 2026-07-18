import AppKit
import SwiftUI
import XCTest
@testable import CosmoOS

/// Performance harness for the note block editor. Mounts the REAL
/// BlockListView stack (per-block NSTextViews and all) inside an offscreen
/// window with a document shaped like a real long note (~196 blocks of
/// paragraphs/headings/bullets, ~85 chars each) and measures the phases the
/// user actually feels: open (mount + settle), and typing (external document
/// edit → update pass).
///
/// Run with timings printed:
///   swift test --filter BlockEditorPerformanceBench
///
/// The assertions are generous ceilings meant to catch order-of-magnitude
/// regressions (the O(N²) storms this guards against were seconds), not to
/// flake on CI noise.
@MainActor
final class BlockEditorPerformanceBenchTests: XCTestCase {

    // MARK: - Fixture

    /// ~196 blocks matching the measured shape of a real long note:
    /// mostly paragraphs (~85 chars), a heading every ~24 blocks, a bullet
    /// every ~9. Deterministic content so runs are comparable.
    static func makeLongNoteDocument(blockCount: Int = 196) -> RichDocument {
        let filler = "the deal came together after months of waiting and a second cold text that finally landed"
        var blocks: [RichBlock] = []
        blocks.reserveCapacity(blockCount)
        for index in 0..<blockCount {
            if index % 24 == 0 {
                blocks.append(RichBlock(
                    kind: .heading2,
                    inlines: [.text("Section \(index / 24): from cold text to cash-flowing asset")]
                ))
            } else if index % 9 == 0 {
                blocks.append(RichBlock(
                    kind: .bulletList,
                    inlines: [.text("Point \(index) — \(filler.prefix(60))")]
                ))
            } else {
                blocks.append(RichBlock(
                    kind: .paragraph,
                    inlines: [.text("Paragraph \(index): \(filler)")]
                ))
            }
        }
        return RichDocument(blocks: blocks)
    }

    @Observable
    final class BenchDocumentModel {
        var document: RichDocument
        init(document: RichDocument) { self.document = document }
    }

    /// Mirrors how NoteFocusModeView hosts the block list (outer ScrollView,
    /// fixed measure width, override ink color, non-internal scrolling).
    struct BenchNoteBody: View {
        let model: BenchDocumentModel
        let focusCoordinator: BlockFocusCoordinator
        var progressive = false

        var body: some View {
            ScrollView(.vertical, showsIndicators: false) {
                BlockListView(
                    document: Binding(
                        get: { model.document },
                        set: { model.document = $0 }
                    ),
                    fontSize: 17,
                    placeholder: "",
                    darkMode: false,
                    overrideTextColor: NSColor.textColor,
                    allowSlashCommands: true,
                    allowMentions: true,
                    allowSelectionMenu: true,
                    allowImages: true,
                    typewriterMode: false,
                    scrollsInternally: false,
                    editorTargetID: "bench:note",
                    focusCoordinator: focusCoordinator,
                    progressiveHydration: progressive
                )
                .frame(width: 700, alignment: .topLeading)
            }
        }
    }

    private struct PhaseTimer {
        let start = ContinuousClock.now
        func elapsedMS() -> Double {
            let duration = ContinuousClock.now - start
            let (seconds, attoseconds) = duration.components
            return Double(seconds) * 1000 + Double(attoseconds) / 1e15
        }
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func countTextViews(in root: NSView?) -> Int {
        guard let root else { return 0 }
        var count = 0
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            if view is CosmoTextView { count += 1 }
            stack.append(contentsOf: view.subviews)
        }
        return count
    }

    // MARK: - Bench

    func testOpenAndTypingCostBreakdown() throws {
        let document = Self.makeLongNoteDocument()

        // Phase 0 — pure serialization cost for every block (what N row
        // editors do on first sync), for scale.
        let serializeTimer = PhaseTimer()
        for block in document.blocks {
            _ = RichDocumentSerializer.attributedString(
                from: RichDocument(blocks: [block]),
                fontSize: 17,
                darkMode: false
            )
        }
        let serializeMS = serializeTimer.elapsedMS()

        // Phase 1 — open: window + hosting view + first layout.
        let model = BenchDocumentModel(document: document)
        let focusCoordinator = BlockFocusCoordinator()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(
            rootView: BenchNoteBody(model: model, focusCoordinator: focusCoordinator)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 760, height: 900)

        let mountTimer = PhaseTimer()
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let firstLayoutMS = mountTimer.elapsedMS()

        // Phase 2 — settle: pump the runloop in slices until the mounted
        // text-view count and content height stop changing (onAppear syncs,
        // deferred measurements, intrinsic-size reconciles).
        var settleMS: Double = 0
        var lastCount = -1
        var lastHeight: CGFloat = -1
        for _ in 0..<120 { // hard cap 12s
            let sliceTimer = PhaseTimer()
            pump(0.1)
            settleMS += sliceTimer.elapsedMS()
            let count = countTextViews(in: window.contentView)
            let height = hosting.fittingSize.height
            if count == lastCount, abs(height - lastHeight) < 0.5 { break }
            lastCount = count
            lastHeight = height
        }

        let mountedTextViews = countTextViews(in: window.contentView)

        // Phase 3 — typing: external single-block edits through the binding
        // (the structural shape of a keystroke reaching the document), each
        // followed by a runloop slice like a frame boundary.
        var typingSamplesMS: [Double] = []
        for i in 0..<8 {
            var updated = model.document
            let targetIndex = min(100, updated.blocks.count - 1)
            var block = updated.blocks[targetIndex]
            block.inlines = [.text(block.plainInlineText + String(UnicodeScalar(65 + i)!))]
            updated.blocks[targetIndex] = block
            let typeTimer = PhaseTimer()
            model.document = updated
            pump(0.03)
            typingSamplesMS.append(typeTimer.elapsedMS())
        }
        let typingWorstMS = typingSamplesMS.max() ?? 0

        print("""
        [BLOCK-BENCH] blocks=\(document.blocks.count) mountedTextViews=\(mountedTextViews)
        [BLOCK-BENCH] serialize-all: \(String(format: "%.1f", serializeMS))ms
        [BLOCK-BENCH] first-layout: \(String(format: "%.1f", firstLayoutMS))ms
        [BLOCK-BENCH] settle: \(String(format: "%.1f", settleMS))ms
        [BLOCK-BENCH] typing slices (30ms pump included): \(typingSamplesMS.map { String(format: "%.1f", $0) }.joined(separator: ", "))
        """)

        // Order-of-magnitude guards (the bugs this catches were seconds).
        XCTAssertGreaterThan(mountedTextViews, 150, "harness failed to mount the block editors")
        XCTAssertLessThan(firstLayoutMS + settleMS, 8_000, "open cost regressed to multi-second territory")
        XCTAssertLessThan(typingWorstMS - 30, 250, "typing update pass regressed to stutter territory")

        window.contentView = nil
    }

    /// The note-focus open path: progressive hydration on. First layout is
    /// the blocking freeze the user feels; hydration then completes across
    /// runloop ticks without blocking input.
    func testProgressiveOpenFirstPaint() throws {
        let model = BenchDocumentModel(document: Self.makeLongNoteDocument())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 900),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let hosting = NSHostingView(
            rootView: BenchNoteBody(
                model: model,
                focusCoordinator: BlockFocusCoordinator(),
                progressive: true
            )
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 760, height: 900)

        let mountTimer = PhaseTimer()
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let firstLayoutMS = mountTimer.elapsedMS()

        // Pump until fully hydrated (every block has a live editor).
        var hydrateMS: Double = 0
        var mounted = 0
        for _ in 0..<200 {
            let slice = PhaseTimer()
            pump(0.05)
            hydrateMS += slice.elapsedMS()
            mounted = countTextViews(in: window.contentView)
            if mounted >= model.document.blocks.count { break }
        }

        print("""
        [BLOCK-BENCH] progressive first-layout: \(String(format: "%.1f", firstLayoutMS))ms
        [BLOCK-BENCH] progressive full-hydration (non-blocking): \(String(format: "%.1f", hydrateMS))ms, mounted=\(mounted)
        """)

        XCTAssertGreaterThanOrEqual(mounted, model.document.blocks.count, "hydration never completed")
        XCTAssertLessThan(firstLayoutMS, 2_000, "progressive first paint regressed")

        window.contentView = nil
    }

    // MARK: - Sampling loops (opt-in via env — for attaching `sample`)

    /// Repeats the mount phase for ~15s so a profiler can be attached.
    /// Enable with BLOCK_BENCH_SAMPLE=mount.
    func testMountSampleLoop() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BLOCK_BENCH_SAMPLE"] == "mount")
        let document = Self.makeLongNoteDocument()
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let model = BenchDocumentModel(document: document)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 900),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            let hosting = NSHostingView(
                rootView: BenchNoteBody(model: model, focusCoordinator: BlockFocusCoordinator())
            )
            hosting.frame = NSRect(x: 0, y: 0, width: 760, height: 900)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            pump(1.5)
            window.contentView = nil
        }
    }

    /// Mounts once, then loops external single-block edits for ~15s.
    /// Enable with BLOCK_BENCH_SAMPLE=typing.
    func testTypingSampleLoop() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BLOCK_BENCH_SAMPLE"] == "typing")
        let model = BenchDocumentModel(document: Self.makeLongNoteDocument())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 900),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let hosting = NSHostingView(
            rootView: BenchNoteBody(model: model, focusCoordinator: BlockFocusCoordinator())
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 760, height: 900)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        pump(3.0) // settle fully first

        let deadline = Date().addingTimeInterval(15)
        var i = 0
        while Date() < deadline {
            var updated = model.document
            let targetIndex = min(100, updated.blocks.count - 1)
            var block = updated.blocks[targetIndex]
            let base = "Paragraph typing target"
            block.inlines = [.text(base + String(repeating: "x", count: i % 40))]
            updated.blocks[targetIndex] = block
            model.document = updated
            pump(0.02)
            i += 1
        }
        window.contentView = nil
    }
}
