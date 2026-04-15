// CosmoOS/Canvas/ContentBlockView.swift
// Blue-accented Content block for Thinkspace canvas
// Dark glass design matching Sanctuary aesthetic
// December 2025 - Thinkspace revamp
// February 2026 - Workflow card redesign with step indicators + GRDB observation

import SwiftUI
import GRDB
import Combine

struct ContentBlockView: View {
    let block: CanvasBlock

    @State private var contentTitle: String = ""
    @State private var contentBody: String = ""
    // Workflow state from ContentFocusModeState
    @State private var currentStep: ContentStep = .brainstorm
    @State private var currentContentPhase: ContentPhase = .ideation
    @State private var coreIdea: String = ""
    @State private var hooks: [String] = []
    @State private var contentDescription: String = ""
    @State private var draftContent: String = ""
    @State private var outlineItems: [String] = []
    @State private var wordCount: Int = 0
    @State private var polishAnalysis: PolishAnalysis?
    @State private var lastModified: Date?
    @State private var platformName: String?
    @State private var clientName: String?

    // GRDB observation
    @State private var observationCancellable: AnyCancellable?
    @State private var lastParsedMetadata: String?

    // Blue accent for content
    private let accentColor = CosmoMentionColors.content

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: accentColor,
            icon: "doc.text.fill",
            title: displayTitle,
            onFocusMode: openFocusMode
        ) {
            workflowCardView
        }
        .onAppear {
            loadContent()
            startObservingAtom()
        }
        .onDisappear {
            observationCancellable?.cancel()
        }
        .onChange(of: block.entityId) { _, newId in
            // Restart GRDB observation when backing atom is linked (e.g. after first focus mode open)
            if newId > 0 {
                observationCancellable?.cancel()
                startObservingAtom()
                reloadFocusState()
            }
        }
        // Listen for direct state change notifications from focus mode
        .onReceive(NotificationCenter.default.publisher(for: .contentFocusStateDidChange)) { notification in
            if let uuid = notification.userInfo?["atomUUID"] as? String,
               uuid == block.entityUuid {
                reloadFocusState()
            }
        }
    }

    // MARK: - Display Title

    private var displayTitle: String {
        if !contentTitle.isEmpty {
            return contentTitle
        }
        return "Untitled Content"
    }

    // MARK: - Workflow Card View

    private var workflowCardView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header strip — gilt corner lives on the wrapper
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 6)

                HStack {
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: currentStep.icon)
                            .font(.system(size: 9))
                        Text(currentStep.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(accentColor.opacity(0.7))
                }
                .padding(.top, 4)
            }
            .padding(.top, 12)
            .padding(.horizontal, 16)

            // Title section
            titleSection
                .padding(.top, 4)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // Thin separator
            Rectangle()
                .fill(DS.border)
                .frame(height: 1)

            // Unified content preview (scrollable when content overflows)
            ScrollView(.vertical, showsIndicators: false) {
                contentPreview
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxHeight: .infinity)

            // Bottom info bar
            bottomInfoBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.text)
                .lineLimit(3)

            if let client = clientName, !client.isEmpty {
                Text("For \(client)")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(1)
            } else if let platform = platformName, !platform.isEmpty {
                Text(platform)
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Unified Content Preview

    private var contentPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !draftContent.isEmpty {
                // Draft excerpt — primary display
                Text(draftContent)
                    .font(.system(size: 12))
                    .foregroundColor(DS.textSecondary)

                // Word count badge
                if wordCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "text.word.spacing")
                            .font(.system(size: 9))
                        Text("\(wordCount) words")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(accentColor.opacity(0.1), in: Capsule())
                }
            } else if !coreIdea.isEmpty {
                // Fallback to core idea
                Text(coreIdea)
                    .font(.system(size: 12))
                    .foregroundColor(DS.textSecondary)
            } else if !contentDescription.isEmpty {
                // Fallback to description
                Text(contentDescription)
                    .font(.system(size: 12))
                    .foregroundColor(DS.textSecondary)
            } else if !hooks.isEmpty {
                // Fallback to hooks
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(hooks.prefix(2).enumerated()), id: \.offset) { _, hook in
                        HStack(spacing: 4) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 8))
                                .foregroundColor(accentColor)
                            Text(String(hook.prefix(50)))
                                .font(.system(size: 10))
                                .foregroundColor(DS.text)
                                .lineLimit(1)
                        }
                    }
                }
            } else {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 20))
                        .foregroundColor(accentColor.opacity(0.25))
                    Text("Open to start writing...")
                        .font(.system(size: 12))
                        .foregroundColor(DS.textMuted)
                        .italic()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Bottom Info Bar

    private var bottomInfoBar: some View {
        HStack(spacing: 4) {
            // 3-dot step progress (brainstorm / draft / polish)
            HStack(spacing: 3) {
                ForEach(ContentStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(stepDotColor(step))
                        .frame(width: 5, height: 5)
                }
            }

            if wordCount > 0 {
                Text("\u{00B7}")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
                Text("\(wordCount)w")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
            }

            Spacer()

            // Last modified
            if let modified = lastModified {
                Text(formatRelativeDate(modified))
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
            } else if let timestamp = block.metadata["updated"] {
                Text(formatTimestamp(timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
            }
        }
    }

    private func stepDotColor(_ step: ContentStep) -> Color {
        if step.stepNumber < currentStep.stepNumber {
            return DS.green.opacity(0.6)
        } else if step.stepNumber == currentStep.stepNumber {
            return accentColor
        } else {
            return DS.borderSubtle
        }
    }

    // MARK: - (Step switching removed — unified editor, phase navigation via pipeline bar)

    // MARK: - GRDB Observation

    private func startObservingAtom() {
        guard block.entityId > 0 else { return }
        let id = block.entityId
        let observation = ValueObservation.tracking { db in
            try Atom
                .filter(Column("id") == id)
                .fetchOne(db)
        }
        observationCancellable = observation.publisher(in: CosmoDatabase.shared.dbQueue)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [self] atom in
                    guard let atom else { return }
                    let newTitle = atom.title ?? ""
                    let newBody = atom.body ?? ""
                    // Only update if something actually changed
                    let titleChanged = newTitle != contentTitle
                    let bodyChanged = newBody != contentBody
                    if titleChanged { contentTitle = newTitle }
                    if bodyChanged { contentBody = newBody }
                    // Only re-parse atom state if the atom's metadata changed
                    if titleChanged || bodyChanged || atom.metadata != lastParsedMetadata {
                        lastParsedMetadata = atom.metadata
                        parseAtomState(atom)
                    }
                }
            )
    }

    // MARK: - Load Content

    private func loadContent() {
        contentTitle = block.title
        reloadFocusState()

        // Load atom from database for title/body
        if block.entityId > 0 {
            Task {
                if let atom = try? await AtomRepository.shared.fetch(id: block.entityId) {
                    await MainActor.run {
                        if let title = atom.title, !title.isEmpty {
                            contentTitle = title
                        }
                        if let body = atom.body {
                            contentBody = body
                        }
                    }
                }
            }
        }
    }

    /// Reload workflow state from the atom in the database
    private func reloadFocusState() {
        guard block.entityId > 0 else { return }
        Task {
            if let atom = try? await AtomRepository.shared.fetch(id: block.entityId) {
                await MainActor.run {
                    parseAtomState(atom)
                }
            }
        }
    }

    /// Extract focus state fields from atom metadata
    private func parseAtomState(_ atom: Atom) {
        // Read pipeline phase from ContentAtomMetadata
        if let metadata = atom.metadataValue(as: ContentAtomMetadata.self) {
            currentContentPhase = metadata.phase
            if let platform = metadata.platform {
                platformName = platform.displayName
            }
            // Load client name if linked
            if let clientUUID = metadata.clientProfileUUID, !clientUUID.isEmpty {
                loadClientName(uuid: clientUUID)
            }
        }

        if let state = ContentFocusModeState.from(atom: atom) {
            print("🔄 ContentBlock parseAtomState: step=\(state.currentStep.rawValue), coreIdea=\(state.coreIdea.prefix(20)), hooks=\(state.hooks.count), outline=\(state.outline.count), draft=\(state.draftContent.count)chars")
            currentStep = state.currentStep
            coreIdea = state.coreIdea
            hooks = state.hooks
            contentDescription = state.contentDescription
            draftContent = state.draftContent
            outlineItems = state.sortedOutline.map { $0.text }
            wordCount = state.draftContent.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            polishAnalysis = state.polishAnalysis
            lastModified = state.lastModified
        } else {
            print("🔄 ContentBlock parseAtomState: from(atom:) returned nil — metadata: \(atom.metadata?.prefix(100) ?? "nil")")
        }
    }

    /// Load client display name from clientProfile atom
    private func loadClientName(uuid: String) {
        Task {
            if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                await MainActor.run {
                    clientName = atom.title
                }
            }
        }
    }

    // MARK: - Focus Mode

    private func openFocusMode() {
        print("📂 ContentBlockView.openFocusMode: entityId=\(block.entityId), entityUuid=\(block.entityUuid), blockId=\(block.id)")
        guard block.entityId > 0 else {
            print("⚠️ ContentBlockView.openFocusMode: no backing atom (entityId=\(block.entityId)), skipping")
            return
        }
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "type": EntityType.content,
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

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Content Stats Bar

struct ContentStatsBar: View {
    let wordCount: Int
    let readingTime: String
    let status: String

    var body: some View {
        HStack(spacing: 12) {
            // Word count
            HStack(spacing: 4) {
                Image(systemName: "text.word.spacing")
                    .font(.system(size: 10))
                Text("\(wordCount) words")
                    .font(CosmoTypography.caption)
            }
            .foregroundColor(CosmoColors.textTertiary)

            // Reading time
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(readingTime)
                    .font(CosmoTypography.caption)
            }
            .foregroundColor(CosmoColors.textTertiary)

            Spacer()

            // Status badge
            StatusBadge(status: status)
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: String

    private var statusColor: Color {
        switch status.lowercased() {
        case "published", "complete": return CosmoColors.emerald
        case "draft": return CosmoColors.glassGrey
        case "review", "editing": return CosmoColors.lavender
        case "archived": return CosmoColors.textTertiary
        default: return CosmoColors.glassGrey
        }
    }

    private var statusIcon: String {
        switch status.lowercased() {
        case "published", "complete": return "checkmark.circle.fill"
        case "draft": return "doc.text"
        case "review", "editing": return "pencil.circle"
        case "archived": return "archivebox"
        default: return "circle"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.system(size: 10))
            Text(status.capitalized)
                .font(CosmoTypography.caption)
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.12), in: Capsule())
    }
}

