// CosmoOS/UI/FocusMode/Ideas/IdeaInspectorView.swift
// July 2026 — the Idea bench's panels.
// Right: the swipe wall — the inspiration linked to this idea, and the
// library's best performers in the idea's format offered underneath.
// Left: the conversation panel — the resident assistant (where /Research,
// strategy, and riffs live), same grammar as the Concept Desk's thread.
// Both are bench panels: self-sized, edge-docked on the study panel surface,
// welded into the worksheet by their hairlines. Every swipe wears its own
// thumbnail (identity outranks type), and absence teaches the fix.

import SwiftUI

struct IdeaInspectorView: View {
    var viewModel: IdeaFocusModeViewModel
    let actions: IdeaWorkspaceActions
    var isOverlay: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space20) {
                    swipesSection
                    recommendedSection
                }
                .padding(.horizontal, DS.space16)
                .padding(.bottom, DS.space16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
        .frame(width: StudyMetrics.panelWidth)
        .studyPanelSurface(edge: .trailing, isOverlay: isOverlay)
    }

    /// The panel's one header (the bench panel grammar): what this wall is,
    /// and how much is on it.
    private var header: some View {
        HStack(spacing: DS.space6) {
            Text("INSPIRATION")
                .dsSmallCapsLabel()
            Spacer()
            Text("\(viewModel.linkedSwipes.count)")
                .font(DS.caption)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space10)
    }

    // MARK: - Linked swipes

    private var swipesSection: some View {
        IdeaInspectorSection(
            title: "Swipes",
            count: viewModel.linkedSwipes.isEmpty ? nil : viewModel.linkedSwipes.count
        ) {
            if viewModel.linkedSwipes.isEmpty {
                IdeaInspectorTeachingButton(
                    text: "Link a swipe to borrow its structure.",
                    actionLabel: "Add swipes",
                    action: actions.onShowLinkSwipes
                )
            } else {
                VStack(alignment: .leading, spacing: DS.space6) {
                    ForEach(viewModel.linkedSwipes, id: \.uuid) { swipe in
                        IdeaInspectorSwipeRow(
                            swipe: swipe,
                            onOpen: { actions.onOpenAtomInPane(swipe.uuid) },
                            onRemove: { Task { await viewModel.unlinkSwipe(swipe.uuid) } }
                        )
                    }
                    Button("Add or remove…") {
                        actions.onShowLinkSwipes()
                    }
                    .buttonStyle(.plain)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.space2)
                    .help("Add or remove linked swipes (⌘⇧L)")
                }
            }
        }
    }

    // MARK: - Recommended (the library's best performers in this format)

    /// The steal-from-the-winners shelf: when the idea has a format, the top
    /// performers of that format offer themselves — one click links them.
    private var recommendedSection: some View {
        IdeaInspectorSection(
            title: "Recommended",
            count: viewModel.recommendedSwipes.isEmpty ? nil : viewModel.recommendedSwipes.count
        ) {
            if viewModel.selectedFormat == nil {
                Text("Set a format on the idea to see your library's best performers in that style.")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if viewModel.recommendedSwipes.isEmpty {
                Text("No \(viewModel.selectedFormat?.displayName.lowercased() ?? "matching") swipes in your library yet — everything in this format is already linked, or none are saved.")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: DS.space6) {
                    ForEach(viewModel.recommendedSwipes, id: \.uuid) { swipe in
                        IdeaInspectorRecommendedRow(
                            swipe: swipe,
                            onOpen: { actions.onOpenAtomInPane(swipe.uuid) },
                            onLink: { Task { await viewModel.linkSwipe(swipe.uuid) } }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Section container

struct IdeaInspectorSection<Content: View>: View {
    let title: String
    var count: Int?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: DS.space6) {
                Text(title)
                    .font(DS.smallCaps)
                    .tracking(1.4)
                    .foregroundStyle(DS.textMuted)
                if let count {
                    Text("\(count)")
                        .font(DS.caption.monospacedDigit())
                        .foregroundStyle(DS.textMuted)
                        .contentTransition(.numericText())
                        .animation(ProMotionSprings.gentle, value: count)
                }
                Spacer(minLength: 0)
            }
            content
        }
    }
}

// MARK: - Actions

/// The rail's one action voice — the app's soft-accent button, never a stock
/// bordered control.
struct IdeaInspectorActionButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .dsAccentSoftButton()
                .brightness(isHovered ? -0.03 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityLabel(title)
    }
}

/// Teaching empty state: a sentence about why, then the action.
struct IdeaInspectorTeachingButton: View {
    let text: String
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(text)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            IdeaInspectorActionButton(title: actionLabel, action: action)
        }
    }
}

