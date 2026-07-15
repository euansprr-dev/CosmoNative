// CosmoOS/UI/FocusMode/Connection/ConnectionInspectorView.swift
// June 2026 — Connection workspace revamp.
// Right inspector: selection-aware detail. Connection level shows maturity,
// concept type, and live insights; section/item/source levels show their
// provenance and actions — the macOS inspector idiom.

import SwiftUI

struct ConnectionInspectorView: View {
    var viewModel: ConnectionFocusModeViewModel
    var workspace: ConnectionWorkspaceModel
    let sources: ConnectionWorkspaceSources
    /// Pages/photos the capture carried in when this concept was germinated or
    /// fed — the evidence, re-owned onto the atom by the router.
    var attachmentUUIDs: [String] = []
    let isRefreshingInsights: Bool
    let actions: ConnectionWorkspaceActions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space20) {
                switch workspace.selection {
                case .connection:
                    connectionDetail
                case .section(let type):
                    ConnectionInspectorSectionDetail(type: type, viewModel: viewModel, workspace: workspace)
                case .item(let type, let id):
                    ConnectionInspectorItemDetail(type: type, itemID: id, viewModel: viewModel, actions: actions)
                case .source(let uuid):
                    ConnectionInspectorSourceDetail(uuid: uuid, sources: sources, actions: actions)
                }
            }
            .padding(DS.space16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 280)
        .background(DS.surface)
    }

    // MARK: - Connection level

    private var connectionDetail: some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            maturityBlock
            typePicker
            statsBlock
            if !attachmentUUIDs.isEmpty { capturedBlock }
            LiveInsightsPanel(
                insights: viewModel.state.liveInsights,
                isRefreshing: isRefreshingInsights,
                onRefresh: actions.onRefreshInsights,
                onDismiss: actions.onDismissInsight
            )
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(DS.borderSubtle, lineWidth: 1)
            )
        }
    }

    private var maturityBlock: some View {
        VStack(alignment: .center, spacing: DS.space8) {
            MaturityCrystalView(
                filledCount: viewModel.state.completedSectionCount,
                diameter: 64
            )
            Text(MaturityCrystalView.captionText(for: viewModel.state.completedSectionCount))
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.space8)
        .accessibilityElement(children: .combine)
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text("Type")
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(DS.textMuted)
            Picker("Concept type", selection: conceptTypeBinding) {
                ForEach(ConceptFrameworkType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var conceptTypeBinding: Binding<ConceptFrameworkType> {
        Binding(
            get: { viewModel.state.conceptType },
            set: { viewModel.updateConceptType($0) }
        )
    }

    private var statsBlock: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text("At a glance")
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(DS.textMuted)
            ConnectionInspectorStatRow(label: "Items", value: "\(viewModel.state.totalItemCount)")
            ConnectionInspectorStatRow(label: "Sections filled", value: "\(viewModel.state.completedSectionCount) of \(ConnectionSectionType.allCases.count)")
            ConnectionInspectorStatRow(label: "Sources", value: "\(sources.linked.count)")
        }
    }

    private var capturedBlock: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text("Captured")
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(DS.textMuted)
            AttachmentRail(
                attachmentUUIDs: attachmentUUIDs,
                thumbSize: CGSize(width: 56, height: 74)
            )
        }
    }
}

// MARK: - Stat row

struct ConnectionInspectorStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text(value)
                .font(DS.callout)
                .foregroundStyle(DS.text)
        }
    }
}

// MARK: - Section level

struct ConnectionInspectorSectionDetail: View {
    let type: ConnectionSectionType
    var viewModel: ConnectionFocusModeViewModel
    var workspace: ConnectionWorkspaceModel

    private var section: ConnectionSection? {
        viewModel.state.section(for: type)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            HStack(spacing: DS.space8) {
                Image(systemName: type.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(type.accentColor)
                    .accessibilityHidden(true)
                Text(type.displayName)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
            }

            Text(type.promptQuestion)
                .font(DS.callout)
                .italic()
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DS.space6) {
                ConnectionInspectorStatRow(label: "Items", value: "\(section?.itemCount ?? 0)")
            }

            Button("Open Section") {
                workspace.openSection(type)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Item level

struct ConnectionInspectorItemDetail: View {
    let type: ConnectionSectionType
    let itemID: UUID
    var viewModel: ConnectionFocusModeViewModel
    let actions: ConnectionWorkspaceActions

    private var item: ConnectionItem? {
        viewModel.state.section(for: type)?.items.first { $0.id == itemID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            Text(type.displayName)
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(DS.textMuted)

            if let item {
                if let linkedUUID = item.linkedConnectionUUID {
                    ConnectionLinkPill(title: item.resolvedPlainText) {
                        actions.onSourceTap(linkedUUID)
                    }
                } else {
                    ConnectionLinkedText(text: item.resolvedPlainText, font: DS.callout)
                }

                if let snippet = item.sourceSnippet, !snippet.isEmpty {
                    VStack(alignment: .leading, spacing: DS.space4) {
                        Text("From source")
                            .font(DS.smallCaps)
                            .tracking(1.4)
                            .foregroundStyle(DS.textMuted)
                        Text(snippet)
                            .font(DS.caption)
                            .italic()
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(6)
                    }
                }

                if let sourceUUID = item.sourceAtomUUID, !item.isConnectionLink {
                    Button("Open Source") {
                        actions.onSourceTap(sourceUUID)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ConnectionInspectorStatRow(label: "Added", value: item.createdAt.formatted(date: .abbreviated, time: .omitted))
            } else {
                Text("This item was removed.")
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }
}

// MARK: - Source level

struct ConnectionInspectorSourceDetail: View {
    let uuid: String
    let sources: ConnectionWorkspaceSources
    let actions: ConnectionWorkspaceActions

    private var source: Atom? {
        sources.linked.first { $0.uuid == uuid }
    }

    private var contributions: [ConnectionSectionType] {
        Array(sources.contributions[uuid] ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            if let source {
                HStack(spacing: DS.space8) {
                    Image(systemName: source.type.iconName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                        .accessibilityHidden(true)
                    Text(source.title ?? "Untitled")
                        .font(DS.headline)
                        .foregroundStyle(DS.text)
                        .lineLimit(3)
                }

                if let body = source.body, !body.isEmpty {
                    Text(body)
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(8)
                }

                if !contributions.isEmpty {
                    VStack(alignment: .leading, spacing: DS.space6) {
                        Text("Feeds")
                            .font(DS.smallCaps)
                            .tracking(1.4)
                            .foregroundStyle(DS.textMuted)
                        ConnectionInspectorContributionChips(contributions: contributions)
                    }
                }

                Button("Open Source") {
                    actions.onSourceTap(uuid)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Text("Source unavailable.")
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }
}

struct ConnectionInspectorContributionChips: View {
    let contributions: [ConnectionSectionType]

    var body: some View {
        FlowingChips(items: contributions)
    }
}

/// Minimal wrapping chip row for section contributions.
private struct FlowingChips: View {
    let items: [ConnectionSectionType]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            ForEach(items, id: \.self) { type in
                HStack(spacing: DS.space4) {
                    Image(systemName: type.icon)
                        .font(.system(size: 9, weight: .medium))
                        .accessibilityHidden(true)
                    Text(type.displayName)
                        .font(DS.caption)
                }
                .foregroundStyle(type.accentColor)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, DS.space2)
                .background(type.accentColor.opacity(0.10), in: Capsule())
            }
        }
    }
}
