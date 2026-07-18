// CosmoOS/UI/FocusMode/Ideas/IdeaWorkspaceToolbar.swift
// July 2026 — the Idea bench's navigation band (the Study chrome anatomy).
// Three glass islands on the shared app baseline: navigate · the idea pill ·
// tools — plus Begin Writing as the screen's ONE tinted glass element (tint
// marks the primary action, exactly Crystallize's role in the Study).
// Status and client live in the manuscript head; the pill is orientation.
// Islands recede while the user is writing and wake on hover.

import SwiftUI

struct IdeaWorkspaceToolbar: View {
    var viewModel: IdeaFocusModeViewModel
    var workspace: IdeaWorkspaceModel
    let isPaneContext: Bool
    let isPromoting: Bool
    /// True while keystrokes are landing — islands quiet to a whisper.
    var isReceded: Bool = false
    let actions: IdeaWorkspaceActions

    @Environment(\.atomWindowChromeContext) private var atomChrome
    @Environment(\.paneDeckChrome) private var paneDeckChrome

    private var isBodyEmpty: Bool {
        viewModel.editableBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Quiet writing vitals for the idea pill — computed from the manuscript.
    private var wordCount: Int {
        viewModel.editableBody.split(whereSeparator: \.isWhitespace).count
    }

    var body: some View {
        // The band owns its insets — it sits above the worksheet, not inside
        // a scroll inset (the Study chrome anatomy). Absolute centering needs
        // regular width AND full-screen hosting — beside the open pane deck
        // main content can be squeezed to pane widths, where the pill flows
        // between the clusters so overlap is structurally impossible.
        CosmoChromeRow(centersAbsolutely: !isPaneContext && workspace.breakpoint == .regular) {
            if atomChrome == nil, !isPaneContext {
                NavigationTrailIsland()
            }
            if let paneDeckChrome {
                CosmoChromeIsland(recede: isReceded) { PaneDeckTabStrip(context: paneDeckChrome) }
            }
            CosmoChromeIsland(recede: isReceded) { leadingControls }
        } center: {
            // The focused deck tab already names the idea in pane context —
            // the pill would say it twice.
            if paneDeckChrome == nil {
                CosmoChromeIsland(recede: isReceded) { ideaPill }
            }
        } trailing: {
            CosmoChromeIsland(recede: isReceded) { trailingControls }
            beginWritingIsland
        }
    }

    // MARK: - Navigate island

    @ViewBuilder
    private var leadingControls: some View {
        if let atomChrome {
            AtomWindowChromeLeadingControls(context: atomChrome)
            AtomWindowChromeDivider()
        }
        toolbarButton(
            icon: "sidebar.squares.left",
            help: workspace.isConversationShowing ? "Hide conversation (⌘0)" : "Show conversation (⌘0)",
            isActive: workspace.isConversationShowing
        ) {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.toggleConversation()
            }
        }
    }

    // MARK: - The idea pill (orientation — the center island)

    /// Identity + vitals as tinted text: the idea's mark, its name, and a
    /// live word count. The serif head in the manuscript stays the hero;
    /// this is the bench's inline title.
    private var ideaPill: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "lightbulb.fill")
                .font(DS.caption2)
                .foregroundStyle(DS.entityIdea)
                .accessibilityHidden(true)
            Text(pillTitle)
                .font(DS.buttonText.weight(.semibold))
                .foregroundStyle(DS.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: isCompact ? 200 : 320)
            if wordCount > 0, !isCompact {
                Text("·")
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
                Text("\(wordCount) \(wordCount == 1 ? "word" : "words")")
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, DS.space4)
        .help("Idea · \(viewModel.selectedStatus.displayName)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Idea: \(pillTitle), \(wordCount) words")
    }

    /// Pane and Atom-window widths — labels yield to the columns.
    private var isCompact: Bool { workspace.breakpoint == .compact }

    private var pillTitle: String {
        let title = viewModel.editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled idea" : title
    }

    // MARK: - Tools island

    @ViewBuilder
    private var trailingControls: some View {
        toolbarButton(
            icon: "sidebar.right",
            help: workspace.isInspectorShowing ? "Hide swipes (⌘⌥I)" : "Show swipes (⌘⌥I)",
            isActive: workspace.isInspectorShowing
        ) {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.toggleInspector()
            }
        }
        if let atomChrome {
            AtomWindowChromeDivider()
            AtomWindowChromeTrailingControls(context: atomChrome)
        }
        // Pane close lives in the deck tab (the strip's ✕).
    }

    // MARK: - Begin Writing (the one tinted glass element)

    private var beginWritingIsland: some View {
        IdeaBeginWritingIsland(
            showsLabel: !isCompact,
            isPromoting: isPromoting,
            isDisabled: isBodyEmpty,
            action: actions.onBeginWriting
        )
    }

    // MARK: - Button factory

    private func toolbarButton(
        icon: String,
        help: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        StudyToolbarButton(icon: icon, help: help, isActive: isActive, action: action)
    }
}

// MARK: - The tinted primary island

/// Begin Writing wears the screen's only glass tint — the Study's
/// Crystallize anatomy: accent ink on soft-accent interactive glass,
/// island height, ⌘⏎.
@MainActor
private struct IdeaBeginWritingIsland: View {
    var showsLabel: Bool = true
    let isPromoting: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                if isPromoting {
                    ProgressView()
                        .scaleEffect(0.45)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "square.and.pencil")
                        .font(DS.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                if showsLabel || isPromoting {
                    Text(isPromoting ? "Writing…" : "Begin Writing")
                        .font(DS.buttonText.weight(.semibold))
                }
            }
            .foregroundStyle(DS.accent)
            .padding(.horizontal, DS.space12)
            .frame(height: CosmoChromeMetrics.height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(DS.accentSoft).interactive(), in: .capsule)
        .opacity(isDisabled && !isPromoting ? 0.45 : 1)
        .scaleEffect(isHovered && !isDisabled ? 1.02 : 1)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .disabled(isPromoting || isDisabled)
        .keyboardShortcut(.return, modifiers: [.command])
        .help("Begin writing — promotes this idea to content (⌘⏎)")
        .accessibilityLabel("Begin writing")
    }
}
