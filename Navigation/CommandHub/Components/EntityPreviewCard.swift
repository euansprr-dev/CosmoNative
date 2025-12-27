// CosmoOS/Navigation/CommandHub/Components/EntityPreviewCard.swift
// Base Entity Preview Card with Cosmic Gem Styling
// Custom cards for each entity type with rich previews
// December 2025 - Apple-grade 3D tilt, symbol effects, ProMotion springs

import SwiftUI

// MARK: - Entity Preview Card (Base)
struct EntityPreviewCard: View {
    let entity: LibraryEntity
    let isSelected: Bool
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void
    let onDelete: () -> Void

    @State private var isCardHovered = false
    @State private var isDeleteHovered = false
    @State private var deleteButtonAppeared = false

    // Show delete button when card OR delete button is hovered
    private var showDeleteButton: Bool {
        isCardHovered || isDeleteHovered
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardContent
                .onTapGesture(count: 2) {
                    CosmicHaptics.shared.play(.selection)
                    onDoubleTap()
                }
                .onTapGesture(count: 1) {
                    CosmicHaptics.shared.play(.selection)
                    onSingleTap()
                }
                .onHover { hovering in
                    withAnimation(ProMotionSprings.hover) {
                        isCardHovered = hovering
                    }
                }
                // Context menu for quick actions
                .contextMenu {
                    Button {
                        onDoubleTap()
                    } label: {
                        Label("Open in Focus", systemImage: "arrow.up.left.and.arrow.down.right")
                    }

                    Button {
                        onSingleTap()
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }

                    Divider()

                    Button(role: .destructive) {
                        CosmicHaptics.shared.play(.delete)
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

            // Delete button (appears on hover with symbol effect)
            if showDeleteButton {
                Button {
                    CosmicHaptics.shared.play(.delete)
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .symbolEffect(.bounce, value: deleteButtonAppeared)
                        .foregroundStyle(isDeleteHovered ? .white : CosmoColors.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(isDeleteHovered ? CosmoColors.softRed : CosmoColors.glassGrey.opacity(0.9))
                                .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)
                        )
                        .scaleEffect(isDeleteHovered ? 1.15 : 1.0)
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .onHover { hovering in
                    withAnimation(ProMotionSprings.hover) {
                        isDeleteHovered = hovering
                    }
                }
                .onAppear {
                    // Trigger symbol bounce on appear
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        deleteButtonAppeared.toggle()
                    }
                }
            }
        }
        .animation(ProMotionSprings.snappy, value: showDeleteButton)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch entity.type {
        case .idea:
            IdeaCard(entity: entity, isHovered: isCardHovered, isSelected: isSelected)
        case .content:
            ContentCard(entity: entity, isHovered: isCardHovered, isSelected: isSelected)
        case .research:
            ResearchCard(entity: entity, isHovered: isCardHovered, isSelected: isSelected)
        case .connection:
            ConnectionCard(entity: entity, isHovered: isCardHovered, isSelected: isSelected)
        case .project:
            ProjectCard(entity: entity, isHovered: isCardHovered, isSelected: isSelected)
        case .task:
            TaskCard(entity: entity, isHovered: isCardHovered, isSelected: isSelected)
        case .swipeFile:
            SwipeFileCard(entity: entity, isHovered: isCardHovered, isSelected: isSelected)
        default:
            GenericEntityCard(entity: entity, isHovered: isCardHovered, isSelected: isSelected)
        }
    }
}

// MARK: - Idea Card
struct IdeaCard: View {
    let entity: LibraryEntity
    let isHovered: Bool
    let isSelected: Bool

