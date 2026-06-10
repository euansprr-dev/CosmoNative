// CosmoOS/UI/FocusMode/Content/NewProfileFlowView.swift
// Multi-step wizard for creating and editing client profiles
// February 2026

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - New Profile Flow View

struct NewProfileFlowView: View {
    @Environment(\.dismiss) private var dismiss
    let existingAtom: Atom?
    let onSave: (Atom) -> Void

    @State private var currentStep = 1

    // Step 1: Identity
    @State private var clientName = ""
    @State private var handle = ""
    @State private var primaryPlatform: SocialPlatform = .instagram

    // Step 2: Documents
    @State private var documents: [ProfileDocument] = []
    @State private var selectedDocCategory: ProfileDocumentCategory = .story
    @State private var showGuidedStory = false
    @State private var showPasteModal = false
    @State private var showWriteModal = false
    @State private var pasteText = ""
    @State private var pasteTitle = ""
    @State private var writeText = ""
    @State private var writeTitle = ""

    // URL transcription
    @StateObject private var transcriptionManager = ProfileTranscriptionManager()
    @State private var showURLModal = false
    @State private var urlInput = ""
    @State private var reviewingDocumentId: UUID?
    @State private var reviewEditText: String = ""

    // Step 3: Generation
    @State private var isGenerating = false
    @State private var generationProgress = ""
    @State private var intelligenceModel: ClientIntelligenceModel?
    @State private var generationError: String?

    // Step 4: Overrides
    @State private var overrides: [IntelligenceOverride] = []
    @State private var editingMetricId: UUID?  // unused, kept for compat
    @State private var editingMetricKey = ""
    @State private var editingMetricValue = ""

