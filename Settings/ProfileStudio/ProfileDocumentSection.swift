// CosmoOS/Settings/ProfileStudio/ProfileDocumentSection.swift
// The hero section of the Profile Studio: the document library.
// One grouped container, category filter pills, inline composers (write/paste,
// URL transcription, library search) — no stacked sheets. Files can be
// dropped anywhere on the section.

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - Filter

enum ProfileDocumentFilter: String, CaseIterable, Identifiable {
    case all, story, reels, threads, voice, underperformers

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .story: return "Story"
        case .reels: return "Reels"
        case .threads: return "Threads"
        case .voice: return "Voice"
        case .underperformers: return "Underperformers"
        }
    }

    var categories: [ProfileDocumentCategory] {
        switch self {
        case .all: return ProfileDocumentCategory.allCases
        case .story: return [.story]
        case .reels: return [.reel]
        case .threads: return [.thread]
        case .voice: return [.voiceGuide]
        case .underperformers: return [.underperformingReel, .underperformingThread]
        }
    }

    var defaultAddCategory: ProfileDocumentCategory {
        switch self {
        case .all, .story: return .story
        case .reels: return .reel
        case .threads: return .thread
        case .voice: return .voiceGuide
        case .underperformers: return .underperformingReel
        }
    }
}

// MARK: - Section

struct ProfileDocumentSection: View {
    let store: ProfileStudioStore

    @State private var filter: ProfileDocumentFilter = .all
    @State private var composer: ProfileComposerKind?
    @State private var expandedDocumentId: UUID?
    @State private var transcription = ProfileTranscriptionManager()
    @State private var showGuidedStory = false
    @State private var isDropTargeted = false

    private var filteredDocuments: [ProfileDocument] {
        store.documents.filter { filter.categories.contains($0.category) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            SettingsSectionHeader(label: "DOCUMENTS", detail: "\(store.documents.count)")
            filterPills
            documentsBox
        }
        .sheet(isPresented: $showGuidedStory) {
            GuidedStoryCreatorView { document in
                store.addDocument(document)
            }
        }
    }

    /// Collapse the inline composer; returns true when something was open.
    /// The studio's Esc handler peels this layer before backing out.
    func collapseComposer() -> Bool {
        guard composer != nil else { return false }
        withAnimation(ProMotionSprings.snappy) { composer = nil }
        return true
    }

    // MARK: - Filter pills

    private var filterPills: some View {
        HStack(spacing: DS.space6) {
            ForEach(ProfileDocumentFilter.allCases) { item in
                filterPill(item)
            }
            Spacer(minLength: 0)
        }
    }