    private let cardWidth: CGFloat = 180
    private let cardHeight: CGFloat = 140
    private let entityColor = CosmoColors.lavender

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Accent seam (top) - animates width on selection
            LinearGradient(
                colors: [entityColor, entityColor.opacity(0.5)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: isSelected ? 4 : 3)
            .animation(ProMotionSprings.snappy, value: isSelected)

            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(entity.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CosmoColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Preview
                Text(entity.preview)
                    .font(.system(size: 12))
                    .foregroundColor(CosmoColors.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Footer with tags and date
                HStack(spacing: 6) {
                    // Tags (if available)
                    if let tags = entity.metadata["tags"], !tags.isEmpty {
                        Text(tags)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(entityColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(entityColor.opacity(0.1), in: Capsule())
                            .lineLimit(1)
                    }

                    Spacer()

                    // Date
                    if let date = entity.updatedAt {
                        Text(date, style: .relative)
                            .font(.system(size: 9))
                            .foregroundColor(CosmoColors.textTertiary)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // 3-layer shadow system
        .shadow(color: .black.opacity(0.03), radius: 1, y: 1) // Ambient
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.05), radius: isHovered ? 10 : 6, y: isHovered ? 5 : 3) // Direct
        .shadow(color: entityColor.opacity(isHovered ? 0.12 : 0), radius: isHovered ? 20 : 0, y: 0) // Accent glow
        // 3D tilt effect
        .cosmoTiltSimple(isHovered, amount: 2.0)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .offset(y: isHovered ? -2 : 0)
        .animation(ProMotionSprings.hover, value: isHovered)
    }

    private var cardBackground: some View {
        LinearGradient(
            colors: [Color.white.opacity(0.98), CosmoColors.softWhite.opacity(0.92)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(
                isHovered ? entityColor.opacity(0.4) : CosmoColors.glassGrey.opacity(0.4),
                lineWidth: isSelected ? 2 : 1
            )
    }
}

// MARK: - Content Card
struct ContentCard: View {
    let entity: LibraryEntity
    let isHovered: Bool
    let isSelected: Bool

    private let cardWidth: CGFloat = 180
    private let cardHeight: CGFloat = 160
    private let entityColor = CosmoColors.skyBlue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Accent seam - animates on selection
            LinearGradient(
                colors: [entityColor, entityColor.opacity(0.5)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: isSelected ? 4 : 3)
            .animation(ProMotionSprings.snappy, value: isSelected)

            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(entity.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CosmoColors.textPrimary)
                    .lineLimit(2)

                // Word count badge
                if let wordCount = entity.metadata["wordCount"] {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9))
                        Text("\(wordCount) words")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(entityColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(entityColor.opacity(0.1), in: Capsule())
                }

                // Preview
                Text(entity.preview)
                    .font(.system(size: 12))
                    .foregroundColor(CosmoColors.textSecondary)
                    .lineLimit(3)

                Spacer()

                // Footer
                HStack {
                    // Status indicator
                    if let status = entity.metadata["status"] {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(status == "draft" ? CosmoColors.coral : CosmoColors.emerald)
                                .frame(width: 6, height: 6)
                            Text(status.capitalized)
                                .font(.system(size: 9))
                                .foregroundColor(CosmoColors.textTertiary)
                        }
                    }

                    Spacer()

                    if let date = entity.updatedAt {
                        Text(date, style: .relative)
                            .font(.system(size: 9))
                            .foregroundColor(CosmoColors.textTertiary)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.98), CosmoColors.softWhite.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? entityColor.opacity(0.4) : CosmoColors.glassGrey.opacity(0.4), lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // 3-layer shadow system
        .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.05), radius: isHovered ? 10 : 6, y: isHovered ? 5 : 3)
        .shadow(color: entityColor.opacity(isHovered ? 0.12 : 0), radius: isHovered ? 20 : 0, y: 0)
        // 3D tilt effect
        .cosmoTiltSimple(isHovered, amount: 2.0)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .offset(y: isHovered ? -2 : 0)
        .animation(ProMotionSprings.hover, value: isHovered)
    }
}

// MARK: - Research Card (with thumbnail hero)
struct ResearchCard: View {
    let entity: LibraryEntity
    let isHovered: Bool
    let isSelected: Bool

    private let cardWidth: CGFloat = 220
    private let thumbnailHeight: CGFloat = 120

    private var thumbnailUrl: String? {
        let url = entity.metadata["thumbnailUrl"] ?? ""
        return url.isEmpty ? nil : url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero Thumbnail (16:9-ish)
            ZStack {
                // Thumbnail image with CosmicShimmer loading
                if let urlString = thumbnailUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        case .failure:
                            thumbnailPlaceholder
                        case .empty:
                            // CosmicShimmer instead of ProgressView
                            CosmicShimmer(entityColor: sourceColor, cornerRadius: 0)
                        @unknown default:
                            thumbnailPlaceholder
                        }
                    }
                } else {
                    thumbnailPlaceholder
                }

                // Source badge overlay (top-left)
                VStack {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: sourceIcon)
                                .font(.system(size: 10))
                            Text(sourceLabel)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(sourceColor.opacity(0.9), in: Capsule())

                        Spacer()
                    }
                    .padding(8)