    @State private var isSaving = false


    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(DS.border)
            stepIndicator
            Divider().background(DS.border)
            stepContent
            Divider().background(DS.border)
            bottomNavigation
        }
        .frame(width: 620, height: 720)
        .background(DS.surface)
        .clipShape(.rect(cornerRadius: DS.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLarge)
                .stroke(DS.border, lineWidth: 1)
        )
        .onAppear { loadExisting() }
        .sheet(isPresented: $showGuidedStory) {
            GuidedStoryCreatorView { document in
                documents.append(document)
            }
        }
        .sheet(isPresented: $showPasteModal) {
            pasteTextModal
        }
        .sheet(isPresented: $showWriteModal) {
            writeInAppModal
        }
        .sheet(isPresented: $showURLModal) {
            urlInputModal
        }
        .overlay {
            if reviewingDocumentId != nil {
                urlTranscriptReviewOverlay
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.rectangle.stack.fill")
                .font(.system(size: 16))
                .foregroundStyle(DS.accent)

            Text(existingAtom == nil ? "New Profile" : "Edit Profile")
                .font(DS.cardTitle)
                .foregroundStyle(DS.text)

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 28, height: 28)
                    .background(DS.border, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(1...4, id: \.self) { step in
                stepDot(step: step)
                if step < 4 {
                    stepConnector(completed: currentStep > step)
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func stepDot(step: Int) -> some View {
        let isActive = currentStep == step
        let isCompleted = currentStep > step

        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isCompleted ? DS.accent : (isActive ? DS.accent.opacity(0.3) : DS.border))
                    .frame(width: 28, height: 28)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.textOnAccent)
                } else {
                    Text("\(step)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? DS.text : DS.textMuted)
                }
            }

            Text(stepName(step))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isActive ? DS.textSecondary : DS.textMuted)
        }
    }

    private func stepConnector(completed: Bool) -> some View {
        Rectangle()
            .fill(completed ? DS.accent.opacity(0.5) : DS.border)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .offset(y: -8)
    }

    private func stepName(_ step: Int) -> String {
        switch step {
        case 1: return "Identity"
        case 2: return "Documents"
        case 3: return "Generate"
        case 4: return "Review"
        default: return ""
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        ScrollView {
            switch currentStep {
            case 1: step1Identity
            case 2: step2Documents
            case 3: step3Generate
            case 4: step4Review
            default: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step 1: Identity

    private var step1Identity: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionLabel("CLIENT IDENTITY")

            identityField(label: "Client Name", placeholder: "Brand or creator name", text: $clientName, required: true)
            identityField(label: "Handle", placeholder: "@handle", text: $handle)

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Primary Platform")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(SocialPlatform.allCases, id: \.self) { platform in
                        platformSelectionButton(platform)
                    }
                }
            }

        }
        .padding(24)
    }

    @ViewBuilder
    private func identityField(label: String, placeholder: String, text: Binding<String>, required: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                fieldLabel(label)
                if required {
                    Text("*")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.red.opacity(0.6))
                }
            }
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(DS.sectionDesc)
                .foregroundStyle(DS.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.border, lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private func platformSelectionButton(_ platform: SocialPlatform) -> some View {
        let isSelected = primaryPlatform == platform
        Button(action: { primaryPlatform = platform }) {
            platformSelectionLabel(platform, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func platformSelectionLabel(_ platform: SocialPlatform, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: platform.iconName)
                .font(.system(size: 10))
            Text(platform.displayName)
                .font(DS.timestamp)
        }
        .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
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

    // MARK: - Step 2: Documents

    private var step2Documents: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("UPLOAD DOCUMENTS")

            Text("Upload your brand story, top-performing content, and voice guides to train the AI model.")
                .font(DS.cardMeta)
                .foregroundStyle(DS.textSecondary)

            documentCategoryTabs
            documentsForCategory
            documentActionButtons
        }
        .padding(24)
    }

    private var documentCategoryTabs: some View {
        let categories = ProfileDocumentCategory.allCases
        let topRow = Array(categories.prefix(3))    // Story, Reels, Threads
        let bottomRow = Array(categories.dropFirst(3)) // Voice Guide, Underperforming Reels/Threads

        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(topRow, id: \.self) { category in
                    documentCategoryTab(category)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 2) {
                ForEach(bottomRow, id: \.self) { category in
                    documentCategoryTab(category)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    @ViewBuilder
    private func documentCategoryTab(_ category: ProfileDocumentCategory) -> some View {
        let isSelected = selectedDocCategory == category
        let count = documents.filter { $0.category == category }.count

        Button(action: { selectedDocCategory = category }) {
            documentCategoryTabLabel(category, isSelected: isSelected, count: count)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func documentCategoryTabLabel(_ category: ProfileDocumentCategory, isSelected: Bool, count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: category.iconName)
                .font(.system(size: 10))
            Text(category.displayName)
                .font(DS.timestamp)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? DS.text : DS.textMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(isSelected ? DS.accent.opacity(0.4) : DS.border)
                    )
            }
        }
        .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? DS.accent.opacity(0.2) : Color.clear)
        )
    }

    private var documentsForCategory: some View {
        let filtered = documents.filter { $0.category == selectedDocCategory }

        return VStack(spacing: 8) {
            if filtered.isEmpty {
                emptyDocumentState
            } else {
                ForEach(filtered) { doc in
                    documentCard(doc)
                }
            }
        }
    }

    private var emptyDocumentState: some View {
        VStack(spacing: 8) {
            Image(systemName: selectedDocCategory.iconName)
                .font(.system(size: 24))
                .foregroundStyle(DS.borderActive)

            Text("No \(selectedDocCategory.displayName.lowercased()) documents yet")
                .font(DS.cardMeta)
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundStyle(DS.border)
        )
    }

    @ViewBuilder
    private func documentCard(_ doc: ProfileDocument) -> some View {
        let txState = transcriptionManager.states[doc.id]
        let isTranscribing = txState?.isTranscribing == true

        VStack(alignment: .leading, spacing: 6) {
            documentCardHeader(doc, isTranscribing: isTranscribing)
            documentCardBody(doc, txState: txState)
        }
        .padding(10)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(isTranscribing ? DS.accent.opacity(0.3) : DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func documentCardHeader(_ doc: ProfileDocument, isTranscribing: Bool) -> some View {
        HStack {
            if doc.sourceURL != nil {
                Image(systemName: "link")
                    .font(DS.timestamp)
                    .foregroundStyle(DS.accent.opacity(0.7))
            } else {
                Image(systemName: doc.filename != nil ? "doc.text.fill" : "text.alignleft")
                    .font(DS.timestamp)
                    .foregroundStyle(DS.accent.opacity(0.7))
            }

            Text(doc.title.isEmpty ? (doc.filename ?? "Untitled") : doc.title)
                .font(DS.buttonText)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer()

            if !isTranscribing && !doc.content.isEmpty {
                Text("\(doc.content.count) chars")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textMuted)
            }

            Button(action: { removeDocument(doc.id); transcriptionManager.states.removeValue(forKey: doc.id) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.cardMeta)
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func documentCardBody(_ doc: ProfileDocument, txState: ProfileTranscriptionManager.TranscriptionState?) -> some View {
        if txState?.isTranscribing == true {
            // Shimmer while transcribing
            VStack(alignment: .leading, spacing: 4) {
                CosmicShimmerText(lines: 3, entityColor: DS.accent, lineHeight: 10, lineSpacing: 4)
                    .frame(height: 42)
                Text(txState?.progressText ?? "Transcribing...")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.accent.opacity(0.6))
            }
        } else if let error = txState?.error {
            // Error state
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.orange)
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.orange.opacity(0.9))
                    .lineLimit(2)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let warning = txState?.warning ?? doc.warning {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.accent.opacity(0.8))
                        Text(warning)
                            .font(.system(size: 10))
                            .foregroundStyle(DS.accent.opacity(0.85))
                            .lineLimit(2)
                    }
                }

                if !doc.content.isEmpty {
                    if doc.sourceURL != nil {
                        documentCardPreviewButton(doc)
                    } else {
                        Text(String(doc.content.prefix(120)) + (doc.content.count > 120 ? "..." : ""))
                            .font(DS.timestamp)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func documentCardPreviewButton(_ doc: ProfileDocument) -> some View {
        Button(action: {
            reviewingDocumentId = doc.id
            reviewEditText = doc.content
        }) {
            VStack(alignment: .leading, spacing: 2) {
                if let sourceURL = doc.sourceURL {
                    Text(sourceURL)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(DS.textMuted.opacity(0.6))
                        .lineLimit(1)
                }
                Text(String(doc.content.prefix(120)) + (doc.content.count > 120 ? "..." : ""))
                    .font(DS.timestamp)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var documentActionButtons: some View {
        HStack(spacing: 10) {
            // URL button — only for content categories (reels/threads)
            if selectedDocCategory.hasMetrics {
                Button(action: {
                    urlInput = ""
                    showURLModal = true
                }) {
                    actionButtonLabel(icon: "link", text: "Add URL")
                }
                .buttonStyle(.plain)
            }

            Button(action: { openDocumentPicker() }) {
                actionButtonLabel(icon: "doc.badge.plus", text: "Upload .docx")
            }
            .buttonStyle(.plain)

            Button(action: {
                pasteText = ""
                pasteTitle = ""
                showPasteModal = true
            }) {
                actionButtonLabel(icon: "doc.on.clipboard", text: "Paste Text")
            }
            .buttonStyle(.plain)

            Button(action: {
                writeText = ""
                writeTitle = ""
                showWriteModal = true
            }) {
                actionButtonLabel(icon: "square.and.pencil", text: "Write in App")
            }
            .buttonStyle(.plain)

            if selectedDocCategory == .story {
                Button(action: { showGuidedStory = true }) {
                    actionButtonLabel(icon: "list.bullet.rectangle", text: "Guided Template")
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func actionButtonLabel(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(DS.timestamp)
        }
        .foregroundStyle(DS.accent.opacity(0.8))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(DS.accentSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(DS.accent.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Step 3: Generate

    private var step3Generate: some View {
        VStack(spacing: 24) {
            sectionLabel("GENERATE INTELLIGENCE MODEL")

            let storyCount = documents.filter { $0.category == .story }.count
            let reelCount = documents.filter { $0.category == .reel }.count
            let threadCount = documents.filter { $0.category == .thread }.count
            let underReelCount = documents.filter { $0.category == .underperformingReel }.count
            let underThreadCount = documents.filter { $0.category == .underperformingThread }.count
            let underperformerCount = underReelCount + underThreadCount
            let highPerformerCount = reelCount + threadCount
            let canGenerate = storyCount >= 1 && highPerformerCount >= 3

            VStack(alignment: .leading, spacing: 8) {
                requirementRow(label: "Brand Story document", met: storyCount >= 1, detail: "\(storyCount) uploaded")
                requirementRow(label: "High-performing content (min 3 reels + threads)", met: highPerformerCount >= 3, detail: "\(reelCount) reels, \(threadCount) threads")
                requirementRow(
                    label: "Underperforming content (for Failure Fingerprint)",
                    met: underperformerCount >= 2,
                    detail: underperformerCount > 0 ? "\(underReelCount) reels, \(underThreadCount) threads" : "optional"
                )
            }
            .padding(14)
            .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 10))

            if underperformerCount == 0 {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.accent.opacity(0.6))
                    Text("Add underperforming content in Step 2 to generate a Failure Fingerprint — the AI will compare what works vs what doesn't across 8 dimensions.")
                        .font(DS.timestamp)
                        .foregroundStyle(DS.textMuted)
                }
            }

            if isGenerating {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(DS.accent)

                    Text(generationProgress)
                        .font(DS.buttonText)
                        .foregroundStyle(DS.textSecondary)
                        .animation(.easeInOut, value: generationProgress)
                }
                .padding(.vertical, 20)
            } else if let model = intelligenceModel {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(DS.green)

                    Text("Intelligence Model Generated")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.text)

                    Text("Generated at \(model.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(DS.timestamp)
                        .foregroundStyle(DS.textMuted)

                    // Failure fingerprint summary
                    if let fp = model.failureFingerprint, !fp.rules.isEmpty {
                        failureFingerprintSummary(fp)
                    }

                    Button(action: { Task { await generateModel() } }) {
                        Text("Regenerate")
                            .font(DS.timestamp)
                            .foregroundStyle(DS.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.vertical, 16)
            } else {
                Button(action: { Task { await generateModel() } }) {
                    generateButtonLabel(canGenerate: canGenerate)
                }
                .buttonStyle(.plain)
                .disabled(!canGenerate)
            }

            if let error = generationError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DS.timestamp)
                        .foregroundStyle(DS.orange)
                    Text(error)
                        .font(DS.timestamp)
                        .foregroundStyle(DS.orange.opacity(0.9))
                        .lineLimit(3)
                }
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private func requirementRow(label: String, met: Bool, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(met ? DS.green : DS.textMuted)

            Text(label)
                .font(DS.cardMeta)
                .foregroundStyle(DS.textSecondary)

            Spacer()

            Text(detail)
                .font(DS.timestamp)
                .foregroundStyle(DS.textMuted)
        }
    }

    @ViewBuilder
    private func generateButtonLabel(canGenerate: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 13))
            Text("Generate Intelligence Model")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(DS.textOnAccent)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(canGenerate ? CosmoColors.cosmoAI : DS.border)
        )
    }

    // MARK: - Step 4: Review

    private var step4Review: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let model = intelligenceModel {
                IntelligenceModelView(
                    model: Binding(
                        get: { model },
                        set: { intelligenceModel = $0 }
                    ),
                    overrides: $overrides,
                    editingMetricId: $editingMetricId,
                    editingMetricKey: $editingMetricKey,
                    editingMetricValue: $editingMetricValue,
                    showUpdateButton: false
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(DS.textMuted)

                    Text("No intelligence model generated yet")
                        .font(DS.sectionDesc)
                        .foregroundStyle(DS.textMuted)

                    Text("Go back to Step 3 to generate one, or save the profile without it.")
                        .font(DS.timestamp)
                        .foregroundStyle(DS.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
        .padding(24)
    }

    // MARK: - Bottom Navigation

    private var bottomNavigation: some View {
        HStack {
            if currentStep > 1 {
                Button(action: { withAnimation(.spring(response: 0.3)) { currentStep -= 1 } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Back")
                            .font(DS.sectionDesc)
                    }
                    .foregroundStyle(DS.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if currentStep == 2 {
                Button(action: { withAnimation(.spring(response: 0.3)) { currentStep = 3 } }) {
                    Text("Skip")
                        .font(DS.buttonText)
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }

            if currentStep == 3 && intelligenceModel == nil && !isGenerating {
                Button(action: { withAnimation(.spring(response: 0.3)) { currentStep = 4 } }) {
                    Text("Skip")
                        .font(DS.buttonText)
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }

            if currentStep < 4 {
                Button(action: { withAnimation(.spring(response: 0.3)) { currentStep += 1 } }) {
                    nextButtonLabel
                }
                .buttonStyle(.plain)
                .disabled(currentStep == 1 && clientName.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                Button(action: { Task { await saveProfile() } }) {
                    doneButtonLabel
                }
                .buttonStyle(.plain)
                .disabled(clientName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var nextButtonLabel: some View {
        let isDisabled = currentStep == 1 && clientName.trimmingCharacters(in: .whitespaces).isEmpty
        HStack(spacing: 4) {
            Text("Next")
                .font(.system(size: 13, weight: .semibold))
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(DS.textOnAccent)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(isDisabled ? DS.border : DS.accent)
        )
    }

    @ViewBuilder
    private var doneButtonLabel: some View {
        HStack(spacing: 6) {
            if isSaving {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.white)
            }
            Text(existingAtom == nil ? "Create Profile" : "Save Changes")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(DS.textOnAccent)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.accent)
        )
    }

    // MARK: - Paste Text Modal

    private var pasteTextModal: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Paste Text")
                    .font(DS.navTitle)
                    .foregroundStyle(DS.text)
                Spacer()
                Button("Cancel") { showPasteModal = false }
                    .font(DS.cardMeta)
                    .foregroundStyle(DS.textSecondary)
                    .buttonStyle(.plain)
            }
            .padding(16)

            Divider().background(DS.border)

            VStack(alignment: .leading, spacing: 10) {
                TextField("Title (optional)", text: $pasteTitle)
                    .textFieldStyle(.plain)
                    .font(DS.sectionDesc)
                    .foregroundStyle(DS.text)
                    .padding(10)
                    .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))

                ZStack(alignment: .topLeading) {
                    if pasteText.isEmpty {
                        Text("Paste your content here...")
                            .font(DS.cardMeta)
                            .foregroundStyle(DS.textMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                    TextEditor(text: $pasteText)
                        .font(DS.cardMeta)
                        .foregroundStyle(DS.text)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .frame(height: 200)
                .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            }
            .padding(16)

            Divider().background(DS.border)

            HStack {
                Spacer()
                Button(action: {
                    let doc = ProfileDocument(
                        category: selectedDocCategory,
                        title: pasteTitle.isEmpty ? "Pasted content" : pasteTitle,
                        content: pasteText,
                        platform: selectedDocCategory.platformTag
                    )
                    documents.append(doc)
                    showPasteModal = false
                }) {
                    pasteAddButtonLabel
                }
                .buttonStyle(.plain)
                .disabled(pasteText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 500, height: 400)
        .background(DS.surface)
        .clipShape(.rect(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var pasteAddButtonLabel: some View {
        Text("Add")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(pasteText.trimmingCharacters(in: .whitespaces).isEmpty ? DS.border : DS.accent)
            )
    }

    // MARK: - Write In App Modal

    private var writeInAppModal: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Write Document")
                    .font(DS.navTitle)
                    .foregroundStyle(DS.text)
                Spacer()
                Button("Cancel") { showWriteModal = false }
                    .font(DS.cardMeta)
                    .foregroundStyle(DS.textSecondary)
                    .buttonStyle(.plain)
            }
            .padding(16)

            Divider().background(DS.border)

            VStack(alignment: .leading, spacing: 10) {
                TextField("Document title", text: $writeTitle)
                    .textFieldStyle(.plain)
                    .font(DS.sectionDesc)
                    .foregroundStyle(DS.text)
                    .padding(10)
                    .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))

                ZStack(alignment: .topLeading) {
                    if writeText.isEmpty {
                        Text("Start writing...")
                            .font(DS.cardMeta)
                            .foregroundStyle(DS.textMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                    TextEditor(text: $writeText)
                        .font(DS.cardMeta)
                        .foregroundStyle(DS.text)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .frame(minHeight: 250)
                .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            }
            .padding(16)

            Divider().background(DS.border)

            HStack {
                Spacer()
                Button(action: {
                    let doc = ProfileDocument(
                        category: selectedDocCategory,
                        title: writeTitle.isEmpty ? "Written document" : writeTitle,
                        content: writeText,
                        platform: selectedDocCategory.platformTag
                    )
                    documents.append(doc)
                    showWriteModal = false
                }) {
                    writeSaveButtonLabel
                }
                .buttonStyle(.plain)
                .disabled(writeText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 520, height: 480)
        .background(DS.surface)
        .clipShape(.rect(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var writeSaveButtonLabel: some View {
        Text("Save")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(writeText.trimmingCharacters(in: .whitespaces).isEmpty ? DS.border : DS.accent)
            )
    }

    // MARK: - URL Input Modal

    private var urlInputModal: some View {
        VStack(spacing: 0) {
            urlInputModalHeader
            Divider().background(DS.border)
            urlInputModalBody
            Divider().background(DS.border)
            urlInputModalFooter
        }
        .frame(width: 480, height: 220)
        .background(DS.surface)
        .clipShape(.rect(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var urlInputModalHeader: some View {
        HStack {
            Text("Add Instagram URL")
                .font(DS.navTitle)
                .foregroundStyle(DS.text)
            Spacer()
            Button("Cancel") { showURLModal = false }
                .font(DS.cardMeta)
                .foregroundStyle(DS.textSecondary)
                .buttonStyle(.plain)
        }
        .padding(16)
    }

    @ViewBuilder
    private var urlInputModalBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste the Instagram URL of a \(selectedDocCategory.displayName.lowercased()) post. It will be auto-transcribed using the same engine as the swipe file.")
                .font(DS.timestamp)
                .foregroundStyle(DS.textMuted)

            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.accent.opacity(0.6))

                TextField("https://www.instagram.com/reel/...", text: $urlInput)
                    .textFieldStyle(.plain)
                    .font(DS.sectionDesc)
                    .foregroundStyle(DS.text)
                    .onSubmit { submitURLFromModal() }
            }
            .padding(10)
            .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.border, lineWidth: 1)
            )
        }
        .padding(16)
    }

    @ViewBuilder
    private var urlInputModalFooter: some View {
        HStack {
            Spacer()
            Button(action: { submitURLFromModal() }) {
                urlAddButtonLabel
            }
            .buttonStyle(.plain)
            .disabled(!isValidInstagramURL(urlInput))
        }
        .padding(16)
    }

    @ViewBuilder
    private var urlAddButtonLabel: some View {
        let isValid = isValidInstagramURL(urlInput)
        Text("Transcribe")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(isValid ? DS.accent : DS.border)
            )
    }

    private func isValidInstagramURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased() else { return false }
        return host.contains("instagram.com")
    }

    private func submitURLFromModal() {
        let urlString = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString), isValidInstagramURL(urlString) else { return }

        let docId = UUID()
        let placeholder = ProfileDocument(
            id: docId,
            category: selectedDocCategory,
            title: "Transcribing...",
            content: "",
            platform: selectedDocCategory.platformTag,
            sourceURL: urlString
        )
        documents.append(placeholder)
        showURLModal = false
        urlInput = ""

        Task {
            if let completed = await transcriptionManager.transcribe(
                url: url, documentId: docId, category: selectedDocCategory
            ) {
                if let index = documents.firstIndex(where: { $0.id == docId }) {
                    documents[index] = completed
                }
            }
        }
    }

    // MARK: - Transcript Review Overlay

    @ViewBuilder
    private var urlTranscriptReviewOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { saveAndCloseURLReview() }

            VStack(spacing: 0) {
                urlReviewHeader
                Divider().background(DS.border)
                urlReviewEditor
                Divider().background(DS.border)
                urlReviewFooter
            }
            .frame(width: 500, height: 420)
            .background(DS.surface)
            .clipShape(.rect(cornerRadius: DS.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(DS.border, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var urlReviewHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcript Review")
                    .font(DS.navTitle)
                    .foregroundStyle(DS.text)
                if let reviewId = reviewingDocumentId,
                   let doc = documents.first(where: { $0.id == reviewId }),
                   let sourceURL = doc.sourceURL {
                    Text(sourceURL)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: { saveAndCloseURLReview() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(DS.borderSubtle, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    @ViewBuilder
    private var urlReviewEditor: some View {
        TextEditor(text: $reviewEditText)
            .font(DS.cardMeta)
            .foregroundStyle(DS.text)
            .scrollContentBackground(.hidden)
            .padding(12)
    }

    @ViewBuilder
    private var urlReviewFooter: some View {
        HStack {
            Text("\(reviewEditText.count) characters")
                .font(.system(size: 10))
                .foregroundStyle(DS.textMuted)
            Spacer()
            Button(action: { saveAndCloseURLReview() }) {
                Text("Save Changes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(DS.accent, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private func saveAndCloseURLReview() {
        if let reviewId = reviewingDocumentId,
           let index = documents.firstIndex(where: { $0.id == reviewId }) {
            documents[index].content = reviewEditText
            // Update title if it was the placeholder
            if documents[index].title == "Transcribing..." {
                documents[index].title = String(reviewEditText.prefix(60))
            }
        }
        reviewingDocumentId = nil
        reviewEditText = ""
    }

    // MARK: - Shared Components

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .dsSectionLabel()
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .font(DS.buttonText)
            .foregroundStyle(DS.textSecondary)
    }

    // MARK: - Failure Fingerprint Summary

    @ViewBuilder
    private func failureFingerprintSummary(_ fp: FailureFingerprint) -> some View {
        let highCount = fp.rules.filter { $0.severity == .high }.count
        let medCount = fp.rules.filter { $0.severity == .medium }.count

        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 12))
                .foregroundStyle(.red.opacity(0.8))

            Text("Failure Fingerprint: \(fp.rules.count) rules")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.text)

            if highCount > 0 {
                Text("\(highCount) HIGH")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red.opacity(0.12)))
            }
            if medCount > 0 {
                Text("\(medCount) MED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(Color.red.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(Color.red.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func openDocumentPicker() {
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
            for url in panel.urls {
                let content = extractText(from: url)
                guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let doc = ProfileDocument(
                    category: selectedDocCategory,
                    title: url.deletingPathExtension().lastPathComponent,
                    content: content,
                    filename: url.lastPathComponent,
                    platform: selectedDocCategory.platformTag
                )
                documents.append(doc)
            }
        }
    }

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
            let stripped = xmlString.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            return stripped.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        } catch {
            return ""
        }
    }

    private func removeDocument(_ id: UUID) {
        documents.removeAll { $0.id == id }
    }

    /// Infer whether content is a reel (short-form) or thread (long-form) based on length heuristics.
    private func inferDocCategory(from content: String) -> ProfileDocumentCategory {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentenceCount = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
        if trimmed.count < 500 || sentenceCount < 5 { return .reel }
        return .thread
    }

    private func generateModel() async {
        isGenerating = true
        generationError = nil

        let underperformerCount = documents.filter { $0.category.isUnderperformer }.count
        var stages = [
            "Analyzing voice patterns...",
            "Extracting performance data...",
            "Building audience model..."
        ]
        if underperformerCount > 0 {
            stages.append("Comparing top vs underperforming content...")
        }
        stages.append("Finalizing...")

        do {
            // Build a temporary atom with documents to pass to the engine
            let trimmedName = clientName.trimmingCharacters(in: .whitespaces)
            let metadata = ClientProfileMetadata(
                clientId: existingAtom.flatMap { $0.metadataValue(as: ClientProfileMetadata.self)?.clientId } ?? UUID().uuidString,
                clientName: trimmedName,
                platforms: [primaryPlatform],
                activeStatus: true,
                handle: handle.isEmpty ? nil : handle,
                documents: documents,
                primaryPlatform: primaryPlatform
            )

            var tempAtom = existingAtom ?? Atom.new(type: .clientProfile, title: trimmedName, body: nil)
            tempAtom.metadata = metadata.toJSON()

            for stage in stages {
                generationProgress = stage
                try await Task.sleep(nanoseconds: 500_000_000)
            }

            let model = try await ClientIntelligenceEngine.shared.generateModel(profile: tempAtom)
            intelligenceModel = model
            isGenerating = false

            withAnimation(.spring(response: 0.3)) {
                currentStep = 4
            }
        } catch {
            isGenerating = false
            generationError = error.localizedDescription
        }
    }

    private func loadExisting() {
        guard let atom = existingAtom else { return }
        clientName = atom.title ?? ""

        if let meta = atom.metadataValue(as: ClientProfileMetadata.self) {
            handle = meta.handle ?? ""
            if let pp = meta.primaryPlatform {
                primaryPlatform = pp
            } else if let first = meta.platforms.first {
                primaryPlatform = first
            }
            // Load documents from metadata
            if let docs = meta.documents {
                documents = docs
            } else {
                // Legacy migration: reconstruct documents from old fields
                if let story = meta.brandStory, !story.isEmpty {
                    documents.append(ProfileDocument(category: .story, title: "Brand Story", content: story))
                }
                if let voice = meta.voiceNotes, !voice.isEmpty {
                    documents.append(ProfileDocument(category: .voiceGuide, title: "Voice Notes", content: voice))
                }
                if let posts = meta.topPerformingPosts {
                    for post in posts where !post.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let category = inferDocCategory(from: post.transcript)
                        documents.append(ProfileDocument(
                            category: category,
                            title: "\(category == .reel ? "Reel" : "Thread") (\(post.platform.isEmpty ? "unknown" : post.platform))",
                            content: post.transcript,
                            platform: post.platform,
                            likes: post.likes,
                            shares: post.shares
                        ))
                    }
                }
            }

            // Load existing intelligence model
            intelligenceModel = meta.intelligenceModel
            if let model = meta.intelligenceModel {
                overrides = model.userOverrides
            }
        }
    }

    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }

        let trimmedName = clientName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // Build TopPost array from high-performer documents for legacy compat
        let topPosts: [TopPost] = documents
            .filter { $0.category.isHighPerformer && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { doc in
                TopPost(
                    transcript: doc.content,
                    platform: doc.platform ?? doc.category.platformTag ?? ""
                )
            }

        let brandStoryText = documents
            .filter { $0.category == .story }
            .map { $0.content }
            .joined(separator: "\n\n")

        let voiceNotesText = documents
            .filter { $0.category == .voiceGuide }
            .map { $0.content }
            .joined(separator: "\n\n")

        var finalModel = intelligenceModel
        if var model = finalModel {
            model.userOverrides = overrides
            finalModel = model
        }

        let metadata = ClientProfileMetadata(
            clientId: existingAtom.flatMap { $0.metadataValue(as: ClientProfileMetadata.self)?.clientId } ?? UUID().uuidString,
            clientName: trimmedName,
            platforms: [primaryPlatform],
            activeStatus: true,
            brandStory: brandStoryText.isEmpty ? nil : brandStoryText,
            voiceNotes: voiceNotesText.isEmpty ? nil : voiceNotesText,
            handle: handle.isEmpty ? nil : handle,
            intelligenceModel: finalModel,
            documents: documents.isEmpty ? nil : documents,
            primaryPlatform: primaryPlatform,
            topPerformingPosts: topPosts.isEmpty ? nil : topPosts
        )

        do {
            if var existing = existingAtom {
                existing.title = trimmedName
                existing.metadata = metadata.toJSON()
                let saved = try await AtomRepository.shared.update(existing)
                onSave(saved)
            } else {
                var atom = Atom.new(type: .clientProfile, title: trimmedName, body: nil)
                atom.metadata = metadata.toJSON()
                let saved = try await AtomRepository.shared.create(atom)
                onSave(saved)
            }
            dismiss()
        } catch {
            print("NewProfileFlowView: Save failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Preview

#Preview("New Profile Flow") {
    NewProfileFlowView(
        existingAtom: nil,
        onSave: { _ in }
    )
    .frame(width: 620, height: 720)
}
