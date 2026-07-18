// CosmoOS/Canvas/FilePortalPDFView.swift
// Live PDF tier of a file portal — PDFKit's PDFView wrapped the CosmoOS way:
// AppKit view behind an NSViewRepresentable, identity-gated updateNSView (the
// document reloads ONLY when the file identity changes, never on layout
// passes), teardown in dismantleNSView. Same lifecycle contract as
// CosmoVideoPlayerView and PDFSourceView.

import PDFKit
import SwiftUI

struct FilePortalPDFView: NSViewRepresentable {
    let fileURL: URL
    let initialPageIndex: Int
    /// Fires when the visible page settles — the portal persists it as view
    /// state so the block reopens on the same page.
    let onPageChanged: (Int) -> Void

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.pageShadowsEnabled = false
        view.backgroundColor = .clear
        view.pageBreakMargins = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        context.coordinator.attach(to: view)
        context.coordinator.load(fileURL: fileURL, into: view, initialPageIndex: initialPageIndex)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.onPageChanged = onPageChanged
        // Identity gate: reload only when the portal points at a new file.
        if context.coordinator.loadedFileURL != fileURL {
            context.coordinator.load(fileURL: fileURL, into: view, initialPageIndex: initialPageIndex)
        }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.detach()
        view.document = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChanged: onPageChanged)
    }

    @MainActor
    final class Coordinator: NSObject {
        var onPageChanged: (Int) -> Void
        private(set) var loadedFileURL: URL?
        private weak var pdfView: PDFView?
        private var pageObserver: NSObjectProtocol?

        init(onPageChanged: @escaping (Int) -> Void) {
            self.onPageChanged = onPageChanged
        }

        func attach(to view: PDFView) {
            pdfView = view
            pageObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged, object: view, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.notifyPageChanged()
                }
            }
        }

        func detach() {
            if let pageObserver {
                NotificationCenter.default.removeObserver(pageObserver)
            }
            pageObserver = nil
            pdfView = nil
        }

        func load(fileURL: URL, into view: PDFView, initialPageIndex: Int) {
            loadedFileURL = fileURL
            // Document decode off-main; a large PDF must not hitch the canvas.
            Task { [weak self, weak view] in
                let document = await Task.detached(priority: .userInitiated) {
                    PDFDocument(url: fileURL)
                }.value
                guard let self, let view, self.loadedFileURL == fileURL else { return }
                view.document = document
                if let document,
                   initialPageIndex > 0, initialPageIndex < document.pageCount,
                   let page = document.page(at: initialPageIndex) {
                    view.go(to: page)
                }
            }
        }

        private func notifyPageChanged() {
            guard let view = pdfView,
                  let document = view.document,
                  let currentPage = view.currentPage else { return }
            onPageChanged(document.index(for: currentPage))
        }
    }
}
