// CosmoOS/UI/FocusMode/Inquiry/Source/PDFSourceView.swift
// The Reading Room: first-class PDFs inside the inquiry source pane (and
// reused by Research focus mode). The reader follows the same selection
// contract as the web/internal sources — select text and the pane's capture
// mini-menu appears — and captures leave PERSISTENT highlights: page-space
// quads stored in pdf_highlights, rehydrated as annotations on every open.
// First open extracts page-marked text into the source atom's body (with a
// Vision OCR fallback for scanned documents), which carries it into the
// Recall index so citations can say "p. 12".
// July 2026

import SwiftUI
import PDFKit

// MARK: - Selection detail (page + quads for persistent highlights)

struct PDFSelectionDetail: Equatable {
    let pageIndex: Int
    let quads: [CGRect]
    let text: String
}

// MARK: - Reader controller (search + page jumps, owned by the chrome)

@MainActor @Observable
final class PDFReaderController {
    weak var pdfView: PDFView?

    private(set) var matchCount = 0
    private(set) var matchIndex = 0
    private var matches: [PDFSelection] = []

    func search(_ query: String) {
        guard let pdfView, let document = pdfView.document else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return clearSearch() }
        matches = document.findString(trimmed, withOptions: [.caseInsensitive])
        matchCount = matches.count
        matchIndex = 0
        pdfView.highlightedSelections = matches.isEmpty ? nil : matches
        focusCurrentMatch()
    }

    func clearSearch() {
        matches = []
        matchCount = 0
        matchIndex = 0
        pdfView?.highlightedSelections = nil
    }

    func step(_ delta: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + delta + matches.count) % matches.count
        focusCurrentMatch()
    }

    func goToPage(_ pageNumber: Int) {
        guard let pdfView, let document = pdfView.document else { return }
        let index = max(0, min(pageNumber - 1, document.pageCount - 1))
        guard let page = document.page(at: index) else { return }
        pdfView.go(to: PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .mediaBox).height)))
    }

    private func focusCurrentMatch() {
        guard matches.indices.contains(matchIndex), let pdfView else { return }
        let selection = matches[matchIndex]
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.scrollSelectionToVisible(nil)
    }
}

// MARK: - Container (resolve → download → chrome + reader)

/// Resolves a PDF location (local files display immediately; remote URLs
/// download once into Application Support) and wraps the reader in its
/// chrome: in-document search and a thumbnail rail on wide panes.
struct PDFSourceContainer: View {
    let urlString: String?
    let sourceUUID: String?
    @Binding var lastSelectedText: String
    @Binding var lastPDFSelection: PDFSelectionDetail?
    var onTextExtracted: (String) -> Void = { _ in }

    @State private var localURL: URL?
    @State private var loadFailed: String?
    @State private var controller = PDFReaderController()
    @State private var searchText = ""
    @State private var showThumbnails = true

    init(
        tab: SourceTab,
        lastSelectedText: Binding<String>,
        lastPDFSelection: Binding<PDFSelectionDetail?>,
        onTextExtracted: @escaping (String) -> Void = { _ in }
    ) {
        self.urlString = tab.url
        self.sourceUUID = tab.sourceUUID
        self._lastSelectedText = lastSelectedText
        self._lastPDFSelection = lastPDFSelection
        self.onTextExtracted = onTextExtracted
    }

    init(
        urlString: String?,
        sourceUUID: String?,
        lastSelectedText: Binding<String>,
        lastPDFSelection: Binding<PDFSelectionDetail?>,
        onTextExtracted: @escaping (String) -> Void = { _ in }
    ) {
        self.urlString = urlString
        self.sourceUUID = sourceUUID
        self._lastSelectedText = lastSelectedText
        self._lastPDFSelection = lastPDFSelection
        self.onTextExtracted = onTextExtracted
    }

