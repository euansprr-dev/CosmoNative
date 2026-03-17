// CosmoOS/Canvas/ClusterBoardContent.swift
// Board (Kanban) mode rendering for clusters — columns native to the cluster zone

import SwiftUI

struct BoardDropEvent: Sendable {
    let blockUUID: String
    let targetClusterId: UUID
    let targetColumnValue: String
}

struct ClusterBoardContent: View {

    let cluster: CanvasCluster
    let clusterColor: Color
    let blocks: [CanvasBlock]
    let highlightedColumnValue: String?
    let onOpenFocusMode: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(columns, id: \.title) { column in
                boardColumn(column)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
    }

    // MARK: - Column Determination

    private var columns: [BoardColumn] {
        cluster.boardColumns(from: blocks)
    }

    // MARK: - Column View

    @ViewBuilder
    private func boardColumn(_ column: BoardColumn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            columnHeader(column)

            Rectangle()
                .fill(clusterColor.opacity(0.22))
                .frame(height: 1)

            columnCards(column)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DS.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    highlightedColumnValue == column.value ? DS.accent.opacity(0.5) : DS.borderSubtle,
                    style: StrokeStyle(lineWidth: highlightedColumnValue == column.value ? 1.5 : 1)
                )
        )
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: highlightedColumnValue == column.value)
    }

    @ViewBuilder
    private func columnHeader(_ column: BoardColumn) -> some View {
        HStack(spacing: 6) {
            Text(column.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.textSecondary)
                .tracking(0.6)
                .lineLimit(1)

            Text("\(column.blocks.count)")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.textMuted)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(clusterColor.opacity(0.14)))

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func columnCards(_ column: BoardColumn) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 4) {
                ForEach(column.blocks, id: \.id) { block in
                    ClusterBoardCard(
                        block: block,
                        sourceClusterId: cluster.id,
                        onDoubleTap: { onOpenFocusMode(block.entityUuid) }
                    )
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Board Card

struct ClusterBoardCard: View {

    let block: CanvasBlock
    let sourceClusterId: UUID
    let onDoubleTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            typeIcon
            cardText
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardBorder)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleTap() }
        .onHover { hovering in isHovered = hovering }
        .onDrag { dragProvider }
    }

    private var typeIcon: some View {
        Circle()
            .fill(CosmoMentionColors.color(for: block.entityType))
            .frame(width: 18, height: 18)
            .overlay(
                Image(systemName: block.entityType.icon)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(.white)
            )
    }

    private var cardText: some View {
        Text(block.title)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(DS.text)
            .lineLimit(2)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(DS.surfaceElevated)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 7)
            .stroke(isHovered ? DS.borderActive : DS.border, lineWidth: 1)
    }

    private var dragProvider: NSItemProvider {
        ClusterViewDragSession.sourceClusterId = sourceClusterId
        return NSItemProvider(object: block.entityUuid as NSString)
    }
}

// MARK: - Supporting Types

struct BoardColumn {
    let title: String
    let value: String
    let blocks: [CanvasBlock]
}

enum GroupingStrategy {
    case byTaskStatus
    case byContentPhase
    case byIdeaStatus
    case byType
}

extension CanvasCluster {
    func boardColumns(from blocks: [CanvasBlock]) -> [BoardColumn] {
        let members = boardMemberBlocks(from: blocks)
        let strategy = boardGroupingStrategy(memberBlocks: members)

        switch strategy {
        case .byTaskStatus:
            return buildColumns(
                blocks: members,
                columnDefs: [("TODO", "todo"), ("IN PROGRESS", "in_progress"), ("DONE", "completed")],
                keyPath: { block in
                    CanvasClusterEngine.canonicalTaskStatus(block.metadata["status"] ?? "todo")
                }
            )
        case .byContentPhase:
            return buildColumns(
                blocks: members,
                columnDefs: [("IDEATION", "ideation"), ("DRAFT", "draft"), ("POLISH", "polish"), ("ARCHIVED", "archived")],
                keyPath: { block in
                    let raw = block.metadata["currentStep"] ?? block.metadata["status"] ?? "ideation"
                    return CanvasClusterEngine.canonicalContentPhase(raw)
                }
            )
        case .byIdeaStatus:
            return buildColumns(
                blocks: members,
                columnDefs: [("SPARK", "spark"), ("DEVELOPING", "developing"), ("READY", "ready"), ("ARCHIVED", "archived")],
                keyPath: { block in
                    CanvasClusterEngine.canonicalIdeaStatus(block.metadata["ideaStatus"] ?? "spark")
                }
            )
        case .byType:
            return buildTypeColumns(blocks: members)
        }
    }

