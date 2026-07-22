// CosmoOS/UI/FocusMode/DeepDive/DeepDiveStudyBar.swift
// The Study's chrome: floating glass islands on the shared chrome baseline —
// [‹ › trail · topic pill]  [Overview · Sessions · Map]  [filter · Start Inquiry]
// — never a full-width bar. The trail island is the app's NavigationTrailChrome
// itself, driven through trail notifications, so back/forward/long-press
// history behave identically to everywhere else. Everything keyboard-reachable:
// ⌘1/2/3 modes, ⇧⌘I start inquiry, Esc steps back.

import SwiftUI

@MainActor
struct DeepDiveStudyBar: View {
    let title: String
    let maturityLabel: String
    @Binding var selectedTab: DeepDiveOverviewTab
    /// Context-pill law: the title shows only when the masthead isn't (scrolled
    /// off in Overview; always in Sessions/Map, which have no masthead).
    let showsTitle: Bool
    /// True while the user is down in the content — islands recede to 60%.
    var recede: Bool = false
    @Binding var mapShowsQuestions: Bool
    /// True while a forced Cartographer pass runs — the Tidy control waits.
    var isTidyingMap: Bool = false
    /// The Tidy button: asks the Cartographer to look at the map now.
    var onTidyMap: (() -> Void)? = nil
    let onTitleTap: () -> Void
    let onStartInquiry: () -> Void

    @Namespace private var switcherNamespace

    var body: some View {
        CosmoChromeRow {
            NavigationTrailIsland()
            if showsTitle {
                titleIsland
            }
        } center: {
            CosmoChromeIsland(recede: recede) { modeSwitcher }
        } trailing: {
            CosmoChromeIsland(recede: recede) {
                if selectedTab == .map {
                    mapFilter
                }
                startInquiryButton
            }
        }
        .animation(ProMotionSprings.focusTransition, value: selectedTab)
        .animation(ProMotionSprings.gentle, value: showsTitle)
    }

    // MARK: - Leading islands