                    Spacer()
                }

                // Play button for YouTube with symbol effect
                if sourceType == "youtube" {
                    Circle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 40, height: 40)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 16))
                                .foregroundColor(sourceColor)
                                .offset(x: 2)
                                .symbolEffect(.bounce, value: isHovered)
                        )
                        .scaleEffect(isHovered ? 1.1 : 1.0)
                        .animation(ProMotionSprings.bouncy, value: isHovered)
                }
            }
            .frame(height: thumbnailHeight)
            .clipped()

            // Accent seam - animates on selection
            sourceColor
                .frame(height: isSelected ? 4 : 3)
                .animation(ProMotionSprings.snappy, value: isSelected)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(entity.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CosmoColors.textPrimary)
                    .lineLimit(2)

                // Summary
                if !entity.preview.isEmpty {
                    Text(entity.preview)
                        .font(.system(size: 11))
                        .foregroundColor(CosmoColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                // Footer: Date + Tag
                HStack {
                    if let date = entity.updatedAt {
                        Text(date, style: .date)
                            .font(.system(size: 10))
                            .foregroundColor(CosmoColors.textTertiary)
                    }

                    Spacer()

                    Text("#research")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(CosmoMentionColors.research)
                }
            }
            .padding(12)
        }
        .frame(width: cardWidth)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.98), CosmoColors.softWhite.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? sourceColor.opacity(0.4) : CosmoColors.glassGrey.opacity(0.4), lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // 3-layer shadow system
        .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.05), radius: isHovered ? 10 : 6, y: isHovered ? 5 : 3)
        .shadow(color: sourceColor.opacity(isHovered ? 0.12 : 0), radius: isHovered ? 20 : 0, y: 0)
        // 3D tilt effect
        .cosmoTiltSimple(isHovered, amount: 2.0)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .offset(y: isHovered ? -2 : 0)
        .animation(ProMotionSprings.hover, value: isHovered)
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [CosmoColors.mistGrey.opacity(0.5), CosmoColors.glassGrey.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: sourceIcon)
                .font(.system(size: 28))
                .foregroundColor(sourceColor.opacity(0.5))
        }
    }

    private var sourceType: String {
        entity.metadata["sourceType"] ?? "website"
    }

    private var sourceIcon: String {
        switch sourceType {
        case "youtube": return "play.rectangle.fill"
        case "twitter": return "bubble.left.fill"
        case "pdf": return "doc.fill"
        default: return "globe"
        }
    }

    private var sourceLabel: String {
        switch sourceType {
        case "youtube": return "YouTube"
        case "twitter": return "Twitter"
        case "pdf": return "PDF"
        default: return "Web"
        }
    }

    private var sourceColor: Color {
        switch sourceType {
        case "youtube": return CosmoColors.softRed
        case "twitter": return CosmoColors.skyBlue
        case "pdf": return CosmoColors.coral
        default: return CosmoColors.emerald
        }
    }
}

// MARK: - Connection Card
struct ConnectionCard: View {
    let entity: LibraryEntity
    let isHovered: Bool
    let isSelected: Bool

