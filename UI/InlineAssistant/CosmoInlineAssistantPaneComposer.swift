// CosmoOS/UI/InlineAssistant/CosmoInlineAssistantPaneComposer.swift
// The pane's composer, rebuilt on the real mention composer: @-mentions render
// as the same pills everywhere, the context picker is the bar's own menu, and
// a sticky skill session wears its chip above the field.
// June 2026

import AppKit
import SwiftUI

struct CosmoInlineAssistantPaneComposer: View {
    @ObservedObject var store: CosmoInlineAssistantStore

    @State private var selectionRange = NSRange(location: 0, length: 0)
    @State private var isFocused = false
    @State private var isContextMenuVisible = false
    @State private var contextSearchText = ""
    @State private var skillResolver = CosmoInlineSkillResolver()
    @State private var contextMenuModel = CosmoInlineContextMenuModel()
    @State private var keyDownMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            sessionChipRow
            inputField
        }
        .padding(DS.space16)
        .overlay(alignment: .topLeading) { contextMenuLayer }
        .animation(ProMotionSprings.snappy, value: isFocused)
        .animation(ProMotionSprings.snappy, value: store.selectedSkillID)
        .onAppear { installKeyDownMonitorIfNeeded() }
        .onDisappear { removeKeyDownMonitor() }
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
                isMentionOverlayVisible: isContextMenuVisible,
                usesPillMentions: true,
                onSubmit: submit,
                onTextChange: {
                    syncMentionSearch(text: store.composerText)
                    store.refreshSkillSuggestion()
                },
                onDismissMentionOverlayFromBackspace: {
                    dismissContextMenu(trimMentionQuery: false)
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

    // MARK: - Context menu

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
            // The menu's bottom edge hangs just above the composer's top.
            .alignmentGuide(.top) { dimensions in dimensions[.bottom] + DS.space4 }
            .padding(.leading, DS.space16)
            .transition(.opacity)
            .zIndex(10)
        }
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
        if event.keyCode == 53 { // Escape closes the open menu first
            guard isContextMenuVisible else { return false }
            dismissContextMenu(trimMentionQuery: true)
            return true
        }
        switch CosmoAssistantMenuKeyRouter.action(keyCode: event.keyCode, isMenuVisible: isContextMenuVisible) {
        case .moveUp:
            CosmicHaptics.shared.play(.threshold)
            contextMenuModel.moveHighlight(-1)
            return true
        case .moveDown:
            CosmicHaptics.shared.play(.threshold)
            contextMenuModel.moveHighlight(1)
            return true
        case .commit:
            guard let entry = contextMenuModel.highlightedEntry else { return false }
            CosmicHaptics.shared.play(.selection)
            commitContextEntry(entry)
            return true
        case .passthrough:
            return false
        }
    }

    // MARK: - Behavior (ported from the bar, mention-menu only)

    private func syncMentionSearch(text: String) {
        guard let activeMention = MentionComposerMentionParser.activeMention(
            in: text,
            selectedRange: selectionRange
        ) else {
            if isContextMenuVisible { dismissContextMenu(trimMentionQuery: false) }
            return
        }

        if isCompletedInsertedMention(activeMention) {
            if isContextMenuVisible { dismissContextMenu(trimMentionQuery: false) }
            return
        }

        contextSearchText = activeMention.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isContextMenuVisible {
            withAnimation(ProMotionSprings.snappy) { isContextMenuVisible = true }
        }
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

    private func refocusComposer() {
        Task { @MainActor in
            await Task.yield()
            isFocused = true
            NotificationCenter.default.post(name: .focusCosmoComposer, object: nil)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        dismissContextMenu(trimMentionQuery: false)
        Task { await store.submit() }
    }

    private var canSubmit: Bool {
        !store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isProcessing
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
