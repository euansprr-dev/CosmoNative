// CosmoOS/Canvas/FilePortalBlockView.swift
// File portal — a file previewed in place on the canvas. Render ladder:
//   Tier 0  cached thumbnail skin (always available; the only tier for
//           formats without a live renderer, and the off-viewport frame)
//   Tier 1  live content when viewport-active — PDFKit page view for PDFs,
//           virtualized grid for spreadsheets
//   Tier 2  peek (full reader / full-size grid) on double-click
// Interaction law: portals are INERT until entered. Single click selects the
// block (canvas chrome only); a second click on the selected portal enters it
// (internal scroll live); deselection exits. Scroll never fights canvas pan.
// Chrome: recessed window (hairline + inner shadow), not a raised card —
// inherited from the thinkspace-portal spec.

import SwiftUI

// MARK: - Resolution

/// What the portal knows about its file right now.
enum FilePortalResolveState: Equatable {
    case loading
    /// Atom + attachment resolved. `fileURL` nil means the blob hasn't
    /// arrived on this device yet (thumbnail may still render via mirror).
    case resolved(FilePortalResolvedFile)
    case unavailable(String)
}

struct FilePortalResolvedFile: Equatable {
    let metadata: FilePortalMetadata
    let fileURL: URL?
    let thumbnailFileURL: URL?
    /// True when this device owns the original bytes — the gate for in-portal
    /// editing (peers stay read-only until the fresh blob mirrors down).
    let isLocallyEditable: Bool
}

/// Ephemeral per-block UI state that must survive block-record rebuilds:
/// an atom write (view-state persist, sync ripple) can replace the
/// CanvasBlock and remount the view — entered-ness and sheet selection are
/// UX state, not render data, and must not reset when that happens.
@MainActor
final class FilePortalSessionState {
    static let shared = FilePortalSessionState()

    private var enteredBlockIds: Set<String> = []
    private var sheetSelections: [String: Int] = [:]

    private init() {}

    func isEntered(_ blockId: String) -> Bool { enteredBlockIds.contains(blockId) }

    func setEntered(_ blockId: String, _ entered: Bool) {
        if entered {
            enteredBlockIds.insert(blockId)
        } else {
            enteredBlockIds.remove(blockId)
        }
    }

    func sheetSelection(_ blockId: String) -> Int? { sheetSelections[blockId] }

    func setSheetSelection(_ blockId: String, _ index: Int) {
        sheetSelections[blockId] = index
    }
}

enum FilePortalResolver {
    /// Atom → portal metadata → attachment row → local bytes (or the synced
    /// thumbnail while the blob downloads).
    static func resolve(entityUuid: String) async -> FilePortalResolveState {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: entityUuid),
              let metadata = atom.filePortalMetadata,
              !metadata.attachmentUUID.isEmpty else {
            return .unavailable("File details missing")
        }
        guard let attachment = try? await MediaAttachmentRepository.shared.fetch(uuid: metadata.attachmentUUID),
              !attachment.isDeleted else {
            return .unavailable("File record missing")
        }
        let fileURL = await AttachmentCloudStore.shared.localOriginalURL(for: attachment)
        let thumbnailURL = await AttachmentCloudStore.shared.localThumbnailURL(for: attachment)
        return .resolved(FilePortalResolvedFile(
            metadata: metadata,
            fileURL: fileURL,
            thumbnailFileURL: thumbnailURL,
            isLocallyEditable: FilePortalEditService.canEdit(attachment: attachment)
        ))
    }
}

// MARK: - Block View

struct FilePortalBlockView: View {
    let block: CanvasBlock
    let isViewportActive: Bool

    @State private var blockSize: CGSize
    @State private var isHovered = false
    @State private var isEntered = false
    @State private var resolveState: FilePortalResolveState = .loading
    @State private var thumbnail: NSImage?
    @State private var persistTask: Task<Void, Never>?
    @Environment(\.canvasBlockSelectionSuppressed) private var selectionNotificationsSuppressed

    private var isSelected: Bool { block.isSelected }

