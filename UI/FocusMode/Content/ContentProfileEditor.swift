// CosmoOS/UI/FocusMode/Content/ContentProfileEditor.swift
// Profile editor for creating and managing client/brand profiles
// February 2026

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - Content Profile Editor

/// Full-form editor for ClientProfileMetadata. Used from:
/// - IdeaFocusModeView "Assign Client" dropdown (create new)
/// - Creative dimension dashboard (manage profiles)
/// - Settings (profile management)
struct ContentProfileEditor: View {
    @Environment(\.dismiss) private var dismiss

    /// If editing an existing profile, pass its atom. Nil = create new.
    let existingAtom: Atom?
    let onSave: (Atom) -> Void

    @State private var clientName: String = ""
    @State private var handle: String = ""
    @State private var niche: String = ""
    @State private var industry: String = ""
    @State private var targetAudience: String = ""
    @State private var notes: String = ""

    // Brand context
    @State private var brandStory: String = ""
    @State private var brandVision: String = ""
    @State private var coreBeliefs: [String] = []
    @State private var newBelief: String = ""
    @State private var voiceNotes: String = ""
    @State private var uniqueAngle: String = ""

    // Performance
    @State private var topPerformingTranscripts: [String] = [""]
    @State private var bestFormats: Set<String> = []
    @State private var topPerformingPosts: [TopPost] = []
    @State private var extractedVoicePatterns: VoiceProfile? = nil
    @State private var isExtractingVoice = false
    @State private var voiceExtractionError: String? = nil

    // Posting
    @State private var postingFrequency: String = ""
    @State private var preferredPostTimes: [String] = []
    @State private var newPostTime: String = ""

    // Signature phrases
    @State private var signaturePhrases: [String] = []
    @State private var newPhrase: String = ""

    // Identity
    @State private var isPersonalBrand: Bool = true
    @State private var selectedPlatforms: Set<SocialPlatform> = []

    // Context files & AI auto-fill
    @State private var contextFileURLs: [URL] = []
    @State private var isAutoFilling = false
    @State private var autoFillError: String?

    // Document library
    @State private var documents: [ProfileDocument] = []
    @State private var reelSubTab: DocumentSubTab = .topPerformers
    @State private var threadSubTab: DocumentSubTab = .topPerformers

    @State private var isSaving = false

    /// Sub-tab selector for top-performer vs underperformer document views
    enum DocumentSubTab: String, CaseIterable {
        case topPerformers
        case underperformers

        var displayName: String {
            switch self {
            case .topPerformers: return "Top Performers"
            case .underperformers: return "Underperformers"
            }
        }

        var accentColor: Color {
            switch self {
            case .topPerformers: return .green
            case .underperformers: return .red
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider().background(DS.border)
            formContent
            Divider().background(DS.border)
            bottomBar
        }
        .frame(width: 560, height: 680)
        .background(DS.surface)
        .cornerRadius(DS.radiusLarge)
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLarge)
                .stroke(DS.border, lineWidth: 1)
        )
        .onAppear { loadExisting() }
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.rectangle.stack.fill")
                .font(.system(size: 16))
                .foregroundColor(DS.accent)