// MARK: - Rows

struct IdeaInspectorSwipeRow: View {
    let swipe: Atom
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Button(action: onOpen) {
                IdeaInspectorSwipeRowBody(swipe: swipe)
            }
            .buttonStyle(.plain)
            .help("Open swipe")

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.medium))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 18, height: 18)
                    .background(DS.border.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("Unlink swipe")
            .accessibilityLabel("Remove swipe \(swipe.title ?? "untitled")")
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space6)
        .background(
            isHovered ? DS.surfaceElevated : .clear,
            in: .rect(cornerRadius: 8)
        )
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A best performer offering itself: same object grammar as the linked rows,
/// plus the performance line that earned it the slot and a one-click link.
struct IdeaInspectorRecommendedRow: View {
    let swipe: Atom
    let onOpen: () -> Void
    let onLink: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Button(action: onOpen) {
                IdeaInspectorSwipeRowBody(swipe: swipe, detail: performanceLine)
            }
            .buttonStyle(.plain)
            .help("Open swipe")

            Button(action: onLink) {
                Image(systemName: "plus")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 18, height: 18)
                    .background(DS.accentSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("Link to this idea")
            .accessibilityLabel("Link swipe \(swipe.title ?? "untitled") to this idea")
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space6)
        .background(
            isHovered ? DS.surfaceElevated : .clear,
            in: .rect(cornerRadius: 8)
        )
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
    }

    /// "1.2M views · 4.8% engagement" — the receipt for why this row is here.
    private var performanceLine: String? {
        let analysis = swipe.swipeAnalysis
        var parts: [String] = []
        if let views = analysis?.viewsCount, views > 0 {
            parts.append("\(Self.compactCount(views)) views")
        }
        if let engagement = analysis?.engagementRate, engagement > 0 {
            parts.append(String(format: "%.1f%% engagement", engagement))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func compactCount(_ value: Int) -> String {
        switch value {
        case 1_000_000...:
            return String(format: "%.1fM", Double(value) / 1_000_000)
                .replacingOccurrences(of: ".0M", with: "M")
        case 1_000...:
            return String(format: "%.1fK", Double(value) / 1_000)
                .replacingOccurrences(of: ".0K", with: "K")
        default:
            return "\(value)"
        }
    }
}

// MARK: - The conversation panel (the bench's left column)

/// The resident assistant: the same pane timeline and composer the floating
/// assistant uses, docked as a bench panel and bound to this idea's surface.
/// This is where /Research, strategy, and riffs live while the idea is being
/// worked — replies land here, edits stage into the manuscript as reviewed
/// diffs. Same grammar as the Concept Desk's conversation column, plus a
/// composer (the Study feeds its thread from the thinking bar; the bench
/// panel carries its own field).
@MainActor
struct IdeaConversationPanel: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    var isOverlay: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.paneMessages.isEmpty {
                teachingState
            } else {
                CosmoInlineAssistantPaneMessages(store: store)
            }
            Divider().overlay(DS.borderSubtle)
            CosmoInlineAssistantPaneComposer(store: store)
        }
        .frame(width: StudyMetrics.panelWidth)
        .studyPanelSurface(edge: .leading, isOverlay: isOverlay)
    }

    private var header: some View {
        HStack(spacing: DS.space6) {
            Text("CONVERSATION")
                .dsSmallCapsLabel()
            Spacer()
            if store.isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space10)
    }

    private var teachingState: some View {
        VStack {
            Text("Work the idea out loud. /Research pulls sourced stats for this angle; edits stage into the manuscript for review.")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, DS.space16)
                .padding(.vertical, DS.space12)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
    }
}

/// The shared row body: thumbnail (mirror→CDN fallback chain, the Ideas-page
/// contract), title, and one quiet detail line.
private struct IdeaInspectorSwipeRowBody: View {
    let swipe: Atom
    var detail: String? = nil

    private var thumbCandidates: [String] {
        var candidates: [String] = []
        if let preferred = swipe.toSwipeGalleryItem()?.thumbnailUrl { candidates.append(preferred) }
        if let cdn = swipe.researchMetadata?.thumbnailUrl, !candidates.contains(cdn) { candidates.append(cdn) }
        return candidates
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            IdeaInspirationThumb(
                candidates: thumbCandidates,
                hairline: DS.palette.sepiaBorder,
                width: 32,
                height: 40
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(swipe.title ?? "Untitled")
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(DS.caption2.monospacedDigit())
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                } else if let hook = swipe.researchMetadata?.hook {
                    Text(hook)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