// MARK: - Content Type Badge

struct ContentTypeBadge: View {
    let type: String

    private var typeColor: Color {
        switch type.lowercased() {
        case "article", "blog": return CosmoMentionColors.content
        case "script", "video": return CosmoColors.coral
        case "newsletter", "email": return CosmoColors.lavender
        case "social", "post": return CosmoColors.skyBlue
        default: return CosmoColors.glassGrey
        }
    }

    private var typeIcon: String {
        switch type.lowercased() {
        case "article", "blog": return "doc.richtext"
        case "script", "video": return "film"
        case "newsletter", "email": return "envelope"
        case "social", "post": return "bubble.left"
        default: return "doc"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: typeIcon)
                .font(.system(size: 10))
            Text(type.capitalized)
                .font(CosmoTypography.caption)
        }
        .foregroundColor(typeColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(typeColor.opacity(0.1), in: Capsule())
    }
}

// MARK: - Content Detailed Stats

struct ContentDetailedStats: View {
    let wordCount: Int
    let characterCount: Int
    let paragraphCount: Int

    var body: some View {
        HStack(spacing: 16) {
            StatItem(value: "\(wordCount)", label: "Words", icon: "text.word.spacing")
            StatItem(value: "\(characterCount)", label: "Characters", icon: "character")
            StatItem(value: "\(paragraphCount)", label: "Paragraphs", icon: "text.alignleft")
        }
        .padding(12)
        .background(CosmoMentionColors.content.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(value)
                    .font(CosmoTypography.titleSmall)
            }
            .foregroundColor(CosmoMentionColors.content)

            Text(label)
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textTertiary)
        }
    }
}

