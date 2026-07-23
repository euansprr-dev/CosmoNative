// CosmoOS/UI/FocusMode/Connection/ConnectionSectionCardView.swift
// June 2026 — Connection workspace revamp.
// One scannable card per section on the board: header with count, up to three
// item previews, and a quick-add field. Clicking the header opens the section
// detail in the center column.

import SwiftUI

struct ConnectionSectionCardView: View {
    let section: ConnectionSection
    var isSelected: Bool = false
    var highlightQuery: String = ""
    /// Staged concept-collaborator inserts for this section, rendered as ghost
    /// rows with inline ✓/✗ below the real items.
    var pendingInserts: [ConnectionPendingInsert] = []

    /// Media refs anchored to this section — a thumbnail strip between the
    /// item previews and the quick-add.
    var anchoredMedia: [ConnectionMediaItem] = []
    var mediaAtoms: [String: Atom] = [:]
    /// Collaborator-staged rebuttals for THIS card's objections (Beliefs &
    /// Objections only) — ghost threads with ✓/✗.
    var stagedHandlings: [StagedObjectionHandling] = []
    /// Resolves a board ref for staged-handling link labels.
    var resolveBoardRef: (ConnectionBoardItemRef) -> (section: ConnectionSectionType, item: ConnectionItem)? = { _ in nil }

    var onOpen: () -> Void = {}
    var onSelect: () -> Void = {}
    var onAddItem: (RichDocument, String) -> Void = { _, _ in }
    var onSourceTap: (String) -> Void = { _ in }
    var onAcceptInsert: (ConnectionPendingInsert) -> Void = { _ in }
    var onRejectInsert: (ConnectionPendingInsert) -> Void = { _ in }
    /// Media tile actions (open lightbox, context menu) — the workspace's.
    var mediaActions: ConnectionWorkspaceActions = ConnectionWorkspaceActions()

    @State private var isHovered = false

    private var accent: Color { section.type.accentColor }
    private var previewItems: [ConnectionItem] { Array(section.items.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            header
            if section.items.isEmpty && pendingInserts.isEmpty {
                emptyPrompt
            } else if !section.items.isEmpty {
                previewList
            }
            if !pendingInserts.isEmpty {
                pendingList
            }
            if !stagedHandlings.isEmpty {
                stagedHandlingList
            }
            if !anchoredMedia.isEmpty {
                mediaStrip
            }
            ConnectionQuickAddField(accent: accent, sectionName: section.type.displayName, onSubmit: onAddItem)
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardSurface)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(cardBorder)
        .shadow(
            color: .black.opacity(isHovered ? 0.10 : 0.05),
            radius: isHovered ? 10 : 4,
            y: isHovered ? 4 : 1
        )
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .contentShape(.rect(cornerRadius: 12))
        .onTapGesture(count: 2) { onOpen() }
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(section.type.displayName), \(section.itemCount) items")
    }

    private var cardSurface: some ShapeStyle {
        DS.surfaceElevated
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(
                isSelected ? accent.opacity(0.55) : (isHovered ? DS.border : DS.borderSubtle),
                lineWidth: isSelected ? 1.2 : 1
            )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: section.type.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(section.type.displayName)
                .font(DS.headline)
                .foregroundStyle(DS.text)

            if section.itemCount > 0 {
                Text("\(section.itemCount)")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DS.space6)
                    .padding(.vertical, 1)
                    .background(DS.border.opacity(0.6), in: Capsule())
            }

            Spacer(minLength: 0)

