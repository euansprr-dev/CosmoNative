// CosmoOS/Editor/ResearchEditorView.swift
// Premium Research Editor - Full editable research view with Cosmo styling
// Mirrors the polish and design system of ConnectionEditorView

import SwiftUI
import GRDB
import AppKit
import WebKit
import Combine

/// Premium editable research view with full rich text editing
struct ResearchEditorView: View {
    let researchId: Int64
    let presentation: EditorPresentation

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var voiceEngine: VoiceEngine

    // Content state
    @State private var title = ""
    @State private var summary = ""
    @State private var findings = ""
    @State private var personalNotes = ""
    @State private var url: String?
    @State private var sourceType: ResearchRichContent.SourceType = .unknown
    @State private var author: String?
    @State private var publishedAt: String?
    @State private var duration: Int?
    @State private var thumbnailUrl: String?
    @State private var videoId: String?
    @State private var loomId: String?
    @State private var screenshotImage: NSImage?
    @State private var transcriptSegments: [TranscriptSegment] = []
    @State private var formattedTranscript: String?
    @State private var transcriptSections: [TranscriptSectionData]?
    @State private var twitterEmbedHtml: String?

    // UI state
    @State private var isLoading = true
    @State private var showURLCopied = false
    @State private var isAISummarizing = false
    @State private var aiErrorMessage: String?
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var canvasSize: CGSize = .zero
    @State private var isAppeared = false
    @State private var observationCancellable: AnyCancellable?
    @State private var isInitialLoad = true

    private let autoSaveDelay: TimeInterval = 1.5
    private let database = CosmoDatabase.shared
    private let contextTracker = EditingContextTracker.shared

    init(researchId: Int64, presentation: EditorPresentation = .focus) {
        self.researchId = researchId
        self.presentation = presentation
    }

    // MARK: - Responsive Layout Properties

    /// Horizontal padding adapts to presentation mode
    private var horizontalPadding: CGFloat {
        presentation == .focus ? ResearchDesign.horizontalPadding : 12
    }

    /// Max width for content - only constrain in focus mode
    private var contentMaxWidth: CGFloat? {
        presentation == .focus ? ResearchDesign.maxContentWidth : nil
    }

    /// Top spacing
    private var topSpacing: CGFloat {
        presentation == .focus ? 40 : 8
    }

    /// Section spacing
    private var sectionSpacing: CGFloat {
        presentation == .focus ? ResearchDesign.sectionSpacing : 12
    }

    /// Title font adapts to presentation
    private var titleFont: Font {
        presentation == .focus ? CosmoTypography.displayLarge : CosmoTypography.title
    }

    /// Whether to use two-column layout
    private var useTwoColumnLayout: Bool {
        presentation == .focus
    }

    private var accentColor: Color {
        ResearchDesign.accentColor(for: sourceType)
    }

    private var domain: String? {
        guard let urlString = url, let parsedUrl = URL(string: urlString) else { return nil }
        return parsedUrl.host?.replacingOccurrences(of: "www.", with: "")
    }