// MARK: - Content Metadata View

struct ContentMetadataView: View {
    let content: ContentWrapper

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(CosmoTypography.label)
                .foregroundColor(CosmoColors.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                MetadataRow(icon: "calendar", label: "Created", value: formatDate(content.createdAt))
                MetadataRow(icon: "pencil", label: "Updated", value: formatDate(content.updatedAt))

                if let lastOpened = content.lastOpenedAt {
                    MetadataRow(icon: "eye", label: "Last opened", value: formatDate(lastOpened))
                }

                if let scheduledAt = content.scheduledAt {
                    MetadataRow(icon: "calendar.badge.clock", label: "Scheduled", value: formatDate(scheduledAt))
                }
            }
        }
        .padding(12)
        .background(CosmoColors.mistGrey.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

struct MetadataRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(CosmoColors.textTertiary)
                .frame(width: 16)

            Text(label)
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textTertiary)

            Spacer()

            Text(value)
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textSecondary)
        }
    }
}

// MARK: - Content Footer

struct ContentFooter: View {
    let content: ContentWrapper
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Last updated
            Text(timeAgo(from: content.updatedAt))
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textTertiary)

            Spacer()

            // Actions (visible when expanded)
            if isExpanded {
                Button(action: copyContent) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text("Copy")
                            .font(CosmoTypography.caption)
                    }
                    .foregroundColor(CosmoColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CosmoColors.glassGrey.opacity(0.3), in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: exportContent) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 10))
                        Text("Export")
                            .font(CosmoTypography.caption)
                    }
                    .foregroundColor(CosmoColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CosmoColors.glassGrey.opacity(0.3), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func timeAgo(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return ""
        }

        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .abbreviated
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func copyContent() {
        guard let body = content.body else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
    }

    private func exportContent() {
        // Future: implement export functionality
    }
}

// MARK: - Preview

#Preview("Content Block") {
    ZStack {
        CosmoColors.thinkspaceVoid
            .ignoresSafeArea()

        ContentBlockView(
            block: CanvasBlock.previewContentBlock()
        )
    }
    .frame(width: 400, height: 350)
}