            Button(action: onOpen) {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("Open \(section.type.displayName)")
            .accessibilityLabel("Open \(section.type.displayName)")
        }
    }

    // MARK: - Staged handlings

    /// Ghost rebuttal threads on the board card — each names its objection
    /// so the card reads standalone.
    private var stagedHandlingList: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            ForEach(stagedHandlings) { staged in
                StagedObjectionHandlingRow(
                    staged: staged,
                    showsObjectionSnippet: true,
                    resolveRef: resolveBoardRef,
                    onAccept: { mediaActions.onAcceptStagedHandling(staged.id) },
                    onReject: { mediaActions.onRejectStagedHandling(staged.id) }
                )
            }
        }
    }

    // MARK: - Media strip

    /// Up to three anchored thumbnails in a row; the overflow count opens the
    /// section detail where the full set lives.
    private var mediaStrip: some View {
        HStack(spacing: DS.space6) {
            ForEach(anchoredMedia.prefix(3)) { item in
                ConceptMediaTile(
                    item: item,
                    atom: item.atomUUID.flatMap { mediaAtoms[$0] },
                    actions: mediaActions,
                    tileAspect: 1.4
                )
                .frame(maxWidth: 96)
            }
            if anchoredMedia.count > 3 {
                Text("+\(anchoredMedia.count - 3)")
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(DS.glassSectionFill, in: .rect(cornerRadius: 8))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Body content

    private var emptyPrompt: some View {
        Text(section.type.promptQuestion)
            .font(DS.callout)
            .italic()
            .foregroundStyle(DS.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DS.space2)
    }

    private var previewList: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ForEach(previewItems) { item in
                ConnectionItemPreviewRow(
                    item: item,
                    accent: accent,
                    highlightQuery: highlightQuery,
                    objectionBadge: section.type == .beliefsObjections
                )
            }
            if section.itemCount > previewItems.count {
                Button(action: onOpen) {
                    Text("\(section.itemCount - previewItems.count) more…")
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 13)
            }
        }
    }

    // MARK: - Staged inserts

    private var pendingList: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            ForEach(pendingInserts) { insert in
                ConnectionPendingInsertRow(
                    insert: insert,
                    accent: accent,
                    onAccept: onAcceptInsert,
                    onReject: onRejectInsert
                )
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Staged insert row (ghost)

/// A not-yet-accepted concept-collaborator insert shown in place — dashed,
/// accent-tinted, with the proposed bullet(s) and a ✓/✗ pair. Accepting routes
/// through the same per-operation apply path as the old full-screen diff.
/// A row with `revisesText` is a REVISION of an existing entry: the current
/// wording shows struck-through above the proposed one.
struct ConnectionPendingInsertRow: View {
    let insert: ConnectionPendingInsert
    let accent: Color
    var onAccept: (ConnectionPendingInsert) -> Void = { _ in }
    var onReject: (ConnectionPendingInsert) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            // Sparkles = collaborator proposal; pencil = revision of an
            // existing entry; tray = your own captured material waiting to be
            // swept in (inbox feed, seedling develop).
            Image(systemName: glyph)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.top, 3)
                .accessibilityHidden(true)

            content

            HStack(spacing: DS.space4) {
                decisionButton(system: "checkmark", tint: accent, label: "Accept") { onAccept(insert) }
                decisionButton(system: "xmark", tint: DS.textMuted, label: "Dismiss") { onReject(insert) }
            }
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space6)
        .background(accent.opacity(0.08), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var glyph: String {
        if insert.isRevision { return "pencil" }
        return insert.isFromCapture ? "tray.and.arrow.down" : "sparkles"
    }

    private var content: some View {
        // Each bullet previews as its own dotted row — the exact rows that
        // will land in the section — so a multi-item capture never reads
        // as one blob before it's accepted.
        VStack(alignment: .leading, spacing: DS.space6) {
            if let revises = insert.revisesText {
                Text(revises)
                    .font(DS.callout)
                    .strikethrough(true, color: DS.textMuted)
                    .foregroundStyle(DS.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(insert.bullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .top, spacing: DS.space8) {
                    Circle()
                        .fill(accent.opacity(0.9))
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                        .accessibilityHidden(true)
                    Text(bullet)
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let after = insert.afterText {
                Text("after: \(after)")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
        }
    }

    private var accessibilityText: String {
        let joined = insert.bullets.joined(separator: ", ")
        if let revises = insert.revisesText {
            return "Suggested revision, replacing \(revises) with: \(joined)"
        }
        if insert.isFromCapture {
            return "From your inbox, waiting to be swept in: \(joined)"
        }
        if let after = insert.afterText {
            return "Suggested for this section after \(after): \(joined)"
        }
        return "Suggested for this section: \(joined)"
    }

    private func decisionButton(
        system: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Item preview row

struct ConnectionItemPreviewRow: View {
    let item: ConnectionItem
    let accent: Color
    var highlightQuery: String = ""
    var lineLimit: Int = 2
    /// Beliefs & Objections rows wear their handled/open shield.
    var objectionBadge: Bool = false

    private var isMatch: Bool {
        !highlightQuery.isEmpty &&
        item.resolvedPlainText.localizedCaseInsensitiveContains(highlightQuery)
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            if item.isConnectionLink {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(CosmoMentionColors.connection)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            } else {
                Circle()
                    .fill(accent.opacity(0.9))
                    .frame(width: 5, height: 5)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }
            ConnectionLinkedText(
                text: item.resolvedPlainText,
                font: DS.callout,
                color: item.isConnectionLink ? CosmoMentionColors.connection : DS.text,
                mentions: item.explicitMentions,
                lineLimit: lineLimit
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            if objectionBadge {
                ObjectionStatusBadge(isHandled: item.isHandled)
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, isMatch ? DS.space4 : 0)
        .background(isMatch ? accent.opacity(0.10) : .clear, in: .rect(cornerRadius: 4))
    }
}

// MARK: - Quick add

struct ConnectionQuickAddField: View {
    let accent: Color
    let sectionName: String
    let onSubmit: (RichDocument, String) -> Void

    @State private var text = ""
    @State private var mentions: [RichMention] = []
    /// Non-nil while the user is typing an @-query; drives the same context
    /// menu the inline assistant's composer uses.
    @State private var mentionQuery: String? = nil
    @State private var mentionInsertionPoint: String.Index? = nil
    @State private var menuModel = CosmoInlineContextMenuModel()
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            fieldRow
            if let query = mentionQuery {
                mentionMenu(query: query)
            }
        }
        .animation(ProMotionSprings.hover, value: mentionQuery == nil)
        .accessibilityLabel("Add item to \(sectionName)")
    }

    private var fieldRow: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isFocused ? accent : DS.textMuted)
                .accessibilityHidden(true)
            TextField("Add to \(sectionName)", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineLimit(1...4)
                .focused($isFocused)
                .onSubmit(submit)
                .onChange(of: text) { detectMentionTrigger() }
                .onKeyPress(.escape) { handleEscape() }
                .onKeyPress(.upArrow) { routeMenuKey { menuModel.moveHighlight(-1) } }
                .onKeyPress(.downArrow) { routeMenuKey { menuModel.moveHighlight(1) } }
                .onKeyPress(.tab) { commitHighlightedMention() }
                .onKeyPress(.return) { commitHighlightedMention() }
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space6)
        .background(isFocused ? DS.bg : .clear, in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? accent.opacity(0.4) : DS.borderSubtle.opacity(0.6), lineWidth: 1)
        )
        .animation(ProMotionSprings.hover, value: isFocused)
    }

    /// The inline assistant's own @ menu, hosted inline so the card grows
    /// beneath the field instead of clipping an overlay.
    private func mentionMenu(query: String) -> some View {
        CosmoInlineAssistantContextMenu(
            model: menuModel,
            searchText: query,
            selectedAtoms: [],
            onCommit: { entry in insertMention(entry.atom) },
            onClear: {},
            menuWidth: nil
        )
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Mention trigger (same contract as TaskTitleMentionField)

    private func detectMentionTrigger() {
        guard let atIndex = text.lastIndex(of: "@") else {
            dismissMention()
            return
        }
        let afterAt = String(text[text.index(after: atIndex)...])
        // Skip "@" runs that are already committed mentions.
        guard !mentions.contains(where: { afterAt.hasPrefix($0.titleSnapshot) }),
              !afterAt.contains("\n"), afterAt.count <= 30 else {
            dismissMention()
            return
        }
        mentionInsertionPoint = atIndex
        mentionQuery = afterAt
    }

    private func insertMention(_ atom: Atom) {
        guard let atIndex = mentionInsertionPoint else { return }
        let title = atom.title ?? "Untitled"
        text.replaceSubrange(atIndex..<text.endIndex, with: "@\(title) ")
        let mention = RichMention(
            entityUUID: atom.uuid,
            entityID: atom.id,
            entityType: EntityType(rawValue: atom.type.rawValue) ?? .note,
            titleSnapshot: title
        )
        if !mentions.contains(where: { $0.entityUUID == mention.entityUUID }) {
            mentions.append(mention)
        }
        dismissMention()
    }

    private func dismissMention() {
        mentionQuery = nil
        mentionInsertionPoint = nil
    }

    // MARK: - Keys

    private func handleEscape() -> KeyPress.Result {
        if mentionQuery != nil {
            dismissMention()
            return .handled
        }
        text = ""
        mentions = []
        isFocused = false
        return .handled
    }

    private func routeMenuKey(_ action: () -> Void) -> KeyPress.Result {
        guard mentionQuery != nil else { return .ignored }
        action()
        return .handled
    }

    private func commitHighlightedMention() -> KeyPress.Result {
        guard mentionQuery != nil else { return .ignored }
        guard let entry = menuModel.highlightedEntry else {
            dismissMention()
            return .handled
        }
        insertMention(entry.atom)
        return .handled
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Mentions whose "@Title" run survived editing become mention inlines.
        let live = mentions.filter { trimmed.contains($0.displayText) }
        let parsed = ConceptMentionToken.document(text: trimmed, mentions: live)
        onSubmit(parsed.document, parsed.plainText)
        text = ""
        mentions = []
        dismissMention()
    }
}