    private func filterPill(_ item: ProfileDocumentFilter) -> some View {
        let count = item == .all
            ? store.documents.count
            : item.categories.reduce(0) { $0 + store.documentCount(in: $1) }
        let isSelected = filter == item

        return Button {
            withAnimation(ProMotionSprings.snappy) { filter = item }
        } label: {
            HStack(spacing: DS.space4) {
                Text(item.label)
                    .font(DS.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                if count > 0 {
                    Text("\(count)")
                        .font(DS.caption2.monospacedDigit())
                        .contentTransition(.numericText())
                        .foregroundStyle(isSelected ? DS.accent : DS.textMuted)
                }
            }
            .foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background(isSelected ? AnyShapeStyle(DS.accentSoft) : AnyShapeStyle(Color.clear), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? DS.accent.opacity(0.35) : DS.glassBorder, lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Grouped box

    private var documentsBox: some View {
        SettingsGroupedBox {
            if filteredDocuments.isEmpty && composer == nil {
                emptyTeachingRow
            } else {
                documentRows
            }
            SettingsRowDivider(inset: 0)
            addRow
            if let composer {
                SettingsRowDivider(inset: 0)
                ProfileComposerView(
                    kind: composer,
                    store: store,
                    transcription: transcription,
                    onDismiss: { withAnimation(ProMotionSprings.snappy) { self.composer = nil } }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .stroke(isDropTargeted ? DS.accent : Color.clear, lineWidth: 1.5)
        )
        .animation(ProMotionSprings.hover, value: isDropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            importDroppedFiles(urls)
        } isTargeted: { targeting in
            isDropTargeted = targeting
        }
    }

    private var documentRows: some View {
        let docs: [ProfileDocument] = filteredDocuments
        let lastId: UUID? = docs.last?.id
        return VStack(spacing: 0) {
            ForEach(docs) { doc in
                documentRow(doc, isLast: doc.id == lastId)
            }
        }
    }

    @ViewBuilder
    private func documentRow(_ doc: ProfileDocument, isLast: Bool) -> some View {
        ProfileDocumentRow(
            document: doc,
            showsCategory: filter == .all,
            isExpanded: expandedDocumentId == doc.id,
            transcriptionState: transcription.states[doc.id],
            onToggleExpand: { toggleExpanded(doc.id) },
            onContentEdit: { store.updateDocumentContent(id: doc.id, content: $0) },
            onRemove: { removeDocument(doc.id) }
        )
        if !isLast {
            SettingsRowDivider()
        }
    }

    private func toggleExpanded(_ id: UUID) {
        withAnimation(ProMotionSprings.gentle) {
            expandedDocumentId = expandedDocumentId == id ? nil : id
        }
    }

    private func removeDocument(_ id: UUID) {
        withAnimation(ProMotionSprings.snappy) {
            store.removeDocument(id: id)
            transcription.states.removeValue(forKey: id)
        }
    }

    private var emptyTeachingRow: some View {
        VStack(spacing: DS.space6) {
            Image(systemName: "doc.text")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text("Feed this voice")
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.textSecondary)
            Text("Start with your brand story and 3 posts you're proud of — Cosmo drafts from what it reads here.")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space24)
        .padding(.horizontal, DS.space16)
    }

    // MARK: - Add row

    private var addRow: some View {
        HStack(spacing: DS.space6) {
            addChip(icon: "square.and.pencil", label: "Write or paste", shortcutHelp: "Write or paste a document") {
                toggleComposer(.write(category: filter.defaultAddCategory))
            }
            if filter.defaultAddCategory.hasMetrics || filter == .all {
                addChip(icon: "link", label: "From URL", shortcutHelp: "Transcribe an Instagram post") {
                    toggleComposer(.url(category: filter == .all ? .reel : filter.defaultAddCategory))
                }
            }
            addChip(icon: "doc.badge.plus", label: "Upload", shortcutHelp: "Import .pdf, .docx, or .txt files") {
                openFilePicker()
            }
            addChip(icon: "books.vertical", label: "From Library", shortcutHelp: "Reference a note or document from your library") {
                toggleComposer(.library)
            }
            if filter == .story || filter == .all {
                addChip(icon: "list.bullet.rectangle", label: "Guided story", shortcutHelp: "Answer 8 prompts to draft your brand story") {
                    showGuidedStory = true
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
    }

    private func toggleComposer(_ kind: ProfileComposerKind) {
        withAnimation(ProMotionSprings.gentle) {
            composer = composer == kind ? nil : kind
        }
    }

    private func addChip(icon: String, label: String, shortcutHelp: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(DS.caption)
            }
            .foregroundStyle(DS.accent)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background(DS.accentSoft, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(shortcutHelp)
    }

    // MARK: - File import

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ProfileDocumentImporter.allowedTypes

        let category = filter.defaultAddCategory
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in
                importFiles(panel.urls, category: category)
            }
        }
    }

    private func importDroppedFiles(_ urls: [URL]) -> Bool {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return false }
        importFiles(fileURLs, category: filter.defaultAddCategory)
        return true
    }

    private func importFiles(_ urls: [URL], category: ProfileDocumentCategory) {
        for url in urls {
            let content = ProfileDocumentImporter.extractText(from: url)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            withAnimation(ProMotionSprings.cardEntrance) {
                store.addDocument(ProfileDocument(
                    category: category,
                    title: url.deletingPathExtension().lastPathComponent,
                    content: content,
                    filename: url.lastPathComponent,
                    platform: category.platformTag
                ))
            }
        }
    }
}

// MARK: - Document Row

private struct ProfileDocumentRow: View {
    let document: ProfileDocument
    let showsCategory: Bool
    let isExpanded: Bool
    let transcriptionState: ProfileTranscriptionManager.TranscriptionState?
    let onToggleExpand: () -> Void
    let onContentEdit: (String) -> Void
    let onRemove: () -> Void

    @State private var isHovered = false
    @State private var draftContent = ""

    private var isTranscribing: Bool { transcriptionState?.isTranscribing == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsedRow
            if isExpanded {
                expandedEditor
            }
        }
        .background(isHovered && !isExpanded ? DS.surfaceHover : Color.clear)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }

    private var collapsedRow: some View {
        Button(action: {
            guard !isTranscribing else { return }
            draftContent = document.content
            onToggleExpand()
        }) {
            HStack(spacing: DS.space12) {
                sourceIcon
                rowText
                Spacer(minLength: DS.space8)
                trailing
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(document.title), \(document.category.displayName)")
        .help(isTranscribing ? "Transcribing…" : "Edit document")
    }

    private var sourceIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DS.entityContent)
            .frame(width: 28, height: 28)
            .background(DS.entityContent.opacity(0.1), in: .rect(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }

    private var iconName: String {
        if document.sourceURL != nil { return "link" }
        if document.sourceAtomUUID != nil { return "books.vertical" }
        if document.filename != nil { return "doc.text" }
        return "text.alignleft"
    }

    @ViewBuilder
    private var rowText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(document.title.isEmpty ? (document.filename ?? "Untitled") : document.title)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)

            if isTranscribing {
                Text(transcriptionState?.progressText ?? "Transcribing…")
                    .font(DS.footnote)
                    .foregroundStyle(DS.accent)
                    .contentTransition(.opacity)
            } else if let error = transcriptionState?.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.footnote)
                    .foregroundStyle(DS.orange)
                    .lineLimit(1)
            } else {
                metaLine
            }
        }
    }

