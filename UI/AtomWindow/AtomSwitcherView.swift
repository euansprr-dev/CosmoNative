// CosmoOS/UI/AtomWindow/AtomSwitcherView.swift
// The Atom window's switcher surface: the bar, one hero search field with
// scope pills, a results rail beside the Command-K detail pane, and a
// footer that teaches the keyboard. Where "Back" from any item lands.

import AppKit
import SwiftUI

struct AtomSwitcherView: View {
    @Bindable var model: AtomSwitcherModel
    let chrome: AtomWindowChromePayload
    let onOpen: (AtomSwitcherRow) -> Void
    let onOpenInMainWindow: (AtomSwitcherRow) -> Void
    let onTogglePin: (AtomSwitcherRow) -> Void
    let onCreateFromQuery: (String) -> Void
    let onReturnToOpenItem: () -> Void
    let onEscape: () -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var hasAppeared = false

    var body: some View {
        GeometryReader { geometry in
            let showsPreview = geometry.size.width >= AtomWindowMetrics.switcherPreviewBreakpoint
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, DS.space16)
                    .padding(.top, DS.space12)
                hero(width: geometry.size.width)
                Rectangle()
                    .fill(DS.commandChromeSeparatorStrong)
                    .frame(height: 0.5)
                content(showsPreview: showsPreview, width: geometry.size.width)
                footer
            }
        }
        .onAppear { isSearchFocused = true }
        .task(id: model.sections.isEmpty) { await arrive() }
        .onKeyPress(.escape) { onEscape(); return .handled }
        .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
        .onKeyPress(keys: [.tab]) { press in
            model.cycleScope(by: press.modifiers.contains(.shift) ? -1 : 1)
            return .handled
        }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard press.modifiers.contains(.command),
                  let digit = Int(press.characters),
                  let scope = AtomSwitcherScope.allCases.first(where: { $0.shortcutDigit == digit }) else {
                return .ignored
            }
            model.setScope(scope)
            return .handled
        }
    }

    // MARK: Bar

    private var header: some View {
        CosmoChromeRow(insetsEnabled: false) {
            CosmoChromeIsland {
                AtomWindowChromeLeadingControls(context: chrome, showsTitle: false)
            }
        } center: {
            EmptyView()
        } trailing: {
            CosmoChromeIsland {
                if let title = model.openTitle {
                    AtomSwitcherReturnButton(
                        title: title,
                        icon: chrome.state.typeIcon,
                        tint: chrome.state.typeColor.color,
                        action: onReturnToOpenItem
                    )
                    AtomWindowChromeDivider()
                }
                AtomWindowChromeCreateMenu(context: chrome)
            }
        }
        .frame(height: AtomWindowMetrics.focusToolbarHeight)
    }

    // MARK: Hero

    private func hero(width: CGFloat) -> some View {
        VStack(spacing: DS.space12) {
            searchField
                .frame(maxWidth: AtomWindowMetrics.switcherFieldMaxWidth)
                .padding(.horizontal, DS.space24)
            scopeRow(width: width)
        }
        .padding(.top, DS.space20)
        .padding(.bottom, DS.space16)
    }

    private var searchField: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: "magnifyingglass")
                .font(DS.headline)
                .foregroundStyle(isSearchFocused ? DS.accent : DS.textMuted)
                .accessibilityHidden(true)

            TextField(model.scope.placeholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(DS.title2.weight(.regular))
                .foregroundStyle(DS.text)
                .focused($isSearchFocused)
                .onChange(of: model.query) { model.queryDidChange() }
                .onSubmit(submitSearchField)
                .accessibilityLabel(model.scope.placeholder)

            if !model.query.isEmpty {
                Button {
                    model.clearQuery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.callout)
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear (esc)")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DS.space16)
        .frame(height: AtomWindowMetrics.switcherFieldHeight)
        .dsGlassInput(isFocused: isSearchFocused, cornerRadius: 16)
        .animation(ProMotionSprings.hover, value: isSearchFocused)
    }

    private func scopeRow(width: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space6) {
                ForEach(AtomSwitcherScope.allCases) { scope in
                    AtomSwitcherScopePill(
                        scope: scope,
                        isActive: model.scope == scope
                    ) { model.setScope(scope) }
                }
            }
            .padding(.horizontal, DS.space24)
            .frame(minWidth: width)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: 28)
    }

    // MARK: Body

    private func content(showsPreview: Bool, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            rail(opensOnSelect: !showsPreview)
                .frame(maxWidth: .infinity)
            if showsPreview {
                Rectangle()
                    .fill(DS.commandChromeSeparatorStrong)
                    .frame(width: 0.5)
                preview
                    .frame(width: AtomWindowMetrics.switcherPreviewWidth(for: width))
            }
        }
        .frame(maxHeight: .infinity)
        // ONE ground for results and previews (the Command-K anatomy):
        // content sits on near-opaque paper; only the bar above is glass.
        .background(DS.bg.opacity(0.96))
    }

    private func rail(opensOnSelect: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.space6) {
                    ForEach(Array(model.sections.enumerated()), id: \.element.id) { index, section in
                        CosmoSectionHeader(label: section.title, detail: "\(section.count)")
                            .padding(.top, index == 0 ? DS.space4 : DS.space16)
                            .padding(.bottom, DS.space2)
                            .padding(.horizontal, DS.space8)
                            .cascadeIn(hasAppeared, index: min(index, 8))
                        ForEach(section.rows) { row in
                            AtomSwitcherRowView(
                                row: row,
                                query: model.query,
                                isSelected: row.id == model.selectedID,
                                onSelect: {
                                    model.select(row.id)
                                    if opensOnSelect { onOpen(row) }
                                },
                                onOpen: { onOpen(row) },
                                onOpenInMainWindow: { onOpenInMainWindow(row) },
                                onTogglePin: { onTogglePin(row) }
                            )
                            .id(row.id)
                            .cascadeIn(hasAppeared, index: min(index, 8))
                        }
                    }
                    if model.sections.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, DS.space16)
                .padding(.vertical, DS.space12)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                withAnimation(ProMotionSprings.snappy) { proxy.scrollTo(id, anchor: nil) }
            }
        }
    }

    private var preview: some View {
        Group {
            if let row = model.selectedRow {
                CortexDetailPane(subject: model.previewSubject(for: row))
            } else {
                CortexDetailPane(subject: .empty)
            }
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    // MARK: Empty / teaching states

    @ViewBuilder
    private var emptyState: some View {
        let query = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            AtomSwitcherTeachingState(
                title: "Nothing matches “\(query)”",
                detail: model.scope == .everything
                    ? "Try fewer words, or start it fresh."
                    : "Not in \(model.scope.title.lowercased()). Try everything (⇥), or start it fresh.",
                actionTitle: "Create page “\(query)”",
                actionIcon: "plus",
                action: { onCreateFromQuery(query) }
            )
        } else if model.scope == .everything {
            AtomSwitcherTeachingState(
                title: "Nothing to continue yet",
                detail: "Create a page and it will wait for you here.",
                actionTitle: "New page",
                actionIcon: "plus",
                action: { chrome.actions.createAtom(.note) }
            )
        } else {
            AtomSwitcherTeachingState(
                title: "No \(model.scope.title.lowercased()) yet",
                detail: "Everything you make of this kind will list here, newest first.",
                actionTitle: nil,
                actionIcon: nil,
                action: nil
            )
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: DS.space16) {
            AtomSwitcherHint(keys: ["arrow.up", "arrow.down"], label: "Navigate")
            AtomSwitcherHint(keys: ["return"], label: "Open")
            AtomSwitcherHint(keys: ["command", "return"], label: "Open in Cosmo")
            AtomSwitcherHint(keys: ["arrow.right.to.line"], label: "Scope")
            Spacer(minLength: 0)
            if model.isDeepSearching {
                Text("Searching deeper")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .transition(.opacity)
            }
            AtomSwitcherHint(keys: ["escape"], label: escapeLabel)
        }
        .padding(.horizontal, DS.space16)
        .frame(height: AtomWindowMetrics.switcherFooterHeight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DS.commandChromeSeparatorStrong)
                .frame(height: 0.5)
        }
        .animation(ProMotionSprings.gentle, value: model.isDeepSearching)
    }

    private var escapeLabel: String {
        switch model.escapeAction {
        case .clearQuery: "Clear"
        case .returnToOpenItem: "Back to \(model.openTitle ?? "item")"
        case .closeWindow: "Close"
        }
    }

    // MARK: Actions

    /// Return commits the selection; ⌘Return opens it in the main window.
    /// `onSubmit` carries no modifiers, so the flags are read off the event.
    private func submitSearchField() {
        guard let row = model.selectedRow else { return }
        if NSEvent.modifierFlags.contains(.command) {
            onOpenInMainWindow(row)
        } else {
            onOpen(row)
        }
    }

    /// The rail assembles once, a frame after its first data lands —
    /// flipped in the same update, rows mount already visible.
    private func arrive() async {
        guard !hasAppeared, !model.sections.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(16))
        guard !Task.isCancelled else { return }
        hasAppeared = true
    }
}