    func boardDropColumnValue(for localX: CGFloat, clusterWidth: CGFloat, blocks: [CanvasBlock]) -> String? {
        let columns = boardColumns(from: blocks)
        guard !columns.isEmpty else { return nil }

        // Match the visible board columns more closely by discounting the outer content padding.
        let horizontalInset: CGFloat = 16
        let usableWidth = max(clusterWidth - (horizontalInset * 2), 1)
        let clampedX = min(max(localX - horizontalInset, 0), usableWidth)
        let fraction = clampedX / usableWidth
        let index = min(Int(fraction * CGFloat(columns.count)), columns.count - 1)
        return columns[index].value
    }

    func defaultBoardDropColumnValue(for block: CanvasBlock, among blocks: [CanvasBlock]) -> String {
        switch boardGroupingStrategy(memberBlocks: boardMemberBlocks(from: blocks)) {
        case .byTaskStatus:
            return CanvasClusterEngine.canonicalTaskStatus(block.metadata["status"] ?? "todo")
        case .byContentPhase:
            let raw = block.metadata["currentStep"] ?? block.metadata["status"] ?? "ideation"
            return CanvasClusterEngine.canonicalContentPhase(raw)
        case .byIdeaStatus:
            return CanvasClusterEngine.canonicalIdeaStatus(block.metadata["ideaStatus"] ?? "spark")
        case .byType:
            return block.entityType.rawValue
        }
    }
}

private extension CanvasCluster {
    func boardMemberBlocks(from blocks: [CanvasBlock]) -> [CanvasBlock] {
        let uuids = Set(blockUUIDs)
        return blocks.filter { uuids.contains($0.entityUuid) }
    }

    func boardGroupingStrategy(memberBlocks: [CanvasBlock]) -> GroupingStrategy {
        switch boardGrouping {
        case .type:
            return .byType
        case .pipeline:
            return pipelineStrategyForDominantType(memberBlocks: memberBlocks)
        case .auto:
            guard !memberBlocks.isEmpty else { return .byType }
            let typeCounts = Dictionary(grouping: memberBlocks, by: \.entityType)
            let dominant = typeCounts.max(by: { $0.value.count < $1.value.count })
            guard let dominantType = dominant?.key, let dominantCount = dominant?.value.count else {
                return .byType
            }
            let ratio = Double(dominantCount) / Double(memberBlocks.count)
            return ratio > 0.5 ? pipelineStrategy(for: dominantType) : .byType
        }
    }

    func pipelineStrategyForDominantType(memberBlocks: [CanvasBlock]) -> GroupingStrategy {
        guard !memberBlocks.isEmpty else { return .byType }
        let typeCounts = Dictionary(grouping: memberBlocks, by: \.entityType)
        guard let dominantType = typeCounts.max(by: { $0.value.count < $1.value.count })?.key else {
            return .byType
        }
        return pipelineStrategy(for: dominantType)
    }

    func pipelineStrategy(for type: EntityType) -> GroupingStrategy {
        switch type {
        case .task: return .byTaskStatus
        case .content: return .byContentPhase
        case .idea: return .byIdeaStatus
        default: return .byType
        }
    }

    func buildColumns(
        blocks: [CanvasBlock],
        columnDefs: [(title: String, value: String)],
        keyPath: (CanvasBlock) -> String
    ) -> [BoardColumn] {
        var grouped: [String: [CanvasBlock]] = [:]
        for block in blocks {
            let key = keyPath(block)
            let matchedValue = columnDefs.first(where: { $0.value == key })?.value ?? columnDefs.first?.value ?? key
            grouped[matchedValue, default: []].append(block)
        }
        return columnDefs.map { def in
            BoardColumn(title: def.title, value: def.value, blocks: grouped[def.value] ?? [])
        }
    }

    func buildTypeColumns(blocks: [CanvasBlock]) -> [BoardColumn] {
        let typeOrder: [EntityType] = [.research, .idea, .content, .task, .connection, .project, .note]
        let grouped = Dictionary(grouping: blocks, by: \.entityType)
        return typeOrder.compactMap { type in
            guard let group = grouped[type], !group.isEmpty else { return nil }
            return BoardColumn(title: type.rawValue.uppercased(), value: type.rawValue, blocks: group)
        }
    }
}
