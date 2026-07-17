// CosmoOS/UI/FocusMode/Inquiry/Study/StudyChromeRow.swift
// The Study's top chrome: three glass islands on the shared app baseline —
// navigate · question · actions. Crystallize is the screen's ONE tinted glass
// element (tint marks the primary action). Islands recede while the user is
// thinking in the dock or reading a source, and wake on hover.

import SwiftUI
import AppKit

@MainActor
struct StudyChromeRow: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let breakpoint: StudyBreakpoint
    /// The shell's width, quantized to 24pt steps (pane divider drags must
    /// not invalidate the row every frame). The center island is absolutely
    /// centered, so its title cap is derived from this — overlap with the
    /// side clusters becomes arithmetically impossible at any pane width.
    let availableWidth: CGFloat
    let isReceded: Bool

    @State private var isQuestionHovered = false

    static func quantizedWidth(_ width: CGFloat) -> CGFloat {
        (width / 24).rounded() * 24
    }

    /// Width the centered question title may claim: the row width minus the
    /// wider side cluster mirrored on BOTH sides (absolute centering), minus
    /// the pill's own glyph/chevron/padding chrome.
    private var questionTitleCap: CGFloat {
        min(400, max(120, availableWidth - 530))
    }

    /// The reader's center island carries more controls (back, open, reader
    /// mode) — its title budget is tighter.
    private var readerTitleCap: CGFloat {
        min(320, max(120, availableWidth - 640))
    }

    /// Hard title width: the measured text, capped by the budget. A hard
    /// frame is the only shape that both HUGS a short title (a flexible
    /// `maxWidth` frame greedily fills, ballooning the glass island) and
    /// CAPS a long one (`.fixedSize()` reports the uncapped ideal — the bug
    /// that ran a long question clean over the side islands at pane widths).
    private static func measuredTitleWidth(_ title: String, cap: CGFloat) -> CGFloat {
        // DS.buttonText.weight(.semibold) → 12pt semibold system.
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let measured = (title as NSString)
            .size(withAttributes: [.font: font])
            .width
            .rounded(.up)
        return min(measured + 2, cap)
    }

    var body: some View {
        CosmoChromeRow {
            NavigationTrailIsland()
            CosmoChromeIsland(recede: isReceded) { navigateControls }
        } center: {
            // One center island: the question pill at the desk, the reader
            // controls while a source is open — never both.
            CosmoChromeIsland(recede: isReceded) {
                if let tab = activeReaderTab {
                    readerControls(tab)
                } else {
                    questionControl
                }
            }
        } trailing: {
            CosmoChromeIsland(recede: isReceded) { actionControls }
            crystallizeIsland
        }
    }

    private var activeReaderTab: SourceTab? {
        guard let id = viewModel.activeReaderSourceId else { return nil }
        return viewModel.structured.sourceTabs.first { $0.id == id }
    }

    // MARK: - Reader controls (the center island while reading)

    @ViewBuilder
    private func readerControls(_ tab: SourceTab) -> some View {
        StudyChromeTextButton(icon: "chevron.left", label: "Study", help: "Back to the study (Esc)") {
            withAnimation(ProMotionSprings.focusTransition) { viewModel.dismissReader() }
        }

        Text(tab.title)
            .font(DS.buttonText.weight(.semibold))
            .foregroundStyle(DS.text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: Self.measuredTitleWidth(tab.title, cap: readerTitleCap))

        if let urlString = tab.url, let url = URL(string: urlString) {
            toolbarButton(icon: "safari", help: "Open in browser") {
                NSWorkspace.shared.open(url)
            }
        }
        if tab.kind == .web {
            toolbarButton(
                icon: viewModel.readerPrefersReaderMode ? "doc.text.fill" : "doc.text",
                help: viewModel.readerPrefersReaderMode ? "Show original page" : "Show reader view",
                isActive: viewModel.readerPrefersReaderMode
            ) {
                viewModel.readerPrefersReaderMode.toggle()
            }
        }
    }

    // MARK: - Navigate island

    @ViewBuilder
    private var navigateControls: some View {
        toolbarButton(
            icon: "sidebar.squares.left",
            help: viewModel.isTrailShowing ? "Hide trail (⌘0)" : "Show trail (⌘0)",
            isActive: viewModel.isTrailShowing
        ) {
            withAnimation(ProMotionSprings.focusTransition) { viewModel.toggleTrail() }
        }
    }

    // MARK: - Question island (the orientation pill)

    private var questionControl: some View {
        Menu {
            questionMenuContent
        } label: {
            HStack(spacing: DS.space6) {
                Image(systemName: "questionmark.bubble")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
                Text(viewModel.activeQuestionTitle)
                    .font(DS.buttonText.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: Self.measuredTitleWidth(
                        viewModel.activeQuestionTitle,
                        cap: questionTitleCap
                    ))
                Image(systemName: "chevron.down")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(isQuestionHovered ? DS.surfaceElevated.opacity(0.6) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // Safe now that the title carries a HARD measured width — the pill's
        // ideal is bounded, so fixing to it hugs without ever overflowing.
        .fixedSize()
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isQuestionHovered = hovering }
        }
        .help("Switch question (⌘] cycles)")
        .accessibilityLabel("Active question: \(viewModel.activeQuestionTitle). Click to switch.")
    }

    @ViewBuilder
    private var questionMenuContent: some View {
        // The breadcrumb lives here, not in the chrome — one-line islands.
        Text(viewModel.activeQuestionBreadcrumb)
        Divider()
        ForEach(viewModel.orderedQuestionNodes(), id: \.id) { node in
            Button {
                withAnimation(ProMotionSprings.focusTransition) {
                    viewModel.setActiveQuestion(node.atomUUID, branchNodeId: node.id)
                }
            } label: {
                let counts = viewModel.counts(for: node.atomUUID)
                if node.atomUUID == viewModel.activeQuestionUUID {
                    Label("\(viewModel.questionTitle(for: node.atomUUID))  \(counts.compactLabel)", systemImage: "checkmark")
                } else {
                    Text("\(viewModel.questionTitle(for: node.atomUUID))  \(counts.compactLabel)")
                }
            }
        }
        Divider()
        Button("New branch question…") { viewModel.focusDock() }
        Button("Pin active question") { viewModel.togglePinActiveQuestion() }
        Menu("Mark active question") {
            Button("Researching") {
                Task { await viewModel.updateQuestionStatus(viewModel.activeQuestionUUID, status: .researching) }
            }
            Button("Answered") {
                Task { await viewModel.updateQuestionStatus(viewModel.activeQuestionUUID, status: .answered) }
            }
        }
    }

    // MARK: - Actions island

    @ViewBuilder
    private var actionControls: some View {
        toolbarButton(
            icon: "circle.hexagongrid",
            help: "Session map — this session's question tree (⌘M)",
            isActive: viewModel.isMapOverlayPresented
        ) {
            withAnimation(ProMotionSprings.focusTransition) { viewModel.toggleMap() }
        }
        toolbarButton(
            icon: "sidebar.right",
            help: viewModel.isReadingShowing ? "Hide reading panel (⌘⌥I)" : "Show reading panel (⌘⌥I)",
            isActive: viewModel.isReadingShowing
        ) {
            withAnimation(ProMotionSprings.focusTransition) { viewModel.toggleReading() }
        }
    }

    /// The one tinted glass element on the screen — the primary action.
    /// Tap = the Debrief (teach-back, then review); the menu holds the quiet
    /// close for low-energy sessions (everything simply incubates).
    private var crystallizeIsland: some View {
        StudyCrystallizeIsland(
            showsLabel: breakpoint != .narrow,
            action: { viewModel.startDebrief() },
            onQuickClose: { Task { await viewModel.quickCloseSession() } }
        )
    }

    // MARK: - Button factory (the Connection toolbar anatomy + hover life)

    private func toolbarButton(
        icon: String,
        help: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        StudyToolbarButton(icon: icon, help: help, isActive: isActive, action: action)
    }
}

