// CosmoOS/UI/InlineAssistant/CosmoInlineAssistantPaneComposer.swift
// The pane's composer, rebuilt on the real mention composer: @-mentions render
// as the same pills everywhere, the @/ menus are the bar's own menus, and
// a sticky skill session wears its chip above the field.
// June 2026

import AppKit
import SwiftUI

private struct CosmoInlinePaneMenuFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct CosmoInlinePaneComposerFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct CosmoInlineAssistantPaneComposer: View {
    @ObservedObject var store: CosmoInlineAssistantStore

    @State private var selectionRange = NSRange(location: 0, length: 0)
    @State private var isFocused = false
    @State private var isContextMenuVisible = false
    @State private var isSkillMenuVisible = false
    @State private var contextSearchText = ""
    @State private var skillSearchText = ""
    @State private var skillResolver = CosmoInlineSkillResolver()
    @State private var contextMenuModel = CosmoInlineContextMenuModel()
    @State private var skillMenuModel = CosmoInlineSkillMenuModel()
    @State private var isStudioPresented = false
    @State private var menuFrame: CGRect = .zero
    @State private var composerFrame: CGRect = .zero
    @State private var keyDownMonitor: Any?
    @State private var mouseDownMonitor: Any?
    private let skillRecency = CosmoInlineSkillRecencyStore()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            sessionChipRow
            inputField
        }
        .padding(DS.space16)
        .background(composerFrameReader)
        .overlay(alignment: .topLeading) { contextMenuLayer }
        .overlay(alignment: .topLeading) { skillMenuLayer }
        .onPreferenceChange(CosmoInlinePaneMenuFramePreferenceKey.self) { menuFrame = $0 }
        .onPreferenceChange(CosmoInlinePaneComposerFramePreferenceKey.self) { composerFrame = $0 }
        .animation(ProMotionSprings.snappy, value: isFocused)
        .animation(ProMotionSprings.snappy, value: store.selectedSkillID)
        .onAppear {
            installKeyDownMonitorIfNeeded()
            installMouseDownMonitorIfNeeded()
            contextMenuModel.prewarmSearchIndex()
        }
        .onDisappear {
            removeKeyDownMonitor()
            removeMouseDownMonitor()
        }
        .modifier(studioSheet)
    }

    /// The Assistant Studio presenter: the bar is unmounted while the pane is
    /// open, so the pane composer owns both the / utility entry and the
    /// "promote this run to a skill" hand-off from run cards.
    private var studioSheet: some ViewModifier {
        CosmoInlinePaneStudioSheetModifier(
            store: store,
            isPresented: $isStudioPresented
        )
    }

    // MARK: - Session chips

    @ViewBuilder
    private var sessionChipRow: some View {
        if hasSessionChips {
            HStack(spacing: DS.space6) {
                if let skill = activeSkill {
                    CosmoInlineAssistantSkillSessionChip(skill: skill) {
                        withAnimation(ProMotionSprings.snappy) {
                            store.selectedSkillID = nil
                        }
                    }
                }
                skillSuggestionChip
                Spacer(minLength: 0)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var hasSessionChips: Bool {
        activeSkill != nil || (store.skillSuggestion != nil && !store.isProcessing)
    }

    private var activeSkill: CosmoInlineSkillDefinition? {
        skillResolver.skill(id: store.selectedSkillID)
    }

    @ViewBuilder
    private var skillSuggestionChip: some View {
        if store.selectedSkillID == nil,
           !store.isProcessing,
           let suggestion = store.skillSuggestion {
            Button {
                withAnimation(ProMotionSprings.snappy) { store.acceptSkillSuggestion() }
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

    // MARK: - Input

    private var inputField: some View {
        HStack(alignment: .bottom, spacing: DS.space8) {
            MentionComposerTextView(
                text: $store.composerText,
                selection: $selectionRange,
                mentionedAtoms: store.selectedContextAtoms,
                placeholder: "Ask, or describe an edit — @ adds context",
                isFocused: $isFocused,
                isMentionOverlayVisible: isContextMenuVisible || isSkillMenuVisible,
                usesPillMentions: true,
                onSubmit: submit,
                onTextChange: {
                    syncComposerMenus(text: store.composerText)
                    store.refreshSkillSuggestion()
                },
                onTab: {
                    guard store.skillSuggestion != nil else { return false }
                    withAnimation(ProMotionSprings.snappy) { store.acceptSkillSuggestion() }
                    return true
                },
                tokenWashProvider: { text, selection in
                    CosmoInlineComposerTokenWashPolicy.rendered(
                        text: text,
                        selection: selection,
                        armedSkillName: activeSkill?.name
                    )
                }
            )
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)

            sendButton
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .dsGlassInput(isFocused: isFocused, cornerRadius: 14)
    }

    private var sendButton: some View {
        Button(action: primaryAction) {
            Image(systemName: store.isProcessing ? "stop.fill" : "arrow.up")
                .font(DS.caption.weight(.bold))
                .frame(width: 28, height: 28)
                .background(primaryActionEnabled ? DS.accent : DS.borderSubtle, in: Circle())
                .foregroundStyle(primaryActionEnabled ? DS.textOnAccent : DS.textMuted)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .cosmoClickCursor()
        .disabled(!primaryActionEnabled)
        .keyboardShortcut(store.isProcessing ? KeyEquivalent(".") : .return, modifiers: .command)
        .help(store.isProcessing ? "Stop (⌘.)" : "Send (⏎)")
        .accessibilityLabel(store.isProcessing ? "Stop" : "Send")
    }

    private func primaryAction() {
        if store.isProcessing {
            store.cancelActiveRun()
        } else {
            submit()
        }
    }

    private var primaryActionEnabled: Bool {
        store.isProcessing || canSubmit
    }

    // MARK: - Menu layers

    @ViewBuilder
    private var contextMenuLayer: some View {
        if isContextMenuVisible {
            CosmoInlineAssistantContextMenu(
                model: contextMenuModel,
                searchText: contextSearchText,
                selectedAtoms: store.selectedContextAtoms,
                onCommit: { entry in commitContextEntry(entry) },
                onClear: {
                    store.selectedContextAtoms.forEach { store.removeContext($0) }
                }
            )
            .modifier(paneMenuPlacement)
            .zIndex(10)
        }
    }

    @ViewBuilder
    private var skillMenuLayer: some View {
        if isSkillMenuVisible {
            CosmoInlineAssistantSkillMenu(
                model: skillMenuModel,
                searchText: skillSearchText,
                selectedSkillID: store.selectedSkillID,
                onCommit: { entry in commitSkillEntry(entry) }
            )
            .modifier(paneMenuPlacement)
            .zIndex(11)
        }
    }

    /// Hangs a menu just above the composer's top edge. The overlay proposes
    /// the composer's own (small) height, so the menu must lay out at its
    /// natural size — without fixedSize the list collapses to header + footer.
    private var paneMenuPlacement: some ViewModifier {
        CosmoInlinePaneMenuPlacementModifier()
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

    // MARK: - Keyboard routing

    /// The pane composer's menu is keyboard-first like the bar's: a local
    /// monitor sees arrows/Return/Tab before the text view and routes them to
    /// the highlighted row while the menu is open.
    private func installKeyDownMonitorIfNeeded() {
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleMenuNavigationKey(event) ? nil : event
        }
    }

    private func removeKeyDownMonitor() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        keyDownMonitor = nil
    }

    private func handleMenuNavigationKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            return false
        }
        if event.keyCode == 53 { // Escape closes the open menu before the pane
            guard isContextMenuVisible || isSkillMenuVisible else { return false }
            dismissInlineMenus(trimActiveQuery: true)
            return true
        }
        let menuVisible = isContextMenuVisible || isSkillMenuVisible
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

    /// Menus don't block the pane behind them — but a click outside the open
    /// menu should put it away, exactly like the bar.
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
        mouseDownMonitor = nil
    }

    private func handleMouseDown(_ event: NSEvent) {
        guard isContextMenuVisible || isSkillMenuVisible else { return }
        guard let window = event.window ?? NSApp.keyWindow,
              let contentView = window.contentView else { return }
        let location = event.locationInWindow
        let clickPoint = CGPoint(x: location.x, y: contentView.bounds.height - location.y)
        if menuFrame.width > 0, menuFrame.insetBy(dx: -8, dy: -8).contains(clickPoint) {
            return
        }
        if composerFrame.width > 0, composerFrame.contains(clickPoint) {
            return
        }
        dismissInlineMenus(trimActiveQuery: false)
    }

    private var composerFrameReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: CosmoInlinePaneComposerFramePreferenceKey.self,
                value: proxy.frame(in: .global)
            )
        }
    }

    // MARK: - Behavior (ported from the bar)

    private func syncComposerMenus(text: String) {
        syncMentionSearch(text: text)
        syncSkillSearch(text: text)
    }

    private func syncMentionSearch(text: String) {
        guard let activeMention = MentionComposerMentionParser.activeMention(
            in: text,
            selectedRange: selectionRange
        ) else {
            CosmoInlineContextMenuDebug.log("pane sync text=\"\(text)\" sel=\(selectionRange) → no active mention")
            if isContextMenuVisible { dismissContextMenu(trimMentionQuery: false) }
            return
        }

        CosmoInlineContextMenuDebug.log("pane sync text=\"\(text)\" sel=\(selectionRange) → mention query=\"\(activeMention.query)\"")

        if isCompletedInsertedMention(activeMention) {
            if isContextMenuVisible { dismissContextMenu(trimMentionQuery: false) }
            return
        }

        if isSkillMenuVisible {
            dismissSkillMenu(trimSlashQuery: false)
        }
        contextSearchText = activeMention.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isContextMenuVisible {
            withAnimation(ProMotionSprings.snappy) { isContextMenuVisible = true }
        }
    }

    private func syncSkillSearch(text: String) {
        guard let activeSlash = CosmoInlineSlashSkillParser.activeCommand(
            in: text,
            selectedRange: selectionRange
        ) else {
            if isSkillMenuVisible { dismissSkillMenu(trimSlashQuery: false) }
            return
        }

        if isContextMenuVisible {
            dismissContextMenu(trimMentionQuery: false)
        }
        skillSearchText = activeSlash.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isSkillMenuVisible {
            withAnimation(ProMotionSprings.snappy) { isSkillMenuVisible = true }
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
            selectedRange: selectionRange
        ) else {
            store.selectedSkillID = skill.id
            dismissSkillMenu(trimSlashQuery: false)
            refocusComposer()
            return
        }

        let token = "/\(skill.name) "
        let mutable = NSMutableString(string: store.composerText)
        mutable.replaceCharacters(in: activeSlash.range, with: token)
        store.composerText = mutable as String
        store.selectedSkillID = skill.id
        selectionRange = NSRange(location: activeSlash.range.location + (token as NSString).length, length: 0)
        dismissSkillMenu(trimSlashQuery: false)
        refocusComposer()
    }

    /// Already in the pane — just seed the builder prompt where the bar would
    /// also have had to open the pane first.
    private func startSkillBuilder() {
        dismissSkillMenu(trimSlashQuery: true)
        store.selectedSkillID = nil
        store.composerText = "Create a new inline assistant skill that "
        selectionRange = NSRange(location: (store.composerText as NSString).length, length: 0)
        refocusComposer()
    }

    private func isCompletedInsertedMention(_ activeMention: MentionComposerActiveMention) -> Bool {
        store.selectedContextAtoms.contains { atom in
            let title = CosmoInlineAssistantContextMentionFormatter.mentionTitle(for: atom)
            return activeMention.query == title
                || activeMention.query.hasPrefix("\(title) ")
                || activeMention.query.hasPrefix("\(title)\t")
        }
    }

    private func selectContext(_ atom: Atom) {
        let replacement = store.insertContextMention(atom, selection: selectionRange)
        store.composerText = replacement.text
        selectionRange = replacement.selection
        dismissContextMenu(trimMentionQuery: false)
        refocusComposer()
    }

    private func dismissInlineMenus(trimActiveQuery: Bool) {
        dismissContextMenu(trimMentionQuery: trimActiveQuery)
        dismissSkillMenu(trimSlashQuery: trimActiveQuery)
    }

    private func dismissContextMenu(trimMentionQuery: Bool) {
        if trimMentionQuery,
           let replacement = MentionComposerMentionParser.removingActiveMention(
                in: store.composerText,
                selectedRange: selectionRange
           ) {
            store.composerText = replacement.text
            selectionRange = replacement.selection
        }

        withAnimation(ProMotionSprings.snappy) {
            isContextMenuVisible = false
            contextSearchText = ""
        }
    }

    private func dismissSkillMenu(trimSlashQuery: Bool) {
        if trimSlashQuery,
           let activeSlash = CosmoInlineSlashSkillParser.activeCommand(
                in: store.composerText,
                selectedRange: selectionRange
           ) {
            let mutable = NSMutableString(string: store.composerText)
            mutable.deleteCharacters(in: activeSlash.range)
            store.composerText = mutable as String
            selectionRange = NSRange(location: activeSlash.range.location, length: 0)
        }

        withAnimation(ProMotionSprings.snappy) {
            isSkillMenuVisible = false
            skillSearchText = ""
        }
    }

    private func refocusComposer() {
        Task { @MainActor in
            await Task.yield()
            isFocused = true
            NotificationCenter.default.post(name: .focusCosmoComposer, object: nil)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        dismissInlineMenus(trimActiveQuery: false)
        Task { await store.submit() }
    }

    private var canSubmit: Bool {
        !store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isProcessing
    }
}

/// Places a menu hanging just above the composer's top edge, at its natural
/// size. Two invariants earned the hard way:
/// - Keep the fixedSize: the hosting overlay proposes only the composer's
///   ~100pt height, and without it the menu's scroll list collapses to zero,
///   leaving a header glued to a footer.
/// - Position via the zero-height bottom-aligned frame, never an
///   `alignmentGuide(.top)` override: the explicit guide doesn't survive the
///   fixedSize wrapper, and the menu silently falls back to the overlay's
///   top-leading corner — rendering BELOW the composer, cut off by the
///   window edge. The collapsed frame pins an anchor line at the composer's
///   top and the content hangs upward from it deterministically.
private struct CosmoInlinePaneMenuPlacementModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: CosmoInlinePaneMenuFramePreferenceKey.self,
                        value: proxy.frame(in: .global)
                    )
                }
            }
            .frame(height: 0, alignment: .bottom)
            .offset(y: -DS.space4)
            .padding(.leading, DS.space16)
            .transition(.opacity)
    }
}