// MARK: - Row

private struct AtomSwitcherRowView: View {
    let row: AtomSwitcherRow
    let query: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onOpenInMainWindow: () -> Void
    let onTogglePin: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.space12) {
            mark
            VStack(alignment: .leading, spacing: DS.space2) {
                HStack(spacing: DS.space6) {
                    Text(row.title)
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                    if row.isOpen {
                        Text("Open")
                            .font(DS.caption2.weight(.semibold))
                            .foregroundStyle(DS.accent)
                            .padding(.horizontal, DS.space6)
                            .padding(.vertical, 1)
                            .background(DS.accentSoft, in: Capsule())
                    }
                }
                secondLine
            }
            Spacer(minLength: 0)
            pinButton
        }
        .padding(DS.space8)
        .background(rowBackground)
        .overlay(rowBorder)
        .clipShape(.rect(cornerRadius: DS.radiusMedium))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture { onSelect() }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .contextMenu {
            Button("Open", action: onOpen)
            Button("Open in Cosmo", action: onOpenInMainWindow)
            Divider()
            Button(row.isPinned ? "Unpin" : "Pin", action: onTogglePin)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(row.subtitle)\(row.isOpen ? ", open" : "")")
        .accessibilityHint("Press return to open")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private var secondLine: some View {
        if let excerpt = row.excerpt, !query.isEmpty {
            Text(CommandKMatchHighlighter.attributed(
                excerpt, query: query,
                baseColor: DS.inkFaded, emphasisColor: DS.text, font: DS.caption2
            ))
            .lineLimit(1)
        } else {
            Text(row.subtitle)
                .font(DS.caption2)
                .foregroundStyle(DS.inkFaded)
                .lineLimit(1)
        }
    }

    /// Icon territory (Raycast): real media keeps its thumbnail, everything
    /// else wears the compact identity chip — excerpts live in the pane.
    @ViewBuilder
    private var mark: some View {
        if let url = row.thumbnailURL, !url.isEmpty {
            SpotlightImageContent(urlString: url)
                .frame(width: AtomWindowMetrics.switcherMarkSize.width, height: AtomWindowMetrics.switcherMarkSize.height)
                .clipShape(.rect(cornerRadius: DS.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                        .strokeBorder(DS.commandChromeSeparator, lineWidth: 0.5)
                )
        } else {
            CosmoIdentityChip(icon: row.icon, tint: row.accent)
                .frame(width: AtomWindowMetrics.switcherMarkSize.width, height: AtomWindowMetrics.switcherMarkSize.height)
        }
    }

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: row.isPinned ? "pin.fill" : "pin")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(row.isPinned ? DS.textSecondary : DS.textMuted)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(row.isPinned || isHovered ? 1 : 0)
        .help(row.isPinned ? "Unpin" : "Pin to the switcher")
        .accessibilityLabel(row.isPinned ? "Unpin" : "Pin")
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .fill(isSelected ? row.accent.opacity(0.10) : (isHovered ? DS.surfaceHover.opacity(0.40) : Color.clear))
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .strokeBorder(
                isSelected ? row.accent.opacity(0.45) : (isHovered ? DS.commandChromeSeparator : Color.clear),
                lineWidth: isSelected ? 1 : 0.5
            )
    }
}

