// CosmoOS/Canvas/ConnectionBlockView.swift
// Purple-accented Connection block for Thinkspace canvas
// Dark glass design matching Sanctuary aesthetic
// December 2025 - Shows actual connection content with sections

import SwiftUI

struct ConnectionBlockView: View {
    let block: CanvasBlock

    @State private var isExpanded = false
    @State private var atom: Atom?
    @State private var connectionData: ConnectionStructuredData?
    @State private var isLoading = true
    @EnvironmentObject private var expansionManager: BlockExpansionManager

    // Purple accent for connections
    private let accentColor = CosmoColors.blockConnection

    // Parsed section stats
    private var populatedSections: [(type: ConnectionSectionType, count: Int)] {
        guard let data = connectionData else { return [] }
        return data.sections
            .filter { !$0.items.isEmpty }
            .map { ($0.type, $0.items.count) }
    }

    private var totalItemCount: Int {
        connectionData?.sections.reduce(0) { $0 + $1.items.count } ?? 0
    }

    private var linkedSourceCount: Int {
        guard let data = connectionData else { return 0 }
        var uniqueSources = Set<String>()
        for section in data.sections {
            for item in section.items {
                if let sourceUUID = item.sourceAtomUUID {
                    uniqueSources.insert(sourceUUID)
                }
            }
        }
        return uniqueSources.count
    }

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: accentColor,
            icon: "link.circle.fill",
            title: block.title,
            isExpanded: $isExpanded,
            onFocusMode: openFocusMode
        ) {
            connectionContent
        }
        .onAppear {
            loadAtom()
        }
    }

    // MARK: - Connection Content

    private var connectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon and title
            HStack(spacing: 12) {
                // Connection icon with purple glow
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("CONNECTION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accentColor)
                        .tracking(0.8)

                    Text(block.title.isEmpty ? "Untitled Connection" : block.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                Spacer()
            }

            // Body preview or sections summary
            if let body = atom?.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.6))
                    .lineLimit(isExpanded ? 4 : 2)
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(accentColor)
                    Text("Loading...")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.4))
                }
            }

            // Section chips showing populated sections
            if !populatedSections.isEmpty {
                sectionChipsView
            } else if !isLoading {
                // Empty state with section type hints
                emptyStateSections
            }

            Spacer()

            // Footer with stats
            HStack {
                // Items count
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 10))
                    Text("\(totalItemCount) items")
                        .font(.system(size: 10))
                }
                .foregroundColor(accentColor.opacity(0.7))

                // Link indicator
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                    Text("\(linkedSourceCount) sources")
                        .font(.system(size: 10))
                }
                .foregroundColor(Color.white.opacity(0.4))

                Spacer()

                // Timestamp
                if let created = block.metadata["created"] {
                    Text(formatTimestamp(created))
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.3))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Section Chips

    private var sectionChipsView: some View {
        FlowLayout(spacing: 6) {
            ForEach(populatedSections.prefix(isExpanded ? 8 : 4), id: \.type) { section in
                HStack(spacing: 4) {
                    Image(systemName: section.type.icon)
                        .font(.system(size: 8))
                    Text(section.type.displayName)
                        .font(.system(size: 9, weight: .medium))
                    Text("(\(section.count))")
                        .font(.system(size: 8))
                        .foregroundColor(section.type.accentColor.opacity(0.7))
                }
                .foregroundColor(section.type.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(section.type.accentColor.opacity(0.1))
                )
            }

            if populatedSections.count > 4 && !isExpanded {
                Text("+\(populatedSections.count - 4)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.05))
                    )
            }
        }
    }

    // Empty state showing available section types
    private var emptyStateSections: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Structure your idea")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.4))

            FlowLayout(spacing: 6) {
                ForEach(Array(ConnectionSectionType.allCases.prefix(4)), id: \.self) { type in
                    HStack(spacing: 4) {
                        Image(systemName: type.icon)
                            .font(.system(size: 8))
                        Text(type.displayName)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(type.accentColor.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(type.accentColor.opacity(0.2), lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadAtom() {
        Task {
            if let loaded = try? await AtomRepository.shared.fetch(id: block.entityId) {
                await MainActor.run {
                    atom = loaded
                    parseConnectionData(from: loaded)
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }

    private func parseConnectionData(from atom: Atom) {
        // Try to load from persisted state first
        if let state = ConnectionFocusModeState.load(atomUUID: atom.uuid) {
            connectionData = ConnectionStructuredData(sections: state.sections)
            return
        }

        // Try to parse from atom structured JSON
        if let json = atom.structured, let data = ConnectionStructuredData.fromJSON(json) {
            connectionData = data
        }
    }

    // MARK: - Focus Mode

    private func openFocusMode() {
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "type": EntityType.connection,
                "id": block.entityId
            ]
        )
    }

    // MARK: - Helpers

    private func formatTimestamp(_ timestamp: String) -> String {
        if let date = ISO8601DateFormatter().date(from: timestamp) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: Date())
        }
        return timestamp
    }
}

// MARK: - Flow Layout for Section Chips

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                // Move to next line
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}

// MARK: - Preview

#if DEBUG
struct ConnectionBlockView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            CosmoColors.thinkspaceVoid
                .ignoresSafeArea()

            ConnectionBlockView(
                block: CanvasBlock(
                    position: CGPoint(x: 200, y: 200),
                    size: CGSize(width: 320, height: 280),
                    entityType: .connection,
                    entityId: 1,
                    entityUuid: "preview",
                    title: "Second Brain Architecture"
                )
            )
            .environmentObject(BlockExpansionManager())
        }
        .frame(width: 500, height: 400)
    }
}
#endif
