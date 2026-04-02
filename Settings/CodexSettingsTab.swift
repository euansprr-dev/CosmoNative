// CosmoOS/Settings/CodexSettingsTab.swift
// Content Physics Codex — View, generate, and browse the Exemplar Codex
// Parses Opus synthesis output into navigable sections with sidebar + detail

import SwiftUI

// MARK: - Codex Section Model

struct CodexSection: Identifiable, Hashable {
    let id: String
    let title: String
    let category: String
    let body: String
    let icon: String

    static func parse(from text: String) -> [CodexSection] {
        var sections: [CodexSection] = []

        // Split on ═══ headers: "═══ CONCEPT_NAME (Category) ═══" or "═══ TITLE ═══"
        let pattern = /═{3,}\s*(.+?)\s*═{3,}/
        let parts = text.split(separator: pattern)
        let headers = text.matches(of: pattern)

        for (index, header) in headers.enumerated() {
            let titleRaw = String(header.output.1).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = index < parts.count - 1 ? String(parts[index + 1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if body.isEmpty { continue }

            // Parse "CONCEPT_NAME (Category)" format
            let categoryMatch = titleRaw.firstMatch(of: /^(.+?)\s*\((.+?)\)\s*$/)
            let title = categoryMatch.map { String($0.output.1) } ?? titleRaw
            let category = categoryMatch.map { String($0.output.2) } ?? classifySection(titleRaw)

            sections.append(CodexSection(
                id: "\(index)-\(title.prefix(20))",
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category.trimmingCharacters(in: .whitespacesAndNewlines),
                body: body,
                icon: iconForCategory(category)
            ))
        }

        return sections
    }

    private static func classifySection(_ title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("law") { return "Laws" }
        if lower.contains("interaction") { return "Interactions" }
        if lower.contains("deep structure") || lower.contains("e=mc") { return "Deep Structure" }
        if lower.contains("hypothesis") { return "Hypothesis Tests" }
        if lower.contains("voice") { return "Voice DNA" }
        if lower.contains("lexicon") { return "Lexicon" }
        return "Physics"
    }

    private static func iconForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case let c where c.contains("speech"): return "quote.bubble"
        case let c where c.contains("reader") || c.contains("delta"): return "brain.head.profile"
        case let c where c.contains("transition"): return "arrow.right.arrow.left"
        case let c where c.contains("proof"): return "checkmark.seal"
        case let c where c.contains("motiv"): return "flame"
        case let c where c.contains("compress"): return "arrow.down.right.and.arrow.up.left"
        case let c where c.contains("frame"): return "rectangle.3.group"
        case let c where c.contains("distance"): return "ruler"
        case let c where c.contains("technique"): return "wrench.and.screwdriver"
        case let c where c.contains("arc"): return "chart.line.uptrend.xyaxis"
        case let c where c.contains("dominant"): return "star"
        case let c where c.contains("symmetry") || c.contains("phase") || c.contains("gravity") || c.contains("energy"): return "bolt.fill"
        case let c where c.contains("long") || c.contains("bond") || c.contains("echo") || c.contains("entangle"): return "link"
        case let c where c.contains("rhythm") || c.contains("pacing"): return "waveform"
        case let c where c.contains("reader sim") || c.contains("simulation"): return "person.crop.rectangle"
        case let c where c.contains("antimatter"): return "xmark.octagon"
        case let c where c.contains("reson"): return "antenna.radiowaves.left.and.right"
        case let c where c.contains("fabric") || c.contains("synth"): return "sparkles"
        case let c where c.contains("law"): return "book.closed"
        case let c where c.contains("interact"): return "arrow.triangle.branch"
        case let c where c.contains("deep") || c.contains("structure"): return "atom"
        case let c where c.contains("hypothesis"): return "flask"
        case let c where c.contains("voice"): return "mic"
        case let c where c.contains("lexicon"): return "character.book.closed"
        default: return "circle.fill"
        }
    }
}

// MARK: - View Model

@Observable
final class CodexViewModel {
    var codexText: String = ""
    var sections: [CodexSection] = []
    var selectedSection: CodexSection?
    var isGenerating = false
    var progress: String = ""
    var lastGenerated: String = ""
    var error: String?
    var extractionStats: ExtractionStats?
    var searchQuery: String = ""
    var showCopied: Bool = false

