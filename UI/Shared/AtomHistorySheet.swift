// CosmoOS/UI/Shared/AtomHistorySheet.swift
// Version history for a single atom: timeline of pre-image snapshots on the
// left, a readable excerpt of the selected revision on the right, with
// copy-out and guarded restore. Local-only data from atom_revisions.
// July 2026

import SwiftUI
import GRDB

struct AtomHistorySheet: View {
    let atom: Atom
    let onClose: () -> Void

    @State private var revisions: [AtomRevision] = []
    @State private var selectedID: Int64?
    @State private var isLoading = true
    @State private var restoreBlockedByEditor = false
    @State private var didRestore = false
    @State private var isRestoring = false
    @State private var restoreError: String?

    private var selected: AtomRevision? {
        guard let selectedID else { return revisions.first }
        return revisions.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DS.borderSubtle)
            content
        }
        .frame(width: 760, height: 520)
        .background(DS.bg)
        .task { await loadRevisions() }
        .alert("Item is open in an editor", isPresented: $restoreBlockedByEditor) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Close the editor for this item first, then restore. Restoring under an open editor could be overwritten by its next autosave.")
        }
        .alert("Couldn’t restore this version", isPresented: Binding(
            get: { restoreError != nil }, set: { if !$0 { restoreError = nil } }
        )) {
            Button("OK", role: .cancel) { restoreError = nil }
        } message: {
            Text(restoreError ?? "Please try again.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(DS.body.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("History")
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                Text(atom.title?.isEmpty == false ? atom.title! : "Untitled")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 26, height: 26)
                    .background(DS.border.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Close history")
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if revisions.isEmpty {
            emptyState
        } else {
            HStack(spacing: 0) {
                timeline
                    .frame(width: 250)
                Divider().overlay(DS.borderSubtle)
                detail
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "clock")
                .font(DS.title2)
                .foregroundStyle(DS.textMuted.opacity(0.5))
                .accessibilityHidden(true)
            Text("No revisions yet")
                .font(DS.headline)
                .foregroundStyle(DS.text)
            Text("Cosmo snapshots this item before meaningful changes —\nedits, AI applies, and sync updates all leave a trail here.")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Timeline

    private var timeline: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(revisions) { revision in
                    timelineRow(revision)
                }
            }
            .padding(DS.space10)
        }
    }

    private func timelineRow(_ revision: AtomRevision) -> some View {
        let isSelected = (selected?.id == revision.id)
        return Button {
            selectedID = revision.id
        } label: {
            HStack(spacing: DS.space8) {
                Image(systemName: revision.revisionSource.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? DS.accent : DS.textMuted)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(relativeDate(revision.createdAtDate))
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                    HStack(spacing: DS.space6) {
                        Text(revision.revisionSource.displayName)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                        Text(wordCountText(revision.body))
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background(
                isSelected ? DS.surfaceElevated : Color.clear,
                in: .rect(cornerRadius: 8)
            )
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(relativeDate(revision.createdAtDate)), \(revision.revisionSource.displayName)")
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let revision = selected {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.space12) {
                        if let title = revision.title, !title.isEmpty {
                            Text(title)
                                .font(DS.title3)
                                .foregroundStyle(DS.text)
                        }

                        // Excerpt law: never typeset an unbounded body.
                        Text(excerpt(for: revision))
                            .font(DS.callout)
                            .foregroundStyle(DS.textSecondary)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)

                        if (revision.body?.count ?? 0) > CommandKPreviewExcerpt.readingLimit {
                            Text("Showing the first \(CommandKPreviewExcerpt.readingLimit.formatted()) characters — Copy Text grabs everything.")
                                .font(DS.caption2)
                                .foregroundStyle(DS.textMuted)
                        }
                    }
                    .padding(DS.space20)
                }

                Divider().overlay(DS.borderSubtle)
                detailFooter(revision)
            }
        } else {
            Color.clear
        }
    }

    private func detailFooter(_ revision: AtomRevision) -> some View {
        HStack(spacing: DS.space10) {
            if didRestore {
                Label("Restored", systemImage: "checkmark.circle.fill")
                    .font(DS.caption)
                    .foregroundStyle(DS.green)
            }

            Spacer()

            Button("Copy Text") {
                let text = [revision.title, revision.body]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Restore This Version") {
                Task { await restore(revision) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isRestoring)
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
    }

    // MARK: - Data

    private func loadRevisions() async {
        let uuid = atom.uuid
        let loaded: [AtomRevision] = (try? await CosmoDatabase.shared.asyncRead { db in
            try AtomRevision
                .filter(AtomRevision.CodingKeys.atomUuid == uuid)
                .order(AtomRevision.CodingKeys.createdAt.desc)
                .limit(200)
                .fetchAll(db)
        }) ?? []
        revisions = loaded
        selectedID = loaded.first?.id
        isLoading = false
    }

    /// Restore = write the revision's CONTENT (title/body/structured) over the
    /// current atom through the normal update path. The write itself snapshots
    /// the replaced current state (source .restore), so restores are undoable.
    /// Metadata and links stay current — history restores words, not wiring.
    private func restore(_ revision: AtomRevision) async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        restoreError = nil
        // The editing-lock guard exists because an open editor holds its content
        // in @State and would write it straight back over the restore. An editor
        // that registered as an adopter takes the restore into its live state
        // instead, so it is safe to proceed.
        let openEditorAdopts = AtomRestoreAdopterRegistry.shared.canAdopt(uuid: atom.uuid)
        guard openEditorAdopts || !AtomRepository.shared.isBeingEdited(atom.uuid) else {
            restoreBlockedByEditor = true
            return
        }

        // Commit anything the open editor hasn't written yet, so the pre-image
        // this restore snapshots includes the user's latest work — restoring
        // must never be the thing that loses it.
        DirtyEditorRegistry.shared.flushAll()
        guard await AtomRestoreAdopterRegistry.shared.prepare(uuid: atom.uuid) else {
            restoreError = "Your latest edits couldn’t be saved. They are still in the editor. Save them successfully before restoring this version."
            return
        }

        guard let current = try? await AtomRepository.shared.fetch(uuid: atom.uuid) else { return }

        let restored = AtomHistoryRestoreContent.applying(revision, to: current)

        do {
            let saved = try await AtomRepository.shared.update(restored, revisionSource: .restore)
            didRestore = true
            AtomRestoreAdopterRegistry.shared.adopt(saved)
            NotificationCenter.default.post(name: .atomsDidChange, object: nil)
            await loadRevisions()
        } catch {
            restoreError = error.localizedDescription
            print("AtomHistorySheet: restore failed for \(atom.uuid.prefix(8)): \(error)")
        }
    }

    // MARK: - Formatting

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func wordCountText(_ body: String?) -> String {
        let count = body?.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count ?? 0
        return "\(count)w"
    }

    private func excerpt(for revision: AtomRevision) -> String {
        let body = revision.body ?? ""
        guard !body.isEmpty else { return "No body content in this revision." }
        return CommandKPreviewExcerpt.clamp(body, limit: CommandKPreviewExcerpt.readingLimit)
    }
}


