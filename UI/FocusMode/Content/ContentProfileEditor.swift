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

    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider().background(Color.white.opacity(0.08))
            formContent
            Divider().background(Color.white.opacity(0.08))
            bottomBar
        }
        .frame(width: 560, height: 680)
        .background(CosmoColors.thinkspaceSecondary)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear { loadExisting() }
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.rectangle.stack.fill")
                .font(.system(size: 16))
                .foregroundColor(CosmoColors.lavender)

            Text(existingAtom == nil ? "New Profile" : "Edit Profile")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06), in: Circle())
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
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(isSelected ? .white : .white.opacity(0.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? CosmoColors.lavender.opacity(0.3) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? CosmoColors.lavender.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
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
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
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
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { coreBeliefs.remove(at: index) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private var addBeliefRow: some View {
        HStack(spacing: 8) {
            TextField("Add a core belief...", text: $newBelief)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .onSubmit {
                    addBelief()
                }

            Button(action: { addBelief() }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(CosmoColors.lavender.opacity(0.7))
            }
            .buttonStyle(.plain)
            .disabled(newBelief.trimmingCharacters(in: .whitespaces).isEmpty)
        }
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
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))

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
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? CosmoColors.skyBlue.opacity(0.3) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? CosmoColors.skyBlue.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
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
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.8))
            .scrollContentBackground(.hidden)
            .frame(height: 60)
            .padding(8)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

            if topPerformingTranscripts.count > 1 {
                Button(action: { topPerformingTranscripts.remove(at: index) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
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
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(CosmoColors.lavender.opacity(0.7))
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
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { preferredPostTimes.remove(at: index) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private var addPostTimeRow: some View {
        HStack(spacing: 8) {
            TextField("e.g., 9:00 AM EST", text: $newPostTime)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .onSubmit { addPostTime() }

            Button(action: { addPostTime() }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(CosmoColors.lavender.opacity(0.7))
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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
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
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(clientName.trimmingCharacters(in: .whitespaces).isEmpty
                      ? Color.white.opacity(0.08)
                      : CosmoColors.lavender)
        )
    }

    // MARK: - Shared Field Components

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.3))
            .tracking(1.2)
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
    }

    private func fieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            fieldLabel(label)
                .frame(width: 80, alignment: .trailing)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func textAreaField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.2))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                TextEditor(text: text)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                    .scrollContentBackground(.hidden)
                    .frame(height: 56)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Signature Phrase Rows

    @ViewBuilder
    private func phraseRow(index: Int) -> some View {
        HStack(spacing: 8) {
            Text(signaturePhrases[index])
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { signaturePhrases.remove(at: index) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private var addPhraseRow: some View {
        HStack(spacing: 8) {
            TextField("Add a signature phrase...", text: $newPhrase)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .onSubmit { addPhrase() }

            Button(action: { addPhrase() }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(CosmoColors.lavender.opacity(0.7))
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
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))

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
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.orange.opacity(0.9))
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private func contextFileRow(index: Int, url: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: fileIcon(for: url))
                .font(.system(size: 12))
                .foregroundColor(CosmoColors.lavender.opacity(0.7))

            Text(url.lastPathComponent)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button(action: { contextFileURLs.remove(at: index) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var addFilesButtonLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 11))
            Text("Add Files (.pdf, .txt, .docx)")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(CosmoColors.lavender.opacity(0.7))
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
                        .font(.system(size: 12))
                }
                Text(isAutoFilling ? "Analyzing..." : "Auto-Fill with AI")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(contextFileURLs.isEmpty || isAutoFilling
                          ? Color.white.opacity(0.08)
                          : CosmoColors.lavender)
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
            signaturePhrases: signaturePhrases.isEmpty ? nil : signaturePhrases
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
