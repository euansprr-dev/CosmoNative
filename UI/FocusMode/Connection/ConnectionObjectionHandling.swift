// CosmoOS/UI/FocusMode/Connection/ConnectionObjectionHandling.swift
// Objection resolution on the concept board (July 2026): an objection in
// Beliefs & Objections can be HANDLED — a comment-style rebuttal thread
// beneath the row (the swipe slide-comment grammar), optionally citing other
// board entries ("this Examples entry answers it") as tappable chips that
// jump to their section. The thread rides ConnectionItem.handling through
// the existing sections sync; the AI sees it as a read-only `↳ handled:`
// line in the surface text.

import SwiftUI

// MARK: - Thread (display)

/// The handled state under an objection row: shield mark, rebuttal text,
/// evidence chips, quiet edit/reopen controls on hover.
struct ObjectionHandlingThread: View {
    let handling: ObjectionHandling
    /// Resolves a ref to its live section + item (nil = entry was deleted).
    let resolveRef: (ConnectionBoardItemRef) -> (section: ConnectionSectionType, item: ConnectionItem)?
    let onJump: (ConnectionBoardItemRef) -> Void
    let onEdit: () -> Void
    let onReopen: () -> Void

    @State private var isHovered = false

    private let handledTint = Color(hex: "#22C55E") // evidence green

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            HStack(alignment: .firstTextBaseline, spacing: DS.space6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(handledTint)
                    .accessibilityHidden(true)
                Text("Handled")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(handledTint)
                Spacer(minLength: 0)
                controls
            }
            if !handling.text.isEmpty {
                Text(handling.text)
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !handling.linkedRefs.isEmpty {
                linkChips
            }
        }
        .padding(DS.space10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(handledTint.opacity(0.06), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(handledTint.opacity(0.25), lineWidth: 1)
        )
        .padding(.leading, DS.space16)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Objection handled: \(handling.text)")
    }