    struct ExtractionStats {
        let total: Int
        let extracted: Int
        let skipped: Int
        let failed: Int
    }

    var filteredSections: [CodexSection] {
        if searchQuery.isEmpty { return sections }
        let q = searchQuery.lowercased()
        return sections.filter {
            $0.title.lowercased().contains(q) ||
            $0.category.lowercased().contains(q) ||
            $0.body.lowercased().contains(q)
        }
    }

    func loadExistingCodex() async {
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .research)
            if let exemplar = atoms.first(where: { $0.metadataDict?["isCodexSynthesis"] as? Bool == true }) {
                codexText = exemplar.body ?? ""
                lastGenerated = exemplar.metadataDict?["updatedAt"] as? String ?? exemplar.updatedAt
            } else if let codexAtom = atoms.first(where: { $0.metadataDict?["isCodex"] as? Bool == true }) {
                codexText = codexAtom.body ?? ""
                lastGenerated = codexAtom.metadataDict?["updatedAt"] as? String ?? codexAtom.updatedAt
            }

            if !codexText.isEmpty {
                sections = CodexSection.parse(from: codexText)
                if selectedSection == nil { selectedSection = sections.first }
            }
        } catch {
            print("Failed to load codex: \(error)")
        }
    }

    private static let cloudBaseURL = "https://cosmonative-production.up.railway.app"

    func generateCodex(reExtractAll: Bool = false, skipExtraction: Bool = false, pass2Only: Bool = false, pass3Only: Bool = false) async {
        isGenerating = true
        progress = pass3Only ? "Unifying Content Physics language (Pass 3)..." : pass2Only ? "Deepening existing Codex (Pass 2)..." : skipExtraction ? "Preparing synthesis..." : reExtractAll ? "Re-extracting all swipes..." : "Extracting unanalyzed swipes..."
        error = nil

        do {
            let startURL = URL(string: "\(Self.cloudBaseURL)/api/writing/codex/generate")!
            var startRequest = URLRequest(url: startURL)
            startRequest.httpMethod = "POST"
            startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            startRequest.httpBody = try JSONSerialization.data(withJSONObject: ["reExtractAll": reExtractAll, "skipExtraction": skipExtraction, "pass2Only": pass2Only, "pass3Only": pass3Only])
            startRequest.timeoutInterval = 30

            let (_, startResponse) = try await URLSession.shared.data(for: startRequest)
            guard (startResponse as? HTTPURLResponse)?.statusCode == 200 else {
                error = "Failed to start pipeline"
                isGenerating = false
                return
            }

            let progressURL = URL(string: "\(Self.cloudBaseURL)/api/writing/codex/progress")!
            while true {
                try await Task.sleep(for: .seconds(5))
                var progressRequest = URLRequest(url: progressURL)
                progressRequest.httpMethod = "GET"
                progressRequest.timeoutInterval = 10

                let (data, _) = try await URLSession.shared.data(for: progressRequest)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let status = json["status"] as? String ?? "unknown"
                    let phase = json["phase"] as? String ?? ""
                    let extracted = json["extracted"] as? Int ?? 0
                    let skipped = json["skipped"] as? Int ?? 0
                    let failed = json["failed"] as? Int ?? 0
                    let total = json["total"] as? Int ?? 0

                    progress = phase
                    extractionStats = ExtractionStats(total: total, extracted: extracted, skipped: skipped, failed: failed)

                    if status == "complete" {
                        progress = "Codex complete! Loading..."
                        try? await Task.sleep(for: .seconds(3))
                        await loadExistingCodex()
                        lastGenerated = Date().formatted(date: .abbreviated, time: .shortened)
                        break
                    } else if status == "failed" {
                        self.error = json["error"] as? String ?? "Pipeline failed"
                        break
                    }
                }
            }
        } catch {
            self.error = error.localizedDescription
        }

        isGenerating = false
        progress = ""
    }
}

// MARK: - Main View

struct CodexSettingsTab: View {
    @State private var viewModel = CodexViewModel()
    @State private var showReExtractConfirmation = false
    @State private var showRawText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            codexHeader
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider().foregroundStyle(DS.borderSubtle)

