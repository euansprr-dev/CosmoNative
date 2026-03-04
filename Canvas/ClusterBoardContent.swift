// CosmoOS/Canvas/ClusterBoardContent.swift
// Board (Kanban) mode rendering for clusters — columns grouped by status/phase/type

import SwiftUI

struct ClusterBoardContent: View {

    let cluster: CanvasCluster
    let blocks: [CanvasBlock]
    let onBoardColumnDrop: (String, String) -> Void  // blockUUID, newColumnValue
    let onOpenFocusMode: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(columns, id: \.title) { column in
                boardColumn(column)
            }
        }
        .padding(8)
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

    // MARK: - Column Determination

    private var memberBlocks: [CanvasBlock] {
        let uuids = Set(cluster.blockUUIDs)
        return blocks.filter { uuids.contains($0.entityUuid) }
    }

    private var groupingStrategy: GroupingStrategy {
        let members = memberBlocks
        guard !members.isEmpty else { return .byType }

        let typeCounts = Dictionary(grouping: members, by: \.entityType)
        let total = members.count

        for (type, group) in typeCounts {
            if Double(group.count) / Double(total) > 0.5 {
                switch type {
                case .task:    return .byTaskStatus
                case .content: return .byContentPhase
                case .idea:    return .byIdeaStatus
                default:       break
                }
            }
        }
        return .byType
    }

    private var columns: [BoardColumn] {
        let members = memberBlocks
        let strategy = groupingStrategy

        switch strategy {
        case .byTaskStatus:
            return buildColumns(
                blocks: members,
                columnDefs: [("TODO", "pending"), ("IN PROGRESS", "in_progress"), ("DONE", "completed")],
                keyPath: { $0.metadata["status"] ?? "pending" }
            )
        case .byContentPhase:
            return buildColumns(
                blocks: members,
                columnDefs: [("IDEATION", "ideation"), ("DRAFT", "draft"), ("POLISH", "polish"), ("ARCHIVED", "archived")],
                keyPath: { $0.metadata["currentStep"] ?? $0.metadata["status"] ?? "draft" }
            )
        case .byIdeaStatus:
            return buildColumns(
                blocks: members,
                columnDefs: [("SPARK", "spark"), ("DEVELOPING", "developing"), ("READY", "ready"), ("ARCHIVED", "archived")],
                keyPath: { $0.metadata["ideaStatus"] ?? "spark" }
            )
        case .byType:
            return buildTypeColumns(blocks: members)
        }
    }

    private func buildColumns(
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

    private func buildTypeColumns(blocks: [CanvasBlock]) -> [BoardColumn] {
        let typeOrder: [EntityType] = [.research, .idea, .content, .task, .connection, .project, .note]
        let grouped = Dictionary(grouping: blocks, by: \.entityType)
        return typeOrder.compactMap { type in
            guard let group = grouped[type], !group.isEmpty else { return nil }
            return BoardColumn(title: type.rawValue.uppercased(), value: type.rawValue, blocks: group)
        }
    }

    // MARK: - Column View

    @ViewBuilder
    private func boardColumn(_ column: BoardColumn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            columnHeader(column)

            Rectangle()
                .fill(DS.accent.opacity(0.25))
                .frame(height: 2)
                .clipShape(Capsule())

            columnCards(column)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DS.surface.opacity(0.5))
        )
        .onDrop(of: [.text], isTargeted: nil) { providers in
            handleDrop(providers: providers, targetColumn: column.value)
        }
    }

    @ViewBuilder
    private func columnHeader(_ column: BoardColumn) -> some View {
        HStack(spacing: 5) {
            Text(column.title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(DS.textSecondary)
                .tracking(0.5)
                .lineLimit(1)

            Text("\(column.blocks.count)")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(DS.textMuted)
                .frame(width: 16, height: 16)
                .background(Circle().fill(DS.surfaceElevated))

            Spacer()
        }
    }

    @ViewBuilder
    private func columnCards(_ column: BoardColumn) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 3) {
                ForEach(column.blocks, id: \.id) { block in
                    ClusterBoardCard(
                        block: block,
                        columnValue: column.value,
                        onDrop: { blockUUID, newValue in
                            onBoardColumnDrop(blockUUID, newValue)
                        },
                        onDoubleTap: { onOpenFocusMode(block.entityUuid) }
                    )
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider], targetColumn: String) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.text", options: nil) { item, _ in
                guard let data = item as? Data,
                      let blockUUID = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    onBoardColumnDrop(blockUUID, targetColumn)
                }
            }
        }
        return true
    }
}

// MARK: - Board Card

struct ClusterBoardCard: View {

    let block: CanvasBlock
    let columnValue: String
    let onDrop: (String, String) -> Void
    let onDoubleTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            typeIcon
            cardText
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardBorder)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleTap() }
        .onHover { hovering in isHovered = hovering }
        .onDrag { NSItemProvider(object: block.entityUuid as NSString) }
    }

    private var typeIcon: some View {
        Circle()
            .fill(CosmoMentionColors.color(for: block.entityType))
            .frame(width: 18, height: 18)
            .overlay(
                Image(systemName: block.entityType.icon)
                    .font(.system(size: 7, weight: .bold))
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
        RoundedRectangle(cornerRadius: 6)
            .fill(DS.surfaceElevated)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(isHovered ? DS.borderActive : DS.border, lineWidth: 1)
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