    private var titleIsland: some View {
        CosmoChromeIsland(recede: recede) {
            Button(action: onTitleTap) {
                HStack(spacing: DS.space6) {
                    Circle()
                        .fill(DS.entityResearch)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(CosmoTypography.label)
                        .foregroundStyle(CosmoColors.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: 200, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, DS.space4)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Scroll to top")
            .accessibilityLabel("\(title) — \(maturityLabel). Scroll to top.")
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    // MARK: - Center: the mode switcher (the hero)

    private var modeSwitcher: some View {
        HStack(spacing: DS.space2) {
            ForEach(Array(DeepDiveOverviewTab.allCases.enumerated()), id: \.element) { index, tab in
                modeSegment(tab, index: index)
            }
        }
    }

    private func modeSegment(_ tab: DeepDiveOverviewTab, index: Int) -> some View {
        Button {
            withAnimation(ProMotionSprings.focusTransition) { selectedTab = tab }
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .medium))
                    .accessibilityHidden(true)
                Text(tab.title)
                    .font(CosmoTypography.label)
            }
            .foregroundStyle(selectedTab == tab ? CosmoColors.textPrimary : CosmoColors.textTertiary)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background {
                if selectedTab == tab {
                    Capsule()
                        .fill(DS.surfaceElevated)
                        .matchedGeometryEffect(id: "study-mode-pill", in: switcherNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        .help("\(tab.title) (⌘\(index + 1))")
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    // MARK: - Trailing: map filter + the one accent

    @ViewBuilder
    private var mapFilter: some View {
        // The one view-mode grammar: the sliding-thumb switcher (the old
        // text-only toggle was nearly invisible). Bare chrome — it already
        // sits inside a glass island.
        CosmoSegmentedSwitcher(
            options: [true, false],
            label: { $0 ? "Everything" : "Concepts" },
            help: { $0 ? "Show concepts and questions" : "Hide questions — pure concept atlas" },
            chrome: .bare,
            selection: $mapShowsQuestions
        )
        .transition(.opacity)
        if let onTidyMap {
            tidyMapButton(onTidyMap)
        }
        Divider()
            .frame(height: 18)
            .overlay(DS.borderSubtle)
    }

    /// The Cartographer on demand: propose sections for a crowded map.
    private func tidyMapButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isTidyingMap {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(CosmoColors.textSecondary)
            .frame(width: 26, height: 24)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isTidyingMap)
        .keyboardShortcut("t", modifiers: [.command, .shift])
        .help("Tidy the map — suggest sections (⇧⌘T)")
        .accessibilityLabel(isTidyingMap ? "Tidying the map" : "Tidy the map")
        .transition(.opacity)
    }

    private var startInquiryButton: some View {
        Button(action: onStartInquiry) {
            HStack(spacing: DS.space6) {
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Start Inquiry")
                    .font(CosmoTypography.label)
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, 6)
            .background(DS.accent, in: Capsule())
            .foregroundStyle(DS.textOnAccent)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("i", modifiers: [.command, .shift])
        .help("Start an inquiry session (⇧⌘I)")
        .accessibilityLabel("Start inquiry")
    }
}

// MARK: - Bottom mode switcher (the thinkspace's three modes)

/// The same bottom pill the canvas shows — Canvas, Library, and Deep Dive are
/// three modes of ONE place, so the switcher survives inside the study.
/// Picking Canvas/Library exits the focus overlay, navigates to the owning
/// thinkspace, and queues the mode swap for when the canvas is mounted.
@MainActor
struct StudyThinkspaceModeSwitcher: View {
    let thinkspaceUUID: String?

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var switcherAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.14)
            : .spring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.08)
    }

    var body: some View {
        HStack(spacing: isExpanded ? 3 : 0) {
            if isExpanded {
                ForEach(ThinkspaceCanvasMode.allCases) { mode in
                    segment(mode)
                }
            } else {
                collapsedButton
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .frame(minWidth: 34)
        .frame(height: 34)
        .background(DS.glassInputFill, in: Capsule())
        .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 1))
        .clipShape(Capsule())
        .dsFloatingShadow()
        .onHover { hovering in
            withAnimation(switcherAnimation) { isExpanded = hovering }
        }
        .animation(switcherAnimation, value: isExpanded)
    }

    private var collapsedButton: some View {
        Button {
            withAnimation(switcherAnimation) { isExpanded.toggle() }
        } label: {
            Image(systemName: ThinkspaceCanvasMode.deepDive.icon)
                .font(DS.footnote.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 34, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch view, currently Deep Dive")
    }

    private func segment(_ mode: ThinkspaceCanvasMode) -> some View {
        let isCurrent = mode == .deepDive
        return Button {
            select(mode)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(DS.footnote.weight(.semibold))
                Text(mode.title)
                    .font(DS.footnote.weight(.semibold))
            }
            .foregroundStyle(isCurrent ? DS.accent : DS.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(isCurrent ? DS.accentSoft : Color.clear))
            .overlay(Capsule().strokeBorder(isCurrent ? DS.accent.opacity(0.4) : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(mode.title) mode")
        .accessibilityLabel("\(mode.title) mode")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    private func select(_ mode: ThinkspaceCanvasMode) {
        withAnimation(switcherAnimation) { isExpanded = false }
        guard mode != .deepDive else { return }
        if let thinkspaceUUID {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.navigateToThinkspaceById,
                object: nil,
                userInfo: ["thinkspaceId": thinkspaceUUID]
            )
        }
        // Queued: delivered the moment the canvas is mounted and observing.
        CanvasPendingPlacementQueue.shared.enqueue(
            name: CosmoNotification.Canvas.setThinkspaceMode,
            userInfo: ["mode": mode.rawValue]
        )
        // Direct close, not `.exitFocusMode`: this is an explicit "go to
        // canvas/library", never a "step back" — the trail must not replay
        // the deep dive we are deliberately leaving.
        FocusNavigationCoordinator.shared.close()
    }
}