            if viewModel.isGenerating {
                generatingSection
            } else if viewModel.sections.isEmpty {
                emptySection
            } else {
                codexBrowser
            }
        }
        .task {
            await viewModel.loadExistingCodex()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var codexHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "atom")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Content Physics Codex")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.text)

                if !viewModel.lastGenerated.isEmpty {
                    Text("Generated \(viewModel.lastGenerated) · \(viewModel.sections.count) sections")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textMuted)
                }
            }

            Spacer()

            if let error = viewModel.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.red)
                    .lineLimit(1)
                    .frame(maxWidth: 200)
            }

            if !viewModel.sections.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.codexText, forType: .string)
                    viewModel.showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        viewModel.showCopied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        if viewModel.showCopied {
                            Text("Copied!")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.showCopied ? DS.accent : DS.textSecondary)
                .help("Copy full Codex to clipboard")

                Button {
                    showRawText.toggle()
                } label: {
                    Image(systemName: showRawText ? "rectangle.split.2x1" : "doc.plaintext")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.textSecondary)
                .help(showRawText ? "Section view" : "Raw text")
            }

            generateButtonCompact
        }
    }

    @ViewBuilder
    private var generateButtonCompact: some View {
        Menu {
            Button {
                Task { await viewModel.generateCodex() }
            } label: {
                Label("Extract + Synthesize", systemImage: "sparkles")
            }

            Button {
                Task { await viewModel.generateCodex(skipExtraction: true) }
            } label: {
                Label("Synthesize Only (skip extraction)", systemImage: "atom")
            }

            Button {
                Task { await viewModel.generateCodex(skipExtraction: true, pass2Only: true) }
            } label: {
                Label("Deepen Existing Codex (Pass 2)", systemImage: "arrow.down.to.line")
            }

            Button {
                Task { await viewModel.generateCodex(skipExtraction: true, pass3Only: true) }
            } label: {
                Label("Unify Language (Pass 3)", systemImage: "tablecells")
            }

            Divider()

            Button {
                showReExtractConfirmation = true
            } label: {
                Label("Re-extract All Swipes", systemImage: "arrow.clockwise")
            }
        } label: {
            Label("Generate", systemImage: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(.white)
                .background(DS.accent, in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(viewModel.isGenerating)
        .confirmationDialog("Re-extract all swipes?", isPresented: $showReExtractConfirmation) {
            Button("Re-extract All", role: .destructive) {
                Task { await viewModel.generateCodex(reExtractAll: true) }
            }
        } message: {
            Text("This will re-analyze every swipe with Opus 4.6, even those already extracted.")
        }
    }

    // MARK: - Generating State

    @ViewBuilder
    private var generatingSection: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .scaleEffect(1.2)

            Text(viewModel.progress)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if let stats = viewModel.extractionStats, stats.total > 0 {
                HStack(spacing: 16) {
                    statPill("Extracted", value: stats.extracted, color: DS.green)
                    statPill("Skipped", value: stats.skipped, color: DS.textMuted)
                    if stats.failed > 0 {
                        statPill("Failed", value: stats.failed, color: DS.red)
                    }
                }

                ProgressView(value: Double(stats.extracted + stats.skipped + stats.failed), total: Double(max(stats.total, 1)))
                    .tint(DS.accent)
                    .frame(maxWidth: 300)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptySection: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "atom")
                .font(.system(size: 36))
                .foregroundStyle(DS.textMuted.opacity(0.5))

            Text("No Codex Generated Yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.text)

            Text("Generate the Exemplar Codex to discover the complete language of viral content from your swipe library. Every physics concept with real examples from proven posts.")
                .font(.system(size: 12))
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Button {
                Task { await viewModel.generateCodex() }
            } label: {
                Label("Generate Exemplar Codex", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(DS.accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Codex Browser (Sidebar + Detail)

    @ViewBuilder
    private var codexBrowser: some View {
        if showRawText {
            rawTextView
        } else {
            HStack(spacing: 0) {
                codexSidebar
                    .frame(width: 240)

                Divider().foregroundStyle(DS.borderSubtle)

                codexDetail
            }
        }
    }

    @ViewBuilder
    private var codexSidebar: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.textMuted)
                TextField("Search sections...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().foregroundStyle(DS.borderSubtle)

            // Section list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.filteredSections) { section in
                        sidebarRow(section)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            }
        }
        .background(DS.surfaceElevated)
    }

    @ViewBuilder
    private func sidebarRow(_ section: CodexSection) -> some View {
        let isSelected = viewModel.selectedSection == section

        Button {
            viewModel.selectedSection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? DS.accent : DS.textMuted)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
                        .lineLimit(1)

                    Text(section.category)
                        .font(.system(size: 9))
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isSelected ? DS.accent.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var codexDetail: some View {
        if let section = viewModel.selectedSection {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Section header
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(DS.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DS.text)

                            Text(section.category)
                                .font(.system(size: 11))
                                .foregroundStyle(DS.textMuted)
                        }
                    }
                    .padding(.bottom, 4)

                    // Section body — rendered as styled text
                    codexBodyView(section.body)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(DS.bg)
        } else {
            VStack {
                Spacer()
                Text("Select a section")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.textMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(DS.bg)
        }
    }

    @ViewBuilder
    private func codexBodyView(_ text: String) -> some View {
        let blocks = parseBodyBlocks(text)

        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
            switch block {
            case .heading(let text):
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .padding(.top, 8)

            case .example(let number, let slideText, let metadata):
                exampleCard(number: number, slideText: slideText, metadata: metadata)

            case .paragraph(let text):
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textSecondary)
                    .textSelection(.enabled)
                    .lineSpacing(4)

            case .pattern(let text):
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(DS.accent)
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textSecondary)
                        .textSelection(.enabled)
                }

            case .antiPattern(let text):
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DS.red)
                        .padding(.top, 4)
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textMuted)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func exampleCard(number: Int, slideText: String, metadata: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(DS.accent)
                    .frame(width: 20)

                Text(slideText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.text)
                    .textSelection(.enabled)
                    .lineSpacing(3)
            }

            if !metadata.isEmpty {
                Text(metadata)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textMuted)
                    .textSelection(.enabled)
                    .padding(.leading, 28)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - Raw Text Fallback

    @ViewBuilder
    private var rawTextView: some View {
        ScrollView {
            Text(viewModel.codexText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DS.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .background(DS.surface)
    }

    // MARK: - Body Block Parser

    private enum BodyBlock {
        case heading(String)
        case example(Int, String, String)
        case paragraph(String)
        case pattern(String)
        case antiPattern(String)
    }

    private func parseBodyBlocks(_ text: String) -> [BodyBlock] {
        var blocks: [BodyBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines
            if line.isEmpty { i += 1; continue }

            // Heading: DEFINITION:, FREQUENCY:, EXAMPLES:, PATTERNS:, ANTI-PATTERNS:, etc.
            if line.hasSuffix(":") && line == line.uppercased() && line.count < 40 {
                blocks.append(.heading(line.replacingOccurrences(of: ":", with: "")))
                i += 1; continue
            }

            // Numbered example: starts with "1.", "2.", etc.
            if let match = line.firstMatch(of: /^(\d+)\.\s+"(.+)/) {
                let number = Int(match.output.1) ?? 0
                var slideText = String(match.output.2)
                // May continue on next line
                if slideText.hasSuffix("\"") { slideText = String(slideText.dropLast()) }

                // Collect metadata lines (indented, starting with —, Mechanism:, Produces:, etc.)
                var metadata: [String] = []
                i += 1
                while i < lines.count {
                    let nextLine = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                    if nextLine.isEmpty || (!nextLine.hasPrefix("—") && !nextLine.hasPrefix("Mechanism:") && !nextLine.hasPrefix("Produces:") && !nextLine.hasPrefix("Techniques:") && !nextLine.hasPrefix("HOW") && !nextLine.hasPrefix("[") && !nextLine.hasPrefix("Bridge") && !nextLine.hasPrefix("Connector") && !nextLine.hasPrefix("Double")) {
                        break
                    }
                    metadata.append(nextLine)
                    i += 1
                }
                blocks.append(.example(number, slideText, metadata.joined(separator: "\n")))
                continue
            }

            // Pattern bullet: starts with "- "
            if line.hasPrefix("- ") {
                let content = String(line.dropFirst(2))
                // Check if this is in an anti-patterns section
                if blocks.last.map({ if case .heading(let h) = $0, h.contains("ANTI") { return true } else { return false } }) == true {
                    blocks.append(.antiPattern(content))
                } else {
                    blocks.append(.pattern(content))
                }
                i += 1; continue
            }

            // Default: paragraph
            blocks.append(.paragraph(line))
            i += 1
        }

        return blocks
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statPill(_ label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(value)").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(DS.text)
            Text(label).font(.system(size: 10)).foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 6))
    }
}