    private let cardWidth: CGFloat = 180
    private let cardHeight: CGFloat = 140
    private let entityColor = CosmoMentionColors.connection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Accent seam - animates on selection
            LinearGradient(
                colors: [entityColor, entityColor.opacity(0.5)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: isSelected ? 4 : 3)
            .animation(ProMotionSprings.snappy, value: isSelected)

            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(entity.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CosmoColors.textPrimary)
                    .lineLimit(2)

                // Core idea preview
                Text(entity.preview)
                    .font(.system(size: 12))
                    .foregroundColor(CosmoColors.textSecondary)
                    .lineLimit(2)

                Spacer()

                // Linked entities count with symbol effect
                HStack(spacing: 8) {
                    if let linkCount = entity.metadata["linkCount"] {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                                .symbolEffect(.pulse, isActive: isHovered)
                            Text("Links to \(linkCount) items")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(entityColor)
                    }

                    Spacer()
                }
            }
            .padding(12)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.98), CosmoColors.softWhite.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? entityColor.opacity(0.4) : CosmoColors.glassGrey.opacity(0.4), lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // 3-layer shadow system
        .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.05), radius: isHovered ? 10 : 6, y: isHovered ? 5 : 3)
        .shadow(color: entityColor.opacity(isHovered ? 0.12 : 0), radius: isHovered ? 20 : 0, y: 0)
        // 3D tilt effect
        .cosmoTiltSimple(isHovered, amount: 2.0)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .offset(y: isHovered ? -2 : 0)
        .animation(ProMotionSprings.hover, value: isHovered)
    }
}

// MARK: - Project Card
struct ProjectCard: View {
    let entity: LibraryEntity
    let isHovered: Bool
    let isSelected: Bool

    private let cardWidth: CGFloat = 200
    private let cardHeight: CGFloat = 160
    private let entityColor = CosmoColors.emerald

    @State private var animatedProgress: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Accent seam - animates on selection
            LinearGradient(
                colors: [entityColor, entityColor.opacity(0.5)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: isSelected ? 4 : 3)
            .animation(ProMotionSprings.snappy, value: isSelected)

            HStack(alignment: .top, spacing: 12) {
                // Progress ring with animated fill
                ZStack {
                    Circle()
                        .stroke(CosmoColors.glassGrey.opacity(0.3), lineWidth: 4)

                    Circle()
                        .trim(from: 0, to: animatedProgress)
                        .stroke(entityColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(animatedProgress * 100))%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(CosmoColors.textSecondary)
                        .contentTransition(.numericText())
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 6) {
                    // Title
                    Text(entity.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(CosmoColors.textPrimary)
                        .lineLimit(2)

                    // Status badge
                    if let status = entity.metadata["status"] {
                        Text(status.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.5)
                            .foregroundColor(statusColor(status))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor(status).opacity(0.1), in: Capsule())
                    }
                }
            }
            .padding(12)

            Spacer()

            // Task count and deadline
            HStack {
                if let taskCount = entity.metadata["taskCount"],
                   let pendingCount = entity.metadata["pendingCount"] {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 10))
                            .symbolEffect(.bounce, value: isHovered)
                        Text("\(taskCount) tasks, \(pendingCount) pending")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(CosmoColors.textTertiary)
                }

                Spacer()

                if let deadline = entity.metadata["deadline"] {
                    Text(deadline)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(CosmoColors.coral)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.98), CosmoColors.softWhite.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? entityColor.opacity(0.4) : CosmoColors.glassGrey.opacity(0.4), lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // 3-layer shadow system
        .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.05), radius: isHovered ? 10 : 6, y: isHovered ? 5 : 3)
        .shadow(color: entityColor.opacity(isHovered ? 0.12 : 0), radius: isHovered ? 20 : 0, y: 0)
        // 3D tilt effect
        .cosmoTiltSimple(isHovered, amount: 2.0)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .offset(y: isHovered ? -2 : 0)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onAppear {
            // Animate progress ring on appear
            withAnimation(ProMotionSprings.bouncy.delay(0.2)) {
                animatedProgress = progressValue
            }
        }
    }

    private var progressValue: CGFloat {
        if let progress = entity.metadata["progress"],
           let value = Double(progress) {
            return CGFloat(value)
        }
        return 0.0
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "active": return CosmoColors.emerald
        case "paused": return CosmoColors.coral
        case "complete", "completed": return CosmoColors.skyBlue
        default: return CosmoColors.textTertiary
        }
    }
}