            Text(existingAtom == nil ? "New Profile" : "Edit Profile")
                .font(DS.cardTitle)
                .foregroundColor(DS.text)

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(DS.buttonText)
                    .foregroundColor(DS.textMuted)
                    .frame(width: 28, height: 28)
                    .background(DS.border, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Form Content

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                identitySection
                contextFilesSection
                brandContextSection
                topPerformingPostsSection
                documentLibrarySection
                performanceSection
                postingSection
            }
            .padding(20)
        }
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Identity")

            fieldRow(label: "Name", placeholder: "Client or brand name", text: $clientName)
            fieldRow(label: "Handle", placeholder: "@handle", text: $handle)
            fieldRow(label: "Niche", placeholder: "e.g., personal finance, fitness", text: $niche)
            fieldRow(label: "Industry", placeholder: "e.g., SaaS, health & wellness", text: $industry)
            fieldRow(label: "Audience", placeholder: "Who they create for", text: $targetAudience)

            // Personal brand toggle
            HStack(spacing: 10) {
                fieldLabel("Brand Type")
                Spacer()
                Picker("", selection: $isPersonalBrand) {
                    Text("Personal").tag(true)
                    Text("Company").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            // Platform multi-select
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Platforms")
                platformChips
            }
        }
    }

    private var platformChips: some View {
        let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(SocialPlatform.allCases, id: \.self) { platform in
                platformChipButton(platform)
            }
        }
    }

    @ViewBuilder
    private func platformChipButton(_ platform: SocialPlatform) -> some View {
        let isSelected = selectedPlatforms.contains(platform)
        Button(action: {
            if isSelected {
                selectedPlatforms.remove(platform)
            } else {
                selectedPlatforms.insert(platform)
            }
        }) {
            platformChipLabel(platform, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func platformChipLabel(_ platform: SocialPlatform, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: platform.iconName)
                .font(.system(size: 10))
            Text(platform.displayName)
                .font(DS.timestamp)
        }
        .foregroundColor(isSelected ? DS.text : DS.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(isSelected ? DS.accent.opacity(0.3) : DS.borderSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(isSelected ? DS.accent.opacity(0.5) : DS.border, lineWidth: 1)
                )
        )
    }

    // MARK: - Brand Context Section

    private var brandContextSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Brand Context")

            textAreaField(label: "Voice Notes", placeholder: "Describe the tone, style, and personality...", text: $voiceNotes)
            textAreaField(label: "Unique Angle", placeholder: "What makes this perspective different...", text: $uniqueAngle)
            textAreaField(label: "Brand Story", placeholder: "Origin story or brand narrative...", text: $brandStory)
            fieldRow(label: "Vision", placeholder: "Long-term mission or vision", text: $brandVision)

            // Core beliefs list
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Core Beliefs")
                ForEach(coreBeliefs.indices, id: \.self) { index in
                    beliefRow(index: index)
                }
                addBeliefRow
            }

            // Signature phrases list
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Signature Phrases")
                Text("Catchphrases, recurring openers, trademark expressions")
                    .font(DS.timestamp)
                    .foregroundColor(DS.textMuted)
                ForEach(signaturePhrases.indices, id: \.self) { index in
                    phraseRow(index: index)
                }
                addPhraseRow
            }
        }
    }

    @ViewBuilder
    private func beliefRow(index: Int) -> some View {
        HStack(spacing: 8) {
            Text(coreBeliefs[index])
                .font(DS.cardMeta)
                .foregroundColor(DS.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { coreBeliefs.remove(at: index) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.cardMeta)
                    .foregroundColor(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
    }

    private var addBeliefRow: some View {
        HStack(spacing: 8) {
            TextField("Add a core belief...", text: $newBelief)
                .textFieldStyle(.plain)
                .font(DS.cardMeta)
                .foregroundColor(DS.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
                .onSubmit {
                    addBelief()
                }

            Button(action: { addBelief() }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(DS.accent.opacity(0.7))
            }
            .buttonStyle(.plain)
            .disabled(newBelief.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Document Library Section

    private var documentLibrarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Document Library")

            Text("Upload transcripts of top and underperforming content for AI analysis")
                .font(DS.timestamp)
                .foregroundColor(DS.textMuted)

            // Reels subsection
            documentSubsection(
                title: "Reels",
                icon: "play.rectangle.fill",
                subTab: $reelSubTab,
                topCategory: .reel,
                underCategory: .underperformingReel
            )

            // Threads subsection
            documentSubsection(
                title: "Threads",
                icon: "text.below.photo.fill",
                subTab: $threadSubTab,
                topCategory: .thread,
                underCategory: .underperformingThread
            )
        }
    }

    @ViewBuilder
    private func documentSubsection(
        title: String,
        icon: String,
        subTab: Binding<DocumentSubTab>,
        topCategory: ProfileDocumentCategory,
        underCategory: ProfileDocumentCategory
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Subsection header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(DS.textSecondary)
                Text(title)
                    .font(DS.buttonText)
                    .foregroundColor(DS.text)
            }

            // Sub-tab pills
            documentSubTabPicker(subTab: subTab)

            // Active category
            let activeCategory = subTab.wrappedValue == .topPerformers ? topCategory : underCategory
            let filtered = documents.filter { $0.category == activeCategory }

            // Underperformer helper text
            if subTab.wrappedValue == .underperformers {
                Text("Upload content that performed poorly. The AI compares this against top performers to learn what to avoid.")
                    .font(DS.timestamp)
                    .foregroundColor(DS.textMuted)
                    .padding(.horizontal, 4)
            }

            // Document cards
            if filtered.isEmpty {
                documentEmptyState(category: activeCategory)
            } else {
                ForEach(filtered) { doc in
                    documentLibraryCard(doc)
                }
            }

            // Add document button
            if filtered.count < 10 {
                addDocumentButton(category: activeCategory)
            }
        }
        .padding(12)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func documentSubTabPicker(subTab: Binding<DocumentSubTab>) -> some View {
        HStack(spacing: 4) {
            ForEach(DocumentSubTab.allCases, id: \.rawValue) { tab in
                documentSubTabChip(tab: tab, isSelected: subTab.wrappedValue == tab) {
                    subTab.wrappedValue = tab
                }
            }
        }
    }

    @ViewBuilder
    private func documentSubTabChip(tab: DocumentSubTab, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            documentSubTabChipLabel(tab: tab, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func documentSubTabChipLabel(tab: DocumentSubTab, isSelected: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tab.accentColor)
                .frame(width: 6, height: 6)
            Text(tab.displayName)
                .font(DS.timestamp)
        }
        .foregroundColor(isSelected ? DS.text : DS.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(isSelected ? tab.accentColor.opacity(0.2) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(isSelected ? tab.accentColor.opacity(0.4) : DS.border, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func documentEmptyState(category: ProfileDocumentCategory) -> some View {
        VStack(spacing: 6) {
            Image(systemName: category.iconName)
                .font(.system(size: 18))
                .foregroundColor(DS.borderActive)
            Text("No \(category.displayName.lowercased()) yet")
                .font(DS.timestamp)
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundColor(DS.border)
        )
    }

    @ViewBuilder
    private func documentLibraryCard(_ doc: ProfileDocument) -> some View {
        let index = documents.firstIndex(where: { $0.id == doc.id })
        VStack(alignment: .leading, spacing: 6) {
            // Title row
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(DS.timestamp)
                    .foregroundColor(doc.category.isUnderperformer ? Color.red.opacity(0.7) : DS.accent.opacity(0.7))

                if let idx = index {
                    TextField("Title...", text: Binding(
                        get: { idx < documents.count ? documents[idx].title : "" },
                        set: { if idx < documents.count { documents[idx].title = $0 } }
                    ))
                    .textFieldStyle(.plain)
                    .font(DS.buttonText)
                    .foregroundColor(DS.text)
                }

                Spacer()

                Text("\(doc.content.count) chars")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)

                Button(action: { removeDocument(doc.id) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.cardMeta)
                        .foregroundColor(DS.textMuted)
                }
                .buttonStyle(.plain)
            }

            // Editable content area
            if let idx = index {
                ZStack(alignment: .topLeading) {
                    if idx < documents.count && documents[idx].content.isEmpty {
                        Text("Paste transcript...")
                            .font(DS.cardMeta)
                            .foregroundColor(DS.textMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                    TextEditor(text: Binding(
                        get: { idx < documents.count ? documents[idx].content : "" },
                        set: { if idx < documents.count { documents[idx].content = $0 } }
                    ))
                    .font(DS.cardMeta)
                    .foregroundColor(DS.text)
                    .scrollContentBackground(.hidden)
                    .frame(height: 60)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            }

            // Metrics row (for categories that have metrics)
            if doc.category.hasMetrics, let idx = index {
                documentMetricsEditRow(index: idx)
            }
        }
        .padding(10)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func documentMetricsEditRow(index: Int) -> some View {
        HStack(spacing: 8) {
            // Platform picker
            Picker("", selection: Binding(
                get: { index < documents.count ? (documents[index].platform ?? "") : "" },
                set: { if index < documents.count { documents[index].platform = $0.isEmpty ? nil : $0 } }
            )) {
                Text("Platform").tag("")
                ForEach(SocialPlatform.allCases, id: \.rawValue) { platform in
                    Text(platform.displayName).tag(platform.rawValue)
                }
            }
            .frame(width: 100)
            .font(DS.timestamp)

            documentMetricField("Likes", index: index, keyPath: \.likes)
            documentMetricField("Shares", index: index, keyPath: \.shares)
            documentMetricField("Saves", index: index, keyPath: \.saves)
            documentMetricField("Comments", index: index, keyPath: \.comments)
        }
    }

    @ViewBuilder
    private func documentMetricField(_ label: String, index: Int, keyPath: WritableKeyPath<ProfileDocument, Int?>) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.textMuted)
            TextField("0", value: Binding(
                get: { index < documents.count ? (documents[index][keyPath: keyPath] ?? 0) : 0 },
                set: { if index < documents.count { documents[index][keyPath: keyPath] = $0 == 0 ? nil : $0 } }
            ), format: .number)
            .textFieldStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(DS.textSecondary)
            .multilineTextAlignment(.center)
            .frame(width: 50)
            .padding(.vertical, 3)
            .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder
    private func addDocumentButton(category: ProfileDocumentCategory) -> some View {
        Button(action: { addNewDocument(category: category) }) {
            addDocumentButtonLabel(category: category)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func addDocumentButtonLabel(category: ProfileDocumentCategory) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 10))
            Text("Add \(category.displayName.lowercased())")
                .font(DS.timestamp)
        }
        .foregroundColor(category.isUnderperformer ? Color.red.opacity(0.7) : DS.accent.opacity(0.7))
    }

    private func addNewDocument(category: ProfileDocumentCategory) {
        let doc = ProfileDocument(
            category: category,
            title: "",
            content: ""
        )
        documents.append(doc)
    }

    private func removeDocument(_ id: UUID) {
        documents.removeAll { $0.id == id }
    }

    // MARK: - Performance Section

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Performance Context")

            // Best formats multi-select
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Best Formats")
                formatChips
            }

            // Top performing transcripts
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Top Performing Content")
                Text("Paste transcripts or text of top-performing posts for AI context")
                    .font(DS.timestamp)
                    .foregroundColor(DS.textMuted)

                ForEach(topPerformingTranscripts.indices, id: \.self) { index in
                    transcriptField(index: index)
                }

                if topPerformingTranscripts.count < 5 {
                    Button(action: { topPerformingTranscripts.append("") }) {
                        addTranscriptButtonLabel
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var formatChips: some View {
        let formats = ContentFormat.allCases
        let columns = [GridItem(.adaptive(minimum: 90), spacing: 6)]
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(formats, id: \.rawValue) { format in
                formatChipButton(format)
            }
        }
    }

    @ViewBuilder
    private func formatChipButton(_ format: ContentFormat) -> some View {
        let isSelected = bestFormats.contains(format.rawValue)
        Button(action: {
            if isSelected {
                bestFormats.remove(format.rawValue)
            } else {
                bestFormats.insert(format.rawValue)
            }
        }) {
            formatChipLabel(format, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func formatChipLabel(_ format: ContentFormat, isSelected: Bool) -> some View {
        Text(format.displayName)
            .font(DS.timestamp)
            .foregroundColor(isSelected ? DS.text : DS.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? CosmoColors.skyBlue.opacity(0.3) : DS.borderSubtle)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? CosmoColors.skyBlue.opacity(0.5) : DS.border, lineWidth: 1)
                    )
            )
    }

    @ViewBuilder
    private func transcriptField(index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            TextEditor(text: Binding(
                get: { index < topPerformingTranscripts.count ? topPerformingTranscripts[index] : "" },
                set: { if index < topPerformingTranscripts.count { topPerformingTranscripts[index] = $0 } }
            ))
            .font(DS.cardMeta)
            .foregroundColor(DS.text)
            .scrollContentBackground(.hidden)
            .frame(height: 60)
            .padding(8)
            .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))

            if topPerformingTranscripts.count > 1 {
                Button(action: { topPerformingTranscripts.remove(at: index) }) {
                    Image(systemName: "trash")
                        .font(DS.timestamp)
                        .foregroundColor(DS.textMuted)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var addTranscriptButtonLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 10))
            Text("Add transcript")
                .font(DS.timestamp)
        }
        .foregroundColor(DS.accent.opacity(0.7))
    }

    // MARK: - Top Performing Posts Section

    private var topPerformingPostsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Top Performing Posts")

            Text("Add transcripts of your best posts with metrics for AI voice extraction")
                .font(DS.timestamp)
                .foregroundColor(DS.textMuted)

            ForEach(topPerformingPosts.indices, id: \.self) { index in
                topPostCard(index: index)
            }

            if topPerformingPosts.count < 10 {
                Button(action: { topPerformingPosts.append(TopPost()) }) {
                    addPostButtonLabel
                }
                .buttonStyle(.plain)
            }

            // Voice extraction
            let hasTranscripts = topPerformingPosts.contains { !$0.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if hasTranscripts {
                extractVoiceButton
            }

            if let error = voiceExtractionError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DS.timestamp)
                        .foregroundColor(DS.orange)
                    Text(error)
                        .font(DS.timestamp)
                        .foregroundColor(DS.orange)
                        .lineLimit(2)
                }
            }

            // Display extracted voice profile
            if let voice = extractedVoicePatterns {
                voiceProfileCard(voice)
            }
        }
    }

    @ViewBuilder
    private func topPostCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Post \(index + 1)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.textSecondary)
                Spacer()
                Button(action: { topPerformingPosts.remove(at: index) }) {
                    Image(systemName: "trash")
                        .font(DS.timestamp)
                        .foregroundColor(DS.textMuted)
                }
                .buttonStyle(.plain)
            }

            // Transcript
            ZStack(alignment: .topLeading) {
                if index < topPerformingPosts.count && topPerformingPosts[index].transcript.isEmpty {
                    Text("Paste transcript...")
                        .font(DS.cardMeta)
                        .foregroundColor(DS.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                TextEditor(text: Binding(
                    get: { index < topPerformingPosts.count ? topPerformingPosts[index].transcript : "" },
                    set: { if index < topPerformingPosts.count { topPerformingPosts[index].transcript = $0 } }
                ))
                .font(DS.cardMeta)
                .foregroundColor(DS.text)
                .scrollContentBackground(.hidden)
                .frame(height: 70)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))

            // Platform and metrics row
            HStack(spacing: 8) {
                topPostPlatformPicker(index: index)
                topPostMetricField("Likes", value: Binding(
                    get: { index < topPerformingPosts.count ? topPerformingPosts[index].likes : 0 },
                    set: { if index < topPerformingPosts.count { topPerformingPosts[index].likes = $0 } }
                ))
                topPostMetricField("Shares", value: Binding(
                    get: { index < topPerformingPosts.count ? topPerformingPosts[index].shares : 0 },
                    set: { if index < topPerformingPosts.count { topPerformingPosts[index].shares = $0 } }
                ))
                topPostMetricField("Views", value: Binding(
                    get: { index < topPerformingPosts.count ? topPerformingPosts[index].views : 0 },
                    set: { if index < topPerformingPosts.count { topPerformingPosts[index].views = $0 } }
                ))
                topPostMetricField("Leads", value: Binding(
                    get: { index < topPerformingPosts.count ? topPerformingPosts[index].leads : 0 },
                    set: { if index < topPerformingPosts.count { topPerformingPosts[index].leads = $0 } }
                ))
            }
        }
        .padding(10)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func topPostPlatformPicker(index: Int) -> some View {
        Picker("", selection: Binding(
            get: { index < topPerformingPosts.count ? topPerformingPosts[index].platform : "" },
            set: { if index < topPerformingPosts.count { topPerformingPosts[index].platform = $0 } }
        )) {
            Text("Platform").tag("")
            ForEach(SocialPlatform.allCases, id: \.rawValue) { platform in
                Text(platform.displayName).tag(platform.rawValue)
            }
        }
        .frame(width: 100)
        .font(DS.timestamp)
    }

    @ViewBuilder
    private func topPostMetricField(_ label: String, value: Binding<Int>) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.textMuted)
            TextField("0", value: value, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DS.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: 50)
                .padding(.vertical, 3)
                .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder
    private var addPostButtonLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 10))
            Text("Add Post")
                .font(DS.timestamp)
        }
        .foregroundColor(DS.accent.opacity(0.7))
    }

    private var extractVoiceButton: some View {
        Button(action: { Task { await extractVoicePatterns() } }) {
            HStack(spacing: 6) {
                if isExtractingVoice {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white)
                } else {
                    Image(systemName: "waveform.and.magnifyingglass")
                        .font(DS.cardMeta)
                }
                Text(isExtractingVoice ? "Extracting..." : "Extract Voice Patterns")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(isExtractingVoice ? DS.border : CosmoColors.cosmoAI)
            )
        }
        .buttonStyle(.plain)
        .disabled(isExtractingVoice)
    }

    @ViewBuilder
    private func voiceProfileCard(_ voice: VoiceProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(DS.cardMeta)
                    .foregroundColor(CosmoColors.cosmoAI)
                Text("Extracted Voice Profile")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.text)
            }

            if voice.avgSentenceLength > 0 {
                voiceRow("Avg Sentence Length", "\(String(format: "%.1f", voice.avgSentenceLength)) words")
            }
            if !voice.readingLevel.isEmpty {
                voiceRow("Reading Level", voice.readingLevel)
            }
            if !voice.emotionalRange.isEmpty {
                voiceRow("Emotional Range", voice.emotionalRange)
            }
            if !voice.recurringPhrases.isEmpty {
                voiceRow("Recurring Phrases", voice.recurringPhrases.joined(separator: ", "))
            }
            if !voice.ctaPatterns.isEmpty {
                voiceRow("CTA Patterns", voice.ctaPatterns.joined(separator: ", "))
            }
            if !voice.stylisticQuirks.isEmpty {
                voiceRow("Stylistic Quirks", voice.stylisticQuirks.joined(separator: ", "))
            }
            if !voice.hookStyleDistribution.isEmpty {
                let hookStyles = voice.hookStyleDistribution.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                voiceRow("Hook Styles", hookStyles)
            }
        }
        .padding(12)
        .background(CosmoColors.cosmoAI.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CosmoColors.cosmoAI.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func voiceRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textMuted)
            Text(value)
                .font(DS.timestamp)
                .foregroundColor(DS.textSecondary)
                .lineLimit(3)
        }
    }

    // MARK: - Voice Extraction

    private func extractVoicePatterns() async {
        guard let apiKey = APIKeys.openRouter, !apiKey.isEmpty else {
            voiceExtractionError = "No OpenRouter API key configured. Add one in Settings > API Keys."
            return
        }

        let transcripts = topPerformingPosts
            .filter { !$0.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { $0.transcript }

        guard !transcripts.isEmpty else {
            voiceExtractionError = "No transcripts to analyze."
            return
        }

        isExtractingVoice = true
        voiceExtractionError = nil
        defer { isExtractingVoice = false }

        let combinedTranscripts = transcripts.enumerated()
            .map { "--- Post \($0.offset + 1) ---\n\($0.element)" }
            .joined(separator: "\n\n")

        let truncated = String(combinedTranscripts.prefix(25000))

        let systemPrompt = """
            You are a content voice analysis expert. Analyze the provided top-performing content transcripts \
            and extract precise voice patterns for AI content generation. Focus on SPECIFIC linguistic patterns, \
            not generic descriptions. Return ONLY valid JSON with these exact keys: \
            "avgSentenceLength" (number - average words per sentence), \
            "hookStyleDistribution" (object - hook type name to count, e.g. {"question": 3, "bold_claim": 2}), \
            "ctaPatterns" (array of strings - recurring call-to-action patterns), \
            "recurringPhrases" (array of strings - exact phrases used repeatedly), \
            "emotionalRange" (string - description of emotional spectrum used), \
            "readingLevel" (string - e.g. "Grade 6-8", "Conversational"), \
            "stylisticQuirks" (array of strings - unique writing habits like "uses em dashes frequently", \
            "starts sentences with And/But", "uses single-word paragraphs for emphasis"). \
            Return raw JSON only, no markdown fences.
            """

        do {
            let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("CosmoOS/1.0", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("CosmoOS Voice Extraction", forHTTPHeaderField: "X-Title")

            let body: [String: Any] = [
                "model": "anthropic/claude-sonnet-4",
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": "Analyze these top-performing transcripts for voice patterns:\n\n\(truncated)"]
                ],
                "temperature": 0.2,
                "max_tokens": 3000,
                "stream": false
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                voiceExtractionError = "API error: \(String(errorText.prefix(200)))"
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                voiceExtractionError = "Failed to parse API response"
                return
            }

            let cleaned = content
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let resultData = cleaned.data(using: .utf8),
                  let result = try JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
                voiceExtractionError = "Failed to parse AI analysis result"
                return
            }

            var profile = VoiceProfile()
            if let v = result["avgSentenceLength"] as? Double { profile.avgSentenceLength = v }
            if let v = result["hookStyleDistribution"] as? [String: Int] { profile.hookStyleDistribution = v }
            if let v = result["ctaPatterns"] as? [String] { profile.ctaPatterns = v }
            if let v = result["recurringPhrases"] as? [String] { profile.recurringPhrases = v }
            if let v = result["emotionalRange"] as? String { profile.emotionalRange = v }
            if let v = result["readingLevel"] as? String { profile.readingLevel = v }
            if let v = result["stylisticQuirks"] as? [String] { profile.stylisticQuirks = v }

            extractedVoicePatterns = profile
        } catch {
            voiceExtractionError = error.localizedDescription
        }
    }

    // MARK: - Posting Section

    private var postingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Posting Schedule")

            fieldRow(label: "Frequency", placeholder: "e.g., 3x/week, daily", text: $postingFrequency)

            // Preferred post times
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Preferred Times")
                ForEach(preferredPostTimes.indices, id: \.self) { index in
                    postTimeRow(index: index)
                }
                addPostTimeRow
            }

            textAreaField(label: "Notes", placeholder: "General notes about this client...", text: $notes)
        }
    }

    @ViewBuilder
    private func postTimeRow(index: Int) -> some View {
        HStack(spacing: 8) {
            Text(preferredPostTimes[index])
                .font(DS.cardMeta)
                .foregroundColor(DS.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { preferredPostTimes.remove(at: index) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.cardMeta)
                    .foregroundColor(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
    }

    private var addPostTimeRow: some View {
        HStack(spacing: 8) {
            TextField("e.g., 9:00 AM EST", text: $newPostTime)
                .textFieldStyle(.plain)
                .font(DS.cardMeta)
                .foregroundColor(DS.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
                .onSubmit { addPostTime() }

            Button(action: { addPostTime() }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(DS.accent.opacity(0.7))
            }
            .buttonStyle(.plain)
            .disabled(newPostTime.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if existingAtom != nil {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(DS.buttonText)
                        .foregroundColor(DS.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button(action: { Task { await save() } }) {
                saveButtonLabel
            }
            .buttonStyle(.plain)
            .disabled(clientName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var saveButtonLabel: some View {
        HStack(spacing: 6) {
            if isSaving {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.white)
            }
            Text(existingAtom == nil ? "Create Profile" : "Save Changes")
                .font(DS.buttonText)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(clientName.trimmingCharacters(in: .whitespaces).isEmpty
                      ? DS.border
                      : DS.accent)
        )
    }

    // MARK: - Shared Field Components

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(DS.sectionLabel)
            .foregroundColor(DS.textMuted)
            .tracking(0.88)
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .font(DS.buttonText)
            .foregroundColor(DS.textSecondary)
    }

    private func fieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            fieldLabel(label)
                .frame(width: 80, alignment: .trailing)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(DS.sectionDesc)
                .foregroundColor(DS.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        }
    }

    private func textAreaField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(DS.cardMeta)
                        .foregroundColor(DS.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                TextEditor(text: text)
                    .font(DS.cardMeta)
                    .foregroundColor(DS.text)
                    .scrollContentBackground(.hidden)
                    .frame(height: 56)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        }
    }

    // MARK: - Signature Phrase Rows

    @ViewBuilder
    private func phraseRow(index: Int) -> some View {
        HStack(spacing: 8) {
            Text(signaturePhrases[index])
                .font(DS.cardMeta)
                .foregroundColor(DS.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { signaturePhrases.remove(at: index) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.cardMeta)
                    .foregroundColor(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
    }

    private var addPhraseRow: some View {
        HStack(spacing: 8) {
            TextField("Add a signature phrase...", text: $newPhrase)
                .textFieldStyle(.plain)
                .font(DS.cardMeta)
                .foregroundColor(DS.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
                .onSubmit { addPhrase() }

            Button(action: { addPhrase() }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(DS.accent.opacity(0.7))
            }
            .buttonStyle(.plain)
            .disabled(newPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addPhrase() {
        let trimmed = newPhrase.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        signaturePhrases.append(trimmed)
        newPhrase = ""
    }

    // MARK: - Context Files Section

    private var contextFilesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Context Files")

            Text("Upload documents with brand context (best posts, brand docs, etc.) for AI auto-fill")
                .font(DS.timestamp)
                .foregroundColor(DS.textMuted)

            // File list
            ForEach(Array(contextFileURLs.enumerated()), id: \.offset) { index, url in
                contextFileRow(index: index, url: url)
            }

            // Add files button
            if contextFileURLs.count < 5 {
                Button(action: { openFilePicker() }) {
                    addFilesButtonLabel
                }
                .buttonStyle(.plain)
            }

            // Auto-fill button
            autoFillButton

            // Error display
            if let error = autoFillError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DS.timestamp)
                        .foregroundColor(DS.orange)
                    Text(error)
                        .font(DS.timestamp)
                        .foregroundColor(DS.orange)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private func contextFileRow(index: Int, url: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: fileIcon(for: url))
                .font(DS.cardMeta)
                .foregroundColor(DS.accent.opacity(0.7))

            Text(url.lastPathComponent)
                .font(DS.cardMeta)
                .foregroundColor(DS.text)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button(action: { contextFileURLs.remove(at: index) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.cardMeta)
                    .foregroundColor(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var addFilesButtonLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.badge.plus")
                .font(DS.timestamp)
            Text("Add Files (.pdf, .txt, .docx)")
                .font(DS.timestamp)
        }
        .foregroundColor(DS.accent.opacity(0.7))
    }

    private var autoFillButton: some View {
        Button(action: { Task { await performAutoFill() } }) {
            HStack(spacing: 6) {
                if isAutoFilling {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white)
                } else {
                    Image(systemName: "sparkles")
                        .font(DS.cardMeta)
                }
                Text(isAutoFilling ? "Analyzing..." : "Auto-Fill with AI")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(contextFileURLs.isEmpty || isAutoFilling
                          ? DS.border
                          : DS.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(contextFileURLs.isEmpty || isAutoFilling)
    }

    private func fileIcon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "docx", "doc": return "doc.text"
        default: return "doc.plaintext"
        }
    }

    // MARK: - File Picker

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        var allowedTypes: [UTType] = [.pdf, .plainText]
        if let docx = UTType("org.openxmlformats.wordprocessingml.document") {
            allowedTypes.append(docx)
        }
        panel.allowedContentTypes = allowedTypes

        panel.begin { response in
            guard response == .OK else { return }
            let remaining = 5 - contextFileURLs.count
            let newURLs = Array(panel.urls.prefix(remaining))
            contextFileURLs.append(contentsOf: newURLs)
        }
    }

    // MARK: - Text Extraction

    private func extractText(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "txt":
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        case "pdf":
            guard let doc = PDFDocument(url: url) else { return "" }
            var text = ""
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i), let pageText = page.string {
                    text += pageText + "\n"
                }
            }
            return text

        case "docx", "doc":
            return extractDocxText(from: url)

        default:
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
    }

    private func extractDocxText(from url: URL) -> String {
        // docx is a zip archive containing word/document.xml
        guard let data = try? Data(contentsOf: url) else { return "" }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let zipPath = tempDir.appendingPathComponent("doc.zip")
            try data.write(to: zipPath)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", zipPath.path, "-d", tempDir.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()

            let docXML = tempDir.appendingPathComponent("word/document.xml")
            guard let xmlString = try? String(contentsOf: docXML, encoding: .utf8) else { return "" }

            // Strip XML tags to get raw text
            let stripped = xmlString.replacingOccurrences(
                of: "<[^>]+>",
                with: " ",
                options: .regularExpression
            )
            // Collapse whitespace
            return stripped.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        } catch {
            return ""
        }
    }

    // MARK: - AI Auto-Fill

    private func performAutoFill() async {
        guard !contextFileURLs.isEmpty else { return }
        guard let apiKey = APIKeys.openRouter, !apiKey.isEmpty else {
            autoFillError = "No OpenRouter API key configured. Add one in Settings > API Keys."
            return
        }

        isAutoFilling = true
        autoFillError = nil
        defer { isAutoFilling = false }

        // Extract text from all files
        var combinedText = ""
        for url in contextFileURLs {
            let text = extractText(from: url)
            if !text.isEmpty {
                combinedText += "--- File: \(url.lastPathComponent) ---\n\(text)\n\n"
            }
        }

        guard !combinedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            autoFillError = "Could not extract text from the uploaded files."
            return
        }

        // Truncate to ~30K chars to stay within token limits
        let truncated = String(combinedText.prefix(30000))

        let systemPrompt = """
            You are a voice analysis expert. Analyze the provided content and extract a detailed brand voice profile \
            optimized for 1:1 voice emulation. Focus on specific linguistic patterns, not generic descriptions. \
            Capture: sentence starters, cadence, vocabulary choices, punctuation habits, recurring structures, \
            and distinctive expressions. Return ONLY valid JSON with these keys (all string values except arrays): \
            "voiceNotes" (detailed voice/tone analysis with specific examples), \
            "uniqueAngle" (what makes this perspective unique), \
            "brandStory" (origin or brand narrative if detectable), \
            "brandVision" (mission or vision if detectable), \
            "coreBeliefs" (array of strings — values driving the content), \
            "targetAudience" (who this content speaks to), \
            "niche" (content vertical), \
            "industry" (business sector), \
            "bestFormats" (array of strings — content formats used), \
            "postingFrequency" (if detectable), \
            "topPerformingTranscripts" (array — 1-2 best content excerpts verbatim, max 300 chars each), \
            "signaturePhrases" (array — catchphrases, trademark openers, recurring expressions). \
            Omit keys where data is insufficient. Return raw JSON only, no markdown fences.
            """

        let userPrompt = "Analyze this content for brand voice profile extraction:\n\n\(truncated)"

        do {
            let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("CosmoOS/1.0", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("CosmoOS Profile Auto-Fill", forHTTPHeaderField: "X-Title")

            let body: [String: Any] = [
                "model": "google/gemini-2.0-flash-001",
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userPrompt]
                ],
                "temperature": 0.3,
                "max_tokens": 4000,
                "stream": false
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                autoFillError = "API error: \(errorText.prefix(200))"
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                autoFillError = "Failed to parse API response"
                return
            }

            // Parse the JSON response
            let cleaned = content
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let resultData = cleaned.data(using: .utf8),
                  let result = try JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
                autoFillError = "Failed to parse AI analysis result"
                return
            }

            // Populate only empty fields to avoid overwriting manual edits
            if voiceNotes.isEmpty, let v = result["voiceNotes"] as? String { voiceNotes = v }
            if uniqueAngle.isEmpty, let v = result["uniqueAngle"] as? String { uniqueAngle = v }
            if brandStory.isEmpty, let v = result["brandStory"] as? String { brandStory = v }
            if brandVision.isEmpty, let v = result["brandVision"] as? String { brandVision = v }
            if targetAudience.isEmpty, let v = result["targetAudience"] as? String { targetAudience = v }
            if niche.isEmpty, let v = result["niche"] as? String { niche = v }
            if industry.isEmpty, let v = result["industry"] as? String { industry = v }
            if postingFrequency.isEmpty, let v = result["postingFrequency"] as? String { postingFrequency = v }

            if coreBeliefs.isEmpty, let v = result["coreBeliefs"] as? [String] { coreBeliefs = v }
            if signaturePhrases.isEmpty, let v = result["signaturePhrases"] as? [String] { signaturePhrases = v }
            if bestFormats.isEmpty, let v = result["bestFormats"] as? [String] { bestFormats = Set(v) }

            if topPerformingTranscripts == [""] || topPerformingTranscripts.allSatisfy({ $0.isEmpty }) {
                if let v = result["topPerformingTranscripts"] as? [String], !v.isEmpty {
                    topPerformingTranscripts = v
                }
            }

        } catch {
            autoFillError = error.localizedDescription
        }
    }

    // MARK: - Actions

    private func addBelief() {
        let trimmed = newBelief.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        coreBeliefs.append(trimmed)
        newBelief = ""
    }

    private func addPostTime() {
        let trimmed = newPostTime.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        preferredPostTimes.append(trimmed)
        newPostTime = ""
    }

    private func loadExisting() {
        guard let atom = existingAtom else { return }
        clientName = atom.title ?? ""

        // Try ClientProfileMetadata first (ContentPipelineService format)
        if let meta = atom.metadataValue(as: ClientProfileMetadata.self) {
            handle = meta.handle ?? ""
            niche = meta.niche ?? meta.industry ?? ""
            industry = meta.industry ?? ""
            targetAudience = meta.targetAudience ?? ""
            notes = meta.notes ?? ""
            brandStory = meta.brandStory ?? ""
            brandVision = meta.brandVision ?? ""
            coreBeliefs = meta.coreBeliefs ?? []
            voiceNotes = meta.voiceNotes ?? ""
            uniqueAngle = meta.uniqueAngle ?? ""
            topPerformingTranscripts = meta.topPerformingTranscripts ?? [""]
            if topPerformingTranscripts.isEmpty { topPerformingTranscripts = [""] }
            bestFormats = Set(meta.bestFormats ?? [])
            postingFrequency = meta.postingFrequency ?? ""
            preferredPostTimes = meta.preferredPostTimes ?? []
            isPersonalBrand = meta.isPersonalBrand ?? true
            selectedPlatforms = Set(meta.platforms)
            signaturePhrases = meta.signaturePhrases ?? []
            topPerformingPosts = meta.topPerformingPosts ?? []
            extractedVoicePatterns = meta.extractedVoicePatterns
            documents = meta.documents ?? []
        }
        // Fallback to ClientMetadata (Atom.swift format)
        else if let meta = atom.metadataValue(as: ClientMetadata.self) {
            niche = meta.niche ?? ""
            voiceNotes = meta.brandVoice ?? ""
            if let formats = meta.preferredFormats {
                bestFormats = Set(formats)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmedName = clientName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // Filter empty transcripts
        let transcripts = topPerformingTranscripts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Filter documents with empty content
        let filteredDocuments = documents.filter {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let metadata = ClientProfileMetadata(
            clientId: existingAtom.flatMap { atom in
                atom.metadataValue(as: ClientProfileMetadata.self)?.clientId
            } ?? UUID().uuidString,
            clientName: trimmedName,
            platforms: Array(selectedPlatforms),
            activeStatus: true,
            notes: notes.isEmpty ? nil : notes,
            industry: industry.isEmpty ? nil : industry,
            targetAudience: targetAudience.isEmpty ? nil : targetAudience,
            brandStory: brandStory.isEmpty ? nil : brandStory,
            brandVision: brandVision.isEmpty ? nil : brandVision,
            coreBeliefs: coreBeliefs.isEmpty ? nil : coreBeliefs,
            voiceNotes: voiceNotes.isEmpty ? nil : voiceNotes,
            uniqueAngle: uniqueAngle.isEmpty ? nil : uniqueAngle,
            topPerformingTranscripts: transcripts.isEmpty ? nil : transcripts,
            bestFormats: bestFormats.isEmpty ? nil : Array(bestFormats),
            postingFrequency: postingFrequency.isEmpty ? nil : postingFrequency,
            preferredPostTimes: preferredPostTimes.isEmpty ? nil : preferredPostTimes,
            handle: handle.isEmpty ? nil : handle,
            niche: niche.isEmpty ? nil : niche,
            isPersonalBrand: isPersonalBrand,
            signaturePhrases: signaturePhrases.isEmpty ? nil : signaturePhrases,
            documents: filteredDocuments.isEmpty ? nil : filteredDocuments,
            topPerformingPosts: topPerformingPosts.isEmpty ? nil : topPerformingPosts.filter { !$0.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            extractedVoicePatterns: extractedVoicePatterns,
            preferredBeatPatterns: nil
        )

        do {
            if var existing = existingAtom {
                existing.title = trimmedName
                existing.body = notes.isEmpty ? nil : notes
                existing.metadata = metadata.toJSON()
                let saved = try await AtomRepository.shared.update(existing)
                onSave(saved)
            } else {
                var atom = Atom.new(type: .clientProfile, title: trimmedName, body: notes.isEmpty ? nil : notes)
                atom.metadata = metadata.toJSON()
                let saved = try await AtomRepository.shared.create(atom)
                onSave(saved)
            }
            dismiss()
        } catch {
            print("ContentProfileEditor: Save failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Preview

#Preview("Content Profile Editor") {
    ContentProfileEditor(
        existingAtom: nil,
        onSave: { _ in }
    )
    .frame(width: 560, height: 680)
}