    var body: some View {
        Group {
            if let localURL {
                reader(localURL)
            } else if let loadFailed {
                failureState(loadFailed)
            } else {
                ProgressView("Fetching PDF…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: urlString) { await resolve() }
    }

    private func reader(_ url: URL) -> some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                readerToolbar
                Divider().background(DS.borderSubtle)
                HStack(spacing: 0) {
                    PDFSourceView(
                        fileURL: url,
                        sourceUUID: sourceUUID,
                        controller: controller,
                        lastSelectedText: $lastSelectedText,
                        lastPDFSelection: $lastPDFSelection,
                        onTextExtracted: onTextExtracted
                    )
                    if showThumbnails && proxy.size.width > 700 {
                        Divider().background(DS.borderSubtle)
                        PDFThumbnailRail(controller: controller)
                            .frame(width: 108)
                    }
                }
            }
        }
    }

    private var readerToolbar: some View {
        HStack(spacing: DS.space8) {
            HStack(spacing: DS.space6) {
                Image(systemName: "magnifyingglass")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
                TextField("Find in document", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(DS.caption)
                    .onSubmit { controller.search(searchText) }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        controller.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 4)
            .background(DS.surfaceHover, in: Capsule())
            .frame(maxWidth: 260)

            if controller.matchCount > 0 {
                Text("\(controller.matchIndex + 1) of \(controller.matchCount)")
                    .font(DS.caption2.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
                Button { controller.step(-1) } label: {
                    Image(systemName: "chevron.up").font(DS.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.textSecondary)
                .help("Previous match")
                .accessibilityLabel("Previous match")
                Button { controller.step(1) } label: {
                    Image(systemName: "chevron.down").font(DS.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.textSecondary)
                .keyboardShortcut(.return, modifiers: [])
                .help("Next match")
                .accessibilityLabel("Next match")
            } else if !searchText.isEmpty, controller.matchCount == 0 {
                Text("No matches")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer()

            Button {
                withAnimation(ProMotionSprings.snappy) { showThumbnails.toggle() }
            } label: {
                Image(systemName: "sidebar.trailing")
                    .font(DS.caption)
                    .foregroundStyle(showThumbnails ? DS.text : DS.textMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showThumbnails ? "Hide page thumbnails" : "Show page thumbnails")
            .accessibilityLabel("Toggle page thumbnails")
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space6)
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
        guard let raw = urlString, let url = URL(string: raw) else {
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

// MARK: - Thumbnail rail

private struct PDFThumbnailRail: NSViewRepresentable {
    let controller: PDFReaderController

    func makeNSView(context: Context) -> PDFThumbnailView {
        let view = PDFThumbnailView()
        view.thumbnailSize = CGSize(width: 84, height: 110)
        view.backgroundColor = .clear
        view.pdfView = controller.pdfView
        return view
    }

    func updateNSView(_ view: PDFThumbnailView, context: Context) {
        if view.pdfView !== controller.pdfView {
            view.pdfView = controller.pdfView
        }
    }
}

// MARK: - Storage + extraction

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
    /// so recall citations can deep-link back into the document.
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

    /// Scanned PDFs have no text layer — fall back to Vision OCR per page
    /// (capped: OCR is expensive and 100 pages covers papers and most books'
    /// useful head; the cap note lands in the text as an honest marker).
    static func extractTextWithOCRFallback(
        from document: PDFDocument,
        maxOCRPages: Int = 100
    ) async -> String {
        let direct = extractText(from: document)
        // A real text layer produces far more than boilerplate; scanned PDFs
        // yield empty or a few chars of metadata junk per page.
        if direct.count > max(40, document.pageCount * 8) { return direct }

        var out = ""
        let pageLimit = min(document.pageCount, maxOCRPages)
        for index in 0..<pageLimit {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let image = page.thumbnail(of: size, for: .mediaBox)
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            guard let result = try? await VisionPageOCR.recognize(imageData: png),
                  !result.lines.isEmpty else { continue }
            let text = result.lines.map(\.text).joined(separator: "\n")
            out += "\n\n[[page \(index + 1)]]\n\(text)"
        }
        if document.pageCount > pageLimit, !out.isEmpty {
            out += "\n\n[[truncated after page \(pageLimit)]]"
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Reader

struct PDFSourceView: NSViewRepresentable {
    let fileURL: URL
    var sourceUUID: String?
    var controller: PDFReaderController?
    @Binding var lastSelectedText: String
    @Binding var lastPDFSelection: PDFSelectionDetail?
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
            extractIfNeeded(document)
        }

        controller?.pdfView = view
        context.coordinator.observe(view)
        context.coordinator.rehydrateHighlights(view, sourceUUID: sourceUUID)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        if view.document?.documentURL != fileURL, let document = PDFDocument(url: fileURL) {
            view.document = document
            extractIfNeeded(document)
            context.coordinator.rehydrateHighlights(view, sourceUUID: sourceUUID)
        }
        if let controller, controller.pdfView !== view {
            controller.pdfView = view
        }
    }

    private func extractIfNeeded(_ document: PDFDocument) {
        let callback = onTextExtracted
        Task { @MainActor in
            let extracted = await PDFSourceStore.extractTextWithOCRFallback(from: document)
            if !extracted.isEmpty { callback(extracted) }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PDFSourceView
        private var selectionObserver: NSObjectProtocol?
        private var highlightsObserver: NSObjectProtocol?
        private static let annotationUserName = "cosmo.highlight"

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
                MainActor.assumeIsolated { self.selectionChanged(view) }
            }
            highlightsObserver = NotificationCenter.default.addObserver(
                forName: .cosmoPDFHighlightsChanged,
                object: nil,
                queue: .main
            ) { [weak self, weak view] note in
                guard let self, let view else { return }
                MainActor.assumeIsolated {
                    guard let uuid = self.parent.sourceUUID,
                          note.userInfo?["atomUuid"] as? String == uuid else { return }
                    self.rehydrateHighlights(view, sourceUUID: uuid)
                }
            }
        }

        private func selectionChanged(_ view: PDFView) {
            let selection = view.currentSelection
            let selected = selection?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Same contract as SelectableText: a collapsed selection
            // dismisses the pane's capture mini-menu.
            parent.lastSelectedText = selected

            // Page + line quads so a capture can persist a visual highlight.
            if let selection, !selected.isEmpty,
               let page = selection.pages.first,
               let document = view.document {
                let quads = selection.selectionsByLine()
                    .filter { $0.pages.first === page }
                    .map { $0.bounds(for: page) }
                parent.lastPDFSelection = PDFSelectionDetail(
                    pageIndex: document.index(for: page),
                    quads: quads,
                    text: selected
                )
            } else {
                parent.lastPDFSelection = nil
            }
        }

        /// Replace all cosmo annotations with the stored set for this source.
        func rehydrateHighlights(_ view: PDFView, sourceUUID: String?) {
            guard let sourceUUID else { return }
            Task { @MainActor [weak view] in
                let highlights = await PDFHighlightStore.highlights(forAtom: sourceUUID)
                guard let view, let document = view.document else { return }
                for index in 0..<document.pageCount {
                    guard let page = document.page(at: index) else { continue }
                    for annotation in page.annotations
                    where annotation.userName == Self.annotationUserName {
                        page.removeAnnotation(annotation)
                    }
                }
                for highlight in highlights {
                    guard let page = document.page(at: highlight.page) else { continue }
                    for rect in highlight.quadRects {
                        let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                        annotation.color = NSColor(DS.gilt).withAlphaComponent(0.35)
                        annotation.userName = Self.annotationUserName
                        annotation.contents = highlight.captureUuid
                        page.addAnnotation(annotation)
                    }
                }
            }
        }

        deinit {
            if let selectionObserver {
                NotificationCenter.default.removeObserver(selectionObserver)
            }
            if let highlightsObserver {
                NotificationCenter.default.removeObserver(highlightsObserver)
            }
        }
    }
}
