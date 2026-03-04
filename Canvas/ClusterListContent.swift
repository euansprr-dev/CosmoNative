// CosmoOS/Canvas/ClusterListContent.swift
// List mode rendering for clusters — compact scannable rows inside the cluster zone

import SwiftUI

struct ClusterListContent: View {

    let cluster: CanvasCluster
    let blocks: [CanvasBlock]
    let sortOrder: ClusterSortOrder
    let expandedBlockUUID: String?
    let onChangeSortOrder: (ClusterSortOrder) -> Void
    let onToggleExpand: (String) -> Void
    let onOpenFocusMode: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            sortBar
            separatorLine
            rowsList
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DS.surfaceElevated.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.border.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 8)
    }

    private var separatorLine: some View {
        Rectangle()
            .fill(DS.border)
            .frame(height: 1)
            .padding(.horizontal, 8)
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        HStack(spacing: 0) {
            ForEach(ClusterSortOrder.allCases, id: \.self) { order in
                sortButton(order)
                if order != .status { Spacer(minLength: 0) }
            }

            Spacer(minLength: 8)

            Text("\(memberBlocks.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(DS.surface)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func sortButton(_ order: ClusterSortOrder) -> some View {
        let isActive = sortOrder == order

        Button {
            onChangeSortOrder(order)
        } label: {
            Text(order.displayName)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? DS.accent : DS.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? DS.accentSoft : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rows List

    private var rowsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(sortedBlocks, id: \.id) { block in
                    VStack(spacing: 0) {
                        ClusterListRow(
                            block: block,
                            isExpanded: expandedBlockUUID == block.entityUuid,
                            onTap: { onToggleExpand(block.entityUuid) },
                            onDoubleTap: { onOpenFocusMode(block.entityUuid) }
                        )

                        if expandedBlockUUID == block.entityUuid {
                            expandedContent(for: block)
                        }

                        if block.id != sortedBlocks.last?.id {
                            Rectangle()
                                .fill(DS.border.opacity(0.4))
                                .frame(height: 1)
                                .padding(.horizontal, 12)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func expandedContent(for block: CanvasBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let subtitle = block.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(5)
            }

            HStack(spacing: 8) {
                if let tags = block.metadata["tags"], !tags.isEmpty {
                    Text(tags)
                        .font(.system(size: 10))
                        .foregroundColor(DS.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    onOpenFocusMode(block.entityUuid)
                } label: {
                    openButtonLabel
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .padding(.leading, 28)
        .background(DS.surface.opacity(0.5))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var openButtonLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .medium))
            Text("Open")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(DS.accent)
    }

    // MARK: - Sorting

    private var memberBlocks: [CanvasBlock] {
        let uuids = Set(cluster.blockUUIDs)
        return blocks.filter { uuids.contains($0.entityUuid) }
    }

    private var sortedBlocks: [CanvasBlock] {
        let members = memberBlocks
        switch sortOrder {
        case .dateUpdated:
            return members.sorted { ($0.metadata["updated"] ?? "") > ($1.metadata["updated"] ?? "") }
        case .type:
            return members.sorted { $0.entityType.rawValue < $1.entityType.rawValue }
        case .status:
            return members.sorted { statusString(for: $0) < statusString(for: $1) }
        }
    }

    private func statusString(for block: CanvasBlock) -> String {
        switch block.entityType {
        case .task:    return block.metadata["status"] ?? ""
        case .content: return block.metadata["currentStep"] ?? block.metadata["status"] ?? ""
        case .idea:    return block.metadata["ideaStatus"] ?? ""
        default:       return block.entityType.rawValue
        }
    }
}

// MARK: - Sort Order Display

extension ClusterSortOrder {
    var displayName: String {
        switch self {
        case .dateUpdated: return "Date"
        case .type:        return "Type"
        case .status:      return "Status"
        }
    }
}

// MARK: - List Row

struct ClusterListRow: View {

    let block: CanvasBlock
    let isExpanded: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            typeIcon
            titleText

            Spacer(minLength: 4)

            metadataBadge

            chevronIcon
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture(count: 1) {
            withAnimation(ProMotionSprings.snappy) { onTap() }
        }
        .onHover { hovering in isHovered = hovering }
    }

    // Extracted subviews to help the type-checker

    private var typeIcon: some View {
        Circle()
            .fill(CosmoMentionColors.color(for: block.entityType))
            .frame(width: 22, height: 22)
            .overlay(
                Image(systemName: block.entityType.icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
            )
    }

    private var titleText: some View {
        Text(block.title)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(DS.text)
            .lineLimit(1)
    }

    private var chevronIcon: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(DS.textMuted)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isHovered ? DS.surface : Color.clear)
    }

    // MARK: - Metadata Badge

    @ViewBuilder
    private var metadataBadge: some View {
        let info = badgeInfo
        if !info.text.isEmpty {
            Text(info.text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(info.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(info.color.opacity(0.12))
                )
        }
    }

    private var badgeInfo: (text: String, color: Color) {
        switch block.entityType {
        case .task:
            let status = block.metadata["status"] ?? "pending"
            return (status.capitalized, CosmoMentionColors.task)
        case .content:
            let phase = block.metadata["currentStep"] ?? block.metadata["status"] ?? "draft"
            return (phase.capitalized, CosmoMentionColors.content)
        case .idea:
            let status = block.metadata["ideaStatus"] ?? "spark"
            return (status.capitalized, CosmoMentionColors.idea)
        case .research:
            let platform = block.metadata["platform"] ?? "Research"
            return (platform.capitalized, CosmoMentionColors.research)
        case .connection:
            return ("Connection", CosmoMentionColors.connection)
        case .project:
            let status = block.metadata["status"] ?? "active"
            return (status.capitalized, CosmoMentionColors.project)
        default:
            return (block.entityType.rawValue.capitalized, CosmoMentionColors.defaultColor)
        }
    }
}
