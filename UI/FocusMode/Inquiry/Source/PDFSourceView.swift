// CosmoOS/UI/FocusMode/Inquiry/Source/PDFSourceView.swift
// The Reading Room: first-class PDFs inside the inquiry source pane. The
// reader follows the same selection contract as the web/internal sources —
// select text and the pane's capture mini-menu appears — so papers and books
// feed the knowledge tree exactly like web pages do. On first open the PDF's
// text is extracted per page into the source atom's body (page-marked), which
// carries it into the Recall index through the normal save hook.
// July 2026

import SwiftUI
import PDFKit

// MARK: - Container (resolve → download → display)

/// Resolves a SourceTab's PDF location: local files display immediately;
/// remote URLs download once into Application Support and are reused after.
struct PDFSourceContainer: View {
    let tab: SourceTab
    @Binding var lastSelectedText: String
    /// Called once after first text extraction so the view model can persist
    /// the page-marked text onto the source atom (→ Recall indexing).
    var onTextExtracted: (String) -> Void = { _ in }

    @State private var localURL: URL?
    @State private var loadFailed: String?

    var body: some View {
        Group {
            if let localURL {
                PDFSourceView(
                    fileURL: localURL,
                    lastSelectedText: $lastSelectedText,
                    onTextExtracted: onTextExtracted
                )
            } else if let loadFailed {
                failureState(loadFailed)
            } else {
                ProgressView("Fetching PDF…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: tab.url) { await resolve() }
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: DS.space10) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 24))
                .foregroundStyle(DS.orange)
            Text("Couldn't open this PDF")
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textPrimary)
            Text(message)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resolve() async {
        guard let raw = tab.url, let url = URL(string: raw) else {
            loadFailed = "The source has no usable location."
            return
        }

        if url.isFileURL {
            localURL = url
            return
        }

        // Remote: cache by URL hash under Application Support.
        do {
            let cached = try PDFSourceStore.cachedLocation(for: url)
            if FileManager.default.fileExists(atPath: cached.path) {
                localURL = cached
                return
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status), !data.isEmpty else {
                loadFailed = "The server answered \(status)."
                return
            }
            guard PDFDocument(data: data) != nil else {
                loadFailed = "The download isn't a readable PDF."
                return
            }
            try data.write(to: cached, options: [.atomic])
            localURL = cached
        } catch {
            loadFailed = error.localizedDescription
        }
    }
}

/// Where downloaded source PDFs live: Application Support/Cosmo/Sources/PDF.
enum PDFSourceStore {
    static func cachedLocation(for url: URL) throws -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cosmo/Sources/PDF", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var hash: UInt64 = 5381
        for byte in url.absoluteString.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return base.appendingPathComponent("\(String(hash, radix: 16)).pdf")
    }

    /// Import a user-picked local PDF (copy, never reference — the original
    /// can move or live on removable storage).
    static func importLocalFile(_ source: URL) throws -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cosmo/Sources/PDF", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let destination = base.appendingPathComponent("\(UUID().uuidString).pdf")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    /// Page-marked plain text for indexing. Pages carry `[[page N]]` markers
    /// so future recall citations can deep-link back into the document.
    static func extractText(from document: PDFDocument, maxCharacters: Int = 400_000) -> String {
        var out = ""
        for index in 0..<document.pageCount {
            guard out.count < maxCharacters else {
                out += "\n\n[[truncated after page \(index)]]"
                break
            }
            guard let page = document.page(at: index),
                  let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { continue }
            out += "\n\n[[page \(index + 1)]]\n\(text)"
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Reader

struct PDFSourceView: NSViewRepresentable {
    let fileURL: URL
    @Binding var lastSelectedText: String
    var onTextExtracted: (String) -> Void = { _ in }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.pageShadowsEnabled = false
        view.backgroundColor = .clear

        if let document = PDFDocument(url: fileURL) {
            view.document = document
            let extracted = PDFSourceStore.extractText(from: document)
            if !extracted.isEmpty {
                let callback = onTextExtracted
                Task { @MainActor in callback(extracted) }
            }
        }

        context.coordinator.observe(view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        if view.document?.documentURL != fileURL, let document = PDFDocument(url: fileURL) {
            view.document = document
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject {
        var parent: PDFSourceView
        private var selectionObserver: NSObjectProtocol?

        init(parent: PDFSourceView) {
            self.parent = parent
        }

        func observe(_ view: PDFView) {
            selectionObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewSelectionChanged,
                object: view,
                queue: .main
            ) { [weak self, weak view] _ in
                guard let self, let view else { return }
                let selected = view.currentSelection?.string?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                // Same contract as SelectableText: a collapsed selection
                // dismisses the pane's capture mini-menu.
                self.parent.lastSelectedText = selected
            }
        }

        deinit {
            if let selectionObserver {
                NotificationCenter.default.removeObserver(selectionObserver)
            }
        }
    }
}
