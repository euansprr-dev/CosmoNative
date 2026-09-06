// CosmoOS/Core/Components/ImageSave/ImageSaver.swift
// The macOS destinations for a resolved image: Downloads (the default, the
// way Safari's "Save Image to Downloads" lands — the Dock stack bounces),
// Save As… (NSSavePanel), the pasteboard, and Finder reveal.

import AppKit
import UniformTypeIdentifiers

@MainActor
enum ImageSaver {

    enum Outcome: Equatable {
        case saved(URL)
        case cancelled
        case failed(String)
    }

    // MARK: - Downloads

    /// Write straight into ~/Downloads under a unique name, then tell the
    /// Dock — the same distributed notification Safari posts, so the
    /// Downloads stack bounces exactly as it does for a browser download.
    static func saveToDownloads(_ payload: ImageSavePayload) -> Outcome {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return .failed("Downloads folder unavailable")
        }
        let filename = ImageSaveNaming.uniqueFilename(payload.filename) { candidate in
            FileManager.default.fileExists(atPath: downloads.appendingPathComponent(candidate).path)
        }
        let destination = downloads.appendingPathComponent(filename)
        do {
            try payload.data.write(to: destination, options: [.atomic])
        } catch {
            return .failed(error.localizedDescription)
        }
        announceDownloadFinished(destination)
        Sound.imageSaved()
        return .saved(destination)
    }

    /// Bounces the Dock's Downloads stack (com.apple.DownloadFileFinished is
    /// the public-by-convention name the Dock listens for).
    private static func announceDownloadFinished(_ url: URL) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.apple.DownloadFileFinished"),
            object: url.path,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    // MARK: - Save As…

    static func saveAs(_ payload: ImageSavePayload) async -> Outcome {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [payload.type]
        panel.nameFieldStringValue = payload.filename
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.title = "Save Image"

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = await withCheckedContinuation { continuation in
                panel.begin { continuation.resume(returning: $0) }
            }
        }
        guard response == .OK, let url = panel.url else { return .cancelled }
        do {
            try payload.data.write(to: url, options: [.atomic])
        } catch {
            return .failed(error.localizedDescription)
        }
        Sound.imageSaved()
        return .saved(url)
    }

    // MARK: - Pasteboard

    /// The original bytes under their own type, plus an NSImage so every
    /// paste target (Pages, Mail, Slack) sees a picture.
    @discardableResult
    static func copy(_ payload: ImageSavePayload) -> Bool {
        guard let image = NSImage(data: payload.data) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        pasteboard.setData(payload.data, forType: NSPasteboard.PasteboardType(payload.type.identifier))
        return true
    }

    // MARK: - Finder

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
