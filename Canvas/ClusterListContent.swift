// CosmoOS/Canvas/ClusterListContent.swift
// List mode rendering for clusters — compact scannable rows native to the cluster zone
// March 2026: Added drag-and-drop between clusters

import SwiftUI

struct ClusterListContent: View {

    let cluster: CanvasCluster
    let clusterColor: Color
    let blocks: [CanvasBlock]
    let isDropTargeted: Bool
    let sortOrder: ClusterSortOrder
    let expandedBlockUUID: String?
    let onChangeSortOrder: (ClusterSortOrder) -> Void
    let onToggleExpand: (String) -> Void
    let onOpenFocusMode: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            sortBar
            separatorLine
            rowsList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var separatorLine: some View {
        Rectangle()
            .fill(clusterColor.opacity(0.2))
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
                .background(Capsule().fill(clusterColor.opacity(0.12)))
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
                .foregroundColor(isActive ? clusterColor : DS.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? clusterColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rows List

    private var rowsList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if let expanded = expandedBlock {
                        pinnedExpandedPreview(for: expanded)
                            .padding(.horizontal, 8)
                            .padding(.top, 6)
                            .padding(.bottom, 4)
                    }

                    ForEach(sortedBlocks, id: \.id) { block in
                        VStack(spacing: 0) {
                            ClusterListRow(
                                block: block,
                                clusterColor: clusterColor,
                                isExpanded: expandedBlockUUID == block.entityUuid,
                                onTap: { onToggleExpand(block.entityUuid) },
                                onDoubleTap: { onOpenFocusMode(block.entityUuid) }
                            )
                            .id(block.entityUuid)
                            .onDrag { dragProvider(for: block) }

                            if block.id != sortedBlocks.last?.id {
                                Rectangle()
                                    .fill(clusterColor.opacity(0.12))
                                    .frame(height: 1)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }

                    // Drop placeholder
                    if isDropTargeted {
                        listDropPlaceholder
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .onChange(of: expandedBlockUUID) { _, newValue in
                guard let newValue else { return }
                if reduceMotion {
                    proxy.scrollTo(newValue, anchor: .top)
                } else {
                    withAnimation(ProMotionSprings.snappy) {
                        proxy.scrollTo(newValue, anchor: .top)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pinnedExpandedPreview(for block: CanvasBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(CosmoMentionColors.color(for: block.entityType))
                    .frame(width: 10, height: 10)
                Text(block.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.text)
                    .lineLimit(2)
                Spacer()
                Button {
                    onToggleExpand(block.entityUuid)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(DS.textMuted)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(DS.surface))
                }
                .buttonStyle(.plain)
            }

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
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .medium))
                        Text("Open")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(DS.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(clusterColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(clusterColor.opacity(0.22), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Drop Placeholder

    private var listDropPlaceholder: some View {
        HStack(spacing: 8) {
            Circle()
                .strokeBorder(clusterColor.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(clusterColor.opacity(0.5))
                )

            Text("Drop here")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(clusterColor.opacity(0.5))

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    clusterColor.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(clusterColor.opacity(0.05))
                )
        )
        .padding(.horizontal, 8)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(ProMotionSprings.snappy, value: isDropTargeted)
    }

    // MARK: - Sorting

    private var memberBlocks: [CanvasBlock] {
        let uuids = Set(cluster.blockUUIDs)
        return blocks.filter { uuids.contains($0.entityUuid) }
    }

    private var expandedBlock: CanvasBlock? {
        guard let uuid = expandedBlockUUID else { return nil }
        return memberBlocks.first(where: { $0.entityUuid == uuid })
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
        case .task:
            let raw = block.metadata["status"] ?? "todo"
            return CanvasClusterEngine.canonicalTaskStatus(raw)
        case .content:
            let raw = block.metadata["currentStep"] ?? block.metadata["status"] ?? "ideation"
            return CanvasClusterEngine.canonicalContentPhase(raw)
        case .idea:
            let raw = block.metadata["ideaStatus"] ?? "spark"
            return CanvasClusterEngine.canonicalIdeaStatus(raw)
        default:
            return block.entityType.rawValue
        }
    }

    private func dragProvider(for block: CanvasBlock) -> NSItemProvider {
        ClusterViewDragSession.sourceClusterId = cluster.id
        return NSItemProvider(object: block.entityUuid as NSString)
    }
}

// MARK: - Sort Order Display

extension ClusterSortOrder {
    var displayName: String {
        switch self {
        case .dateUpdated: return "Updated"
        case .type:        return "Type"
        case .status:      return "Status"
        }
    }
}

// MARK: - List Row

struct ClusterListRow: View {

    let block: CanvasBlock
    let clusterColor: Color
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
            .fill(isHovered ? clusterColor.opacity(0.1) : Color.clear)
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
                .background(Capsule().fill(info.color.opacity(0.12)))
        }
    }

    private var badgeInfo: (text: String, color: Color) {
        switch block.entityType {
        case .task:
            let status = CanvasClusterEngine.canonicalTaskStatus(block.metadata["status"] ?? "todo")
            return (displayTaskStatus(status), CosmoMentionColors.task)
        case .content:
            let raw = block.metadata["currentStep"] ?? block.metadata["status"] ?? "ideation"
            let phase = CanvasClusterEngine.canonicalContentPhase(raw)
            return (phase.capitalized, CosmoMentionColors.content)
        case .idea:
            let status = CanvasClusterEngine.canonicalIdeaStatus(block.metadata["ideaStatus"] ?? "spark")
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

    private func displayTaskStatus(_ status: String) -> String {
        switch status {
        case "todo": return "To Do"
        case "in_progress": return "In Progress"
        case "completed": return "Done"
        default: return status.capitalized
        }
    }
}
