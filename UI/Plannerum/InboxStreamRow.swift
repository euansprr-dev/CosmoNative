// CosmoOS/UI/Plannerum/InboxStreamRow.swift
// Plannerium Inbox Stream Row - Expandable inbox accordion
// Glass morphism with hover effects and item preview

import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - INBOX STREAM ROW
// ═══════════════════════════════════════════════════════════════════════════════

/// An expandable inbox stream row with items.
///
/// Visual Layout:
/// ```
/// ┌────────────────────────────────────┐
/// │  ◆ Ideas                      (12) │ ← Collapsed
/// └────────────────────────────────────┘
///
/// ┌────────────────────────────────────┐
/// │  ◆ Ideas                      (12) │ ← Expanded
/// │  ──────────────────────────────────│
/// │    ◇ New landing page design       │
/// │    ◇ Newsletter topic ideas        │
/// │    ◇ Feature brainstorm notes      │
/// │    + 9 more...                     │
/// └────────────────────────────────────┘
/// ```
public struct InboxStreamRow: View {

    // MARK: - Properties

    let stream: InboxStream
    let isHovered: Bool
    let isExpanded: Bool
    let onTap: () -> Void
    let onItemSelect: (UncommittedItemViewModel) -> Void
    var onQuickAdd: (() -> Void)? = nil  // Quick add callback for + button

    // MARK: - State

    @State private var itemsVisible: [Bool] = []
    @State private var hoveredItemId: String?
    @State private var activeFilter: String = "All"

    // MARK: - Layout

    private enum Layout {
        static let staggerDelay: Double = 0.04  // 40ms per item
    }

    // MARK: - Computed - Per-Inbox Filters

    private var availableFilters: [String] {
        switch stream.type {
        case .ideas:
            return ["All", "New", "Archive"]
        case .tasks:
            return ["All", "Due", "Priority"]
        case .project:
            return ["All", "Active", "Archive"]
        default:
            return ["All"]
        }
    }