// MARK: - Task Card
struct TaskCard: View {
    let entity: LibraryEntity
    let isHovered: Bool
    let isSelected: Bool

    private let cardWidth: CGFloat = 180
    private let cardHeight: CGFloat = 120
    private let entityColor = CosmoColors.coral

    @State private var checkmarkScale: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Accent seam - animates on selection
            LinearGradient(
                colors: [entityColor, entityColor.opacity(0.5)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: isSelected ? 4 : 3)
            .animation(ProMotionSprings.snappy, value: isSelected)

            HStack(alignment: .top, spacing: 10) {
                // Checkbox with animated checkmark
                ZStack {
                    Circle()
                        .stroke(isCompleted ? CosmoColors.emerald : CosmoColors.glassGrey, lineWidth: 2)
                        .frame(width: 20, height: 20)

                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(CosmoColors.emerald)
                            .scaleEffect(checkmarkScale)
                            .symbolEffect(.bounce, value: isCompleted)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(entity.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isCompleted ? CosmoColors.textTertiary : CosmoColors.textPrimary)
                        .strikethrough(isCompleted)
                        .lineLimit(2)

                    if let dueDate = entity.metadata["dueDate"] {
                        Text(dueDate)
                            .font(.system(size: 10))
                            .foregroundColor(entityColor)
                    }
                }
            }
            .padding(12)

            Spacer()
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.98), CosmoColors.softWhite.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? entityColor.opacity(0.4) : CosmoColors.glassGrey.opacity(0.4), lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // 3-layer shadow system
        .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.05), radius: isHovered ? 10 : 6, y: isHovered ? 5 : 3)
        .shadow(color: entityColor.opacity(isHovered ? 0.12 : 0), radius: isHovered ? 20 : 0, y: 0)
        // 3D tilt effect
        .cosmoTiltSimple(isHovered, amount: 2.0)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .offset(y: isHovered ? -2 : 0)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onAppear {
            if isCompleted {
                withAnimation(ProMotionSprings.bouncy.delay(0.1)) {
                    checkmarkScale = 1
                }
            }
        }
    }

    private var isCompleted: Bool {
        entity.metadata["status"] == "completed"
    }
}

// MARK: - Swipe File Card
struct SwipeFileCard: View {
    let entity: LibraryEntity
    let isHovered: Bool
    let isSelected: Bool

