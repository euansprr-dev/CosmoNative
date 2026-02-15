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
    @State private var isExpanded = false

    // Workflow state from ContentFocusModeState
    @State private var currentStep: ContentStep = .brainstorm
    @State private var currentContentPhase: ContentPhase = .ideation
    @State private var coreIdea: String = ""
    @State private var draftContent: String = ""
    @State private var outlineItems: [String] = []
    @State private var wordCount: Int = 0
    @State private var polishAnalysis: PolishAnalysis?
    @State private var lastModified: Date?

    // GRDB observation
    @State private var observationCancellable: AnyCancellable?

    @EnvironmentObject private var expansionManager: BlockExpansionManager

    // Blue accent for content
    private let accentColor = CosmoMentionColors.content

    // Step colors
    private let completedColor = Color(hex: "#22C55E")

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: accentColor,
            icon: "doc.text.fill",
            title: displayTitle,
            isExpanded: $isExpanded,
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
            return String(contentTitle.prefix(40))
        }
        return "Untitled Content"
    }

    // MARK: - Workflow Card View

    private var workflowCardView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clickable step indicator
            stepIndicator
                .padding(.top, 14)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            // Thin separator
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            // Content preview based on current step
            stepPreview
                .padding(.horizontal, 16)
                .padding(.top, 10)

            Spacer(minLength: 0)

            // Bottom info bar
            bottomInfoBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Phase Indicator (8-Phase Pipeline)

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(Array(ContentPhase.allCases.enumerated()), id: \.element) { index, phase in
                if index > 0 {
                    // Connecting line
                    Rectangle()
                        .fill(phaseLineColor(beforePhase: phase))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }

                // Phase dot (clickable only for creation phases)
                Button {
                    if let step = ContentFocusModeState.stepForPhase(phase) {
                        switchStep(to: step)
                    }
                } label: {
                    phaseDot(for: phase)
                }
                .buttonStyle(.plain)
                .disabled(ContentFocusModeState.stepForPhase(phase) == nil)
            }
        }
    }

    @ViewBuilder
    private func phaseDot(for phase: ContentPhase) -> some View {
        let currentIdx = ContentPhase.allCases.firstIndex(of: currentContentPhase) ?? 0
        let phaseIdx = ContentPhase.allCases.firstIndex(of: phase) ?? 0

        if phaseIdx < currentIdx {
            // Completed: green dot
            Circle()
                .fill(completedColor)
                .frame(width: 6, height: 6)
        } else if phase == currentContentPhase {
            // Current: filled accent
            Circle()
                .fill(accentColor)
                .frame(width: 8, height: 8)
        } else {
            // Future: stroke, dimmed for post-creation
            let isCreation = ContentFocusModeState.stepForPhase(phase) != nil
            Circle()
                .stroke(Color.white.opacity(isCreation ? 0.25 : 0.1), lineWidth: 1)
                .frame(width: 6, height: 6)
        }
    }

    private func phaseLineColor(beforePhase phase: ContentPhase) -> Color {
        let currentIdx = ContentPhase.allCases.firstIndex(of: currentContentPhase) ?? 0
        let phaseIdx = ContentPhase.allCases.firstIndex(of: phase) ?? 0
        if phaseIdx <= currentIdx {
            return completedColor.opacity(0.5)
        }
        return Color.white.opacity(0.08)
    }

    // MARK: - Step Preview

    @ViewBuilder
    private var stepPreview: some View {
        switch currentStep {
        case .brainstorm:
            brainstormPreview
        case .draft:
            draftPreview
        case .polish:
            polishPreview
        }
    }

    private var brainstormPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Core idea
            if !coreIdea.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 9))
                        .foregroundColor(accentColor)
                    Text(String(coreIdea.prefix(60)))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }
            }

            // Outline items (mini list)
            if !outlineItems.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(outlineItems.prefix(3).enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 6) {
                            Text("\(index + 1).")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(accentColor.opacity(0.7))
                                .frame(width: 14, alignment: .trailing)
                            Text(String(item.prefix(35)))
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    if outlineItems.count > 3 {
                        Text("+\(outlineItems.count - 3) more")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                            .padding(.leading, 20)
                    }
                }
            }

            if coreIdea.isEmpty && outlineItems.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "lightbulb.max.fill")
                        .font(.system(size: 10))
                        .foregroundColor(accentColor.opacity(0.5))
                    Text("Open to brainstorm...")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.3))
                        .italic()
                }
            }
        }
    }

    private var draftPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            if draftContent.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 10))
                        .foregroundColor(accentColor.opacity(0.5))
                    Text("Open to start drafting...")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.3))
                        .italic()
                }
            } else {
                // Draft excerpt
                Text(String(draftContent.prefix(120)))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(4)

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
            }
        }
    }

    private var polishPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let analysis = polishAnalysis {
                // Readability score bar
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 10))
                        .foregroundColor(accentColor)
                    Text(analysis.readabilityLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                }

                // Stats row
                HStack(spacing: 10) {
                    Label("Grade \(String(format: "%.0f", analysis.fleschKincaidGrade))", systemImage: "graduationcap")
                    Label("\(analysis.wordCount)w", systemImage: "text.word.spacing")
                    Label("\(analysis.sentenceCount)s", systemImage: "text.alignleft")
                }
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
            } else if wordCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(accentColor.opacity(0.6))
                    Text("Ready to polish")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                if wordCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "text.word.spacing")
                            .font(.system(size: 9))
                        Text("\(wordCount) words")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(accentColor.opacity(0.7))
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Draft first, then polish")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.3))
                        .italic()
                }
            }
        }
    }

    // MARK: - Bottom Info Bar

    private var bottomInfoBar: some View {
        HStack(spacing: 6) {
            // Phase badge
            HStack(spacing: 3) {
                Image(systemName: currentContentPhase.iconName)
                    .font(.system(size: 8))
                Text("Phase \((ContentPhase.allCases.firstIndex(of: currentContentPhase) ?? 0) + 1)/8")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(accentColor.opacity(0.6))

            Spacer()

            // Last modified
            if let modified = lastModified {
                Text(formatRelativeDate(modified))
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.25))
            } else if let timestamp = block.metadata["updated"] {
                Text(formatTimestamp(timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.25))
            }
        }
    }

    // MARK: - Step Switching

    private func switchStep(to step: ContentStep) {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = step
        }
        // Write step change directly to atom metadata
        let entityUuid = block.entityUuid
        guard !entityUuid.isEmpty else { return }
        Task {
            do {
                try await CosmoDatabase.shared.asyncWrite { db in
                    if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [entityUuid]),
                       let existing: String = row["metadata"],
                       let data = existing.data(using: .utf8),
                       var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        dict["currentStep"] = step.rawValue
                        if let metadataData = try? JSONSerialization.data(withJSONObject: dict),
                           let str = String(data: metadataData, encoding: .utf8) {
                            try db.execute(
                                sql: "UPDATE atoms SET metadata = ?, updated_at = ?, _local_version = _local_version + 1 WHERE uuid = ?",
                                arguments: [str, ISO8601DateFormatter().string(from: Date()), entityUuid]
                            )
                        }
                    }
                }
            } catch {
                print("ContentBlockView: Failed to update step: \(error)")
            }
        }
    }

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
                    contentTitle = atom.title ?? ""
                    contentBody = atom.body ?? ""
                    // Read focus state directly from atom metadata (not UserDefaults)
                    parseAtomState(atom)
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
        }

        if let state = ContentFocusModeState.from(atom: atom) {
            print("🔄 ContentBlock parseAtomState: step=\(state.currentStep.rawValue), coreIdea=\(state.coreIdea.prefix(20)), outline=\(state.outline.count), draft=\(state.draftContent.count)chars")
            currentStep = state.currentStep
            coreIdea = state.coreIdea
            draftContent = state.draftContent
            outlineItems = state.sortedOutline.map { $0.text }
            wordCount = state.draftContent.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            polishAnalysis = state.polishAnalysis
            lastModified = state.lastModified
        } else {
            print("🔄 ContentBlock parseAtomState: from(atom:) returned nil — metadata: \(atom.metadata?.prefix(100) ?? "nil")")
        }
    }

    // MARK: - Focus Mode

    private func openFocusMode() {
        print("📂 ContentBlockView.openFocusMode: entityId=\(block.entityId), entityUuid=\(block.entityUuid), blockId=\(block.id)")
        if block.entityId > 0 {
            // Has backing atom — open directly
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: [
                    "type": EntityType.content,
                    "id": block.entityId
                ]
            )
        } else {
            // No backing atom — create one first (like NoteBlockView does)
            Task {
                do {
                    let newAtom = try await AtomRepository.shared.createContent(
                        title: contentTitle.isEmpty ? "Untitled Content" : contentTitle,
                        body: contentBody.isEmpty ? nil : contentBody
                    )
                    let atomId = newAtom.id ?? Int64(-1)

                    // Link the canvas block to the new atom
                    try await CosmoDatabase.shared.asyncWrite { db in
                        try db.execute(
                            sql: """
                            UPDATE canvas_blocks
                            SET entity_id = ?, entity_uuid = ?
                            WHERE id = ?
                            """,
                            arguments: [atomId, newAtom.uuid, block.id]
                        )
                    }

                    await MainActor.run {
                        // Notify canvas to reload blocks so entityId is updated in memory
                        NotificationCenter.default.post(
                            name: Notification.Name("com.cosmo.canvasBlocksChanged"),
                            object: nil
                        )

                        NotificationCenter.default.post(
                            name: .enterFocusMode,
                            object: nil,
                            userInfo: [
                                "type": EntityType.content,
                                "id": atomId
                            ]
                        )
                    }
                } catch {
                    print("ContentBlockView: Failed to create backing atom: \(error)")
                }
            }
        }
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