    private var metaLine: some View {
        HStack(spacing: DS.space6) {
            if showsCategory {
                Text(document.category.displayName)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
            if !document.content.isEmpty {
                Text("\(document.content.count) chars")
                    .font(DS.footnote.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
            }
            if let warning = transcriptionState?.warning ?? document.warning {
                Label(warning, systemImage: "exclamationmark.circle")
                    .font(DS.footnote)
                    .foregroundStyle(DS.orange.opacity(0.9))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isTranscribing {
            ProgressView()
                .controlSize(.small)
        } else {
            if isHovered || isExpanded {
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.red.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove document")
                .accessibilityLabel("Remove \(document.title)")
                .transition(.opacity)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .accessibilityHidden(true)
        }
    }

    private var expandedEditor: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            if let sourceURL = document.sourceURL {
                Text(sourceURL)
                    .font(DS.footnote.monospaced())
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
            TextEditor(text: $draftContent)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120, maxHeight: 260)
                .padding(DS.space8)
                .dsGlassInput()
                .onChange(of: draftContent) { _, newValue in
                    onContentEdit(newValue)
                }
            HStack {
                Text("\(draftContent.count) characters")
                    .font(DS.footnote.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
                Spacer()
                Button("Done") { onToggleExpand() }
                    .font(DS.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.accent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Collapse editor (⌘↩)")
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.bottom, DS.space12)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Importer

enum ProfileDocumentImporter {
    static var allowedTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText]
        if let docx = UTType("org.openxmlformats.wordprocessingml.document") {
            types.append(docx)
        }
        return types
    }

    static func extractText(from url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let doc = PDFDocument(url: url) else { return "" }
            return (0..<doc.pageCount)
                .compactMap { doc.page(at: $0)?.string }
                .joined(separator: "\n")
        case "docx", "doc":
            return extractDocxText(from: url)
        default:
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
    }

    private static func extractDocxText(from url: URL) -> String {
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
            return xmlString
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        } catch {
            return ""
        }
    }
}