    private let cardWidth: CGFloat = 200
    private let cardHeight: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with source badge
            ZStack(alignment: .topLeading) {
                // Gradient accent based on source
                LinearGradient(
                    colors: sourceGradientColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 36)

                // Source badge
                HStack(spacing: 6) {
                    Image(systemName: sourceIcon)
                        .font(.system(size: 11, weight: .semibold))

                    Text(sourceLabel)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Hook (main content)
                Text(entity.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CosmoColors.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                // Preview text (if available)
                if !entity.preview.isEmpty {
                    Text(entity.preview)
                        .font(.system(size: 11))
                        .foregroundColor(CosmoColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                // Footer with tags
                HStack(spacing: 6) {
                    // Emotion tag
                    if let emotion = entity.metadata["emotionTone"], !emotion.isEmpty {
                        EmotionTag(emotion: emotion)
                    }

                    // Structure tag
                    if let structure = entity.metadata["structureType"], !structure.isEmpty {
                        StructureTag(structure: structure)
                    }

                    Spacer()

                    // Date
                    if let date = entity.updatedAt {
                        Text(date, style: .relative)
                            .font(.system(size: 9))
                            .foregroundColor(CosmoColors.textTertiary)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.98), CosmoColors.softWhite.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? sourceAccentColor.opacity(0.4) : CosmoColors.glassGrey.opacity(0.4), lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // 3-layer shadow system
        .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.05), radius: isHovered ? 10 : 6, y: isHovered ? 5 : 3)
        .shadow(color: sourceAccentColor.opacity(isHovered ? 0.12 : 0), radius: isHovered ? 20 : 0, y: 0)
        // 3D tilt effect
        .cosmoTiltSimple(isHovered, amount: 2.0)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .offset(y: isHovered ? -2 : 0)
        .animation(ProMotionSprings.hover, value: isHovered)
    }

    private var sourceType: String {
        entity.metadata["sourceType"] ?? "unknown"
    }

    private var sourceIcon: String {
        switch sourceType {
        case "youtube", "youtube_short": return "play.rectangle.fill"
        case "x_post", "twitter": return "at"
        case "threads": return "at.circle"
        case "instagram_reel": return "video.fill"
        case "instagram_post", "instagram_carousel": return "photo.fill"
        case "raw_note": return "note.text"
        default: return "link"
        }
    }

    private var sourceLabel: String {
        switch sourceType {
        case "youtube": return "YouTube"
        case "youtube_short": return "Short"
        case "x_post", "twitter": return "X"
        case "threads": return "Threads"
        case "instagram_reel": return "Reel"
        case "instagram_post": return "IG Post"
        case "instagram_carousel": return "Carousel"
        case "raw_note": return "Note"
        default: return "Link"
        }
    }

    private var sourceGradientColors: [Color] {
        switch sourceType {
        case "youtube", "youtube_short":
            return [Color(hex: "#FF0000"), Color(hex: "#CC0000")]
        case "x_post", "twitter":
            return [Color(hex: "#1DA1F2"), Color(hex: "#0D8ED6")]
        case "threads":
            return [Color(hex: "#000000"), Color(hex: "#333333")]
        case "instagram_reel", "instagram_post", "instagram_carousel":
            return [Color(hex: "#F58529"), Color(hex: "#DD2A7B"), Color(hex: "#8134AF")]
        case "raw_note":
            return [CosmoColors.lavender, CosmoColors.lavender.opacity(0.7)]
        default:
            return [CosmoColors.emerald, CosmoColors.emerald.opacity(0.7)]
        }
    }

    private var sourceAccentColor: Color {
        switch sourceType {
        case "youtube", "youtube_short": return Color(hex: "#FF0000")
        case "x_post", "twitter": return Color(hex: "#1DA1F2")
        case "threads": return Color.black
        case "instagram_reel", "instagram_post", "instagram_carousel": return Color(hex: "#DD2A7B")
        case "raw_note": return CosmoColors.lavender
        default: return CosmoColors.emerald
        }
    }
}

// MARK: - Swipe File Tag Components

private struct EmotionTag: View {
    let emotion: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: emotionIcon)
                .font(.system(size: 8))
            Text(emotionLabel)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(emotionColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(emotionColor.opacity(0.1), in: Capsule())
    }

    private var emotionIcon: String {
        switch emotion {
        case "inspiring": return "sparkles"
        case "provocative": return "flame.fill"
        case "vulnerable": return "heart.fill"
        case "educational": return "book.fill"
        case "entertaining": return "face.smiling.fill"
        case "controversial": return "bolt.fill"
        case "motivational": return "arrow.up.heart.fill"
        case "analytical": return "chart.bar.fill"
        default: return "tag"
        }
    }

    private var emotionLabel: String {
        emotion.capitalized
    }

    private var emotionColor: Color {
        switch emotion {
        case "inspiring": return CosmoColors.lavender
        case "provocative": return CosmoColors.coral
        case "vulnerable": return Color(hex: "#E8B8D8")
        case "educational": return CosmoColors.skyBlue
        case "entertaining": return CosmoColors.emerald
        case "controversial": return CosmoColors.softRed
        case "motivational": return CosmoColors.coral
        case "analytical": return CosmoColors.skyBlue
        default: return CosmoColors.textTertiary
        }
    }
}

private struct StructureTag: View {
    let structure: String

    var body: some View {
        Text(structureLabel)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(CosmoColors.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(CosmoColors.glassGrey.opacity(0.2), in: Capsule())
    }

    private var structureLabel: String {
        switch structure {
        case "story": return "Story"
        case "breakdown": return "Breakdown"
        case "playbook": return "Playbook"
        case "rant": return "Rant"
        case "hot_take": return "Hot Take"
        case "case_study": return "Case Study"
        case "listicle": return "Listicle"
        case "thread": return "Thread"
        case "tutorial": return "Tutorial"
        case "review": return "Review"
        case "question": return "Question"
        case "announcement": return "Announcement"
        default: return structure.capitalized
        }
    }
}

// MARK: - Generic Entity Card
struct GenericEntityCard: View {
    let entity: LibraryEntity
    let isHovered: Bool
    let isSelected: Bool

    private var entityColor: Color {
        entity.type.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: entity.type.icon)
                    .font(.system(size: 16))
                    .foregroundColor(entityColor)
                    .symbolEffect(.bounce, value: isHovered)

                Text(entity.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CosmoColors.textPrimary)
                    .lineLimit(1)
            }

            Text(entity.preview)
                .font(.system(size: 12))
                .foregroundColor(CosmoColors.textSecondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(width: 180, height: 100)
        .background(Color.white.opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? entityColor.opacity(0.4) : CosmoColors.glassGrey.opacity(0.4), lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // 3-layer shadow system
        .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.05), radius: isHovered ? 10 : 6, y: isHovered ? 5 : 3)
        .shadow(color: entityColor.opacity(isHovered ? 0.12 : 0), radius: isHovered ? 20 : 0, y: 0)
        // 3D tilt effect
        .cosmoTiltSimple(isHovered, amount: 2.0)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .offset(y: isHovered ? -2 : 0)
        .animation(ProMotionSprings.hover, value: isHovered)
    }
}

// MARK: - Preview
#if DEBUG
struct EntityPreviewCard_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                IdeaCard(
                    entity: LibraryEntity(entityId: 1, type: .idea, title: "Marketing Strategy 2025", preview: "Key insights about the upcoming year's marketing initiatives and brand positioning."),
                    isHovered: false,
                    isSelected: false
                )

