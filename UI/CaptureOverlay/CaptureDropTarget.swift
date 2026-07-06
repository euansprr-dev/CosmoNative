// CosmoOS/UI/CaptureOverlay/CaptureDropTarget.swift
// The panel's drop engine: an invisible NSView registered as an
// NSDraggingDestination behind the SwiftUI platter. AppKit-level handling
// (not SwiftUI onDrop) because file promises — drags from Mail, Photos,
// Safari images, screenshot thumbnails — only resolve reliably through
// NSFilePromiseReceiver, and because the drag pasteboard is readable on
// entry, which powers the live "what's about to land" preview.
// July 2026 — Capture Anywhere

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CaptureDropTarget: NSViewRepresentable {
    let viewModel: CaptureOverlayViewModel

    func makeNSView(context: Context) -> CaptureDropTargetView {
        let view = CaptureDropTargetView()
        view.viewModel = viewModel
        return view
    }

    func updateNSView(_ view: CaptureDropTargetView, context: Context) {
        view.viewModel = viewModel
    }
}

final class CaptureDropTargetView: NSView {
    weak var viewModel: CaptureOverlayViewModel?
    /// Fired whenever a drop was accepted — the menu-bar target uses it to
    /// flash confirmation (the panel shows its tray instead).
    var onDropHandled: (() -> Void)?

    /// Serial queue for file-promise reception, per the API contract.
    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        var types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .rtf, .tiff, .png]
        types += NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes(types)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Invisible to clicks — drags route by registered types, not hit testing.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let preview = Self.preview(from: sender.draggingPasteboard)
        Task { @MainActor in
            viewModel?.dragPreview = preview
            viewModel?.isDropTargeted = true
        }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        Task { @MainActor in
            viewModel?.isDropTargeted = false
            viewModel?.dragPreview = nil
        }
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        Task { @MainActor in
            viewModel?.isDropTargeted = false
            viewModel?.dragPreview = nil
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        // 1. Real files on disk win outright.
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            ingest(urls.map { .file(url: $0, suggestedName: nil) })
            return true
        }

        // 2. File promises (Mail, Photos, Safari images, screenshot thumbnails)
        //    — received into a temp folder, then captured like real files.
        if let receivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self]
        ) as? [NSFilePromiseReceiver], !receivers.isEmpty {
            onDropHandled?()
            receivePromises(receivers)
            return true
        }

        // 3. A dragged link.
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: false]
        ) as? [URL], let url = urls.first(where: { !$0.isFileURL }) {
            ingest([.url(url)])
            return true
        }

        // 4. Raw image data on the drag pasteboard.
        if let data = pasteboard.data(forType: .png) {
            ingest([.data(data, type: .png, suggestedName: nil)])
            return true
        }
        if let data = pasteboard.data(forType: .tiff) {
            ingest([.data(data, type: .tiff, suggestedName: nil)])
            return true
        }

        // 5. Dragged text (RTF preferred for fidelity, plain fallback).
        if let rtf = pasteboard.data(forType: .rtf),
           let attributed = try? NSAttributedString(
               data: rtf,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ),
           !attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ingest([.text(attributed.string)])
            return true
        }
        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ingest([.text(string)])
            return true
        }

        return false
    }

    private func ingest(_ payloads: [DropPayload]) {
        onDropHandled?()
        Task { @MainActor [weak self] in
            await self?.viewModel?.ingest(payloads)
        }
    }

    // MARK: - Promise reception

    private func receivePromises(_ receivers: [NSFilePromiseReceiver]) {
        let destination = Self.promiseDestinationDirectory()
        Task { @MainActor in
            viewModel?.receivingCount += receivers.count
        }
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: promiseQueue) { url, error in
                Task { @MainActor [weak self] in
                    guard let self, let viewModel = self.viewModel else { return }
                    viewModel.receivingCount = max(0, viewModel.receivingCount - 1)
                    if let error {
                        viewModel.errorLine = "Couldn't receive the file — \(error.localizedDescription)"
                        return
                    }
                    await viewModel.ingest([.file(url: url, suggestedName: nil)])
                }
            }
        }
    }

    private static func promiseDestinationDirectory() -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("CosmoCaptureDrops", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    // MARK: - Pre-drop preview

    /// Reads what it can from the drag pasteboard without consuming anything:
    /// filenames for file drags, promised types for promises, host for links,
    /// a snippet for text — so the well can show what's about to land.
    private static func preview(from pasteboard: NSPasteboard) -> CaptureDragPreview {
        var items: [CaptureDragPreview.Item] = []

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            items = urls.enumerated().map { index, url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return CaptureDragPreview.Item(
                    id: index,
                    name: url.lastPathComponent,
                    systemImage: isDirectory ? "folder" : symbol(forPathExtension: url.pathExtension)
                )
            }
        } else if let receivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self]
        ) as? [NSFilePromiseReceiver], !receivers.isEmpty {
            items = receivers.enumerated().map { index, receiver in
                let type = receiver.fileTypes.first.flatMap { UTType($0) }
                let ext = type?.preferredFilenameExtension
                return CaptureDragPreview.Item(
                    id: index,
                    name: type?.localizedDescription ?? "Promised file",
                    systemImage: symbol(forPathExtension: ext ?? "")
                )
            }
        } else if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: false]
        ) as? [URL], let url = urls.first(where: { !$0.isFileURL }) {
            items = [CaptureDragPreview.Item(id: 0, name: url.host ?? url.absoluteString, systemImage: "link")]
        } else if pasteboard.data(forType: .png) != nil || pasteboard.data(forType: .tiff) != nil {
            items = [CaptureDragPreview.Item(id: 0, name: "Image", systemImage: "photo")]
        } else if let string = pasteboard.string(forType: .string) {
            let snippet = string.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48)
            items = [CaptureDragPreview.Item(id: 0, name: "\u{201C}\(snippet)…\u{201D}", systemImage: "text.quote")]
        }

        return CaptureDragPreview(items: Array(items.prefix(4)), totalCount: items.count)
    }

    private static func symbol(forPathExtension ext: String) -> String {
        guard let type = UTType(filenameExtension: ext.lowercased()) else { return "doc" }
        switch InboxDropIngestService.attachmentKind(for: type) {
        case .image, .screenshot, .pageScan: return "photo"
        case .pdf: return "doc.richtext"
        case .epub: return "book.closed"
        case .markdown, .textFile: return "doc.text"
        case .audio: return "waveform"
        case .video: return "film"
        case .document, .unknown: return "doc"
        }
    }
}
