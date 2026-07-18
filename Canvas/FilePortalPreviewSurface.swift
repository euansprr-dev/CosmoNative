// CosmoOS/Canvas/FilePortalPreviewSurface.swift
// Tier 2 of a file portal: the full-size preview rendered inside Peek, a
// pane, or focus routing (all three arrive via PaneContentView's .file
// route). PDFs reuse the complete Inquiry reading room (PDFSourceContainer:
// search, thumbnail rail); spreadsheets get the uncapped grid; everything
// else a large skin + "Open in default app". No editor pretensions — the
// portal previews, the default app edits.

import SwiftUI

struct FilePortalPreviewSurface: View {
    let atom: Atom
    let onClose: () -> Void

    @State private var resolveState: FilePortalResolveState = .loading
    @State private var skinThumbnail: NSImage?
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var displayTitle = ""
    @FocusState private var renameFieldFocused: Bool
    // PDFSourceContainer's selection plumbing — unused by portals, required
    // by the shared reader.
    @State private var lastSelectedText = ""
    @State private var lastPDFSelection: PDFSelectionDetail?

    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPeekContext) private var isPeekContext
    @Environment(\.paneDeckChrome) private var paneDeckChrome

    var body: some View {
        VStack(spacing: 0) {
            surfaceHeader
            Divider().background(DS.borderSubtle)
            surfaceBody
        }
        .background(CommandKPreviewPaper.fill)
        .task(id: atom.uuid) {
            displayTitle = atom.title ?? ""
            await resolve()
        }
    }

    // MARK: Header — chrome-island grammar (deck tabs INSIDE the mode row in
    // panes, NavigationTrailIsland in full focus, bare identity row in peek).

    private var surfaceHeader: some View {
        CosmoChromeRow(insetsEnabled: false, centersAbsolutely: false) {
            if isPaneContext, let paneDeckChrome {
                CosmoChromeIsland { PaneDeckTabStrip(context: paneDeckChrome) }
            } else if !isPaneContext && !isPeekContext {
                NavigationTrailIsland()
            }
            CosmoChromeIsland { identityCluster }
        } center: {
            EmptyView()
        } trailing: {
            CosmoChromeIsland { headerActions }
        }
        .padding(.vertical, DS.space4)
    }

    private var identityCluster: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: portalKind.placeholderSystemImage)
                .font(DS.caption)
                .foregroundStyle(DS.entityFile)
                .accessibilityHidden(true)
            if isRenaming {
                renameField
            } else {
                Text(displayName)
                    .font(DS.body)
                    .foregroundStyle(CommandKPreviewPaper.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .onTapGesture(count: 2) { beginRename() }
                    .help("Double-click to rename")
            }
        }
    }

    private var renameField: some View {
        TextField("File name", text: $renameDraft)
            .textFieldStyle(.plain)
            .font(DS.body)
            .foregroundStyle(CommandKPreviewPaper.text)
            .frame(minWidth: 160, maxWidth: 320)
            .focused($renameFieldFocused)
            .onSubmit { commitRename() }
            .onExitCommand { isRenaming = false }
            .onAppear { renameFieldFocused = true }

    }

    @ViewBuilder
    private var headerActions: some View {
        Button(action: beginRename) {
            Image(systemName: "pencil")
                .font(DS.caption)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.textSecondary)
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .help("Rename (⇧⌘R)")
        .accessibilityLabel("Rename file")

        Button(action: openExternally) {
            Image(systemName: "arrow.up.forward.app")
                .font(DS.caption)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.textSecondary)
        .keyboardShortcut("o", modifiers: [.command, .shift])
        .help("Open in default app (⇧⌘O)")
        .accessibilityLabel("Open in default app")
        .disabled(resolvedFileURL == nil)
    }

    // MARK: Rename

    private func beginRename() {
        renameDraft = displayName
        isRenaming = true
    }

    private func commitRename() {
        isRenaming = false
        let newTitle = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty, newTitle != displayName else { return }
        displayTitle = newTitle
        let atomUuid = atom.uuid
        Task {
            _ = try? await AtomRepository.shared.update(uuid: atomUuid) { atom in
                atom.title = newTitle
            }
        }
    }

    // MARK: Body

    @ViewBuilder
    private var surfaceBody: some View {
        switch resolveState {
        case .loading:
            ProgressView("Opening…")
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let reason):
            unavailableState(reason)
        case .resolved(let file):
            resolvedBody(file)
        }
    }

    @ViewBuilder
    private func resolvedBody(_ file: FilePortalResolvedFile) -> some View {
        if let fileURL = file.fileURL {
            switch file.metadata.portalKind {
            case .pdf:
                PDFSourceContainer(
                    urlString: fileURL.absoluteString,
                    sourceUUID: nil,
                    lastSelectedText: $lastSelectedText,
                    lastPDFSelection: $lastPDFSelection
                )
            case .spreadsheet, .csv:
                FilePortalSheetHost(
                    fileURL: fileURL,
                    cacheKey: file.metadata.attachmentUUID,
                    stamp: file.metadata.thumbStamp,
                    initialSheetIndex: file.metadata.currentSheetIndex ?? 0,
                    isCompact: false,
                    isContentInteractive: true,
                    isEditable: file.isLocallyEditable,
                    fallback: { AnyView(genericPreview(file)) },
                    onCommitEdit: { sheetIndex, rowIndex, columnIndex, text in
                        commitCellEdit(sheetIndex: sheetIndex, rowIndex: rowIndex, columnIndex: columnIndex, text: text)
                    }
                )
            case .generic:
                genericPreview(file)
            }
        } else {
            downloadingState(file)
        }
    }

    private func genericPreview(_ file: FilePortalResolvedFile) -> some View {
        VStack(spacing: DS.space12) {
            FilePortalSkinView(
                thumbnail: skinThumbnail,
                systemImage: file.metadata.portalKind.placeholderSystemImage,
                caption: nil
            )
            .frame(maxWidth: 560, maxHeight: 640)
            .clipShape(.rect(cornerRadius: DS.radiusMedium))
            .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 6)

            Text(byteSizeText(file))
                .font(DS.caption)
                .foregroundStyle(CommandKPreviewPaper.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.space12)
    }

    private func downloadingState(_ file: FilePortalResolvedFile) -> some View {
        VStack(spacing: DS.space10) {
            Image(systemName: "icloud.and.arrow.down")
                .font(DS.title2)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text("Downloading \(file.metadata.originalFilename)…")
                .font(DS.caption)
                .foregroundStyle(CommandKPreviewPaper.textSecondary)
            ProgressView()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableState(_ reason: String) -> some View {
        VStack(spacing: DS.space10) {
            Image(systemName: "doc.questionmark")
                .font(DS.title2)
                .foregroundStyle(DS.orange)
                .accessibilityHidden(true)
            Text("Couldn't open this file")
                .font(DS.body)
                .foregroundStyle(CommandKPreviewPaper.text)
            Text(reason)
                .font(DS.caption)
                .foregroundStyle(CommandKPreviewPaper.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Data

    private func resolve() async {
        let state = await FilePortalResolver.resolve(entityUuid: atom.uuid)
        resolveState = state
        guard case .resolved(let file) = state, file.metadata.portalKind == .generic else { return }
        if let fileURL = file.fileURL {
            skinThumbnail = await FilePortalThumbnailStore.shared.thumbnail(
                for: fileURL,
                cacheKey: file.metadata.attachmentUUID,
                stamp: file.metadata.thumbStamp,
                pixelWidth: 1280
            )
        } else if let thumbURL = file.thumbnailFileURL {
            skinThumbnail = NSImage(contentsOf: thumbURL)
        }
    }

    private var portalKind: FilePortalMetadata.Kind {
        atom.filePortalMetadata?.portalKind ?? .generic
    }

    private var displayName: String {
        let filename = atom.filePortalMetadata?.originalFilename ?? ""
        return filename.isEmpty ? (atom.title ?? "File") : filename
    }

    private var resolvedFileURL: URL? {
        guard case .resolved(let file) = resolveState else { return nil }
        return file.fileURL
    }

    private func byteSizeText(_ file: FilePortalResolvedFile) -> String {
        guard let bytes = file.metadata.byteSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func openExternally() {
        guard let fileURL = resolvedFileURL else { return }
        NSWorkspace.shared.open(fileURL)
    }

    private func commitCellEdit(sheetIndex: Int, rowIndex: Int, columnIndex: Int, text: String) {
        let atomUuid = atom.uuid
        Task {
            do {
                try await FilePortalEditService.shared.commitCellEdit(
                    atomUuid: atomUuid,
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
            await resolve()
        }
    }
}