    var body: some View {
        ZStack {
            // LAYER 1: Background (only in focus mode)
            if presentation == .focus {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { canvasSize = geo.size }
                }
                .background(CosmoColors.background)
            }

            // LAYER 2: Scrollable Content
            if isLoading {
                loadingView
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Top breathing room
                        Spacer().frame(height: topSpacing)

                        VStack(alignment: .leading, spacing: sectionSpacing) {
                            // 1. Title Section
                            titleSection

                            // 2. Metadata Bar (compact in embedded mode)
                            if presentation == .focus {
                                ResearchMetadataBar(
                                    sourceType: sourceType,
                                    author: author,
                                    publishedAt: publishedAt,
                                    duration: duration,
                                    domain: domain
                                )
                            } else {
                                compactMetadataBar
                            }

                            // 3. Hero Section (Video/Image) - smaller in embedded mode
                            if presentation == .focus {
                                ResearchHeroSection(
                                    sourceType: sourceType,
                                    thumbnailUrl: thumbnailUrl,
                                    videoId: videoId,
                                    loomId: loomId,
                                    screenshotImage: screenshotImage,
                                    twitterEmbedHtml: twitterEmbedHtml
                                )
                            } else {
                                compactHeroSection
                            }

                            // 4. URL Bar (only in focus mode)
                            if presentation == .focus, let urlString = url {
                                ResearchURLBar(url: urlString, sourceType: sourceType)
                            }

                            // 5. Content Cards
                            if useTwoColumnLayout {
                                contentCards
                            } else {
                                compactContentCards
                            }

                            // 6. Smart Transcript (only in focus mode)
                            if presentation == .focus && sourceType == .youtube && !transcriptSegments.isEmpty {
                                SmartTranscriptView(
                                    segments: transcriptSegments,
                                    sections: transcriptSections,
                                    formattedTranscript: formattedTranscript,
                                    accentColor: accentColor
                                )
                            }

                            // Bottom padding
                            Spacer(minLength: presentation == .focus ? 100 : 20)
                        }
                        .padding(.horizontal, horizontalPadding)
                        .frame(maxWidth: contentMaxWidth)
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(presentation == .focus ? .visible : .hidden)
            }

            // LAYER 3: Floating Blocks (only in focus mode)
            if presentation == .focus {
                DocumentBlocksLayer(
                    documentType: "research",
                    documentId: researchId,
                    canvasCenter: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                )
            }

            // LAYER 4: Header Chrome
            if presentation.showsChromeHeader {
                VStack {
                    editorHeader
                    Spacer()
                }
            }
        }
        .background(CosmoColors.background)
        .opacity(isAppeared ? 1 : 0)
        .animation(FocusModeAnimations.backgroundEntry, value: isAppeared)
        .onAppear {
            startObservingResearch()
            isAppeared = true
        }
        .onDisappear {
            observationCancellable?.cancel()
            saveResearch()
            contextTracker.clearEditingContext()
        }
        .onChange(of: title) { _, _ in if !isInitialLoad { triggerAutoSave() } }
        .onChange(of: summary) { _, _ in if !isInitialLoad { triggerAutoSave() } }
        .onChange(of: findings) { _, _ in if !isInitialLoad { triggerAutoSave() } }
        .onChange(of: personalNotes) { _, _ in if !isInitialLoad { triggerAutoSave() } }
    }

    // MARK: - Title Section
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Research Title", text: $title)
                .textFieldStyle(.plain)
                .font(CosmoTypography.displayLarge)
                .foregroundColor(CosmoColors.textPrimary)
        }
        .padding(.horizontal, 4)
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 20)
        .animation(FocusModeAnimations.editorEntry.delay(0.05), value: isAppeared)
    }

    // MARK: - Content Cards
    private var contentCards: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left Column
            VStack(spacing: 16) {
                // Summary Card with AI button
                summaryCard
                
                // Key Findings
                ResearchSectionCard(
                    title: "Key Findings",
                    subtitle: "Important takeaways and insights",
                    placeholder: "• Key point 1\n• Key point 2\n• Key point 3",
                    content: $findings,
                    accentColor: CosmoColors.skyBlue,
                    icon: "list.bullet.clipboard"
                )
            }
            
            // Right Column
            VStack(spacing: 16) {
                // Personal Notes
                ResearchSectionCard(
                    title: "Personal Notes",
                    subtitle: "Your thoughts and reflections",
                    placeholder: "Add your personal notes here...",
                    content: $personalNotes,
                    accentColor: CosmoColors.note,
                    icon: "note.text",
                    isPrivate: true
                )
            }
        }
    }

    // MARK: - Summary Card (with AI button)
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                        .foregroundColor(accentColor)
                    
                    Text("Summary")
                        .font(CosmoTypography.titleSmall)
                        .foregroundColor(CosmoColors.textPrimary)
                }
                
                Spacer()
                
                // AI Summarize button
                Button {
                    aiSummarize()
                } label: {
                    HStack(spacing: 4) {
                        if isAISummarizing {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                        }
                        Text("AI Generate")
                            .font(CosmoTypography.labelSmall)
                    }
                    .foregroundColor(isAISummarizing ? CosmoColors.textTertiary : CosmoColors.lavender)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(CosmoColors.lavender.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isAISummarizing)
                
                // Status indicator
                Circle()
                    .fill(summary.isEmpty ? Color.clear : accentColor)
                    .frame(width: 6, height: 6)
                    .background(
                        Circle()
                            .stroke(summary.isEmpty ? CosmoColors.glassGrey : accentColor.opacity(0.3), lineWidth: 1)
                    )
            }
            
            // Subtitle
            Text("AI-generated or manual overview")
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textTertiary)
            
            // Editor
            TextEditor(text: $summary)
                .font(CosmoTypography.body)
                .foregroundColor(CosmoColors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100)
            
            // Error message
            if let aiErrorMessage = aiErrorMessage {
                Text(aiErrorMessage)
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.coral)
            }
        }
        .padding(ResearchDesign.cardPadding)
        .background(
            ZStack {
                CosmoColors.cardBackground
                accentColor.opacity(0.03)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: ResearchDesign.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: ResearchDesign.cornerRadius)
                .stroke(CosmoColors.glassGrey.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 6)
    }

    // MARK: - Header
    private var editorHeader: some View {
        HStack(spacing: 16) {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(CosmoColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)
            
            Spacer()
            
            // Source badge
            HStack(spacing: 6) {
                Image(systemName: ResearchDesign.icon(for: sourceType))
                    .font(.system(size: 11))
                Text(ResearchDesign.label(for: sourceType))
                    .font(CosmoTypography.labelSmall)
            }
            .foregroundColor(accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(accentColor.opacity(0.1), in: Capsule())
            
            Spacer()
            
            // Balance spacer
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading research...")
                .font(CosmoTypography.body)
                .foregroundColor(CosmoColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Auto Save
    private func triggerAutoSave() {
        guard !isLoading else { return }
        autoSaveTask?.cancel()

        // Update editing context immediately for telepathy (before debounce)
        let fullContent = [title, summary, findings, personalNotes].filter { !$0.isEmpty }.joined(separator: "\n\n")
        contextTracker.updateEditingContext(
            entityType: .research,
            entityId: researchId,
            entityUUID: nil,
            title: title,
            content: fullContent,
            cursorPosition: 0
        )

        autoSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(autoSaveDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    saveResearch()
                }
            } catch {
                // Cancelled
            }
        }
    }

    // MARK: - Live Observation (2-Way Sync)
    private func startObservingResearch() {
        let observation = ValueObservation.tracking { db -> Research? in
            try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("id") == researchId)
                .fetchOne(db)
                .map { ResearchWrapper(atom: $0) }
        }

        observationCancellable = observation.publisher(in: database.dbQueue)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("❌ Research observation error: \(error)")
                    }
                },
                receiveValue: { [self] (research: Research?) in
                    guard let research = research else {
                        isLoading = false
                        return
                    }

                    // Only update editable fields if they differ (prevents looping)
                    let newSummary = research.summary ?? ""
                    let newFindings = research.findings ?? ""
                    let newNotes = research.richContent?.personalNotes ?? ""

                    if research.title != title || newSummary != summary || newFindings != findings || newNotes != personalNotes {
                        title = research.title ?? ""
                        summary = newSummary
                        findings = newFindings
                        personalNotes = newNotes
                    }

                    // Always update read-only metadata
                    url = research.url
                    thumbnailUrl = research.thumbnailUrl

                    // Parse source type
                    if let typeString = research.researchType,
                       let type = ResearchRichContent.SourceType(rawValue: typeString) {
                        sourceType = type
                    }

                    // Parse rich content
                    if let richContent = research.richContent {
                        author = richContent.author
                        publishedAt = richContent.publishedAt
                        duration = richContent.duration
                        videoId = richContent.videoId
                        loomId = richContent.loomId
                        twitterEmbedHtml = richContent.embedHtml
                        formattedTranscript = richContent.formattedTranscript
                        transcriptSections = richContent.transcriptSections

                        // Website screenshot fallback
                        if thumbnailUrl == nil, let base64 = richContent.screenshotBase64 {
                            screenshotImage = NSImage.fromBase64(base64)
                        }
                    }

                    transcriptSegments = research.transcriptSegments ?? []

                    // Update editing context for telepathy/context-aware search
                    let fullContent = [title, summary, findings, personalNotes].filter { !$0.isEmpty }.joined(separator: "\n\n")
                    contextTracker.updateEditingContext(
                        entityType: .research,
                        entityId: research.id ?? researchId,
                        entityUUID: research.uuid,
                        title: research.title ?? "",
                        content: fullContent,
                        cursorPosition: 0
                    )

                    isLoading = false

                    // Mark initial load complete after first observation
                    if isInitialLoad {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isInitialLoad = false
                        }
                    }
                }
            )
    }

    // MARK: - Save Research
    private func saveResearch() {
        GlobalStatusService.shared.showSaving()

        let currentTitle = title
        let currentSummary = summary
        let currentFindings = findings
        let currentNotes = personalNotes

        Task {
            do {
                try await database.asyncWrite { db in
                    if let atom = try Atom
                        .filter(Column("type") == AtomType.research.rawValue)
                        .filter(Column("id") == researchId)
                        .fetchOne(db)
                    {
                        var research = ResearchWrapper(atom: atom)
                        research.title = currentTitle
                        research.summary = currentSummary.isEmpty ? nil : currentSummary
                        research.findings = currentFindings.isEmpty ? nil : currentFindings
                        research.updatedAt = ISO8601DateFormatter().string(from: Date())
                        research.localVersion += 1

                        // Update personal notes in rich content
                        var richContent = research.richContent ?? ResearchRichContent()
                        richContent.personalNotes = currentNotes.isEmpty ? nil : currentNotes
                        research.setRichContent(richContent)

                        try research.update(db)
                    }
                }

                await MainActor.run {
                    GlobalStatusService.shared.showSaved()
                }

                print("✅ Research saved")
            } catch {
                print("❌ Failed to save research: \(error)")
                await MainActor.run {
                    GlobalStatusService.shared.showError("Failed to save")
                }
            }
        }
    }

    // MARK: - AI Summarize
    private func aiSummarize() {
        aiErrorMessage = nil
        isAISummarizing = true

        let currentTitle = title
        let currentURL = url
        let transcriptText = transcriptSegments.map(\.text).joined(separator: " ")
        let existingFindings = findings

        Task {
            do {
                let newSummary: String?

                if !transcriptText.isEmpty {
                    // Local-first: summarize transcript via LocalLLM
                    let prompt = """
                    Create a premium-quality summary for this research.

                    Title: \(currentTitle)

                    Transcript:
                    \(transcriptText.prefix(12_000))

                    Output:
                    - 3–6 bullet points of key takeaways
                    - 1 short paragraph of synthesis
                    """
                    newSummary = await LocalLLM.shared.generate(prompt: prompt, maxTokens: 500)
                } else if let urlString = currentURL, let url = URL(string: urlString) {
                    // Network-backed if available
                    let result = try await ResearchService.shared.performResearch(
                        query: "Summarize the content of this webpage in 3-6 bullets + 1 short synthesis paragraph: \(url.absoluteString) - Title: \(currentTitle)",
                        searchType: .web,
                        maxResults: 1
                    )
                    newSummary = result.summary
                } else if !existingFindings.isEmpty {
                    // Fallback: summarize findings text
                    let prompt = """
                    Summarize these notes into 3–6 bullet points + 1 synthesis paragraph:

                    \(existingFindings.prefix(8_000))
                    """
                    newSummary = await LocalLLM.shared.generate(prompt: prompt, maxTokens: 350)
                } else {
                    newSummary = nil
                }

                if let newSummary, !newSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await MainActor.run {
                        summary = newSummary
                        saveResearch()
                        isAISummarizing = false
                    }
                } else {
                    throw ProcessingError.processingFailed("No content available to summarize.")
                }
            } catch {
                await MainActor.run {
                    aiErrorMessage = error.localizedDescription
                    isAISummarizing = false
                }
            }
        }
    }

    // MARK: - Compact Metadata Bar (for embedded mode)
    private var compactMetadataBar: some View {
        HStack(spacing: 8) {
            // Source type icon
            Image(systemName: ResearchDesign.icon(for: sourceType))
                .font(.system(size: 10))
                .foregroundColor(accentColor)

            Text(ResearchDesign.label(for: sourceType))
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textSecondary)

            if let domain = domain {
                Text("·")
                    .foregroundColor(CosmoColors.textTertiary)
                Text(domain)
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    // MARK: - Compact Hero Section (for embedded mode)
    private var compactHeroSection: some View {
        Group {
            if let thumbnailUrl = thumbnailUrl, let url = URL(string: thumbnailUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 120)
                            .clipped()
                    case .failure, .empty:
                        Rectangle()
                            .fill(accentColor.opacity(0.1))
                            .frame(height: 80)
                            .overlay(
                                Image(systemName: ResearchDesign.icon(for: sourceType))
                                    .font(.system(size: 24))
                                    .foregroundColor(accentColor.opacity(0.5))
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let screenshotImage = screenshotImage {
                Image(nsImage: screenshotImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Rectangle()
                    .fill(accentColor.opacity(0.1))
                    .frame(height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        Image(systemName: ResearchDesign.icon(for: sourceType))
                            .font(.system(size: 20))
                            .foregroundColor(accentColor.opacity(0.5))
                    )
            }
        }
    }

    // MARK: - Compact Content Cards (for embedded mode)
    private var compactContentCards: some View {
        VStack(spacing: 8) {
            // Summary (collapsed by default)
            CompactResearchCard(
                title: "Summary",
                content: $summary,
                accentColor: accentColor,
                icon: "doc.text"
            )

            // Key Findings
            CompactResearchCard(
                title: "Key Findings",
                content: $findings,
                accentColor: CosmoColors.skyBlue,
                icon: "list.bullet.clipboard"
            )

            // Personal Notes
            CompactResearchCard(
                title: "Notes",
                content: $personalNotes,
                accentColor: CosmoColors.note,
                icon: "note.text"
            )
        }
    }
}

// MARK: - Compact Research Card (for embedded mode)

struct CompactResearchCard: View {
    let title: String
    @Binding var content: String
    let accentColor: Color
    let icon: String

    @FocusState private var isFocused: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header (always visible)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(accentColor)

                    Text(title)
                        .font(CosmoTypography.labelSmall)
                        .foregroundColor(CosmoColors.textPrimary)

                    Circle()
                        .fill(content.isEmpty ? CosmoColors.glassGrey : accentColor)
                        .frame(width: 5, height: 5)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(CosmoColors.textTertiary)
                }
            }
            .buttonStyle(.plain)

            // Content (expanded)
            if isExpanded {
                ZStack(alignment: .topLeading) {
                    if content.isEmpty && !isFocused {
                        Text("Add content...")
                            .font(CosmoTypography.bodySmall)
                            .foregroundColor(CosmoColors.textTertiary.opacity(0.5))
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $content)
                        .font(CosmoTypography.bodySmall)
                        .foregroundColor(CosmoColors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .frame(minHeight: 40, maxHeight: 100)
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !content.isEmpty {
                // Preview when collapsed
                Text(content)
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(accentColor.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isFocused ? accentColor.opacity(0.4) : accentColor.opacity(0.1),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Preview
#Preview {
    ResearchEditorView(researchId: 1, presentation: .focus)
        .frame(width: 1000, height: 800)
}

