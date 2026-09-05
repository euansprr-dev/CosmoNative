import AppKit
import SwiftUI
import XCTest
@testable import CosmoOS

/// Row-height truth for the note block editor.
///
/// Every block row is its own NSTextView whose SwiftUI height is the
/// `CosmoScrollView.intrinsicHeight` cache. The user-facing failure when
/// that cache goes stale is a "massive gap" — a row whose frame is taller
/// than its text (empty-looking, but the caret lands there on click).
/// These tests drive the REAL editor stack offscreen through the exact
/// keystroke sequences that produced the gap (type → Return, Return
/// mid-paragraph, wrap → Backspace, the "- " alias, a space at the wrap
/// edge) and assert, after every idle settle, that every mounted row's
/// frame AND intrinsic height equal its laid-out text height.
@MainActor
final class BlockRowHeightTruthTests: XCTestCase {

    @Observable
    final class Model {
        var document: RichDocument
        init(document: RichDocument) { self.document = document }
    }

    struct Body: View {
        let model: Model
        let focusCoordinator: BlockFocusCoordinator

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
                    editorTargetID: "test:height-truth",
                    focusCoordinator: focusCoordinator
                )
                .frame(width: 520, alignment: .topLeading)
            }
        }
    }

    private static let wrappingParagraph =
        "The deal came together after months of waiting and a second cold text that finally landed, "
        + "which is the kind of sentence that wraps across several lines at this measure."

    private var window: NSWindow!
    private var model: Model!
    private var focusCoordinator: BlockFocusCoordinator!

    override func tearDown() {
        window?.contentView = nil
        window = nil
        super.tearDown()
    }

    private func mount(_ document: RichDocument) {
        model = Model(document: document)
        focusCoordinator = BlockFocusCoordinator()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 900),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let hosting = NSHostingView(rootView: Body(model: model, focusCoordinator: focusCoordinator))
        hosting.frame = NSRect(x: 0, y: 0, width: 600, height: 900)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        pump(1.0)
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func allTextViews() -> [CosmoTextView] {
        guard let root = window.contentView else { return [] }
        var result: [CosmoTextView] = []
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            if let textView = view as? CosmoTextView { result.append(textView) }
            stack.append(contentsOf: view.subviews)
        }
        return result
    }

    private func textView(for blockID: UUID) -> CosmoTextView? {
        allTextViews().first { $0.rowBlockID == blockID }
    }

    private func focusedTextView() throws -> CosmoTextView {
        try XCTUnwrap(window.firstResponder as? CosmoTextView, "no focused block text view")
    }

    private func focus(_ blockID: UUID, caretAtEnd: Bool = true) throws -> CosmoTextView {
        let view = try XCTUnwrap(textView(for: blockID), "row \(blockID) not mounted")
        window.makeFirstResponder(view)
        let length = (view.string as NSString).length
        view.setSelectedRange(NSRange(location: caretAtEnd ? length : 0, length: 0))
        pump(0.05)
        return view
    }

    private func type(_ text: String, into view: CosmoTextView) {
        for character in text {
            view.insertText(String(character), replacementRange: view.selectedRange())
        }
    }

    private func pressReturn(in view: CosmoTextView) {
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    }

    private func pressBackspace(in view: CosmoTextView, times: Int = 1) {
        for _ in 0..<times {
            view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        }
    }

    /// The truth check. For every mounted row: lay the text out at the row's
    /// current width and compare the laid-out height with both the scroll
    /// view's frame (what SwiftUI is showing) and the intrinsic cache (what
    /// SwiftUI will show next). Tolerance covers sub-pixel positioning.
    private func assertRowHeightsTruthful(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let views = allTextViews()
        XCTAssertFalse(views.isEmpty, "\(label): no rows mounted", file: file, line: line)
        for view in views {
            guard let scrollView = view.enclosingScrollView as? CosmoScrollView,
                  let layoutManager = view.layoutManager,
                  let container = view.textContainer else {
                XCTFail("\(label): row missing scroll view or layout", file: file, line: line)
                continue
            }
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container)
            let expected = ceil(used.height + view.textContainerInset.height * 2)
            let frameHeight = scrollView.frame.height
            let intrinsic = scrollView.intrinsicHeight ?? -1
            let preview = view.string.prefix(28).replacingOccurrences(of: "\n", with: "⏎")
            XCTAssertLessThanOrEqual(
                abs(frameHeight - expected), 2.0,
                "\(label): row \"\(preview)…\" frame \(frameHeight) ≠ text height \(expected) (intrinsic \(intrinsic))",
                file: file, line: line
            )
            XCTAssertLessThanOrEqual(
                abs(intrinsic - expected), 2.0,
                "\(label): row \"\(preview)…\" intrinsic \(intrinsic) ≠ text height \(expected) (frame \(frameHeight))",
                file: file, line: line
            )
        }
    }

    // MARK: - Scenarios

    func testOrdinaryParagraphsUseDocumentRhythmInsteadOfEditorCardMargins() throws {
        let first = RichBlock.paragraph("First paragraph")
        let second = RichBlock.paragraph("Second paragraph")
        mount(RichDocument(blocks: [first, second]))
        let a = try XCTUnwrap(textView(for: first.id))
        let b = try XCTUnwrap(textView(for: second.id))
        let firstFrame = a.convert(a.bounds, to: nil)
        let secondFrame = b.convert(b.bounds, to: nil)
        let gap = abs(firstFrame.midY - secondFrame.midY) - (firstFrame.height + secondFrame.height) / 2
        XCTAssertLessThanOrEqual(gap, 16, "Each paragraph must not bring a separate 32pt padding box")
    }

    func testClickAfterTextSelectionStillHitsNativeWritingSurface() throws {
        let paragraph = RichBlock.paragraph("A paragraph with a formatting selection")
        mount(RichDocument(blocks: [paragraph]))
        let view = try focus(paragraph.id)
        view.setSelectedRange(NSRange(location: 2, length: 9))
        pump(0.3)
        let root = try XCTUnwrap(window.contentView)
        // NSView.hitTest takes its SUPERview's coordinates. NSHostingView
        // is flipped relative to the window frame, so root-local coordinates
        // otherwise probe blank scroll space instead of this paragraph.
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: root.superview)
        let hit = root.hitTest(point)
        XCTAssertTrue(hit === view || hit?.isDescendant(of: view) == true,
                      "Formatting chrome must not consume the next caret click: \(String(describing: hit))")
    }

    func testBlockClickUsesNativeViewCoordinatesWithInsets() throws {
        let view = CosmoTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 160))
        view.font = .monospacedSystemFont(ofSize: 17, weight: .regular)
        view.textContainerInset = NSSize(width: 24, height: 16)
        view.string = "A native insertion point is measured in view coordinates."
        view.isEditable = true
        view.blockRowMode = true
        let controller = BlockDragSelectionController()
        view.blockDragSelectionController = controller
        window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        let point = NSPoint(x: 180, y: 28)
        let expected = view.characterIndexForInsertion(at: point)
        let windowPoint = view.convert(point, to: nil)
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: windowPoint,
            modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 0))
        NSApp.postEvent(up, atStart: true)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: windowPoint,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        view.mouseDown(with: down)
        XCTAssertEqual(view.selectedRange().location, expected)
    }

    func testExternalFormattingKeepsCaretAtUTF16EndOfEmojiText() throws {
        let paragraph = RichBlock.paragraph("A 🧑🏽‍💻 writes café")
        mount(RichDocument(blocks: [paragraph]))
        let view = try focus(paragraph.id)
        let end = (view.string as NSString).length
        model.document.blocks[0].inlines[0].marks = [.bold]
        pump(0.3)
        XCTAssertEqual(view.selectedRange(), NSRange(location: end, length: 0))
    }

    func testMarkedTextDoesNotTriggerMarkdownTransformBeforeCommit() throws {
        let paragraph = RichBlock.paragraph("")
        mount(RichDocument(blocks: [paragraph]))
        let view = try focus(paragraph.id)
        view.setMarkedText("# ", selectedRange: NSRange(location: 2, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        view.didChangeText()
        pump(0.1)
        XCTAssertTrue(view.hasMarkedText())
        XCTAssertEqual(model.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(model.document.blocks.count, 1)
        view.insertText("# ", replacementRange: view.markedRange())
        pump(0.3)
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(model.document.blocks[0].kind, .heading1)
    }

    func testQueuedTypingSyncDoesNotPersistAnUncommittedIMECandidate() throws {
        let paragraph = RichBlock.paragraph("Committed")
        mount(RichDocument(blocks: [paragraph]))
        let view = try focus(paragraph.id)

        // Ordinary typing queues a 250ms attributed-buffer sync. Starting
        // composition before it fires must not let that older job serialize
        // the candidate currently owned by the input method.
        view.insertText(" ", replacementRange: view.selectedRange())
        view.setMarkedText("候補", selectedRange: NSRange(location: 2, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        view.didChangeText()
        pump(0.4)

        XCTAssertTrue(view.hasMarkedText())
        XCTAssertFalse(model.document.plainText.contains("候補"),
                       "A queued sync must leave the unfinished candidate in native storage only")
        XCTAssertEqual(model.document.blocks.count, 1)

        view.insertText("確定", replacementRange: view.markedRange())
        pump(0.4)
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(model.document.plainText, "Committed 確定")
        XCTAssertEqual(model.document.blocks.count, 1)
    }

    /// Type a burst and press Return within the 250ms commit window.
    func testReturnRightAfterTypingLeavesNoGap() throws {
        let paragraph = RichBlock.paragraph(Self.wrappingParagraph)
        mount(RichDocument(blocks: [paragraph, .paragraph("After")]))
        assertRowHeightsTruthful("mounted")

        let view = try focus(paragraph.id)
        type(" and then some more words", into: view)
        pressReturn(in: view)
        pump(0.6)
        assertRowHeightsTruthful("after typing burst + Return")
        XCTAssertEqual(model.document.blocks.count, 3)
    }

    /// Return in the middle of a wrapped paragraph shrinks the before-row.
    func testReturnMidParagraphShrinksTheBeforeRow() throws {
        let paragraph = RichBlock.paragraph(Self.wrappingParagraph)
        mount(RichDocument(blocks: [paragraph, .paragraph("After")]))

        let view = try focus(paragraph.id, caretAtEnd: false)
        view.setSelectedRange(NSRange(location: 30, length: 0))
        pump(0.05)
        pressReturn(in: view)
        pump(0.6)
        assertRowHeightsTruthful("after mid-paragraph Return")
        XCTAssertEqual(model.document.blocks.count, 3)
    }

    /// Type until the row wraps, then Backspace until it un-wraps. The
    /// immediate resize path refuses shrinks; the deferred measure must land.
    func testBackspaceUnwrapShrinksTheRow() throws {
        let bullet = RichBlock(kind: .bulletList, inlines: [.text("Short bullet")])
        mount(RichDocument(blocks: [bullet, .paragraph("After")]))

        let view = try focus(bullet.id)
        let startHeight = (view.enclosingScrollView as? CosmoScrollView)?.frame.height ?? 0
        type(" that keeps going until it has to wrap onto a second line for sure", into: view)
        pump(0.4)
        let wrappedHeight = (view.enclosingScrollView as? CosmoScrollView)?.frame.height ?? 0
        XCTAssertGreaterThan(wrappedHeight, startHeight + 8, "fixture did not wrap; widen the typed text")
        assertRowHeightsTruthful("after wrap")

        pressBackspace(in: view, times: 40)
        pump(0.6)
        assertRowHeightsTruthful("after Backspace un-wrap")
    }

    /// The "- " markdown alias path returns before the usual sync — the
    /// converted bullet row must still measure one line.
    func testDashSpaceAliasRowMeasuresOneLine() throws {
        let empty = RichBlock.paragraph("")
        mount(RichDocument(blocks: [.paragraph("Before"), empty, .paragraph("After")]))

        let view = try focus(empty.id)
        type("-", into: view)
        type(" ", into: view)
        pump(0.6)
        XCTAssertEqual(model.document.blocks[1].kind, .bulletList)
        assertRowHeightsTruthful("after '- ' alias")

        let bulletView = try focusedTextView()
        type("first item", into: bulletView)
        pressReturn(in: bulletView)
        pump(0.6)
        assertRowHeightsTruthful("after typing into alias bullet + Return")
    }

    /// A space typed exactly at the wrap edge of a bullet, then more text.
    func testSpaceAtWrapEdgeOfBulletLeavesNoGap() throws {
        let bullet = RichBlock(kind: .bulletList, inlines: [.text("")])
        mount(RichDocument(blocks: [bullet, .paragraph("After")]))

        let view = try focus(bullet.id)
        let scrollView = try XCTUnwrap(view.enclosingScrollView as? CosmoScrollView)
        let oneLine = scrollView.frame.height
        // Type word by word until the row grows, then back off one word and
        // probe the edge with a space + a word.
        var words = 0
        while scrollView.frame.height <= oneLine + 4, words < 60 {
            type("word\(words) ", into: view)
            pump(0.02)
            words += 1
        }
        XCTAssertGreaterThan(words, 2, "fixture never wrapped")
        pump(0.4)
        assertRowHeightsTruthful("after wrapping bullet")
        pressBackspace(in: view, times: 7)
        pump(0.4)
        type(" ", into: view)
        pump(0.4)
        assertRowHeightsTruthful("after space at wrap edge")
        type("tail", into: view)
        pump(0.4)
        assertRowHeightsTruthful("after word past wrap edge")
        pressReturn(in: view)
        pump(0.6)
        assertRowHeightsTruthful("after Return past wrap edge")
    }

    /// Type until the row wraps, Backspace until it un-wraps (the immediate
    /// path refuses the shrink), then press Return BEFORE the 250ms commit
    /// lands. The split leaves the before-row's block value-identical, so no
    /// external content ever re-measures it — the row must not keep the
    /// wrapped height over one line of text.
    func testUnwrapThenImmediateReturnLeavesNoGap() throws {
        let paragraph = RichBlock.paragraph("Start")
        mount(RichDocument(blocks: [paragraph, .paragraph("After")]))

        let view = try focus(paragraph.id)
        let scrollView = try XCTUnwrap(view.enclosingScrollView as? CosmoScrollView)
        pump(0.4)
        let oneLine = scrollView.frame.height
        let filler = " typed quickly and long enough that this paragraph wraps onto a second line at this width"
        type(filler, into: view)
        pump(0.4)
        XCTAssertGreaterThan(scrollView.frame.height, oneLine + 8, "fixture did not wrap")
        pressBackspace(in: view, times: filler.count)
        // No settle: Return arrives inside the commit window.
        pressReturn(in: view)
        pump(0.6)
        XCTAssertEqual(model.document.blocks.count, 3)
        XCTAssertEqual(model.document.blocks[0].plainInlineText, "Start")
        assertRowHeightsTruthful("after un-wrap + immediate Return")
    }

    /// Same window, replacing a long selection with a short word.
    func testReplaceLongSelectionThenImmediateReturnLeavesNoGap() throws {
        let paragraph = RichBlock.paragraph(Self.wrappingParagraph)
        mount(RichDocument(blocks: [paragraph, .paragraph("After")]))

        let view = try focus(paragraph.id)
        let prefix = RichBlockKind.paragraph.renderedPrefixLength(in: view.string)
        let length = (view.string as NSString).length
        view.setSelectedRange(NSRange(location: prefix, length: length - prefix))
        view.insertText("Short", replacementRange: view.selectedRange())
        pressReturn(in: view)
        pump(0.6)
        XCTAssertEqual(model.document.blocks[0].plainInlineText, "Short")
        assertRowHeightsTruthful("after replace-selection + immediate Return")
    }

    // MARK: - Watchdog mechanics (simulated stale states)

    private func forceStaleHeight(_ view: CosmoTextView, height: CGFloat) throws {
        let scrollView = try XCTUnwrap(view.enclosingScrollView as? CosmoScrollView)
        view.setFrameSize(NSSize(width: view.frame.width, height: height))
        scrollView.intrinsicHeight = height
        scrollView.invalidateIntrinsicContentSize()
        pump(0.3)
        XCTAssertEqual(scrollView.frame.height, height, accuracy: 1, "fixture: SwiftUI did not adopt the stale height")
    }

    /// A row carrying a stale, page-tall intrinsic height (the historical
    /// "split row measured at 1pt width" seed) must heal when the user
    /// types then presses Return at its END — the path where no external
    /// content ever re-measures the row and the deferred settle bails.
    func testStaleTallRowHealsOnReturnAtEnd() throws {
        let bravo = RichBlock.paragraph("Bravo")
        mount(RichDocument(blocks: [.paragraph("Alpha"), bravo, .paragraph("Charlie")]))
        let view = try focus(bravo.id)
        try forceStaleHeight(view, height: 320)

        type("!", into: view)
        pressReturn(in: view) // inside the 250ms commit window
        pump(0.6)
        assertRowHeightsTruthful("stale tall row after type + Return at end")
    }

    /// SwiftUI holding a frame that never followed the intrinsic height (a
    /// dropped invalidation) must heal the next time AppKit re-seats the
    /// row — here because the row above grows and shifts it down.
    func testDroppedInvalidationHealsWhenRowIsReseated() throws {
        let alpha = RichBlock.paragraph("Alpha")
        let bravo = RichBlock.paragraph("Bravo")
        mount(RichDocument(blocks: [alpha, bravo, .paragraph("Charlie")]))
        let bravoView = try XCTUnwrap(textView(for: bravo.id))
        let bravoScroll = try XCTUnwrap(bravoView.enclosingScrollView as? CosmoScrollView)
        let trueHeight = try XCTUnwrap(bravoScroll.intrinsicHeight)
        try forceStaleHeight(bravoView, height: 320)
        // Correct the cache WITHOUT invalidating — SwiftUI keeps the 320 frame.
        bravoScroll.intrinsicHeight = trueHeight
        bravoView.setFrameSize(NSSize(width: bravoView.frame.width, height: trueHeight))
        pump(0.2)
        XCTAssertEqual(bravoScroll.frame.height, 320, accuracy: 1, "fixture: frame should still be stale")

        var frameNotifications = 0
        let token = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: bravoScroll, queue: nil
        ) { _ in frameNotifications += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        let bravoOriginBefore = bravoScroll.convert(bravoScroll.bounds.origin, to: nil)

        let alphaView = try focus(alpha.id)
        type(" grows until this first row wraps onto a second line so the rows below get re-seated", into: alphaView)
        pump(0.6)
        let bravoOriginAfter = bravoScroll.convert(bravoScroll.bounds.origin, to: nil)
        print("[HEIGHTDBG] bravo window-origin before=\(bravoOriginBefore) after=\(bravoOriginAfter) frameNotifications=\(frameNotifications) frame=\(bravoScroll.frame) superview=\(String(describing: bravoScroll.superview.map { Swift.type(of: $0) })) superFrame=\(String(describing: bravoScroll.superview?.frame))")
        if abs(bravoScroll.frame.height - trueHeight) > 2 {
            bravoScroll.invalidateIntrinsicContentSize()
            pump(0.3)
            print("[HEIGHTDBG] after manual invalidate outside layout: frame=\(bravoScroll.frame.height)")
        }
        assertRowHeightsTruthful("after the row above re-seated the stale row")
    }

    /// Seeded random editing session: typing, Return at random places,
    /// Backspace, the "- " alias. After every idle settle every row must
    /// measure true. Deterministic so a failure reproduces.
    func testRandomEditingSessionKeepsRowHeightsTruthful() throws {
        let paragraph = RichBlock.paragraph(Self.wrappingParagraph)
        mount(RichDocument(blocks: [paragraph, .paragraph("After")]))
        _ = try focus(paragraph.id)

        var generator = SeededGenerator(seed: 0xC05A_2026)
        var log: [String] = []
        for step in 0..<40 {
            if !(window.firstResponder is CosmoTextView) {
                // An op moved focus off every row (e.g. deleting the only
                // block). Re-enter the last block and keep going.
                let last = try XCTUnwrap(model.document.blocks.last)
                _ = try focus(last.id)
                log.append("refocus")
            }
            let view = try focusedTextView()
            let length = (view.string as NSString).length
            let roll = Int.random(in: 0..<10, using: &generator)
            switch roll {
            case 0...3:
                let word = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta"][Int.random(in: 0..<6, using: &generator)]
                type(" \(word)", into: view)
                log.append("type \(word)")
            case 4:
                type(" ", into: view)
                log.append("space")
            case 5...6:
                let prefix = RichBlockKind.bulletList.renderedPrefixLength(in: view.string)
                let location = length > prefix ? Int.random(in: prefix...length, using: &generator) : length
                view.setSelectedRange(NSRange(location: location, length: 0))
                pressReturn(in: view)
                log.append("return@\(location)")
            case 7...8:
                pressBackspace(in: view, times: Int.random(in: 1...6, using: &generator))
                log.append("backspace")
            default:
                view.setSelectedRange(NSRange(location: length, length: 0))
                pressReturn(in: view)
                let fresh = try focusedTextView()
                type("-", into: fresh)
                type(" ", into: fresh)
                log.append("return + '- ' alias")
            }
            pump(0.45)
            assertRowHeightsTruthful("step \(step) [\(log.suffix(4).joined(separator: " → "))]")
        }
    }
}

/// Tiny deterministic RNG so the random session reproduces exactly.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