    private var filteredItems: [UncommittedItemViewModel] {
        // For now, return all items - filter logic can be implemented later
        // based on actual item properties
        switch activeFilter {
        case "New":
            // Items created in last 7 days
            let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return stream.items.filter { $0.createdAt >= oneWeekAgo }
        case "Due":
            // Items with due dates, sorted by due date
            return stream.items.filter { $0.dueDate != nil }.sorted { ($0.dueDate ?? Date()) < ($1.dueDate ?? Date()) }
        case "Priority":
            // All items (priority would come from metadata)
            return stream.items
        case "Active":
            return stream.items
        case "Archive":
            return [] // Archived items would be filtered separately
        default:
            return stream.items
        }
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Header row
            headerButton

            // Expanded content with per-inbox filters
            if isExpanded {
                expandedContent
            }
        }
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusMD))
        .overlay(rowBorder)
        .animation(PlannerumSprings.expand, value: isExpanded)
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                animateItemsIn()
            } else {
                itemsVisible = []
            }
        }
    }

    // MARK: - Header Button

    private var headerButton: some View {
        HStack(spacing: PlannerumLayout.spacingSM) {
            // Tappable expand area
            Button(action: onTap) {
                HStack(spacing: PlannerumLayout.spacingSM) {
                    // Icon with colored background
                    ZStack {
                        Circle()
                            .fill(stream.type.color.opacity(0.15))
                            .frame(width: 32, height: 32)

                        Image(systemName: stream.type.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(stream.type.color)
                    }

                    // Stream name
                    Text(stream.type.displayName)
                        .font(PlannerumTypography.inboxTitle)
                        .foregroundColor(
                            isHovered
                                ? PlannerumColors.textPrimary
                                : PlannerumColors.textSecondary
                        )

                    Spacer()

                    // Count badge
                    if stream.count > 0 {
                        Text("\(stream.count)")
                            .font(PlannerumTypography.inboxCount)
                            .foregroundColor(stream.type.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(stream.type.color.opacity(0.12))
                            )
                    } else {
                        Text("0")
                            .font(PlannerumTypography.inboxCount)
                            .foregroundColor(PlannerumColors.textMuted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Quick Add + Button
            if let onQuickAdd = onQuickAdd {
                Button(action: onQuickAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(stream.type.color)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(stream.type.color.opacity(0.12))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(stream.type.color.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            // Expand indicator
            Button(action: onTap) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(PlannerumColors.textMuted)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PlannerumLayout.spacingSM)
        .padding(.vertical, PlannerumLayout.spacingSM)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Soft gradient divider (no hard cuts per plan)
            LinearGradient(
                colors: [Color.clear, PlannerumColors.glassBorder.opacity(0.5), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.horizontal, PlannerumLayout.spacingSM)

            // Per-inbox filter chips
            if availableFilters.count > 1 {
                perInboxFilterChips
            }

            // Items list
            if filteredItems.isEmpty {
                // Empty state for filtered view
                VStack(spacing: 4) {
                    Text("No items")
                        .font(.system(size: 11))
                        .foregroundColor(PlannerumColors.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, PlannerumLayout.spacingMD)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(filteredItems.prefix(PlannerumLayout.inboxMaxVisibleItems).enumerated()), id: \.element.id) { index, item in
                        InboxItemRow(
                            item: item,
                            streamColor: stream.type.color,
                            isVisible: index < itemsVisible.count && itemsVisible[index],
                            isHovered: hoveredItemId == item.id,
                            onTap: { onItemSelect(item) },
                            onHover: { hovering in
                                hoveredItemId = hovering ? item.id : nil
                            }
                        )
                    }

                    // More items button
                    if filteredItems.count > PlannerumLayout.inboxMaxVisibleItems {
                        moreItemsButton
                    }
                }
                .padding(.vertical, PlannerumLayout.spacingXS)
            }
        }
    }

    // MARK: - Per-Inbox Filter Chips

    private var perInboxFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(availableFilters, id: \.self) { filter in
                    Button(action: {
                        withAnimation(PlannerumSprings.micro) {
                            activeFilter = filter
                        }
                    }) {
                        Text(filter)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(
                                activeFilter == filter
                                    ? stream.type.color
                                    : PlannerumColors.textMuted
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(
                                        activeFilter == filter
                                            ? stream.type.color.opacity(0.15)
                                            : Color.white.opacity(0.05)
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        activeFilter == filter
                                            ? stream.type.color.opacity(0.3)
                                            : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, PlannerumLayout.spacingSM)
            .padding(.vertical, PlannerumLayout.spacingXS)
        }
    }

    private var moreItemsButton: some View {
        Button(action: {
            // Expand to show all (could trigger a modal)
        }) {
            HStack(spacing: 4) {
                Text("+ \(filteredItems.count - PlannerumLayout.inboxMaxVisibleItems) more")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(stream.type.color.opacity(0.8))

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundColor(stream.type.color.opacity(0.5))
            }
            .padding(.horizontal, PlannerumLayout.spacingMD)
            .padding(.leading, 32)  // Indent to align with items
            .padding(.vertical, PlannerumLayout.spacingXS)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Background & Border

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM)
            .fill(
                isHovered
                    ? PlannerumColors.glassPrimary
                    : PlannerumColors.glassSecondary.opacity(0.3)
            )
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM)
            .strokeBorder(
                isHovered
                    ? stream.type.color.opacity(0.3)
                    : PlannerumColors.glassBorder,
                lineWidth: 1
            )
    }

    // MARK: - Animation

    private func animateItemsIn() {
        let count = min(stream.items.count, PlannerumLayout.inboxMaxVisibleItems)
        itemsVisible = Array(repeating: false, count: count)

        for index in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * Layout.staggerDelay) {
                withAnimation(PlannerumSprings.expand) {
                    if index < itemsVisible.count {
                        itemsVisible[index] = true
                    }
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - INBOX ITEM ROW
// ═══════════════════════════════════════════════════════════════════════════════

/// A single item row within an expanded inbox stream
public struct InboxItemRow: View {

    let item: UncommittedItemViewModel
    let streamColor: Color
    let isVisible: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: PlannerumLayout.spacingSM) {
                // Indent spacer
                Spacer()
                    .frame(width: 8)

                // Small dot indicator
                Circle()
                    .fill(streamColor.opacity(isHovered ? 1 : 0.6))
                    .frame(width: 6, height: 6)

                // Title
                Text(item.title)
                    .font(PlannerumTypography.inboxItemTitle)
                    .foregroundColor(
                        isHovered
                            ? PlannerumColors.textPrimary
                            : PlannerumColors.textSecondary
                    )
                    .lineLimit(1)

                Spacer()

                // Time ago
                Text(item.timeAgo)
                    .font(.system(size: 10))
                    .foregroundColor(PlannerumColors.textMuted)

                // Drag handle (appears on hover)
                if isHovered {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PlannerumColors.textMuted)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.horizontal, PlannerumLayout.spacingSM)
            .padding(.vertical, PlannerumLayout.spacingXS)
            .background(
                RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM)
                    .fill(isHovered ? streamColor.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(PlannerumSprings.micro) {
                onHover(hovering)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .offset(x: isVisible ? 0 : -10)
        .animation(PlannerumSprings.expand, value: isVisible)
        .draggable(item) {
            // Drag preview
            InboxItemDragPreview(item: item, color: streamColor)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - INBOX ITEM DRAG PREVIEW
// ═══════════════════════════════════════════════════════════════════════════════

/// Preview shown while dragging an inbox item
public struct InboxItemDragPreview: View {

    let item: UncommittedItemViewModel
    let color: Color

    public var body: some View {
        HStack(spacing: 8) {
            // Type icon
            Image(systemName: item.displayIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)

            // Title
            Text(item.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PlannerumColors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM)
                .fill(PlannerumGlass.InboxItem.background)
                .overlay(
                    RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM)
                        .strokeBorder(color.opacity(0.4), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 4)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - INBOX ITEM CARD (for drag preview alternative)
// ═══════════════════════════════════════════════════════════════════════════════

/// A card representation of an inbox item for drag operations
public struct PlannerumInboxItemCard: View {

    let item: UncommittedItemViewModel

    public var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: item.displayIcon)
                .font(.system(size: 14))
                .foregroundColor(item.displayColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(PlannerumColors.textPrimary)
                    .lineLimit(1)

                if let body = item.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 11))
                        .foregroundColor(PlannerumColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: PlannerumLayout.blockCornerRadius)
                .fill(PlannerumGlass.Block.background)
                .overlay(
                    RoundedRectangle(cornerRadius: PlannerumLayout.blockCornerRadius)
                        .strokeBorder(item.displayColor.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - EMPTY STREAM INDICATOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Placeholder for empty inbox streams
public struct EmptyStreamIndicator: View {

    let streamType: InboxStreamType

    public var body: some View {
        HStack(spacing: PlannerumLayout.spacingSM) {
            Image(systemName: streamType.icon)
                .font(.system(size: 12))
                .foregroundColor(PlannerumColors.textMuted)

            Text(streamType.displayName)
                .font(.system(size: 12))
                .foregroundColor(PlannerumColors.textMuted)

            Spacer()

            Text("Empty")
                .font(.system(size: 10))
                .foregroundColor(PlannerumColors.textDisabled)
        }
        .padding(.horizontal, PlannerumLayout.spacingMD)
        .padding(.vertical, PlannerumLayout.spacingSM)
        .opacity(0.5)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - EMPTY STATE VIEW
// ═══════════════════════════════════════════════════════════════════════════════

/// Empty state view for an inbox stream
public struct InboxStreamEmptyState: View {

    let streamType: InboxStreamType

    public var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(streamType.color.opacity(0.4))

            Text("No items")
                .font(.system(size: 11))
                .foregroundColor(PlannerumColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PlannerumLayout.spacingMD)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DRAGGABLE CONFORMANCE
// ═══════════════════════════════════════════════════════════════════════════════

extension UncommittedItemViewModel: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: UncommittedItemViewModel.self, contentType: .text)
    }
}

extension UncommittedItemViewModel: Codable {
    enum CodingKeys: String, CodingKey {
        case id, title, body, inferredType, captureMethod
        case assignmentStatus, projectUuid, projectName, createdAt, dueDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        inferredType = try container.decodeIfPresent(String.self, forKey: .inferredType)
        captureMethod = try container.decodeIfPresent(String.self, forKey: .captureMethod)
        assignmentStatus = try container.decodeIfPresent(String.self, forKey: .assignmentStatus)
        projectUuid = try container.decodeIfPresent(String.self, forKey: .projectUuid)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encodeIfPresent(inferredType, forKey: .inferredType)
        try container.encodeIfPresent(captureMethod, forKey: .captureMethod)
        try container.encodeIfPresent(assignmentStatus, forKey: .assignmentStatus)
        try container.encodeIfPresent(projectUuid, forKey: .projectUuid)
        try container.encodeIfPresent(projectName, forKey: .projectName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - PREVIEW
// ═══════════════════════════════════════════════════════════════════════════════

#if DEBUG
struct InboxStreamRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            // Ideas stream (expanded)
            InboxStreamRow(
                stream: InboxStream(
                    type: .ideas,
                    items: [
                        UncommittedItemViewModel(id: "1", title: "New landing page design", inferredType: "idea"),
                        UncommittedItemViewModel(id: "2", title: "Newsletter topic ideas", inferredType: "idea"),
                        UncommittedItemViewModel(id: "3", title: "Feature brainstorm notes", inferredType: "idea"),
                        UncommittedItemViewModel(id: "4", title: "Marketing campaign concepts", inferredType: "idea"),
                        UncommittedItemViewModel(id: "5", title: "Product roadmap sketches", inferredType: "idea"),
                        UncommittedItemViewModel(id: "6", title: "User research findings", inferredType: "idea")
                    ]
                ),
                isHovered: false,
                isExpanded: true,
                onTap: {},
                onItemSelect: { _ in }
            )

            // Tasks stream (collapsed, hovered)
            InboxStreamRow(
                stream: InboxStream(
                    type: .tasks,
                    items: [
                        UncommittedItemViewModel(id: "t1", title: "Fix auth bug", inferredType: "task"),
                        UncommittedItemViewModel(id: "t2", title: "Review PR #42", inferredType: "task")
                    ]
                ),
                isHovered: true,
                isExpanded: false,
                onTap: {},
                onItemSelect: { _ in }
            )

            // Content stream (empty)
            InboxStreamRow(
                stream: InboxStream(type: .content, items: []),
                isHovered: false,
                isExpanded: false,
                onTap: {},
                onItemSelect: { _ in }
            )
        }
        .padding(20)
        .frame(width: PlannerumLayout.inboxRailWidth)
        .background(PlannerumColors.voidPrimary)
        .preferredColorScheme(.dark)
    }
}
#endif