    init(block: CanvasBlock, isViewportActive: Bool) {
        self.block = block
        self.isViewportActive = isViewportActive
        self._blockSize = State(initialValue: block.size)
    }

    var body: some View {
        portalSurface
            .frame(width: blockSize.width, height: blockSize.height)
            .background(renderedSizeReporter)
            .background(FilePortalChrome.surfaceFill)
            .clipShape(.rect(cornerRadius: FilePortalChrome.cornerRadius))
            .overlay(chromeOverlay)
            .overlay(resizeOverlay)
            .shadow(
                color: .black.opacity(isSelected ? 0.08 : 0.05),
                radius: isHovered ? 14 : 8, x: 0, y: isHovered ? 4 : 2
            )
            .contentShape(.rect(cornerRadius: FilePortalChrome.cornerRadius))
            .gesture(tapGestures)
            .contextMenu { contextMenuItems }
            .onHover { hovering in
                withAnimation(ProMotionSprings.hover) { isHovered = hovering }
            }
            .onAppear {
                // Restore entered-ness across block-record rebuilds (an atom
                // write can remount this view; that must not eject the user).
                isEntered = FilePortalSessionState.shared.isEntered(block.id)
            }
            .onChange(of: block.isSelected) { _, selected in
                if !selected { setEntered(false) }
            }
            .onChange(of: isEntered) { _, entered in
                FilePortalSessionState.shared.setEntered(block.id, entered)
            }
            .onChange(of: block.size) { _, newSize in
                guard blockSize != newSize else { return }
                blockSize = newSize
            }
            .task(id: block.entityUuid) { await resolveAndLoadSkin() }
            .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Layout

    /// Right-click hit-testing mirrors the render snapshot — every block must
    /// report its true rendered size (same contract as ImageBlockView).
    private var renderedSizeReporter: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { BlockRenderedSizeCache.shared.update(blockId: block.id, size: geo.size) }
                .onChange(of: geo.size) { _, newSize in
                    BlockRenderedSizeCache.shared.update(blockId: block.id, size: newSize)
                }
        }
    }

    private var portalSurface: some View {
        VStack(spacing: 0) {
            portalContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            FilePortalFooter(
                state: resolveState,
                blockTitle: block.title,
                isHovered: isHovered,
                isEntered: isEntered,
                onPeek: { openPeek() },
                onOpenPane: { openAsPane() },
                onOpenExternally: { openExternally() }
            )
        }
    }

    @ViewBuilder
    private var portalContent: some View {
        switch resolveState {
        case .loading:
            FilePortalSkinView(thumbnail: thumbnail, systemImage: "doc.fill", caption: nil)
        case .unavailable(let reason):
            FilePortalSkinView(thumbnail: nil, systemImage: "doc.questionmark", caption: reason)
        case .resolved(let file):
            resolvedContent(file)
        }
    }

    @ViewBuilder
    private func resolvedContent(_ file: FilePortalResolvedFile) -> some View {
        if let fileURL = file.fileURL, isViewportActive, showsLiveContent(for: file.metadata.portalKind) {
            liveContent(file: file, fileURL: fileURL)
        } else if file.fileURL == nil {
            FilePortalSkinView(thumbnail: thumbnail, systemImage: "icloud.and.arrow.down", caption: "Downloading…")
        } else {
            FilePortalSkinView(thumbnail: thumbnail, systemImage: file.metadata.portalKind.placeholderSystemImage, caption: nil)
        }
    }

    @ViewBuilder
    private func liveContent(file: FilePortalResolvedFile, fileURL: URL) -> some View {
        switch file.metadata.portalKind {
        case .pdf:
            FilePortalPDFView(
                fileURL: fileURL,
                initialPageIndex: file.metadata.currentPage ?? 0,
                onPageChanged: { pageIndex in persistViewState { $0.currentPage = pageIndex } }
            )
            .allowsHitTesting(isEntered)
        case .spreadsheet, .csv:
            // The sheet host gates only its grid content — the tab strip
            // stays clickable without entering the portal.
            FilePortalSheetHost(
                fileURL: fileURL,
                cacheKey: file.metadata.attachmentUUID,
                stamp: file.metadata.thumbStamp,
                initialSheetIndex: FilePortalSessionState.shared.sheetSelection(block.id)
                    ?? file.metadata.currentSheetIndex ?? 0,
                isCompact: true,
                isContentInteractive: isEntered,
                isEditable: file.isLocallyEditable,
                fallback: { AnyView(FilePortalSkinView(thumbnail: thumbnail, systemImage: "tablecells", caption: "Preview unavailable")) },
                onSheetChanged: { sheetIndex in
                    FilePortalSessionState.shared.setSheetSelection(block.id, sheetIndex)
                    persistViewState { $0.currentSheetIndex = sheetIndex }
                },
                onCommitEdit: { sheetIndex, rowIndex, columnIndex, text in
                    commitCellEdit(sheetIndex: sheetIndex, rowIndex: rowIndex, columnIndex: columnIndex, text: text)
                }
            )
        case .generic:
            FilePortalSkinView(thumbnail: thumbnail, systemImage: "doc.fill", caption: nil)
        }
    }

    private func showsLiveContent(for kind: FilePortalMetadata.Kind) -> Bool {
        switch kind {
        case .pdf, .spreadsheet, .csv: return true
        case .generic: return false
        }
    }

    // MARK: Chrome

    @ViewBuilder
    private var chromeOverlay: some View {
        let shape = RoundedRectangle(cornerRadius: FilePortalChrome.cornerRadius)
        shape.strokeBorder(
            isSelected ? DS.entityFile.opacity(0.65) : DS.sepiaBorder.opacity(0.6),
            lineWidth: isSelected ? 1.5 : 1
        )
        // Recessed-window read: a whisper of inner shadow at the top edge.
        shape.stroke(Color.black.opacity(0.10), lineWidth: 1)
            .blur(radius: 1.5)
            .offset(y: 1)
            .mask(shape.fill(LinearGradient(
                colors: [.black, .clear],
                startPoint: .top, endPoint: .center
            )))
            .allowsHitTesting(false)
        if isEntered {
            shape.strokeBorder(DS.entityFile.opacity(0.35), lineWidth: 2.5)
                .allowsHitTesting(false)
        }
    }

    private var resizeOverlay: some View {
        SimpleResizeOverlay(
            size: $blockSize,
            blockId: block.id,
            minSize: CGSize(width: 200, height: 140),
            maxSize: CGSize(width: 1400, height: 1100)
        )
    }

    // MARK: Interaction

    /// Double-click peeks; single click selects, then a second single click
    /// on the selected portal enters it. `exclusively` keeps the two from
    /// firing together.
    private var tapGestures: some Gesture {
        TapGesture(count: 2).onEnded { openPeek() }
            .exclusively(before: TapGesture().onEnded { handleSingleTap() })
    }

    private func handleSingleTap() {
        if isSelected {
            guard case .resolved(let file) = resolveState,
                  file.fileURL != nil,
                  showsLiveContent(for: file.metadata.portalKind) else { return }
            setEntered(true)
        } else if !selectionNotificationsSuppressed {
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.blockSelected,
                object: nil,
                userInfo: ["blockId": block.id]
            )
        }
    }

    private func setEntered(_ entered: Bool) {
        isEntered = entered
        FilePortalSessionState.shared.setEntered(block.id, entered)
    }

    // MARK: Destinations

    @ViewBuilder
    private var contextMenuItems: some View {
        Button { openPeek() } label: {
            Label("Peek", systemImage: "eye")
        }
        Button { openAsPane() } label: {
            Label("Open in Pane", systemImage: "rectangle.split.2x1")
        }
        Button { openFocusMode() } label: {
            Label("Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        Divider()
        Button { promptRename() } label: {
            Label("Rename…", systemImage: "pencil")
        }
        Button { openExternally() } label: {
            Label("Open in Default App", systemImage: "arrow.up.forward.app")
        }
        Button { revealInFinder() } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        Divider()
        Button(role: .destructive) {
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.removeBlock,
                object: nil,
                userInfo: ["blockId": block.id]
            )
        } label: {
            Label("Remove from Canvas", systemImage: "trash")
        }
    }

    private func openPeek() {
        withResolvedEntityId { entityId in
            PeekController.shared.peek(.entity(EntitySelection(id: entityId, type: .file)))
        }
    }

    private func openAsPane() {
        withResolvedEntityId { entityId in
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openAsPane,
                object: nil,
                userInfo: ["type": EntityType.file, "id": entityId]
            )
        }
    }

    private func openFocusMode() {
        withResolvedEntityId { entityId in
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": EntityType.file, "id": entityId]
            )
        }
    }

    /// Blocks created before this session may carry entityId -1 (insert never
    /// wrote back the rowid) — resolve through the uuid before routing.
    private func withResolvedEntityId(_ action: @escaping (Int64) -> Void) {
        if block.entityId > 0 {
            action(block.entityId)
            return
        }
        let entityUuid = block.entityUuid
        Task {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: entityUuid),
                  let id = atom.id, id > 0 else { return }
            action(id)
        }
    }

    private func promptRename() {
        FilePortalRenamePrompt.run(atomUuid: block.entityUuid, currentTitle: block.title)
    }

    private func openExternally() {
        guard case .resolved(let file) = resolveState, let fileURL = file.fileURL else { return }
        NSWorkspace.shared.open(fileURL)
    }

    private func revealInFinder() {
        guard case .resolved(let file) = resolveState, let fileURL = file.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    // MARK: Data

    private func resolveAndLoadSkin() async {
        // Bounded re-resolve while the blob mirror lands on this device —
        // a portal must not stay "Downloading…" after the download finishes.
        for attempt in 0..<6 {
            let state = await FilePortalResolver.resolve(entityUuid: block.entityUuid)
            guard !Task.isCancelled else { return }
            resolveState = state
            guard case .resolved(let file) = state else { return }

            if let fileURL = file.fileURL {
                thumbnail = await FilePortalThumbnailStore.shared.thumbnail(
                    for: fileURL,
                    cacheKey: file.metadata.attachmentUUID,
                    stamp: file.metadata.thumbStamp,
                    pixelWidth: max(blockSize.width, blockSize.height) * 2
                )
                return
            }
            if thumbnail == nil, let thumbURL = file.thumbnailFileURL {
                thumbnail = NSImage(contentsOf: thumbURL)
            }
            try? await Task.sleep(for: .seconds(Double(attempt + 1) * 2))
            guard !Task.isCancelled else { return }
        }
    }

    /// View-state writes (current page/sheet) merge one key and never race
    /// content writers — `filePortal` is solely portal-owned. Debounced:
    /// scrolling a PDF fires page changes per gesture, and every atom write
    /// ripples through sync + block rebuilds — one write after settling.
    private func persistViewState(_ mutate: @escaping (inout FilePortalMetadata) -> Void) {
        let entityUuid = block.entityUuid
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            _ = try? await AtomRepository.shared.update(uuid: entityUuid) { atom in
                guard var metadata = atom.filePortalMetadata else { return }
                mutate(&metadata)
                atom = atom.mergingFilePortalMetadata(metadata)
            }
        }
    }

    /// Disk + sync commit for an in-grid cell edit. The grid already shows
    /// the value optimistically; failure reloads truth and says so.
    private func commitCellEdit(sheetIndex: Int, rowIndex: Int, columnIndex: Int, text: String) {
        let entityUuid = block.entityUuid
        Task {
            do {
                try await FilePortalEditService.shared.commitCellEdit(
                    atomUuid: entityUuid,
                    sheetIndex: sheetIndex,
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    newText: text
                )
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn't save the edit"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
            // Success: the bumped thumbStamp re-keys the host's task and it
            // reloads the reparsed file. Failure: same reload restores truth.
            await resolveAndLoadSkin()
        }
    }

    private var accessibilityDescription: String {
        guard case .resolved(let file) = resolveState else { return "File portal: \(block.title)" }
        return "File portal: \(file.metadata.originalFilename)"
    }
}

