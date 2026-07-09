import AppKit
import SwiftUI

enum CosmoInlineAssistantBarVisibilityPolicy {
    static func shouldShow(
        isInlinePaneOpen: Bool,
        focusedEntityType: EntityType? = nil,
        isBlockingOverlayPresented: Bool = false
    ) -> Bool {
        if isBlockingOverlayPresented {
            return false
        }

        // The Deep Dive / Inquiry surfaces have their own permanent capture
        // dock — the global assistant orb would duplicate it there.
        if focusedEntityType == .deepDive || focusedEntityType == .inquirySession {
            return false
        }
        return !isInlinePaneOpen
    }
}

enum CosmoInlineAssistantBarPresentationPolicy {
    static func isExpanded(
        isHovering: Bool,
        isFocused: Bool,
        hasComposerText: Bool,
        isProcessing: Bool
    ) -> Bool {
        isHovering || isFocused || hasComposerText || isProcessing
    }

    static func shouldBlur(clickPoint: CGPoint, barFrame: CGRect) -> Bool {
        guard barFrame.width > 0, barFrame.height > 0 else { return false }
        return !barFrame.insetBy(dx: -10, dy: -10).contains(clickPoint)
    }
}

enum CosmoInlineAssistantBarEscapeAction: Equatable {
    case dismissMenus
    case clearComposer
    case collapse
    case ignore
}

/// Spotlight's Escape ladder: first Esc closes an open inline menu, the next
/// clears the draft, the next collapses the bar. While a run is in flight
/// Escape is left alone — ⌘. is the stop affordance, and silently eating the
/// key while nothing visibly changes would read as a dead control.
enum CosmoInlineAssistantBarEscapePolicy {
    static func action(
        isExpanded: Bool,
        isMenuVisible: Bool,
        hasComposerText: Bool,
        isProcessing: Bool
    ) -> CosmoInlineAssistantBarEscapeAction {
        guard isExpanded else { return .ignore }
        if isMenuVisible { return .dismissMenus }
        guard !isProcessing else { return .ignore }
        if hasComposerText { return .clearComposer }
        return .collapse
    }
}

enum CosmoInlineAssistantBarProcessingPolicy {
    static func leadingText(isProcessing: Bool) -> String {
        isProcessing ? "Working..." : ""
    }

    static func trailingText(statusText: String?, isProcessing: Bool) -> String? {
        guard isProcessing else { return statusText }
        let trimmed = statusText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Reading current context" : trimmed
    }

    static func placeholder(isProcessing: Bool) -> String? {
        isProcessing ? nil : "Describe any change or ask"
    }
}

enum CosmoInlineAssistantContextMentionFormatter {
    // The mention's plain-text token. The type is conveyed by the pill's icon, so the
    // token is just the title (also what `MentionComposerTextView` matches to build pills).
    static func mentionTitle(for atom: Atom) -> String {
        atom.title ?? "Untitled"
    }

    static func accessibilityLabel(for atom: Atom) -> String {
        "\(typeLabel(for: atom)) context: \(atom.title ?? "Untitled")"
    }

    static func typeLabel(for atom: Atom) -> String {
        if atom.isSwipeFileAtom { return "Swipe" }

        switch atom.type {
        case .clientProfile:
            return "Profile"
        case .content:
            return "Content"
        case .idea:
            return "Idea"
        case .research:
            return "Research"
        case .note:
            return "Note"
        case .creator:
            return "Swipe"
        default:
            return atom.type.displayName
        }
    }
}

private struct CosmoInlineAssistantBarFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct CosmoInlineAssistantBarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CosmoInlineAssistantContextMenuFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct CosmoInlineAssistantBar: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let onOpenPane: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isComposerFocused = false
    @State private var isHovering = false
    @State private var isStudioPresented = false
    @State private var isPinnedOpen = false
    @State private var isContextMenuVisible = false
    @State private var isSkillMenuVisible = false
    @State private var contextSearchText = ""
    @State private var skillSearchText = ""
    @State private var composerSelectionRange = NSRange(location: 0, length: 0)
    @State private var barFrame: CGRect = .zero
    @State private var contextMenuFrame: CGRect = .zero
    @State private var availableWidth: CGFloat = 0
    @State private var mouseDownMonitor: Any?
    @State private var keyDownMonitor: Any?
    // Set when Escape collapses the bar while the cursor is still parked on it,
    // so hover doesn't instantly re-expand what the user just dismissed.
    // Cleared the moment the pointer leaves or the pill is clicked.
    @State private var isHoverSuppressed = false
    @State private var contextMenuModel = CosmoInlineContextMenuModel()
    @State private var skillMenuModel = CosmoInlineSkillMenuModel()
    private let skillRegistry = CosmoInlineSkillRegistry()
    private let skillRecency = CosmoInlineSkillRecencyStore()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            morphingBar
            contextMenuLayer
            skillMenuLayer
        }
            // Hover tracking is bound to the bar's own (rounded) bounds — not the
            // full-width strip below — so only the orb itself reacts to the cursor.
            .contentShape(barShape)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    isPinnedOpen = false
                    // Hover signals intent — write the prompt-cache prefix now so the
                    // first real request streams from a warm cache.
                    CosmoInlineAssistantCacheWarmer.warmIfNeeded()
                } else {
                    isHoverSuppressed = false
                    collapseIfIdle()
                }
            }
            .frame(maxWidth: .infinity)
            .background(widthReader)
            .onPreferenceChange(CosmoInlineAssistantBarWidthPreferenceKey.self) { availableWidth = $0 }
            .onPreferenceChange(CosmoInlineAssistantBarFramePreferenceKey.self) { barFrame = $0 }
            .onPreferenceChange(CosmoInlineAssistantContextMenuFramePreferenceKey.self) { contextMenuFrame = $0 }
            .onChange(of: isComposerFocused) { _, focused in
                guard !focused else { return }
                collapseIfIdle()
            }
            .onChange(of: store.composerText) { _, text in
                syncComposerMenus(text: text)
                store.refreshSkillSuggestion()
            }
            .onAppear {
                installMouseDownMonitorIfNeeded()
                installKeyDownMonitorIfNeeded()
            }
            .onDisappear {
                removeMouseDownMonitor()
                removeKeyDownMonitor()
            }
            .sheet(isPresented: $isStudioPresented) {
                CosmoAssistantStudioView(initialSkillDraft: store.pendingStudioSkillDraft) {
                    isStudioPresented = false
                    store.pendingStudioSkillDraft = nil
                }
            }
            .onChange(of: store.pendingStudioSkillDraft) { _, draft in
                // "Promote this run to a skill" — a run card set a prefilled
                // draft; open the Studio straight into its editor.
                if draft != nil { isStudioPresented = true }
            }
            .accessibilityElement(children: .contain)
    }

    // MARK: - Morphing container

    // A single persistent surface that stretches from a small empty pill into the
    // full composer. Content is laid out at its final size and the animating clip
    // window reveals it (the Dynamic Island move) — width, height, corner radius,
    // and shadow all ride one spring so the bar reads as a single object
    // stretching, never parts assembling.
    private var morphingBar: some View {
        barContent
            .frame(width: expandedWidth, alignment: .leading)
            .frame(minHeight: expandedMinHeight)
            .frame(width: barWidth, height: isExpanded ? nil : collapsedHeight, alignment: .leading)
            .clipShape(barShape)
            .background {
                barShape
                    .fill(DS.surfaceCard.opacity(isExpanded ? 0.96 : 1.0))
                    .shadow(
                        color: Color.black.opacity(isExpanded ? 0.14 : 0.08),
                        radius: isExpanded ? 22 : 10,
                        x: 0,
                        y: isExpanded ? 10 : 4
                    )
            }
            .background(frameReader)
            .overlay { barShape.stroke(borderColor, lineWidth: 1) }
            .overlay { collapsedTapTarget }
            .animation(morphAnimation, value: isExpanded)
    }

    // Everything inside — sparkles, chips, composer, buttons — fades in as ONE
    // unit while the clip stretches over it, so nothing pops in out of order.
    // The offset rides the same spring as the container, keeping the content
    // physically attached to the surface; collapse drops it instantly so the
    // pill is already clean while the surface is still shrinking.
    private var barContent: some View {
        HStack(spacing: 12) {
            iconView
            trailingControls
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .disabled(!isExpanded)
        .opacity(isExpanded ? 1 : 0)
        .animation(contentFade, value: isExpanded)
        .offset(x: isExpanded ? 0 : -8)
        .animation(morphAnimation, value: isExpanded)
    }

    /// Only visible once the bar opens — the collapsed pill stays clean. Wears
    /// the assistant's state: each phase gets its own symbol and motion so
    /// progress reads as character, not a generic spinner.
    private var iconView: some View {
        Image(systemName: phaseSymbolName)
            .font(DS.title2)
            .foregroundStyle(phaseIconColor)
            .frame(width: 28, height: 28)
            .symbolEffect(.pulse, options: .repeating, isActive: store.phase.isWorking)
            .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : isExpanded)
            .contentTransition(.symbolEffect(.replace))
            .animation(ProMotionSprings.snappy, value: phaseSymbolName)
            .accessibilityHidden(true)
    }

    private var phaseSymbolName: String {
        store.phase.symbolName
    }

    /// Name of the armed skill, driving the "/Skill" token wash in the composer.
    private var armedSkillName: String? {
        store.selectedSkillID.flatMap { skillRegistry.skill(id: $0)?.name }
    }

    private var phaseIconColor: Color {
        store.phase == .reviewing ? DS.green : DS.accent
    }

    private var trailingControls: some View {
        controlsRow
            .animation(ProMotionSprings.snappy, value: store.selectedSkillID)
    }

    private var controlsRow: some View {
        HStack(spacing: 12) {
            activeSkillChip
            skillSuggestionChip
            selectionChip
                .animation(ProMotionSprings.snappy, value: store.currentSelection)
            if store.isProcessing {
                CosmoInlineAssistantWorkingStatusView(
                    leadingText: CosmoInlineAssistantBarProcessingPolicy.leadingText(isProcessing: store.isProcessing),
                    trailingText: CosmoInlineAssistantBarProcessingPolicy.trailingText(
                        statusText: store.statusText,
                        isProcessing: store.isProcessing
                    )
                )
            } else {
                MentionComposerTextView(
                    text: $store.composerText,
                    selection: $composerSelectionRange,
                    mentionedAtoms: store.selectedContextAtoms,
                    placeholder: promptText,
                    isFocused: $isComposerFocused,
                    isMentionOverlayVisible: isContextMenuVisible || isSkillMenuVisible,
                    usesPillMentions: true,
                    onSubmit: submit,
                    onTextChange: {
                        syncComposerMenus(text: store.composerText)
                    },
                    onDismissMentionOverlayFromBackspace: {
                        dismissInlineMenus(trimActiveQuery: false)
                    },
                    onTab: {
                        guard store.skillSuggestion != nil else { return false }
                        withAnimation(ProMotionSprings.snappy) {
                            store.acceptSkillSuggestion()
                        }
                        return true
                    },
                    tokenWashProvider: { text, selection in
                        CosmoInlineComposerTokenWashPolicy.rendered(
                            text: text,
                            selection: selection,
                            armedSkillName: armedSkillName
                        )
                    }
                )
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .onAppear { focusComposerIfPinnedOpen() }
            }

            Button(action: onOpenPane) {
                Image(systemName: "sidebar.right")
                    .font(DS.callout.weight(.medium))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .foregroundStyle(DS.textSecondary)
            .help("Open assistant pane")
            .accessibilityLabel("Open assistant pane")

            Button(action: submitOrStop) {
                Image(systemName: store.isProcessing ? "stop.fill" : "arrow.up")
                    .font(DS.callout.weight(.bold))
                    .frame(width: 34, height: 34)
                    .background(sendFill, in: Circle())
                    .foregroundStyle(sendText)
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .disabled(!canSubmit && !store.isProcessing)
            .help(store.isProcessing ? "Stop (⌘.)" : "Send")
            .accessibilityLabel(store.isProcessing ? "Stop" : "Send")
        }
    }

    /// Visible "skill session" indicator: once a skill is invoked it stays
    /// active for every turn (sticky session), so the bar wears the skill's
    /// name like an agent badge. ✕ exits skill mode without clearing the chat.
    @ViewBuilder
    private var activeSkillChip: some View {
        if let skillID = store.selectedSkillID,
           let skill = skillRegistry.skill(id: skillID) {
            CosmoInlineAssistantSkillSessionChip(skill: skill) {
                withAnimation(ProMotionSprings.snappy) {
                    store.selectedSkillID = nil
                }
            }
        }
    }

    /// Quiet chip quoting the live editor selection — the referent of
    /// "shorten this". The user sees exactly what a bare instruction will
    /// target before hitting return.
    @ViewBuilder
    private var selectionChip: some View {
        if !store.isProcessing, let selection = store.currentSelection {
            HStack(spacing: DS.space4) {
                Image(systemName: "text.cursor")
                    .font(DS.caption2.weight(.medium))
                    .accessibilityHidden(true)
                Text("„\(Self.selectionQuote(selection.text))\u{201C}")
                    .font(DS.caption)
                    .italic()
                    .lineLimit(1)
                Text("· \(Self.wordCount(selection.text)) words")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .monospacedDigit()
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(.quaternary.opacity(0.5), in: Capsule())
            .frame(maxWidth: 260, alignment: .leading)
            .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
            .help("Bare instructions (\"shorten this\") edit this selection")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Selection: \(Self.selectionQuote(selection.text))")
        }
    }

    static func selectionQuote(_ text: String, limit: Int = 36) -> String {
        let flattened = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > limit else { return flattened }
        return String(flattened.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// Ghost chip for the embedding-routed skill suggestion. Tab (or click)
    /// confirms; it never auto-applies — explicit selection always wins.
    @ViewBuilder
    private var skillSuggestionChip: some View {
        if store.selectedSkillID == nil,
           !store.isProcessing,
           let suggestion = store.skillSuggestion {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    store.acceptSkillSuggestion()
                }
            } label: {
                HStack(spacing: DS.space4) {
                    Image(systemName: suggestion.icon)
                        .font(DS.caption2.weight(.medium))
                        .accessibilityHidden(true)
                    Text(suggestion.skillName)
                        .font(DS.caption.weight(.medium))
                        .lineLimit(1)
                    Text("⇥")
                        .font(DS.caption2.weight(.semibold))
                        .foregroundStyle(DS.textMuted)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, DS.space4)
                .background(.quaternary.opacity(0.5), in: Capsule())
                .overlay(Capsule().strokeBorder(DS.border, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .help("Press Tab to use the \(suggestion.skillName) skill")
            .accessibilityLabel("Suggested skill: \(suggestion.skillName). Press Tab to use it.")
            .transition(.scale(scale: 0.92, anchor: .leading).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var contextMenuLayer: some View {
        if isContextMenuVisible && isExpanded {
            CosmoInlineAssistantContextMenu(
                model: contextMenuModel,
                searchText: contextSearchText,
                selectedAtoms: store.selectedContextAtoms,
                onCommit: { entry in
                    commitContextEntry(entry)
                },
                onClear: {
                    store.selectedContextAtoms.forEach { store.removeContext($0) }
                }
            )
            .background(contextMenuFrameReader)
            .offset(x: 16, y: -64)
            .transition(.opacity)
            .zIndex(10)
        }
    }

    @ViewBuilder
    private var skillMenuLayer: some View {
        if isSkillMenuVisible && isExpanded {
            CosmoInlineAssistantSkillMenu(
                model: skillMenuModel,
                searchText: skillSearchText,
                selectedSkillID: store.selectedSkillID,
                onCommit: { entry in
                    commitSkillEntry(entry)
                }
            )
            .background(contextMenuFrameReader)
            .offset(x: 16, y: -64)
            .transition(.opacity)
            .zIndex(11)
        }
    }

    // Invisible hit target that covers the collapsed orb so a click expands and
    // focuses the composer. Removed once expanded so the text field owns clicks.
    @ViewBuilder private var collapsedTapTarget: some View {
        if !isExpanded {
            Button(action: expandAndFocus) {
                barShape.fill(Color.clear).contentShape(barShape)
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .help("Open inline assistant")
            .accessibilityLabel("Open inline assistant")
        }
    }

    // MARK: - Geometry readers

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: CosmoInlineAssistantBarWidthPreferenceKey.self,
                value: proxy.size.width
            )
        }
    }

    private var frameReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: CosmoInlineAssistantBarFramePreferenceKey.self,
                value: proxy.frame(in: .global)
            )
        }
    }

    private var contextMenuFrameReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: CosmoInlineAssistantContextMenuFramePreferenceKey.self,
                value: proxy.frame(in: .global)
            )
        }
    }

    // MARK: - Derived presentation

    // Capsule in both states: radius tracks height (17 closed, 26 open) and
    // interpolates through the morph so the corners never read as a jump.
    private var barShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isExpanded ? 26 : collapsedHeight / 2, style: .continuous)
    }

    private var promptText: String {
        CosmoInlineAssistantBarProcessingPolicy.placeholder(isProcessing: store.isProcessing)
            ?? "Describe any change or ask"
    }

    private var trimmedComposerText: String {
        store.composerText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedComposerText.isEmpty && !store.isProcessing
    }

    private var isExpanded: Bool {
        isPinnedOpen || CosmoInlineAssistantBarPresentationPolicy.isExpanded(
            isHovering: isHovering && !isHoverSuppressed,
            isFocused: isComposerFocused,
            hasComposerText: !trimmedComposerText.isEmpty,
            isProcessing: store.isProcessing || store.statusText != nil || isContextMenuVisible || isSkillMenuVisible
        )
    }

    private var collapsedWidth: CGFloat { 56 }

    private var collapsedHeight: CGFloat { 34 }

    private var expandedMinHeight: CGFloat { 52 }

    private var expandedWidth: CGFloat {
        guard availableWidth > 120 else { return 600 }
        return min(availableWidth - 56, 780)
    }

    private var barWidth: CGFloat {
        isExpanded ? expandedWidth : collapsedWidth
    }

    private var sendFill: Color {
        (canSubmit || store.isProcessing) ? DS.accent : DS.borderSubtle
    }

    private var sendText: Color {
        (canSubmit || store.isProcessing) ? DS.textOnAccent : DS.textMuted
    }

    private var borderColor: Color {
        isComposerFocused ? DS.accent.opacity(0.36) : DS.borderSubtle
    }

    // One spring per direction, shared by every animating attribute (width,
    // height, radius, shadow, content offset): confident with a whisper of life
    // on the way open, crisp and damped on the way closed.
    private var morphAnimation: Animation {
        if reduceMotion { return .easeOut(duration: 0.16) }
        return isExpanded ? ProMotionSprings.modal : ProMotionSprings.sidebar
    }

    // The content's only independent channel — a short fade that lands while the
    // clip is mid-stretch, so the bar reveals its contents rather than growing
    // empty and filling up afterwards.
    private var contentFade: Animation {
        if reduceMotion { return .easeOut(duration: 0.12) }
        return isExpanded
            ? .easeOut(duration: 0.18).delay(0.05)
            : .easeOut(duration: 0.08)
    }

    // MARK: - Behavior

    private func submit() {
        guard canSubmit else { return }
        dismissInlineMenus(trimActiveQuery: false)
        Task { await store.submit() }
    }

    private func submitOrStop() {
        if store.isProcessing {
            store.cancelActiveRun()
        } else {
            submit()
        }
    }

    private func dismissInlineMenus(trimActiveQuery: Bool = false) {
        dismissContextMenu(trimMentionQuery: trimActiveQuery)
        dismissSkillMenu(trimSlashQuery: trimActiveQuery)
    }

    private func dismissContextMenu(trimMentionQuery: Bool = false) {
        if trimMentionQuery,
           let replacement = MentionComposerMentionParser.removingActiveMention(
                in: store.composerText,
                selectedRange: composerSelectionRange
           ) {
            store.composerText = replacement.text
            composerSelectionRange = replacement.selection
        }

        withAnimation(ProMotionSprings.snappy) {
            isContextMenuVisible = false
            contextSearchText = ""
        }
    }

    private func dismissSkillMenu(trimSlashQuery: Bool = false) {
        if trimSlashQuery,
           let activeSlash = CosmoInlineSlashSkillParser.activeCommand(
                in: store.composerText,
                selectedRange: composerSelectionRange
           ) {
            let mutable = NSMutableString(string: store.composerText)
            mutable.deleteCharacters(in: activeSlash.range)
            store.composerText = mutable as String
            composerSelectionRange = NSRange(location: activeSlash.range.location, length: 0)
        }

        withAnimation(ProMotionSprings.snappy) {
            isSkillMenuVisible = false
            skillSearchText = ""
        }
    }

    private func syncComposerMenus(text: String) {
        syncMentionSearch(text: text)
        syncSkillSearch(text: text)
    }

    private func syncMentionSearch(text: String) {
        guard let activeMention = MentionComposerMentionParser.activeMention(
            in: text,
            selectedRange: composerSelectionRange
        ) else {
            if isContextMenuVisible {
                dismissContextMenu(trimMentionQuery: false)
            }
            return
        }

        if isCompletedInsertedMention(activeMention) {
            if isContextMenuVisible {
                dismissContextMenu(trimMentionQuery: false)
            }
            return
        }

        if isSkillMenuVisible {
            dismissSkillMenu(trimSlashQuery: false)
        }
        contextSearchText = activeMention.query.trimmingCharacters(in: .whitespacesAndNewlines)
        isPinnedOpen = true
        if !isContextMenuVisible {
            withAnimation(ProMotionSprings.snappy) {
                isContextMenuVisible = true
            }
        }
    }

    private func syncSkillSearch(text: String) {
        guard let activeSlash = CosmoInlineSlashSkillParser.activeCommand(
            in: text,
            selectedRange: composerSelectionRange
        ) else {
            if isSkillMenuVisible {
                dismissSkillMenu(trimSlashQuery: false)
            }
            return
        }

        if isContextMenuVisible {
            dismissContextMenu(trimMentionQuery: false)
        }
        skillSearchText = activeSlash.query.trimmingCharacters(in: .whitespacesAndNewlines)
        isPinnedOpen = true
        if !isSkillMenuVisible {
            withAnimation(ProMotionSprings.snappy) {
                isSkillMenuVisible = true
            }
        }
    }

    private func selectContext(_ atom: Atom) {
        let replacement = store.insertContextMention(atom, selection: composerSelectionRange)
        store.composerText = replacement.text
        composerSelectionRange = replacement.selection
        dismissContextMenu(trimMentionQuery: false)
        focusComposerSoon()
    }

    private func commitContextEntry(_ entry: CosmoInlineContextMenuModel.Entry) {
        switch entry {
        case .attachCurrent(let atom):
            selectContext(atom)
        case .atom(let atom, let isSelected):
            if isSelected {
                store.removeContext(atom)
            } else {
                selectContext(atom)
            }
        }
    }

    private func commitSkillEntry(_ entry: CosmoInlineSkillMenuModel.Entry) {
        switch entry {
        case .skill(let skill):
            skillRecency.recordUse(skill.id)
            selectSkill(skill)
        case .utility(.clearSession):
            dismissSkillMenu(trimSlashQuery: true)
            Task { await store.clearActiveSession() }
        case .utility(.createSkill):
            startSkillBuilder()
        case .utility(.openStudio):
            dismissSkillMenu(trimSlashQuery: true)
            isStudioPresented = true
        }
    }

    private func selectSkill(_ skill: CosmoInlineSkillDefinition) {
        guard let activeSlash = CosmoInlineSlashSkillParser.activeCommand(
            in: store.composerText,
            selectedRange: composerSelectionRange
        ) else {
            store.selectedSkillID = skill.id
            dismissSkillMenu(trimSlashQuery: false)
            focusComposerSoon()
            return
        }

        let token = "/\(skill.name) "
        let mutable = NSMutableString(string: store.composerText)
        mutable.replaceCharacters(in: activeSlash.range, with: token)
        store.composerText = mutable as String
        store.selectedSkillID = skill.id
        composerSelectionRange = NSRange(location: activeSlash.range.location + (token as NSString).length, length: 0)
        dismissSkillMenu(trimSlashQuery: false)
        focusComposerSoon()
    }

    private func startSkillBuilder() {
        dismissSkillMenu(trimSlashQuery: true)
        store.selectedSkillID = nil
        store.composerText = "Create a new inline assistant skill that "
        composerSelectionRange = NSRange(location: (store.composerText as NSString).length, length: 0)
        onOpenPane()
        focusComposerSoon()
    }

    private func isCompletedInsertedMention(_ activeMention: MentionComposerActiveMention) -> Bool {
        store.selectedContextAtoms.contains { atom in
            let title = CosmoInlineAssistantContextMentionFormatter.mentionTitle(for: atom)
            return activeMention.query == title
                || activeMention.query.hasPrefix("\(title) ")
                || activeMention.query.hasPrefix("\(title)\t")
        }
    }

    private func expandAndFocus() {
        isHoverSuppressed = false
        isPinnedOpen = true
        focusComposerSoon()
    }

    private func focusComposerIfPinnedOpen() {
        guard isPinnedOpen else { return }
        focusComposerSoon()
    }

    private func focusComposerSoon() {
        Task { @MainActor in
            await Task.yield()
            isComposerFocused = true
            NotificationCenter.default.post(name: .focusCosmoComposer, object: nil)
        }
    }

    private func collapseIfIdle() {
        guard !isComposerFocused, trimmedComposerText.isEmpty, !store.isProcessing, !isContextMenuVisible else { return }
        isPinnedOpen = false
    }

    private func installMouseDownMonitorIfNeeded() {
        guard mouseDownMonitor == nil else { return }
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            handleMouseDown(event)
            return event
        }
    }

    private func removeMouseDownMonitor() {
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
        }
        self.mouseDownMonitor = nil
    }

    // The composer's NSTextView forwards Escape up the responder chain, and a
    // hover-opened bar has no first responder at all — a local monitor is the
    // one place that reliably sees the key in both states.
    private func installKeyDownMonitorIfNeeded() {
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                return handleEscape() ? nil : event
            }
            return handleMenuNavigationKey(event) ? nil : event
        }
    }

    /// Arrow/Return/Tab routing while an inline menu is open — the menus are
    /// keyboard-first, and Return must select the highlighted row instead of
    /// falling through to submit the half-typed composer text.
    private func handleMenuNavigationKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            return false
        }
        let menuVisible = (isContextMenuVisible || isSkillMenuVisible) && isExpanded

        switch CosmoAssistantMenuKeyRouter.action(keyCode: event.keyCode, isMenuVisible: menuVisible) {
        case .moveUp:
            moveActiveMenuHighlight(-1)
            return true
        case .moveDown:
            moveActiveMenuHighlight(1)
            return true
        case .commit:
            return commitActiveMenuHighlight()
        case .passthrough:
            return false
        }
    }

    private func moveActiveMenuHighlight(_ delta: Int) {
        CosmicHaptics.shared.play(.threshold)
        if isContextMenuVisible {
            contextMenuModel.moveHighlight(delta)
        } else if isSkillMenuVisible {
            skillMenuModel.moveHighlight(delta)
        }
    }

    /// Returns false when the visible menu has nothing to commit (no matches)
    /// so Return/Tab keep their ordinary composer meaning.
    private func commitActiveMenuHighlight() -> Bool {
        if isContextMenuVisible {
            guard let entry = contextMenuModel.highlightedEntry else { return false }
            CosmicHaptics.shared.play(.selection)
            commitContextEntry(entry)
            return true
        }
        if isSkillMenuVisible {
            guard let entry = skillMenuModel.highlightedEntry else { return false }
            CosmicHaptics.shared.play(.selection)
            commitSkillEntry(entry)
            return true
        }
        return false
    }

    private func removeKeyDownMonitor() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        self.keyDownMonitor = nil
    }

    /// Returns true when the event was consumed; false lets Escape fall through
    /// to whatever surface is behind the bar.
    private func handleEscape() -> Bool {
        guard !isStudioPresented else { return false }

        switch CosmoInlineAssistantBarEscapePolicy.action(
            isExpanded: isExpanded,
            isMenuVisible: isContextMenuVisible || isSkillMenuVisible,
            hasComposerText: !trimmedComposerText.isEmpty,
            isProcessing: store.isProcessing
        ) {
        case .dismissMenus:
            dismissInlineMenus(trimActiveQuery: true)
            return true
        case .clearComposer:
            store.composerText = ""
            composerSelectionRange = NSRange(location: 0, length: 0)
            return true
        case .collapse:
            collapseBar()
            return true
        case .ignore:
            return false
        }
    }

    private func collapseBar() {
        isComposerFocused = false
        isPinnedOpen = false
        isHoverSuppressed = true
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func handleMouseDown(_ event: NSEvent) {
        guard isComposerFocused || isPinnedOpen else { return }
        guard let window = event.window ?? NSApp.keyWindow else { return }

        let clickPoint = windowTopLeftPoint(for: event, in: window)
        if isContextMenuVisible,
           contextMenuFrame.width > 0,
           contextMenuFrame.height > 0,
           contextMenuFrame.insetBy(dx: -8, dy: -8).contains(clickPoint) {
            return
        }
        if isSkillMenuVisible,
           contextMenuFrame.width > 0,
           contextMenuFrame.height > 0,
           contextMenuFrame.insetBy(dx: -8, dy: -8).contains(clickPoint) {
            return
        }
        guard CosmoInlineAssistantBarPresentationPolicy.shouldBlur(
            clickPoint: clickPoint,
            barFrame: barFrame
        ) else { return }

        isComposerFocused = false
        isPinnedOpen = false
        dismissInlineMenus(trimActiveQuery: false)
        window.makeFirstResponder(nil)
    }

    private func windowTopLeftPoint(for event: NSEvent, in window: NSWindow) -> CGPoint {
        let location = event.locationInWindow
        guard let contentView = window.contentView else { return location }
        return CGPoint(x: location.x, y: contentView.bounds.height - location.y)
    }
}
private struct CosmoInlineAssistantSelectedContextChip: View {
    let atom: Atom
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: atom.isSwipeFileAtom ? "bookmark.fill" : atom.type.iconName)
                .font(.system(size: 10, weight: .semibold))
            Text(atom.title ?? "Untitled")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.textMuted)
        }
        .foregroundStyle(DS.accent)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(DS.accentSoft, in: Capsule())
        .overlay(Capsule().strokeBorder(DS.accent.opacity(0.24), lineWidth: 0.75))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selected context \(atom.title ?? "Untitled")")
    }
}

private struct CosmoInlineAssistantWorkingStatusView: View {
    let leadingText: String
    let trailingText: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(leadingText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 16)

            if let trailingText {
                Text(trailingText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(leadingText) \(trailingText ?? "")")
    }
}