    private var controls: some View {
        HStack(spacing: DS.space8) {
            Button("Edit", action: onEdit)
                .buttonStyle(.plain)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.textMuted)
                .accessibilityLabel("Edit handling")
            Button("Reopen", action: onReopen)
                .buttonStyle(.plain)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.textMuted)
                .help("Remove the response — the objection goes back to open")
                .accessibilityLabel("Reopen objection")
        }
        .opacity(isHovered ? 1 : 0)
    }

    private var linkChips: some View {
        // Wrapping chip row — refs are few (≤4 realistically).
        HStack(spacing: DS.space6) {
            ForEach(Array(handling.linkedRefs.enumerated()), id: \.offset) { _, ref in
                linkChip(ref)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func linkChip(_ ref: ConnectionBoardItemRef) -> some View {
        if let resolved = resolveRef(ref) {
            Button {
                onJump(ref)
            } label: {
                HStack(spacing: DS.space4) {
                    Image(systemName: resolved.section.icon)
                        .font(.system(size: 8, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(String(resolved.item.resolvedPlainText.prefix(36)))
                        .font(DS.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(resolved.section.accentColor)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, 3)
                .background(resolved.section.accentColor.opacity(0.1), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Jump to \(resolved.section.displayName)")
            .accessibilityLabel("Answered by \(resolved.section.displayName): \(resolved.item.resolvedPlainText)")
        } else {
            Label("missing entry", systemImage: "questionmark.circle")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .help("The linked entry was removed from the board")
        }
    }
}

// MARK: - Composer (edit)

/// The comment-box composer beneath an objection: response field, "Answered
/// by…" evidence menu (multi-select across the whole board), Save/Cancel.
struct ObjectionHandlingComposer: View {
    /// All board sections, for the evidence-link menu (objection's own
    /// section excluded — an objection can't answer itself).
    let sections: [ConnectionSection]
    let objectionItemID: UUID
    var initial: ObjectionHandling?
    let onSave: (String, [ConnectionBoardItemRef]) -> Void
    let onCancel: () -> Void

    @State private var responseText: String = ""
    @State private var linkedRefs: [ConnectionBoardItemRef] = []
    @FocusState private var fieldFocused: Bool

    private let handledTint = Color(hex: "#22C55E")

    /// Sections that can hold an answering entry, with their items.
    private var linkableSections: [ConnectionSection] {
        sections.filter { section in
            section.type != .beliefsObjections && section.type != .conceptName && !section.items.isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            TextField("How do you answer this objection?", text: $responseText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineLimit(1...5)
                .focused($fieldFocused)
                .onSubmit(save)
                .accessibilityLabel("Objection response")
            if !linkedRefs.isEmpty {
                selectedChips
            }
            HStack(spacing: DS.space10) {
                evidenceMenu
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.textMuted)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.plain)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(canSave ? handledTint : DS.textMuted)
                    .disabled(!canSave)
                    .accessibilityLabel("Save handling")
            }
        }
        .padding(DS.space10)
        .background(DS.bg, in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(handledTint.opacity(0.35), lineWidth: 1)
        )
        .padding(.leading, DS.space16)
        .onAppear {
            responseText = initial?.text ?? ""
            linkedRefs = initial?.linkedRefs ?? []
            fieldFocused = true
        }
    }

    private var canSave: Bool {
        !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !linkedRefs.isEmpty
    }

    private func save() {
        guard canSave else { return }
        onSave(responseText, linkedRefs)
    }

    // MARK: Evidence links

    private var selectedChips: some View {
        HStack(spacing: DS.space6) {
            ForEach(Array(linkedRefs.enumerated()), id: \.offset) { index, ref in
                if let section = ref.section,
                   let item = sections.first(where: { $0.type == section })?.items.first(where: { $0.id == ref.itemID }) {
                    HStack(spacing: DS.space4) {
                        Text(String(item.resolvedPlainText.prefix(30)))
                            .font(DS.caption)
                            .lineLimit(1)
                        Button {
                            linkedRefs.remove(at: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove link")
                    }
                    .foregroundStyle(section.accentColor)
                    .padding(.horizontal, DS.space8)
                    .padding(.vertical, 3)
                    .background(section.accentColor.opacity(0.1), in: Capsule())
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var evidenceMenu: some View {
        Menu {
            ForEach(linkableSections) { section in
                Section(section.type.displayName) {
                    ForEach(section.items) { item in
                        Button {
                            toggleRef(section: section.type, itemID: item.id)
                        } label: {
                            if linkedRefs.contains(where: { $0.itemID == item.id }) {
                                Label(String(item.resolvedPlainText.prefix(56)), systemImage: "checkmark")
                            } else {
                                Text(String(item.resolvedPlainText.prefix(56)))
                            }
                        }
                    }
                }
            }
        } label: {
            Label(
                linkedRefs.isEmpty ? "Answered by…" : "Answered by (\(linkedRefs.count))",
                systemImage: "link"
            )
            .font(DS.caption.weight(.medium))
            .foregroundStyle(DS.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(linkableSections.isEmpty)
        .help("Cite a board entry that answers this objection")
        .accessibilityLabel("Link answering board entries")
    }

    private func toggleRef(section: ConnectionSectionType, itemID: UUID) {
        if let index = linkedRefs.firstIndex(where: { $0.itemID == itemID }) {
            linkedRefs.remove(at: index)
        } else {
            linkedRefs.append(ConnectionBoardItemRef(section: section, itemID: itemID))
        }
    }
}

// MARK: - Staged (ghost) thread

/// A collaborator-proposed rebuttal awaiting review: the handled thread's
/// shape in ghost dress — dashed border, sparkles mark, its own ✓/✗. The
/// objection snippet rides along so board-card ghosts read standalone.
struct StagedObjectionHandlingRow: View {
    let staged: StagedObjectionHandling
    /// Show the objection snippet header (board card, where the row can sit
    /// apart from its objection). Detail/outline rows sit directly under it.
    var showsObjectionSnippet: Bool = false
    let resolveRef: (ConnectionBoardItemRef) -> (section: ConnectionSectionType, item: ConnectionItem)?
    let onAccept: () -> Void
    let onReject: () -> Void

    private let handledTint = Color(hex: "#22C55E")

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            HStack(alignment: .firstTextBaseline, spacing: DS.space6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(handledTint)
                    .accessibilityHidden(true)
                Text("Suggested handling")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(handledTint)
                Spacer(minLength: 0)
                decisionButtons
            }
            if showsObjectionSnippet, !staged.objectionSnippet.isEmpty {
                Text("for: \(staged.objectionSnippet)")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(2)
            }
            Text(staged.text)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !staged.linkedRefs.isEmpty {
                linkedLine
            }
        }
        .padding(DS.space10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(handledTint.opacity(0.05), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(handledTint.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        )
        .padding(.leading, DS.space16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested handling awaiting review: \(staged.text). Accept or dismiss.")
    }

    private var decisionButtons: some View {
        HStack(spacing: DS.space6) {
            Button(action: onAccept) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(handledTint)
                    .frame(width: 26, height: 26)
                    .background(handledTint.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Mark the objection handled with this response")
            .accessibilityLabel("Accept suggested handling")
            Button(action: onReject) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 26, height: 26)
                    .background(DS.border.opacity(0.5), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss suggested handling")
        }
    }

    private var linkedLine: some View {
        HStack(spacing: DS.space6) {
            ForEach(Array(staged.linkedRefs.enumerated()), id: \.offset) { _, ref in
                if let resolved = resolveRef(ref) {
                    Label(String(resolved.item.resolvedPlainText.prefix(30)), systemImage: resolved.section.icon)
                        .font(DS.caption)
                        .foregroundStyle(resolved.section.accentColor)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Handled badge (board previews)

/// The at-a-glance mark on board-card preview rows: green shield = handled,
/// quiet outline = still open. Only Beliefs & Objections rows wear it.
struct ObjectionStatusBadge: View {
    let isHandled: Bool

    var body: some View {
        Image(systemName: isHandled ? "checkmark.shield.fill" : "shield")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(isHandled ? Color(hex: "#22C55E") : DS.textMuted.opacity(0.6))
            .accessibilityLabel(isHandled ? "Handled" : "Open objection")
    }
}
