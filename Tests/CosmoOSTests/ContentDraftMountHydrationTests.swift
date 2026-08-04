import AppKit
import SwiftUI
import XCTest
@testable import CosmoOS

/// Regression tests for the Aug 3 2026 content-focus data-loss bug: every
/// content document opened blank even though the draft was intact on disk.
///
/// ContentFocusModeView seeds `draftDocument` lazily — the @State starts
/// empty and `loadState()` fills it in the ancestor's `.onAppear`, AFTER the
/// editor's NSView is created. The mount-seed optimization (22cb386a) made
/// CosmoDocumentEditor's own `.onAppear` reuse the serialization built at
/// `makeNSView` time, so the editor kept showing the stale EMPTY seed. The
/// `.onChange(of: document)` for the hydration write was swallowed by
/// `isApplyingExternalUpdate` (its reset is queued async in the same runloop
/// turn). First keystroke then persisted the near-empty mirror over the real
/// draft ("plain text is authoritative"), destroying it.
///
/// These tests host the REAL editor + NSTextView, in both seeding orders.
@MainActor
final class ContentDraftMountHydrationTests: XCTestCase {

    @Observable
    final class DraftModel {
        var hydrated: RichDocument
        init(hydrated: RichDocument) { self.hydrated = hydrated }
    }

    /// Mirrors ContentFocusModeView's shape: the editor mounts against an
    /// empty @State document and an ANCESTOR's `.onAppear` hydrates it —
    /// the same lazy loadState() sequence the content focus mode uses.
    private struct LazyHydrationHost: View {
        let model: DraftModel
        @State private var draftDocument = RichDocument.migrateLegacy("")

        var body: some View {
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    CosmoDocumentEditor(
                        document: $draftDocument,
                        placeholder: "begin writing…"
                    )
                    .frame(minHeight: 400, alignment: .top)
                }
            }
            .onAppear {
                draftDocument = model.hydrated
            }
        }
    }

    /// The notes/idea shape: the document is already real at first render
    /// (eager init seeding) — the mount-seed fast path must keep working.
    private struct EagerHost: View {
        let model: DraftModel
        @State private var draftDocument: RichDocument

        init(model: DraftModel) {
            self.model = model
            _draftDocument = State(initialValue: model.hydrated)
        }

        var body: some View {
            ScrollView(.vertical, showsIndicators: false) {
                CosmoDocumentEditor(
                    document: $draftDocument,
                    placeholder: "begin writing…"
                )
                .frame(minHeight: 400, alignment: .top)
            }
        }
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func textViews(in root: NSView?) -> [CosmoTextView] {
        guard let root else { return [] }
        var found: [CosmoTextView] = []
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            if let tv = view as? CosmoTextView { found.append(tv) }
            stack.append(contentsOf: view.subviews)
        }
        return found
    }

    private func mount<V: View>(_ host: V) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: host)
        hosting.frame = NSRect(x: 0, y: 0, width: 760, height: 600)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        pump(1.0)
        return window
    }

    /// THE BUG: a draft hydrated in an ancestor's .onAppear must reach the
    /// text view. Before the fix the editor kept the stale empty mount seed
    /// and every content document opened blank.
    func testDraftHydratedInAncestorOnAppearReachesTextView() throws {
        let draftText = "The real draft the user wrote yesterday."
        let model = DraftModel(
            hydrated: RichDocument(blocks: [
                RichBlock(kind: .paragraph, inlines: [.text(draftText)])
            ])
        )
        let window = mount(LazyHydrationHost(model: model))
        defer { window.orderOut(nil) }

        let textView = try XCTUnwrap(
            textViews(in: window.contentView).first,
            "expected the editor's text view to mount"
        )
        XCTAssertTrue(
            textView.string.contains(draftText),
            "hydrated draft never reached the editor — it shows " +
            "\"\(textView.string.prefix(80))\" (the opens-blank data-loss bug)"
        )
    }

    /// Guard for the perf path: an eagerly-seeded document (notes/ideas
    /// shape) must still render via the reused mount seed.
    func testEagerlySeededDocumentReachesTextView() throws {
        let draftText = "Eagerly seeded body text."
        let model = DraftModel(
            hydrated: RichDocument(blocks: [
                RichBlock(kind: .paragraph, inlines: [.text(draftText)])
            ])
        )
        let window = mount(EagerHost(model: model))
        defer { window.orderOut(nil) }

        let textView = try XCTUnwrap(
            textViews(in: window.contentView).first,
            "expected the editor's text view to mount"
        )
        XCTAssertTrue(
            textView.string.contains(draftText),
            "eagerly-seeded document must render (mount-seed fast path)"
        )
    }
}