                ContentCard(
                    entity: LibraryEntity(entityId: 2, type: .content, title: "Product Launch Blog Post", preview: "Announcing our new AI-powered features...", metadata: ["wordCount": "1,234", "status": "draft"]),
                    isHovered: true,
                    isSelected: false
                )

                ResearchCard(
                    entity: LibraryEntity(entityId: 3, type: .research, title: "The Future of AI Interfaces", preview: "Comprehensive analysis of emerging AI interaction patterns", metadata: ["sourceType": "youtube", "domain": "youtube.com"]),
                    isHovered: false,
                    isSelected: false
                )

                ConnectionCard(
                    entity: LibraryEntity(entityId: 4, type: .connection, title: "Design Systems", preview: "Mental model connecting UI patterns with cognitive science", metadata: ["linkCount": "5"]),
                    isHovered: false,
                    isSelected: false
                )

                ProjectCard(
                    entity: LibraryEntity(entityId: 5, type: .project, title: "CosmoOS Redesign", preview: "", metadata: ["status": "active", "progress": "0.65", "taskCount": "12", "pendingCount": "4"]),
                    isHovered: false,
                    isSelected: false
                )

                TaskCard(
                    entity: LibraryEntity(entityId: 6, type: .task, title: "Review Command Hub implementation", preview: "", metadata: ["status": "pending", "dueDate": "Today"]),
                    isHovered: false,
                    isSelected: false
                )
            }
            .padding(30)
        }
        .background(CosmoColors.softWhite)
        .frame(width: 700, height: 600)
    }
}
#endif