// MARK: - Scope pill

private struct AtomSwitcherScopePill: View {
    let scope: AtomSwitcherScope
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                Image(cosmo: scope.icon)
                    .font(DS.caption2.weight(.semibold))
                    .accessibilityHidden(true)
                Text(scope.title)
                    .font(DS.footnote.weight(.semibold))
            }
            .foregroundStyle(isActive ? DS.accent : DS.textSecondary)
            .padding(.horizontal, DS.space10)
            .frame(height: 28)
            .background(
                Capsule().fill(isActive ? DS.accent.opacity(0.14) : DS.glassInputFill.opacity(isHovered ? 1 : 0.7))
            )
            .overlay(
                Capsule().strokeBorder(isActive ? DS.accent.opacity(0.42) : DS.glassBorder, lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .animation(ProMotionSprings.snappy, value: isActive)
        .help("\(scope.title) (⌘\(scope.shortcutDigit))")
        .accessibilityLabel(scope.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Return button (bar)

/// The way back to the open item: its mark and title, with the key that
/// does the same thing.
private struct AtomSwitcherReturnButton: View {
    let title: String
    let icon: CosmoIcon
    let tint: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space6) {
                Image(cosmo: icon)
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(DS.buttonText.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 180, alignment: .leading)
                CortexKeycap(symbol: "escape")
            }
            .padding(.horizontal, DS.space8)
            .frame(height: 28)
            .background(Capsule().fill(DS.glassCardFill.opacity(isHovered ? 0.9 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Back to \(title) (esc)")
        .accessibilityLabel("Back to \(title)")
    }
}

// MARK: - Footer hint

private struct AtomSwitcherHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: DS.space4) {
            HStack(spacing: 2) {
                ForEach(keys, id: \.self) { CortexKeycap(symbol: $0) }
            }
            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Teaching state

private struct AtomSwitcherTeachingState: View {
    let title: String
    let detail: String
    let actionTitle: String?
    let actionIcon: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(title)
                .font(DS.headline)
                .foregroundStyle(DS.text)
            Text(detail)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: DS.space6) {
                        if let actionIcon {
                            Image(systemName: actionIcon)
                                .font(DS.caption.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                        Text(actionTitle)
                            .font(DS.buttonText.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, DS.space6)
                    .background(DS.accentSoft, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, DS.space6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.space16)
        .padding(.top, DS.space24)
    }
}
