// CosmoOS/CosmoGlass/CosmoGlassOverlayView.swift
// Top-right glass overlay for search results, clarifications, proactive suggestions
// macOS Notification-style cards with premium glass styling

import SwiftUI
import AppKit

// MARK: - Glass Overlay Container

struct CosmoGlassOverlayView: View {
    @EnvironmentObject var glassCenter: CosmoGlassCenter

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(glassCenter.cards) { card in
                GlassCardView(card: card)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .padding(.top, 60)  // Below top controls
        .padding(.trailing, 16)
        .frame(maxWidth: 380)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: glassCenter.cards.count)
    }
}

// MARK: - Glass Card View

struct GlassCardView: View {
    let card: CosmoGlassCard
    @EnvironmentObject var glassCenter: CosmoGlassCenter
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            cardHeader

            Divider()
                .background(Color.white.opacity(0.1))

            // Content based on type
            cardContent
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.1),
                            accentColor.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        .shadow(color: accentColor.opacity(isHovered ? 0.15 : 0), radius: 20)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: cardIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(accentColor)

            // Title
            Text(card.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            // Timestamp
            Text(card.timestamp, style: .relative)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            // Dismiss button
            Button(action: { glassCenter.dismiss(id: card.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var cardContent: some View {
        switch card.type {
        case .searchResults:
            SearchResultsCardContent(card: card)
        case .clarification:
            ClarificationCardContent(card: card)
        case .research:
            ResearchCardContent(card: card)
        case .proactive, .notification:
            ProactiveCardContent(card: card)
        case .taskList:
            TaskListCardContent(card: card)
        case .aiResponse:
            AIResponseCardContent(card: card)
        }
    }

    // MARK: - Styling

    private var cardIcon: String {
        switch card.type {
        case .searchResults: return "magnifyingglass"
        case .clarification: return "questionmark.circle"
        case .research: return "globe"
        case .proactive: return "lightbulb"
        case .notification: return "bell"
        case .taskList: return "checklist"
        case .aiResponse: return "brain.head.profile"
        }
    }

    private var accentColor: Color {
        switch card.type {
        case .searchResults: return CosmoColors.lavender
        case .clarification: return CosmoColors.coral
        case .research: return CosmoColors.emerald
        case .proactive: return CosmoColors.note  // Warm gold-ish
        case .notification: return CosmoColors.coral
        case .taskList: return CosmoColors.lavender
        case .aiResponse: return CosmoColors.lavender  // Cosmo AI purple
        }
    }
}

// MARK: - Search Results Content

struct SearchResultsCardContent: View {
    let card: CosmoGlassCard
    @EnvironmentObject var glassCenter: CosmoGlassCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(card.entities.enumerated()), id: \.element.id) { index, entity in
                SearchResultRow(
                    entity: entity,
                    index: index,
                    isSelected: glassCenter.selection.selectedIndex == index,
                    onSelect: { glassCenter.select(index: index) },
                    onPlace: { glassCenter.executeAction(.placeOnCanvas, cardId: card.id, entityRef: entity) },
                    onOpen: { glassCenter.executeAction(.openEntity, cardId: card.id, entityRef: entity) }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct SearchResultRow: View {
    let entity: CosmoGlassEntityRef
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onPlace: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Index badge
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 16)

            // Entity icon
            Image(systemName: entityIcon)
                .font(.system(size: 12))
                .foregroundColor(entityColor)

            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let preview = entity.preview {
                    Text(preview)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Action buttons (visible on hover)
            if isHovered {
                HStack(spacing: 6) {
                    Button(action: onPlace) {
                        Image(systemName: "plus.square")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Place on canvas")

                    Button(action: onOpen) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? entityColor.opacity(0.15) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? entityColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onSelect()
        }
    }

    private var entityIcon: String {
        switch entity.entityType {
        case "idea": return "lightbulb"
        case "task": return "checkmark.circle"
        case "content": return "doc.text"
        case "research": return "magnifyingglass"
        case "project": return "folder"
        default: return "doc"
        }
    }

    private var entityColor: Color {
        switch entity.entityType {
        case "idea": return CosmoColors.lavender
        case "task": return CosmoColors.coral
        case "content": return CosmoColors.skyBlue
        case "research": return CosmoColors.emerald
        case "project": return CosmoColors.lavender
        default: return CosmoColors.glassGrey
        }
    }
}

// MARK: - Clarification Content

struct ClarificationCardContent: View {
    let card: CosmoGlassCard
    @EnvironmentObject var glassCenter: CosmoGlassCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question
            if let question = card.clarificationQuestion {
                Text(question)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
            }

            // Options
            VStack(spacing: 8) {
                ForEach(card.clarificationOptions) { option in
                    Button(action: {
                        glassCenter.executeAction(.proceed, cardId: card.id, optionId: option.id)
                    }) {
                        Text(option.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                // Cancel button
                Button(action: { glassCenter.dismiss(id: card.id) }) {
                    Text("Cancel")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Research Content

struct ResearchCardContent: View {
    let card: CosmoGlassCard
    @EnvironmentObject var glassCenter: CosmoGlassCenter

    private func insertResearchIntoEditor() {
        let findings = card.researchFindings.map { finding in
            (title: finding.title, snippet: finding.snippet, source: finding.source ?? "Unknown")
        }

        EditorCommandBus.shared.insertResearchFindings(
            title: card.researchQuery ?? "Research",
            summary: "Research findings from Cosmo AI",
            findings: findings
        )

        glassCenter.dismiss(id: card.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Query
            if let query = card.researchQuery {
                Text("Researching: \(query)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Progress
            if !card.isResearchComplete {
                ProgressView(value: card.researchProgress)
                    .progressViewStyle(.linear)
                    .tint(CosmoColors.emerald)
            }

            // Findings
            if !card.researchFindings.isEmpty {
                ForEach(card.researchFindings.prefix(3)) { finding in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let snippet = finding.snippet {
                            Text(snippet)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        if let source = finding.source {
                            Text(source)
                                .font(.system(size: 10))
                                .foregroundColor(CosmoColors.emerald)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Actions when complete
            if card.isResearchComplete && !card.researchFindings.isEmpty {
                HStack(spacing: 10) {
                    Button("Insert") {
                        insertResearchIntoEditor()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CosmoColors.emerald)

                    Button("Dismiss") {
                        glassCenter.dismiss(id: card.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Proactive Content

struct ProactiveCardContent: View {
    let card: CosmoGlassCard
    @EnvironmentObject var glassCenter: CosmoGlassCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Message
            if let message = card.message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
            }

            // Action buttons
            HStack(spacing: 10) {
                if card.entityType != nil && card.entityId != nil {
                    Button("Open") {
                        if let typeStr = card.entityType, let id = card.entityId {
                            let entity = CosmoGlassEntityRef(
                                entityType: typeStr,
                                entityId: id,
                                title: card.title
                            )
                            glassCenter.executeAction(.openEntity, cardId: card.id, entityRef: entity)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CosmoColors.lavender)
                }

                Button("Later") {
                    glassCenter.dismiss(id: card.id)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Task List Content

struct TaskListCardContent: View {
    let card: CosmoGlassCard
    @EnvironmentObject var glassCenter: CosmoGlassCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(card.entities) { entity in
                HStack(spacing: 8) {
                    Image(systemName: "circle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(entity.title)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - AI Response Content

/// Streaming AI response card with dynamic sizing and native entity cards
struct AIResponseCardContent: View {
    let card: CosmoGlassCard
    @EnvironmentObject var glassCenter: CosmoGlassCenter
    @State private var isCopied = false
    @State private var contentHeight: CGFloat = 0
    @State private var parsedSegments: [ResponseSegment] = []

    // Dynamic max height - will be set based on screen size
    private var maxContentHeight: CGFloat {
        // Half of typical MacBook screen height (minus padding)
        min(400, NSScreen.main?.visibleFrame.height ?? 800 * 0.4)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 12) {
                // Response content with streaming support
                responseContent
                    .frame(maxHeight: maxContentHeight)

                // Action buttons (only show when not streaming or has content)
                if !glassCenter.isStreaming || (card.message?.isEmpty == false) {
                    actionButtons
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(height: min(contentHeight + 80, maxContentHeight + 80))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: contentHeight)
        .onChange(of: card.message) { _, newMessage in
            parseContent(newMessage)
            updateContentHeight(newMessage)
        }
        .onAppear {
            parseContent(card.message)
            updateContentHeight(card.message)
        }
    }

    // MARK: - Response Content

    @ViewBuilder
    private var responseContent: some View {
        if let message = card.message, !message.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // Render parsed segments with inline entity cards
                    ForEach(parsedSegments.indices, id: \.self) { index in
                        segmentView(for: parsedSegments[index])
                    }
                }
                .background(GeometryReader { geo in
                    Color.clear.onAppear {
                        contentHeight = geo.size.height
                    }
                    .onChange(of: parsedSegments) { _, _ in
                        contentHeight = geo.size.height
                    }
                })
            }
            .scrollIndicators(.automatic)
        } else if glassCenter.isStreaming {
            // Streaming indicator while waiting for first chunk
            HStack(spacing: 8) {
                StreamingDotsView()
                Text("Thinking...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(height: 30)
        }
    }

    @ViewBuilder
    private func segmentView(for segment: ResponseSegment) -> some View {
        switch segment {
        case .text(let text):
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
                .lineSpacing(4)
                .textSelection(.enabled)

        case .entityReference(let ref):
            InlineEntityCard(reference: ref)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Copy button
            Button(action: copyToClipboard) {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                    Text(isCopied ? "Copied" : "Copy")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(isCopied ? CosmoColors.emerald : CosmoColors.lavender)
            }
            .buttonStyle(.plain)

            // Insert into editor
            Button(action: insertIntoEditor) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.square")
                        .font(.system(size: 11))
                    Text("Insert")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(CosmoColors.lavender)
            }
            .buttonStyle(.plain)

            Spacer()

            // Streaming indicator
            if glassCenter.isStreaming {
                StreamingDotsView()
            }

            // Dismiss
            Button("Done") {
                glassCenter.dismiss(id: card.id)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Content Parsing

    private func parseContent(_ message: String?) {
        guard let message = message, !message.isEmpty else {
            parsedSegments = []
            return
        }

        var segments: [ResponseSegment] = []
        let references = ParsedEntityReference.parseAll(from: message)

        if references.isEmpty {
            // No entity references, just plain text
            segments.append(.text(message))
        } else {
            // Split content around entity references
            var currentIndex = message.startIndex

            for ref in references {
                // Add text before this reference
                if currentIndex < ref.range.lowerBound {
                    let textBefore = String(message[currentIndex..<ref.range.lowerBound])
                    if !textBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        segments.append(.text(textBefore))
                    }
                }

                // Add the entity reference
                segments.append(.entityReference(ref))

                currentIndex = ref.range.upperBound
            }

            // Add any remaining text after last reference
            if currentIndex < message.endIndex {
                let textAfter = String(message[currentIndex...])
                if !textAfter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(textAfter))
                }
            }
        }

        parsedSegments = segments
    }

    private func updateContentHeight(_ message: String?) {
        // Estimate height based on content
        guard let message = message else {
            contentHeight = 30
            return
        }

        // Rough estimate: ~20 chars per line, ~18px per line
        let lines = max(1, message.count / 45)
        contentHeight = min(CGFloat(lines * 20), maxContentHeight)
    }

    private func copyToClipboard() {
        guard let message = card.message else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message, forType: .string)

        withAnimation(.spring(response: 0.2)) {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring(response: 0.2)) {
                isCopied = false
            }
        }
    }

    private func insertIntoEditor() {
        guard let message = card.message else { return }
        EditorCommandBus.shared.insertText(message)
        glassCenter.dismiss(id: card.id)
    }
}

// MARK: - Response Segment

enum ResponseSegment: Equatable {
    case text(String)
    case entityReference(ParsedEntityReference)
}

// MARK: - Streaming Dots Animation

struct StreamingDotsView: View {
    @State private var animatingDots = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(CosmoColors.lavender)
                    .frame(width: 4, height: 4)
                    .opacity(animatingDots == index ? 1.0 : 0.3)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: false)) {
                animatingDots = (animatingDots + 1) % 3
            }

            // Cycle through dots
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                animatingDots = (animatingDots + 1) % 3
            }
        }
    }
}

// MARK: - Inline Entity Card

/// Native entity card rendered inline within AI response
struct InlineEntityCard: View {
    let reference: ParsedEntityReference
    @State private var isHovered = false
    @State private var resolvedEntity: ResolvedGlassEntity?

    var body: some View {
        Button(action: openEntity) {
            HStack(spacing: 6) {
                // Entity icon
                Image(systemName: entityIcon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(entityColor)

                // Entity title
                Text(reference.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Open indicator
                if isHovered {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(entityColor.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(entityColor.opacity(isHovered ? 0.5 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2)) {
                isHovered = hovering
            }
        }
        .onAppear {
            resolveEntity()
        }
    }

    private var entityIcon: String {
        switch reference.entityType {
        case "connection": return "brain"
        case "swipe_file": return "doc.text"
        case "idea": return "lightbulb"
        case "research": return "magnifyingglass"
        case "content": return "doc.richtext"
        default: return "link"
        }
    }

    private var entityColor: Color {
        switch reference.entityType {
        case "connection": return CosmoColors.lavender
        case "swipe_file": return CosmoColors.coral
        case "idea": return CosmoColors.lavender
        case "research": return CosmoColors.emerald
        case "content": return CosmoColors.skyBlue
        default: return CosmoColors.glassGrey
        }
    }

    private func resolveEntity() {
        // Try to resolve the entity from the database by title
        Task {
            // Search for entity by title in vector database or entity stores
            // This is a simplified lookup - in production would use proper search
            if let result = try? await VectorDatabase.shared.search(
                query: reference.title,
                limit: 1,
                entityTypeFilter: reference.entityType == "unknown" ? nil : reference.entityType
            ).first {
                resolvedEntity = ResolvedGlassEntity(
                    entityType: result.entityType,
                    entityId: result.entityId,
                    title: result.text ?? reference.title
                )
            }
        }
    }

    private func openEntity() {
        if let entity = resolvedEntity {
            // Navigate to the entity
            NotificationCenter.default.post(
                name: .openEntity,
                object: nil,
                userInfo: [
                    "type": EntityType(rawValue: entity.entityType) ?? EntityType.idea,
                    "id": entity.entityId
                ]
            )
        } else {
            // Fallback: search for it
            NotificationCenter.default.post(
                name: CosmoNotification.AI.retrievalRequested,
                object: nil,
                userInfo: [
                    "query": reference.title,
                    "intent": "search"
                ]
            )
        }
    }
}

// MARK: - Resolved Glass Entity

struct ResolvedGlassEntity {
    let entityType: String
    let entityId: Int64
    let title: String
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.3)

        VStack {
            Spacer()
        }

        VStack {
            HStack {
                Spacer()
                CosmoGlassOverlayView()
                    .environmentObject(CosmoGlassCenter.shared)
            }
            Spacer()
        }
    }
    .frame(width: 800, height: 600)
}