// MARK: - Hover-aware chrome controls

/// One island control: ink brightens and a soft wash rises under the cursor —
/// the quiet acknowledgment every macOS control owes the pointer.
@MainActor
struct StudyToolbarButton: View {
    let icon: String
    let help: String
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive || isHovered ? DS.text : DS.textSecondary)
                .frame(width: 28, height: 28)
                .background(washStyle, in: Circle())
                .contentShape(Circle())
                .scaleEffect(isHovered ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var washStyle: AnyShapeStyle {
        if isActive { return AnyShapeStyle(DS.surfaceElevated) }
        if isHovered { return AnyShapeStyle(DS.surfaceElevated.opacity(0.6)) }
        return AnyShapeStyle(.clear)
    }
}

/// Small icon+label chrome button with the same hover manners as the circles.
@MainActor
struct StudyChromeTextButton: View {
    let icon: String
    let label: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                Image(systemName: icon)
                    .font(DS.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text(label)
                    .font(DS.buttonText)
            }
            .foregroundStyle(isHovered ? DS.text : DS.textSecondary)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(isHovered ? DS.surfaceElevated.opacity(0.6) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help(help)
        .accessibilityLabel(help)
    }
}

@MainActor
private struct StudyCrystallizeIsland: View {
    let showsLabel: Bool
    let action: () -> Void
    let onQuickClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        Menu {
            Button("Close quietly") { onQuickClose() }
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: "sparkles")
                    .font(DS.caption.weight(.semibold))
                    .accessibilityHidden(true)
                if showsLabel {
                    Text("Debrief")
                        .font(DS.buttonText.weight(.semibold))
                }
            }
            .foregroundStyle(DS.accent)
            .padding(.horizontal, DS.space12)
            .frame(height: CosmoChromeMetrics.height)
            .contentShape(Capsule())
        } primaryAction: {
            action()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glassEffect(.regular.tint(DS.accentSoft).interactive(), in: .capsule)
        .scaleEffect(isHovered ? 1.02 : 1)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .keyboardShortcut(.return, modifiers: [.command])
        .help("Close the session with a teach-back debrief (⌘⏎) — hold for quiet close")
        .accessibilityLabel("Debrief inquiry session")
    }
}
