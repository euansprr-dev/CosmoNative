// CosmoOS/UI/FocusMode/DeepDive/DeepDiveStudyBar.swift
// The Study's chrome: floating glass islands on the shared chrome baseline —
// [‹ › trail · topic pill]  [Overview · Sessions · Map]  [filter · Start Inquiry]
// — never a full-width bar. The islands are shared with the SPACE chrome row:
// when a deep dive is hosted as a view inside its space, the space row mounts
// `DeepDiveStudyTabsIsland` + `DeepDiveStudyToolsIsland` beside the view
// switcher and this bar stands down. Everything keyboard-reachable:
// ⇧⌘1/2/3 tabs, ⇧⌘I start inquiry, ⇧⌘T tidy.

import SwiftUI

@MainActor
struct DeepDiveStudyBar: View {
    let chrome: DeepDiveStudyChromeModel

    var body: some View {
        CosmoChromeRow {
            NavigationTrailIsland()
            if chrome.showsTitle {
                DeepDiveStudyTitleIsland(chrome: chrome)
            }
        } center: {
            DeepDiveStudyTabsIsland(chrome: chrome)
        } trailing: {
            DeepDiveStudyToolsIsland(chrome: chrome)
        }
        .animation(ProMotionSprings.focusTransition, value: chrome.selectedTab)
        .animation(ProMotionSprings.gentle, value: chrome.showsTitle)
    }
}

// MARK: - Title island (context pill)

struct DeepDiveStudyTitleIsland: View {
    let chrome: DeepDiveStudyChromeModel

    var body: some View {
        CosmoChromeIsland(recede: chrome.recede) {
            Button(action: chrome.actions.scrollToTop) {
                HStack(spacing: DS.space6) {
                    Circle()
                        .fill(DS.entityResearch)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(chrome.title)
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
            .accessibilityLabel("\(chrome.title) — \(chrome.maturityLabel). Scroll to top.")
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }
}

// MARK: - Tabs island (Overview · Sessions · Map)

struct DeepDiveStudyTabsIsland: View {
    let chrome: DeepDiveStudyChromeModel

    @Namespace private var switcherNamespace

    var body: some View {
        CosmoChromeIsland(recede: chrome.recede) {
            HStack(spacing: DS.space2) {
                ForEach(Array(DeepDiveOverviewTab.allCases.enumerated()), id: \.element) { index, tab in
                    segment(tab, index: index)
                }
            }
        }
    }

    private func segment(_ tab: DeepDiveOverviewTab, index: Int) -> some View {
        Button {
            chrome.select(tab)
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: tab.icon)
                    .font(DS.caption2.weight(.medium))
                    .accessibilityHidden(true)
                Text(tab.title)
                    .font(CosmoTypography.label)
            }
            .foregroundStyle(chrome.selectedTab == tab ? CosmoColors.textPrimary : CosmoColors.textTertiary)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background {
                if chrome.selectedTab == tab {
                    Capsule()
                        .fill(DS.surfaceElevated)
                        .matchedGeometryEffect(id: "study-mode-pill", in: switcherNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .shift])
        .disabled(!chrome.isFrontmost)
        .help("\(tab.title) (⇧⌘\(index + 1))")
        .accessibilityAddTraits(chrome.selectedTab == tab ? .isSelected : [])
    }
}

// MARK: - Tools island (map filter · tidy · Start Inquiry)

struct DeepDiveStudyToolsIsland: View {
    let chrome: DeepDiveStudyChromeModel

    @AppStorage("deepDiveMapShowsQuestions") private var mapShowsQuestions = true

    var body: some View {
        CosmoChromeIsland(recede: chrome.recede) {
            if chrome.selectedTab == .map {
                mapFilter
            }
            startInquiryButton
        }
    }

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
        tidyMapButton
        Divider()
            .frame(height: 18)
            .overlay(DS.borderSubtle)
    }

    /// The Cartographer on demand: propose sections for a crowded map.
    private var tidyMapButton: some View {
        Button(action: chrome.actions.tidyMap) {
            Group {
                if chrome.isTidyingMap {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "rectangle.3.group")
                        .font(DS.caption2.weight(.medium))
                }
            }
            .foregroundStyle(CosmoColors.textSecondary)
            .frame(width: 26, height: 24)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(chrome.isTidyingMap || !chrome.isFrontmost)
        .keyboardShortcut("t", modifiers: [.command, .shift])
        .help("Tidy the map — suggest sections (⇧⌘T)")
        .accessibilityLabel(chrome.isTidyingMap ? "Tidying the map" : "Tidy the map")
        .transition(.opacity)
    }

    private var startInquiryButton: some View {
        Button(action: chrome.actions.startInquiry) {
            HStack(spacing: DS.space6) {
                Image(systemName: "rectangle.split.3x1")
                    .font(DS.caption2.weight(.semibold))
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
        .disabled(!chrome.isFrontmost)
        .keyboardShortcut("i", modifiers: [.command, .shift])
        .help("Start an inquiry session (⇧⌘I)")
        .accessibilityLabel("Start inquiry")
    }
}
