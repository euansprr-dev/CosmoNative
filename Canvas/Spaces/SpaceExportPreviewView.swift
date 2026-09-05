#if os(macOS)
import AppKit
import Observation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// The reading copy is the hero; the four export choices stay in one quiet footer.
/// Preview and Save share the same frozen snapshot and, for PDF, the same bytes.
struct SpaceExportPreviewView: View {
    let snapshot: SpaceCompositionExportSnapshot
    private let wordCount: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = SpaceExportPreviewModel()

    init(snapshot: SpaceCompositionExportSnapshot) {
        self.snapshot = snapshot
        wordCount = snapshot.wordCount
    }

    var body: some View {
        VStack(spacing: 0) {
            SpaceExportPreviewHeader(title: snapshot.title, wordCount: wordCount,
                                     pageCount: model.document?.pageCount, dismiss: { dismiss() })
            Divider().overlay(DS.borderSubtle)
            SpaceExportPreviewContent(model: model, retry: { Task { await model.load(snapshot) } })
            Divider().overlay(DS.borderSubtle)
            SpaceExportPreviewFooter(model: model)
        }
        .frame(minWidth: 680, idealWidth: 900, minHeight: 560, idealHeight: 760)
        .background(DS.bg)
        .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: model.isLoading)
        .task(id: snapshot.id) { await model.load(snapshot) }
    }
}

@MainActor @Observable
private final class SpaceExportPreviewModel {
    var format: SpaceCompositionExportFormat = .pdf
    var document: PDFDocument?
    var error: String?
    var previewError: String?
    var savedURL: URL?
    var isLoading = true
    var isSaving = false
    private var prepared: SpaceCompositionExportSnapshot?
    private var pdfData: Data?

    var canSave: Bool { prepared != nil && !isSaving && (format != .pdf || pdfData != nil) }

    func load(_ snapshot: SpaceCompositionExportSnapshot) async {
        isLoading = true
        error = nil
        previewError = nil
        prepared = nil
        pdfData = nil
        document = nil
        savedURL = nil
        do {
            let resolved = try await SpaceCompositionExportRenderer.prepare(snapshot)
            try Task.checkCancellation()
            prepared = resolved
            do {
                let data = try await SpaceCompositionExportRenderer.pdf(resolved)
                try Task.checkCancellation()
                pdfData = data
                document = PDFDocument(data: data)
            } catch is CancellationError { return }
            catch { previewError = error.localizedDescription }
        } catch is CancellationError { return }
        catch { self.error = error.localizedDescription }
        isLoading = false
    }

    func save() async {
        guard canSave, let prepared else { return }
        isSaving = true
        error = nil
        savedURL = nil
        defer { isSaving = false }
        let chosenFormat = format
        let panel = NSSavePanel()
        panel.title = "Export \(prepared.title)"
        panel.nameFieldStringValue = SpaceCompositionExportFormatter.filename(title: prepared.title, format: chosenFormat)
        panel.allowedContentTypes = [UTType(filenameExtension: chosenFormat.fileExtension) ?? .data]
        panel.canCreateDirectories = true
        let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let url = panel.url else { return }
        do {
            let data: Data
            if chosenFormat == .pdf, let cached = pdfData { data = cached }
            else { data = try await SpaceCompositionExportRenderer.data(for: prepared, format: chosenFormat) }
            try await Task.detached(priority: .userInitiated) {
                try SpaceCompositionExportArchive.write(data: data, format: chosenFormat, snapshot: prepared, to: url)
            }.value
            savedURL = url
        } catch { self.error = error.localizedDescription }
    }
}

private struct SpaceExportPreviewHeader: View {
    let title: String
    let wordCount: Int
    let pageCount: Int?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: DS.space16) {
            VStack(alignment: .leading, spacing: DS.space4) {
                Text(title).font(DS.title2).foregroundStyle(DS.text).lineLimit(1)
                Text("\(wordCount.formatted()) words" + (pageCount.map { " · \($0) \($0 == 1 ? "page" : "pages")" } ?? ""))
                    .font(DS.caption).monospacedDigit().foregroundStyle(DS.textMuted)
            }
            Spacer(minLength: DS.space16)
            Button("Done", action: dismiss)
                .keyboardShortcut(.cancelAction)
                .help("Close preview (Esc)")
                .controlSize(.large)
        }
        .padding(DS.space24)
    }
}

private struct SpaceExportPreviewContent: View {
    let model: SpaceExportPreviewModel
    let retry: () -> Void

    var body: some View {
        Group {
            if let document = model.document {
                SpaceExportPDFView(document: document)
            } else if model.isLoading {
                SpaceExportPreviewSkeleton()
            } else {
                ContentUnavailableView {
                    Label("Preview unavailable", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text(model.previewError ?? model.error ?? "Try opening this preview again.")
                } actions: {
                    Button("Try again", action: retry).help("Prepare the reading copy again")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SpaceExportPreviewFooter: View {
    @Bindable var model: SpaceExportPreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            if let error = model.error { Text(error).font(DS.caption).foregroundStyle(DS.textSecondary).textSelection(.enabled) }
            HStack(alignment: .center, spacing: DS.space24) {
                VStack(alignment: .leading, spacing: DS.space6) {
                    Picker("Format", selection: $model.format) {
                        ForEach(SpaceCompositionExportFormat.allCases) { format in Text(format.title).tag(format) }
                    }
                    .pickerStyle(.menu).frame(width: 230).disabled(model.isSaving)
                    .help("Choose the format for this reading copy")
                    Text(model.format.detail).font(DS.caption).foregroundStyle(DS.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DS.space16)
                SpaceExportSaveActions(model: model)
            }
        }
        .padding(DS.space24)
    }
}

private struct SpaceExportSaveActions: View {
    let model: SpaceExportPreviewModel

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.space6) {
            Button(model.isSaving ? "Saving…" : "Save…") { Task { await model.save() } }
                .buttonStyle(.borderedProminent).tint(DS.accent).controlSize(.large)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.canSave)
                .help("Save this version (⌘S)")
            if let url = model.savedURL {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(.link).font(DS.caption)
                    .help("Show \(url.lastPathComponent) in Finder")
            }
        }
    }
}

private struct SpaceExportPDFView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = NSColor(DS.bg)
        view.document = document
        view.setAccessibilityLabel("Reading copy")
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        view.backgroundColor = NSColor(DS.bg)
    }
}

private struct SpaceExportPreviewSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            Text("Preparing your reading copy").font(DS.title1)
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DS.radiusXSmall).fill(DS.glassSectionFill).frame(height: DS.space12)
            }
            Spacer()
        }
        .padding(DS.space48)
        .frame(maxWidth: 500, maxHeight: 620)
        .background(DS.surface)
        .padding(DS.space32)
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preparing your reading copy")
    }
}
#endif
