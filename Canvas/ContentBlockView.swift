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
            surfaceStyle: .crisp,
            fixedLayoutSize: CanvasBlock.documentLayoutSize,
            preservesAspectRatio: true,
            suppressGiltCorner: true,
            suppressAccentChip: true,
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
        VStack(alignment: .leading, spacing: 24) {
            titleSection

            ScrollView(.vertical, showsIndicators: false) {
                contentPreview
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)

            documentFooter
        }
        .padding(.top, 78)
        .padding(.horizontal, 56)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayTitle)
                .font(.system(size: 40, weight: .semibold, design: .serif))
                .foregroundStyle(DS.documentText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let client = clientName, !client.isEmpty {
                Text("For \(client)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.documentTextMuted)
                    .lineLimit(1)
            } else if let platform = platformName, !platform.isEmpty {
                Text(platform)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.documentTextMuted)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Unified Content Preview

    private var contentPreview: some View {
        Group {
            if documentBodyText.isEmpty {
                Text("Open to start writing…")
                    .font(.system(size: 20))
                    .foregroundStyle(DS.documentTextMuted)
                    .italic()
            } else {
                // Excerpted: Text typesets the whole string it is given even
                // when clipped — unbounded drafts froze the thinkspace-switch
                // mount frame. The footer keeps the REAL counts.
                Text(CanvasCardTextExcerpt.excerpt(documentBodyText))
                    .font(.system(size: 20))
                    .lineSpacing(8)
                    .foregroundStyle(DS.documentText)
                    .textSelection(.enabled)
            }
        }
    }

    private var documentFooter: some View {
        ZStack {
            Text(currentStep.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accentColor.opacity(0.75))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(accentColor.opacity(0.08), in: Capsule(style: .continuous))

            HStack {
                Spacer()
                Text("\(documentWordCount) words  ·  \(documentBodyText.count) chars")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.documentTextMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DS.documentBorderSubtle, lineWidth: 1)
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var documentBodyText: String {
        if !draftContent.isEmpty { return draftContent }
        if !contentBody.isEmpty { return contentBody }
        if !coreIdea.isEmpty { return coreIdea }
        if !contentDescription.isEmpty { return contentDescription }
        if !outlineItems.isEmpty { return outlineItems.joined(separator: "\n\n") }
        if !hooks.isEmpty { return hooks.joined(separator: "\n\n") }
        return ""
    }

    private var documentWordCount: Int {
        if wordCount > 0 { return wordCount }
        return documentBodyText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    // MARK: - Bottom Info Bar

    private var bottomInfoBar: some View {
        HStack(spacing: 4) {
            Spacer()

            // Last modified
            if let modified = lastModified {
                Text(formatRelativeDate(modified))
                    .font(.system(size: 10))
                    .foregroundStyle(DS.documentTextMuted)
            } else if let timestamp = block.metadata["updated"] {
                Text(formatTimestamp(timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(DS.documentTextMuted)
            }
        }
    }

    private func stepDotColor(_ step: ContentStep) -> Color {
        if step.stepNumber < currentStep.stepNumber {
            return DS.green.opacity(0.6)
        } else if step.stepNumber == currentStep.stepNumber {
            return accentColor
        } else {
            return DS.documentBorderSubtle
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
        observationCancellable = observation.publisher(in: CosmoDatabase.shared.dbPool)
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

        guard block.entityId > 0 else { return }

        // Warm store first — the thinkspace switch batch-fetched every entity
        // atom, and a mount must not queue its own round-trips (content blocks
        // used to fire two fetches each: title/body plus focus state).
        if let warm = CanvasAtomWarmStore.shared.atom(id: block.entityId) {
            applyLoadedAtom(warm)
            return
        }

        Task {
            if let atom = try? await AtomRepository.shared.fetch(id: block.entityId) {
                await MainActor.run {
                    applyLoadedAtom(atom)
                }
            }
        }
    }

    /// Apply a freshly-loaded entity atom: title/body plus the parsed focus
    /// state (pipeline phase, draft, outline). Stamping `lastParsedMetadata`
    /// lets the GRDB observation's first echo skip a redundant re-parse.
    private func applyLoadedAtom(_ atom: Atom) {
        if let title = atom.title, !title.isEmpty {
            contentTitle = title
        }
        if let body = atom.body {
            contentBody = body
        }
        lastParsedMetadata = atom.metadata
        parseAtomState(atom)
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
            currentStep = state.currentStep
            coreIdea = state.coreIdea
            hooks = state.hooks
            contentDescription = state.contentDescription
            draftContent = state.draftContent
            outlineItems = state.sortedOutline.map { $0.text }
            wordCount = state.draftContent.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            polishAnalysis = state.polishAnalysis
            lastModified = state.lastModified
        }
    }

    /// Client display names, cached process-wide — dozens of content blocks
    /// routinely share one client, and each used to fetch the profile atom
    /// on every mount.
    @MainActor private static var clientNameCache: [String: String] = [:]

    /// Load client display name from clientProfile atom
    private func loadClientName(uuid: String) {
        if let cached = Self.clientNameCache[uuid] {
            clientName = cached
            return
        }
        Task {
            if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                await MainActor.run {
                    Self.clientNameCache[uuid] = atom.title ?? ""
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
        if let date = ISO8601.date(from: timestamp) {
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
            .foregroundColor(DS.documentTextMuted)

            // Reading time
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(readingTime)
                    .font(CosmoTypography.caption)
            }
            .foregroundColor(DS.documentTextMuted)

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
        case "archived": return DS.documentTextMuted
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
                .foregroundColor(DS.documentTextMuted)
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
                .foregroundColor(DS.documentTextSecondary)

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
                .foregroundColor(DS.documentTextMuted)
                .frame(width: 16)

            Text(label)
                .font(CosmoTypography.caption)
                .foregroundColor(DS.documentTextMuted)

            Spacer()

            Text(value)
                .font(CosmoTypography.caption)
                .foregroundColor(DS.documentTextSecondary)
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
                .foregroundColor(DS.documentTextMuted)

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
                    .foregroundColor(DS.documentTextSecondary)
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
                    .foregroundColor(DS.documentTextSecondary)
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