// MARK: - Chrome constants

enum FilePortalChrome {
    static let cornerRadius: CGFloat = 14
    static var surfaceFill: Color { DS.surfaceElevated }
}

// MARK: - Skin (Tier 0)

/// The thumbnail card every portal can always draw.
struct FilePortalSkinView: View {
    let thumbnail: NSImage?
    let systemImage: String
    let caption: String?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel(caption ?? "File preview")
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var placeholder: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: systemImage)
                .font(DS.title2)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            if let caption {
                Text(caption)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.space12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FilePortalChrome.surfaceFill)
    }
}

// MARK: - Footer strip

private struct FilePortalFooter: View {
    let state: FilePortalResolveState
    let blockTitle: String
    let isHovered: Bool
    let isEntered: Bool
    let onPeek: () -> Void
    let onOpenPane: () -> Void
    let onOpenExternally: () -> Void

    var body: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: kindSystemImage)
                .font(DS.caption2)
                .foregroundStyle(DS.entityFile)
                .accessibilityHidden(true)
            Text(displayName)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: DS.space6)
            if isHovered {
                hoverActions
            } else {
                Text(detailText)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DS.space10)
        .frame(height: 30)
        .background(FilePortalChrome.surfaceFill)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.sepiaBorder.opacity(0.4)).frame(height: 0.5)
        }
    }

    private var hoverActions: some View {
        HStack(spacing: DS.space4) {
            footerButton("arrow.up.left.and.arrow.down.right", help: "Peek (double-click)",
                         label: "Peek at file", action: onPeek)
            footerButton("rectangle.split.2x1", help: "Open in pane",
                         label: "Open in pane", action: onOpenPane)
            footerButton("arrow.up.forward.app", help: "Open in default app",
                         label: "Open in default app", action: onOpenExternally)
        }
    }

    private func footerButton(_ systemImage: String, help: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(DS.caption2)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.textSecondary)
        .help(help)
        .accessibilityLabel(label)
    }

    private var resolvedMetadata: FilePortalMetadata? {
        guard case .resolved(let file) = state else { return nil }
        return file.metadata
    }

    /// Renames win: the atom title (kept fresh by enrichment) leads, the
    /// original filename is the fallback for un-enriched frames.
    private var displayName: String {
        let title = blockTitle.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty, title != "Untitled" { return title }
        return resolvedMetadata?.originalFilename ?? blockTitle
    }

    private var kindSystemImage: String {
        (resolvedMetadata?.portalKind ?? .generic).placeholderSystemImage
    }

    private var detailText: String {
        guard let metadata = resolvedMetadata else { return "" }
        if isEntered { return "browsing" }
        var parts: [String] = []
        if let pageCount = metadata.pageCount {
            parts.append(pageCount == 1 ? "1 page" : "\(pageCount) pages")
        }
        if let sheetNames = metadata.sheetNames, sheetNames.count > 1 {
            parts.append("\(sheetNames.count) sheets")
        }
        if parts.isEmpty, let bytes = metadata.byteSize {
            parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Kind glyphs

extension FilePortalMetadata.Kind {
    var placeholderSystemImage: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .spreadsheet, .csv: return "tablecells"
        case .generic: return "doc.fill"
        }
    }
}

// MARK: - Rename prompt

/// Finder-style rename: a modal alert with a pre-filled text field. Writes
/// the atom title only — the original filename stays as provenance in the
/// portal metadata, and the canvas block refreshes through atom observation.
@MainActor
enum FilePortalRenamePrompt {
    static func run(atomUuid: String, currentTitle: String) {
        let alert = NSAlert()
        alert.messageText = "Rename File"
        alert.informativeText = "The name changes everywhere in Cosmo; the original file keeps its filename."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = currentTitle
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newTitle = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty, newTitle != currentTitle else { return }
        Task {
            _ = try? await AtomRepository.shared.update(uuid: atomUuid) { atom in
                atom.title = newTitle
            }
        }
    }
}
