// CosmoOS/UI/FocusMode/Ideas/IdeaInspectorView.swift
// June 2026 — Idea Focus Mode v2 (Greenhouse clean).
// Right inspector: the idea's intelligence — swipes, framework, blueprint,
// research — as structured panels in the Connection inspector's vocabulary.

import SwiftUI

struct IdeaInspectorView: View {
    var viewModel: IdeaFocusModeViewModel
    let isLoadingArcRecommendations: Bool
    let actions: IdeaWorkspaceActions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space20) {
                swipesSection
                frameworkSection
                blueprintSection
                researchSection
            }
            .padding(DS.space16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 280)
        .background(DS.surface)
    }

    // MARK: - Swipes

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
                    ForEach(viewModel.linkedSwipes.prefix(3), id: \.uuid) { swipe in
                        IdeaInspectorSwipeRow(
                            swipe: swipe,
                            onOpen: { actions.onOpenAtomInPane(swipe.uuid) },
                            onRemove: { Task { await viewModel.unlinkSwipe(swipe.uuid) } }
                        )
                    }
                    Button(swipeOverflowLabel) {
                        actions.onShowLinkSwipes()
                    }
                    .buttonStyle(.plain)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.space2)
                    .help("Add or remove linked swipes")
                }
            }
        }
    }

    private var swipeOverflowLabel: String {
        let hidden = viewModel.linkedSwipes.count - 3
        return hidden > 0 ? "All \(viewModel.linkedSwipes.count) swipes…" : "Add or remove…"
    }

    // MARK: - Framework

    private var frameworkSection: some View {
        IdeaInspectorSection(title: "Framework") {
            if let framework = viewModel.selectedArcType ?? viewModel.arcRecommendations.first?.arcName {
                VStack(alignment: .leading, spacing: DS.space6) {
                    Text(framework)
                        .font(DS.headline)
                        .foregroundStyle(DS.text)
                    if let top = viewModel.arcRecommendations.first(where: { $0.arcName == framework }) {
                        IdeaInspectorStatRow(label: "Match", value: "\(Int(top.confidence * 100))%")
                    }
                    Button("Change Framework") {
                        actions.onChangeFramework()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if isLoadingArcRecommendations {
                HStack(spacing: DS.space8) {
                    ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                    Text("Reading the idea…")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }
            } else {
                IdeaInspectorTeachingButton(
                    text: "A framework shapes the idea into a story arc.",
                    actionLabel: "Suggest frameworks",
                    action: actions.onSuggestFramework
                )
            }
        }
    }

    // MARK: - Blueprint

    private var blueprintSection: some View {
        IdeaInspectorSection(title: "Blueprint") {
            if let blueprint = viewModel.selectedBlueprint {
                VStack(alignment: .leading, spacing: DS.space6) {
                    Button {
                        actions.onOpenAtomInPane(blueprint.uuid)
                    } label: {
                        Text(blueprint.title ?? "Blueprint")
                            .font(DS.headline)
                            .foregroundStyle(DS.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open blueprint")

                    HStack(spacing: DS.space6) {
                        Button("Expand") { actions.onShowBlueprintSheet() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("Change") { actions.onShowBlueprintPicker() }
                            .buttonStyle(.plain)
                            .font(DS.caption)
                            .foregroundStyle(DS.textSecondary)
                        Button("Remove") { viewModel.clearBlueprint() }
                            .buttonStyle(.plain)
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                    }
                }
            } else {
                IdeaInspectorTeachingButton(
                    text: "Write against a proven post's structure.",
                    actionLabel: "Select blueprint",
                    action: actions.onShowBlueprintPicker
                )
            }
        }
    }

    // MARK: - Research

    private var researchSection: some View {
        IdeaInspectorSection(
            title: "Research",
            count: viewModel.researchResults.isEmpty ? nil : viewModel.researchResults.count
        ) {
            if viewModel.researchResults.isEmpty {
                IdeaInspectorTeachingButton(
                    text: "Research pulls sources for this angle.",
                    actionLabel: "Open research",
                    action: actions.onShowResearch
                )
            } else {
                VStack(alignment: .leading, spacing: DS.space6) {
                    IdeaInspectorStatRow(
                        label: "Sources",
                        value: "\(viewModel.researchResults.count)"
                    )
                    Button("Open Research Panel") {
                        actions.onShowResearch()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
                }
                Spacer(minLength: 0)
            }
            content
        }
    }
}

// MARK: - Rows

struct IdeaInspectorStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text(value)
                .font(DS.callout.monospacedDigit())
                .foregroundStyle(DS.text)
        }
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
            Button(actionLabel, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

struct IdeaInspectorSwipeRow: View {
    let swipe: Atom
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(swipe.title ?? "Untitled")
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let hook = swipe.researchMetadata?.hook {
                        Text(hook)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
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
    }
}