/// The Assistant Studio sheet + the run-card promotion hand-off, exactly as
/// the bar hosts them when the pane is closed.
private struct CosmoInlinePaneStudioSheetModifier: ViewModifier {
    @ObservedObject var store: CosmoInlineAssistantStore
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                CosmoAssistantStudioView(initialSkillDraft: store.pendingStudioSkillDraft) {
                    isPresented = false
                    store.pendingStudioSkillDraft = nil
                }
            }
            .onChange(of: store.pendingStudioSkillDraft) { _, draft in
                if draft != nil { isPresented = true }
            }
    }
}

/// The sticky skill session worn as a chip: icon + name + ✕ to exit the skill
/// without clearing the conversation. Shared by the bar and the pane.
struct CosmoInlineAssistantSkillSessionChip: View {
    let skill: CosmoInlineSkillDefinition
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: DS.space4) {
            Image(systemName: skill.icon)
                .font(DS.caption2.weight(.medium))
                .accessibilityHidden(true)
            Text(skill.name)
                .font(DS.caption.weight(.semibold))
                .lineLimit(1)
            Button(action: onExit) {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.semibold))
                    .frame(width: 14, height: 14)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .help("Exit \(skill.name) mode (or type /clear)")
            .accessibilityLabel("Exit \(skill.name) skill mode")
        }
        .foregroundStyle(DS.accent)
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .background(DS.accentSoft, in: Capsule())
        .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(skill.name) skill session active")
    }
}