/// Restores canonical words while keeping current styling and Space wiring.
/// Older revisions predate rich metadata; their plain text, including an empty
/// field, must replace the current rich document rather than leave it visible.
enum AtomHistoryRestoreContent {
    static func applying(_ revision: AtomRevision, to current: Atom) -> Atom {
        var restored = current
        restored.title = revision.title
        restored.body = revision.body
        restored.structured = revision.structured

        let titleDocument: RichDocument?
        let bodyDocument: RichDocument?
        if current.type == .note {
            titleDocument = RichDocumentPersistence.loadAtomDocument(field: .title,
                metadata: revision.metadata, fallbackPlainText: revision.title)
            bodyDocument = RichDocumentPersistence.loadAtomDocument(field: .body,
                metadata: revision.metadata, fallbackPlainText: revision.body)
        } else {
            titleDocument = RichDocumentMetadataStorage.readDocument(
                from: revision.metadata, key: RichDocumentField.title.metadataKey)
            bodyDocument = RichDocumentMetadataStorage.readDocument(
                from: revision.metadata, key: RichDocumentField.body.metadataKey)
        }
        if titleDocument != nil || bodyDocument != nil {
            let merged = RichDocumentPersistence.writeAtomDocuments(existingMetadata: current.metadata,
                titleDocument: titleDocument, bodyDocument: bodyDocument)
            restored.metadata = merged.metadata
            if titleDocument != nil { restored.title = merged.title }
            if bodyDocument != nil { restored.body = merged.body }
        }
        return restored
    }
}
