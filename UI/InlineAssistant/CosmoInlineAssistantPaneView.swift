import SwiftUI

enum CosmoInlineAssistantPaneProgressPolicy {
    static func shouldShow(
        isProcessing: Bool,
        statusText: String?,
        hasStreamingAnswer: Bool = false,
        hasLiveSteps: Bool = false
    ) -> Bool {
        guard isProcessing, !hasStreamingAnswer else { return false }
        if hasLiveSteps { return true }
        let trimmed = statusText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty
    }

    static func statusLabel(isProcessing: Bool, statusText: String?) -> String {
        guard isProcessing else { return "" }
        let trimmed = statusText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Reading current context" : trimmed
    }
}

/// The assistant pane: a reading surface, not a chat app. Assistant answers are
/// the hero — plain prose on the page with no card chrome. User prompts and
/// staged proposals are quiet, warm-filled cards; the thinking row narrates the
/// phase in Cosmo's own voice; the composer stays out of the way until focused.
struct CosmoInlineAssistantPaneView: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CosmoInlineAssistantPaneHeader(store: store, onClose: onClose)
            CosmoInlineAssistantPaneMessages(store: store)
            CosmoInlineAssistantPaneFollowUps(store: store)
            CosmoInlineAssistantPaneComposer(store: store)
        }
        .background(DS.bg)
    }
}

// MARK: - Header

private struct CosmoInlineAssistantPaneHeader: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let onClose: () -> Void

    @State private var isCloseHovered = false

    var body: some View {
        HStack(spacing: DS.space8) {
            orb
            titleBlock
            Spacer()
            closeButton
        }
        .padding(.horizontal, DS.space16)
        .frame(height: 52)
    }

    /// The orb wears the phase — same symbol vocabulary as the floating bar.
    private var orb: some View {
        Image(systemName: store.phase.symbolName)
            .font(DS.caption.weight(.semibold))
            .foregroundStyle(store.phase.isWorking ? DS.accent : DS.textSecondary)
            .frame(width: 26, height: 26)
            .background(store.phase.isWorking ? AnyShapeStyle(DS.accentSoft) : AnyShapeStyle(Color.clear), in: Circle())
            .symbolEffect(.pulse, options: .repeating, isActive: store.phase.isWorking)
            .contentTransition(.symbolEffect(.replace))
            .animation(ProMotionSprings.snappy, value: store.phase.symbolName)
            .accessibilityHidden(true)
    }

    /// "Cosmo" plus the scope pill — the pane always SHOWS what "this
    /// document" means. Visible context truth.
    private var titleBlock: some View {
        HStack(spacing: DS.space10) {
            Text("Cosmo")
                .font(DS.headline)
                .foregroundStyle(DS.text)

            CosmoScopePill(
                title: store.activeSurfaceTitle,
                entity: store.activeSurfaceEntity
            )
        }
        .animation(ProMotionSprings.gentle, value: store.activeSurfaceTitle)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(isCloseHovered ? DS.text : DS.textMuted)
                .frame(width: 28, height: 28)
                .background(isCloseHovered ? AnyShapeStyle(DS.surfaceHover) : AnyShapeStyle(Color.clear), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .cosmoClickCursor()
        .onHover { hovering in
            withAnimation(ProMotionSprings.snappy) { isCloseHovered = hovering }
        }
        .keyboardShortcut(.escape, modifiers: [])
        .help("Close assistant pane (Esc)")
        .accessibilityLabel("Close assistant pane")
    }
}

// MARK: - Scope pill

/// The pane's name tag for what Cosmo is looking at — the iOS CosmoContextPill
/// grammar (a real glass capsule, semibold title, muted kind subtitle), no
/// ornament. One component for the header and the empty state.
struct CosmoScopePill: View {
    let title: String?
    let entity: String?

    var body: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: entityIcon)
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(title == nil ? DS.textMuted : DS.textSecondary)
                .accessibilityHidden(true)

            if let title {
                Text(title)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Text(entityLabel)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            } else {
                Text("nothing in focus")
                    .font(DS.caption)
                    .italic()
                    .foregroundStyle(DS.textMuted)
            }
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space4)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: 280, alignment: .leading)
        .fixedSize()
        .help(title == nil
            ? "Open a document or thinkspace to scope Cosmo"
            : "Cosmo is scoped to this")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title.map { "Cosmo is scoped to \($0)" } ?? "Nothing in focus")
    }

    private var entityIcon: String {
        switch entity {
        case "content": return "doc.text"
        case "note": return "note.text"
        case "idea": return "lightbulb"
        case "connection": return "point.3.connected.trianglepath.dotted"
        case "thinkspace": return "square.grid.2x2"
        default: return "scope"
        }
    }

    private var entityLabel: String {
        switch entity {
        case "content": return "Draft"
        case "note": return "Note"
        case "idea": return "Idea"
        case "connection": return "Concept"
        case "thinkspace": return "Thinkspace"
        default: return "Document"
        }
    }
}

// MARK: - Follow-up chips

/// Contextual quick replies after a run — one tap prefills and sends. The
/// cadence of a colleague asking "want me to keep going?" without the typing.
private struct CosmoInlineAssistantPaneFollowUps: View {
    @ObservedObject var store: CosmoInlineAssistantStore

    var body: some View {
        if !store.followUpSuggestions.isEmpty, !store.isProcessing {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.space6) {
                    ForEach(store.followUpSuggestions, id: \.self) { suggestion in
                        FollowUpChip(label: suggestion) {
                            store.followUpSuggestions = []
                            store.submitPrompt(suggestion)
                        }
                    }
                }
                .padding(.horizontal, DS.space16)
            }
            .padding(.vertical, DS.space6)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private struct FollowUpChip: View {
        let label: String
        let action: () -> Void

        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                Text(label)
                    .font(DS.caption)
                    .foregroundStyle(isHovered ? DS.text : DS.textSecondary)
                    .padding(.horizontal, DS.space10)
                    .padding(.vertical, DS.space6)
                    .background(
                        isHovered ? AnyShapeStyle(DS.glassCardFill) : AnyShapeStyle(.clear),
                        in: Capsule(style: .continuous)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(DS.glassBorder, lineWidth: 0.5)
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .onHover { hovering in
                withAnimation(ProMotionSprings.hover) { isHovered = hovering }
            }
            .accessibilityLabel("Send follow-up: \(label)")
        }
    }
}

// MARK: - Messages

/// Resolves skill IDs to definitions once and remembers the answer — registry
/// lookups read GRDB, and message rows re-render on every streamed delta.
@MainActor
final class CosmoInlineSkillResolver {
    private var cache: [String: CosmoInlineSkillDefinition?] = [:]
    private let registry = CosmoInlineSkillRegistry()

    func skill(id: String?) -> CosmoInlineSkillDefinition? {
        guard let id else { return nil }
        if let cached = cache[id] { return cached }
        let resolved = registry.skill(id: id)
        cache[id] = resolved
        return resolved
    }
}

private struct CosmoInlineAssistantPaneMessages: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    @State private var skillResolver = CosmoInlineSkillResolver()

    private static let bottomAnchorID = "pane-bottom-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                Color.clear
                    .frame(height: 1)
                    .id(Self.bottomAnchorID)
            }
            .onChange(of: store.paneMessages.count) {
                withAnimation(ProMotionSprings.gentle) {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
            .onChange(of: store.paneMessages.last?.content) {
                // Streaming growth: follow without animating every token.
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
            .onChange(of: store.isProcessing) {
                withAnimation(ProMotionSprings.gentle) {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.paneMessages.isEmpty,
           !shouldShowProgress {
            CosmoInlineAssistantPaneEmptyState(store: store)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(DS.space16)
        } else {
            conversation
        }
    }

    private var conversation: some View {
        LazyVStack(alignment: .leading, spacing: DS.space12) {
            ForEach(store.paneMessages) { message in
                messageRow(message)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if shouldShowProgress {
                CosmoInlineAssistantActivityTimelineView(
                    steps: store.currentRunSteps,
                    phase: store.phase
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(DS.space16)
        .animation(ProMotionSprings.gentle, value: store.paneMessages.count)
        .animation(ProMotionSprings.gentle, value: store.isProcessing)
    }

    private var shouldShowProgress: Bool {
        CosmoInlineAssistantPaneProgressPolicy.shouldShow(
            isProcessing: store.isProcessing,
            statusText: store.statusText,
            hasStreamingAnswer: store.streamingPaneMessageID != nil,
            hasLiveSteps: !store.currentRunSteps.isEmpty
        )
    }

    @ViewBuilder
    private func messageRow(_ message: CosmoInlineAssistantPaneMessage) -> some View {
        if let proposalID = message.proposalID,
           let proposal = store.proposal(id: proposalID) {
            CosmoInlineAssistantPaneProposalCard(store: store, proposal: proposal)
        } else if let inquiryProposalID = message.inquiryProposalID,
                  let inquiryProposal = store.inquiryProposal(id: inquiryProposalID) {
            CosmoInlineAssistantPaneInquiryCard(store: store, proposal: inquiryProposal)
        } else if let canvasPlanID = message.canvasPlanID,
                  let plan = store.canvasPlan(id: canvasPlanID) {
            CosmoInlineAssistantPaneCanvasPlanCard(store: store, plan: plan)
        } else {
            switch message.role {
            case .user:
                CosmoInlineAssistantPaneUserRow(
                    message: message,
                    skill: skillResolver.skill(id: message.skillID)
                )
            case .assistant:
                CosmoInlineAssistantPaneAnswerRow(
                    message: message,
                    isStreaming: store.isStreamingMessage(message.id),
                    streamingRefs: store.isStreamingMessage(message.id) ? store.currentStreamingSourceRefs : []
                )
            case .system:
                CosmoInlineAssistantPaneSectionLabel(text: message.content)
            }
        }
    }
}

// MARK: - Message rows

/// User prompts: a compact, warm chip — quiet context, never the hero. Runs
/// handled by a skill wear it as a small route-tinted badge.
private struct CosmoInlineAssistantPaneUserRow: View {
    let message: CosmoInlineAssistantPaneMessage
    var skill: CosmoInlineSkillDefinition? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            if let skill {
                CosmoInlineAssistantSkillBadge(skill: skill)
            }

            Text(message.content)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space8)
                .background(DS.accentSoft, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(DS.accent.opacity(0.14), lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let skill {
            return "You asked with \(skill.name): \(message.content)"
        }
        return "You asked: \(message.content)"
    }
}

/// The skill a run wore: icon + name + route, tinted by what it does (edits
/// stage green, answers open blue) — same vocabulary as the slash menu.
struct CosmoInlineAssistantSkillBadge: View {
    let skill: CosmoInlineSkillDefinition

    private var tint: Color {
        skill.route == .action ? DS.green : DS.info
    }

    var body: some View {
        HStack(spacing: DS.space4) {
            Image(systemName: skill.icon)
                .font(DS.caption2.weight(.semibold))
                .accessibilityHidden(true)
            Text(skill.name)
                .font(DS.caption2.weight(.semibold))
                .lineLimit(1)
            Text(skill.route == .action ? "· Edits" : "· Answers")
                .font(DS.caption2.weight(.medium))
                .opacity(0.7)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DS.space8)
        .frame(height: 20)
        .background(tint.opacity(0.10), in: Capsule())
        .accessibilityLabel("Skill: \(skill.name), \(skill.route == .action ? "stages edits" : "answers")")
    }
}

/// Assistant answers: the hero. Plain prose on the page — no card, no border —
/// with its work receipt above, inline document pills in the prose, and any
/// sources it didn't cite inline as a quiet "Also read" row underneath.
private struct CosmoInlineAssistantPaneAnswerRow: View {
    let message: CosmoInlineAssistantPaneMessage
    let isStreaming: Bool
    var streamingRefs: [CosmoAssistantSourceRef] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            if let steps = message.activitySteps, !steps.isEmpty {
                CosmoInlineAssistantActivityReceiptView(
                    steps: steps,
                    sourceCount: message.sourceRefs?.count ?? 0
                )
            }

            answerBody
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var answerBody: some View {
        if isStreaming {
            streamingText
        } else {
            CosmoInlineAssistantFinalizedAnswerBody(message: message)
                // The streaming→rich swap must not animate — same font,
                // spacing, and measure on both sides keeps it invisible.
                .transaction { $0.animation = nil }
        }
    }

    private var streamingText: some View {
        Text(CosmoAssistantProseParser.streamingDisplayText(for: message.content, sourceRefs: streamingRefs))
            .font(DS.body)
            .foregroundStyle(DS.text)
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: CosmoAssistantProseTextView.readingMeasure, alignment: .leading)
    }
}

/// Finalized answers parse once into prose + pills; the TextKit view renders
/// pills with the composer's own pill cell, so citations read as mentions.
private struct CosmoInlineAssistantFinalizedAnswerBody: View {
    let message: CosmoInlineAssistantPaneMessage

    private var parsed: CosmoAssistantProseParseResult {
        CosmoAssistantProseParser.parse(answer: message.content, sourceRefs: message.sourceRefs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            if CosmoInlineAssistantMarkdownParser.shouldRenderAsMarkdown(message.content) {
                CosmoInlineAssistantMarkdownAnswerView(content: message.content)

                if let refs = message.sourceRefs, !refs.isEmpty {
                    CosmoInlineAssistantSourceChips(refs: refs, label: "Sources")
                }
            } else {
                let result = parsed
                CosmoAssistantProseTextView(segments: result.segments)
                    .frame(maxWidth: CosmoAssistantProseTextView.readingMeasure, alignment: .leading)

                let remainder = (message.sourceRefs ?? []).filter { !result.linkedRefUUIDs.contains($0.uuid) }
                if !remainder.isEmpty {
                    CosmoInlineAssistantSourceChips(
                        refs: remainder,
                        label: result.linkedRefUUIDs.isEmpty ? "Sources" : "Also read"
                    )
                }
            }
        }
    }
}

enum CosmoInlineAssistantMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet([String])
    case ordered([String])
    case quote(String)
    case code(String)
    case receipt(String)
}

enum CosmoInlineAssistantMarkdownParser {
    static func shouldRenderAsMarkdown(_ content: String) -> Bool {
        parse(content).contains { block in
            switch block {
            case .heading, .bullet, .ordered, .quote, .code, .receipt:
                return true
            case .paragraph:
                return false
            }
        }
    }

    static func parse(_ content: String) -> [CosmoInlineAssistantMarkdownBlock] {
        let lines = content.components(separatedBy: .newlines)
        var blocks: [CosmoInlineAssistantMarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                index += 1
                var codeLines: [String] = []
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(codeLines.joined(separator: "\n")))
                continue
            }

            if let receipt = receipt(from: trimmed) {
                blocks.append(.receipt(receipt))
                index += 1
                continue
            }

            if let heading = heading(from: trimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quoteLine.hasPrefix(">") else { break }
                    quoteLines.append(String(quoteLine.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            if let firstItem = bulletItem(from: trimmed) {
                var items = [firstItem]
                index += 1
                while index < lines.count, let item = bulletItem(from: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.bullet(items))
                continue
            }

            if let firstItem = orderedItem(from: trimmed) {
                var items = [firstItem]
                index += 1
                while index < lines.count, let item = orderedItem(from: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.ordered(items))
                continue
            }

            var paragraphLines = [line]
            index += 1
            while index < lines.count {
                let nextTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty || isSpecialLine(nextTrimmed) { break }
                paragraphLines.append(lines[index])
                index += 1
            }
            blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
        }

        return blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        if line.hasPrefix("### ") { return (3, String(line.dropFirst(4))) }
        if line.hasPrefix("## ") { return (2, String(line.dropFirst(3))) }
        if line.hasPrefix("# ") { return (1, String(line.dropFirst(2))) }
        return nil
    }

    private static func receipt(from line: String) -> String? {
        guard line.hasPrefix("_"), line.hasSuffix("_"), line.count > 2 else { return nil }
        let value = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.contains(" out") || value.contains(" cached") ? value : nil
    }

    private static func bulletItem(from line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return String(line.dropFirst(2))
        }
        return nil
    }

    private static func orderedItem(from line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let numberPart = line[..<dotIndex]
        guard !numberPart.isEmpty, numberPart.allSatisfy(\.isNumber) else { return nil }
        let remainder = line[line.index(after: dotIndex)...]
        guard remainder.first == " " else { return nil }
        return String(remainder.dropFirst())
    }

    private static func isSpecialLine(_ line: String) -> Bool {
        line.hasPrefix("```")
            || receipt(from: line) != nil
            || heading(from: line) != nil
            || line.hasPrefix(">")
            || bulletItem(from: line) != nil
            || orderedItem(from: line) != nil
    }
}

private struct CosmoInlineAssistantMarkdownAnswerView: View {
    let content: String

    private var blocks: [CosmoInlineAssistantMarkdownBlock] {
        CosmoInlineAssistantMarkdownParser.parse(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                CosmoInlineAssistantMarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: CosmoAssistantProseTextView.readingMeasure, alignment: .leading)
        .textSelection(.enabled)
    }
}

private struct CosmoInlineAssistantMarkdownBlockView: View {
    let block: CosmoInlineAssistantMarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(.init(text))
                .font(headingFont(level: level))
                .foregroundStyle(DS.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, level == 3 ? DS.space2 : DS.space4)
        case .paragraph(let text):
            Text(.init(text))
                .font(DS.body)
                .foregroundStyle(paragraphStyle(for: text))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: DS.space6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
                        Circle()
                            .fill(DS.accent)
                            .frame(width: 5, height: 5)
                        Text(.init(item))
                            .font(DS.body)
                            .foregroundStyle(DS.text)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .ordered(let items):
            VStack(alignment: .leading, spacing: DS.space6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: DS.space8) {
                        Text("\(index + 1).")
                            .font(DS.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(DS.accent)
                            .frame(width: 22, alignment: .trailing)
                        Text(.init(item))
                            .font(DS.body)
                            .foregroundStyle(DS.text)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: DS.space10) {
                Capsule()
                    .fill(DS.accent.opacity(0.45))
                    .frame(width: 3)
                Text(.init(text))
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space10)
            .background(DS.glassSectionFill, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DS.glassBorder.opacity(0.7), lineWidth: 1)
            }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(DS.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.space12)
            }
            .background(DS.glassSectionFill, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DS.glassBorder.opacity(0.7), lineWidth: 1)
            }
        case .receipt(let text):
            Text(text)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .monospacedDigit()
                .padding(.top, DS.space2)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            DS.title2
        case 2:
            DS.title3.weight(.semibold)
        default:
            DS.headline
        }
    }

    private func paragraphStyle(for text: String) -> Color {
        text.hasPrefix("Current:") ? DS.textSecondary : DS.text
    }
}

/// System titles ("What I changed", skill names): small-caps section labels.
private struct CosmoInlineAssistantPaneSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.caption.weight(.semibold))
            .foregroundStyle(DS.textMuted)
            .textCase(.uppercase)
            .kerning(0.4)
            .padding(.top, DS.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Source chips

/// Clickable chips for the sources Cosmo actually read — every answer carries
/// its receipts, and a click opens the atom for verification.
private struct CosmoInlineAssistantSourceChips: View {
    let refs: [CosmoAssistantSourceRef]
    var label = "Sources"

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text(label)
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .textCase(.uppercase)
                .kerning(0.4)

            FlexibleChipRows(refs: refs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label): \(refs.map(\.title).joined(separator: ", "))")
    }
}

private struct FlexibleChipRows: View {
    let refs: [CosmoAssistantSourceRef]

    var body: some View {
        // Simple wrapping via vertical stacking of pairs keeps the layout cheap;
        // chips are short and the pane is narrow.
        let rows = stride(from: 0, to: refs.count, by: 2).map { index in
            Array(refs[index..<min(index + 2, refs.count)])
        }
        VStack(alignment: .leading, spacing: DS.space4) {
            ForEach(rows, id: \.first?.uuid) { row in
                HStack(spacing: DS.space4) {
                    ForEach(row) { ref in
                        SourceChip(ref: ref)
                    }
                }
            }
        }
    }
}

private struct SourceChip: View {
    let ref: CosmoAssistantSourceRef

    @State private var isHovered = false

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": ref.uuid, "asPane": true]
            )
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: ref.icon)
                    .font(DS.caption2)
                    .accessibilityHidden(true)
                Text(ref.title.isEmpty ? "Untitled" : ref.title)
                    .font(DS.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isHovered ? DS.accent : DS.textSecondary)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(isHovered ? AnyShapeStyle(DS.accentSoft) : AnyShapeStyle(DS.surface), in: Capsule())
            .overlay {
                Capsule().strokeBorder(isHovered ? DS.accent.opacity(0.3) : DS.borderSubtle, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .cosmoClickCursor()
        .onHover { hovering in
            withAnimation(ProMotionSprings.snappy) { isHovered = hovering }
        }
        .help("Open \(ref.title)")
        .accessibilityLabel("Open source: \(ref.title)")
    }
}

// MARK: - Proposal card

/// Maps a proposal's surface onto the entity tint vocabulary so the card wears
/// the color of the document it edits, like every other chip in the app.
enum CosmoInlineAssistantSurfaceTint {
    static func color(forSurfaceID surfaceID: String) -> Color {
        let prefix = surfaceID.split(separator: ":").first.map(String.init) ?? ""
        let entity: EntityType
        switch prefix {
        case "note": entity = .note
        case "idea": entity = .idea
        case "content", "slide": entity = .content
        case "connection": entity = .connection
        case "canvas", "thinkspace": entity = .thinkspace
        case "research": entity = .research
        default: return DS.accent
        }
        return CosmoMentionColors.color(for: entity)
    }
}

private struct CosmoInlineAssistantPaneProposalCard: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let proposal: CosmoAssistantProposal
    @State private var isReviewExpanded = false

    private var surfaceTint: Color {
        CosmoInlineAssistantSurfaceTint.color(forSurfaceID: proposal.surfaceID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DS.borderSubtle)
            operationList
            if proposal.hasReviewableOperations {
                Divider().overlay(DS.borderSubtle)
                decisionBar
            }
            if isReviewExpanded {
                Divider().overlay(DS.borderSubtle)
                expandedDiff
            }
        }
        .background(DS.surfaceCard, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(DS.borderSubtle, lineWidth: 1)
        }
        .animation(ProMotionSprings.focusTransition, value: isReviewExpanded)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DS.space12) {
            Image(systemName: "text.badge.checkmark")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(surfaceTint)
                .frame(width: 32, height: 32)
                .background(surfaceTint.opacity(0.12), in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.title.isEmpty ? "Staged edits" : proposal.title)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                HStack(spacing: DS.space6) {
                    Text("+\(proposal.addedHunkCount)")
                        .foregroundStyle(DS.green)
                    Text("−\(proposal.removedHunkCount)")
                        .foregroundStyle(DS.red)
                    Text(proposal.operationStatusSummary)
                        .foregroundStyle(DS.textMuted)
                }
                .font(DS.caption.weight(.medium))
                .monospacedDigit()
            }

            Spacer()

            if proposal.hasRevertableOperations {
                CosmoPanePillButton(label: "Undo", icon: "arrow.uturn.backward", help: "Revert applied changes") {
                    Task { await store.revertAll(proposalID: proposal.id) }
                }
            }

            CosmoPanePillButton(
                label: isReviewExpanded ? "Hide" : "Review",
                icon: nil,
                help: isReviewExpanded ? "Collapse the diff" : "Show the full diff"
            ) {
                isReviewExpanded.toggle()
            }
        }
        .padding(DS.space12)
    }

    private var operationList: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ForEach(proposal.operations) { operation in
                CosmoInlineAssistantPaneOperationRow(store: store, operation: operation)
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
    }

    /// One decision, two verbs — the review itself happens in-document, but the
    /// pane offers the whole-proposal call without leaving the conversation.
    private var decisionBar: some View {
        HStack(spacing: DS.space8) {
            Text("Review the diff in the document, or decide here")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)

            Spacer()

            CosmoPanePillButton(label: "Reject all", icon: nil, help: "Reject every pending change") {
                Task { await store.rejectAll(proposalID: proposal.id) }
            }

            CosmoPanePillButton(
                label: "Accept all",
                icon: "checkmark",
                help: "Apply every pending change",
                isProminent: true
            ) {
                Task { await store.acceptAll(proposalID: proposal.id) }
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
    }

    private var expandedDiff: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text(proposal.summary)
                .font(DS.subheadline)
                .foregroundStyle(DS.textSecondary)

            ForEach(proposal.operations) { operation in
                VStack(alignment: .leading, spacing: DS.space6) {
                    Text(operation.rationale)
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.textSecondary)

                    ForEach(operation.hunks) { hunk in
                        CosmoInlineAssistantPaneDiffHunkView(hunk: hunk)
                    }
                }
            }
        }
        .padding(DS.space12)
        .background(DS.surface.opacity(0.55))
    }
}

// MARK: - Canvas plan card

/// The thinkspace copilot's review card: an organize (or any canvas) plan
/// staged by the agent, listing every operation. Nothing touches the canvas
/// until Approve — the same trust contract text edits have.
private struct CosmoInlineAssistantPaneCanvasPlanCard: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let plan: PendingCanvasPlan

    private var status: CosmoCanvasPlanStatus {
        store.canvasPlanStatus(id: plan.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DS.borderSubtle)
            operationRows
            Divider().overlay(DS.borderSubtle)
            footer
        }
        .background(DS.surfaceCard, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(DS.borderSubtle, lineWidth: 1)
        }
        .animation(ProMotionSprings.gentle, value: status)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            Image(systemName: "square.grid.2x2")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 32, height: 32)
                .background(DS.accentSoft, in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.space4) {
                Text("Canvas plan")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .textCase(.uppercase)
                    .kerning(0.4)

                Text(plan.title)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .fixedSize(horizontal: false, vertical: true)

                if !plan.rationale.isEmpty {
                    Text(plan.rationale)
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(DS.space12)
    }

    private var operationRows: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            ForEach(plan.operations) { operation in
                HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
                    Image(systemName: icon(for: operation.kind))
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 14)
                        .accessibilityHidden(true)
                    Text(operation.summary)
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DS.space12)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: DS.space8) {
            switch status {
            case .pending:
                Text("\(plan.operations.count) \(plan.operations.count == 1 ? "change" : "changes")")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Button("Dismiss") {
                    withAnimation(ProMotionSprings.gentle) {
                        store.dismissCanvasPlan(id: plan.id)
                    }
                }
                .buttonStyle(.plain)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .cosmoClickCursor()
                .accessibilityLabel("Dismiss canvas plan")

                Button {
                    withAnimation(ProMotionSprings.gentle) {
                        store.approveCanvasPlan(id: plan.id)
                    }
                } label: {
                    Text("Approve")
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.textOnAccent)
                        .padding(.horizontal, DS.space12)
                        .frame(height: 26)
                        .background(DS.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .cosmoClickCursor()
                .accessibilityLabel("Approve canvas plan")

            case .applied:
                Label("Applied to the canvas", systemImage: "checkmark.circle.fill")
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.green)
                Spacer(minLength: 0)

            case .dismissed:
                Label("Dismissed", systemImage: "xmark.circle")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
    }

    private func icon(for kind: PendingCanvasOperationKind) -> String {
        switch kind {
        case .createCluster: return "square.grid.2x2"
        case .moveToCluster: return "arrow.right.square"
        case .arrange: return "rectangle.3.group"
        case .createEntity, .createAIBlock: return "plus.square"
        case .placeSearch: return "magnifyingglass"
        case .placeExistingAtom: return "square.on.square"
        case .moveSelection: return "arrow.up.and.down.and.arrow.left.and.right"
        case .resizeSelection: return "arrow.up.left.and.arrow.down.right"
        case .unsupported: return "eye"
        }
    }
}

// MARK: - Inquiry question card

/// The "open an inquiry?" confirmation card: when concept conversation hits a
/// genuine unknown, the staged question renders here with its concrete
/// destination. Confirming jumps straight into the deep-dive session; the card
/// stays in the conversation as a receipt either way.
private struct CosmoInlineAssistantPaneInquiryCard: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let proposal: CosmoAssistantInquiryQuestionProposal
    @State private var isStarting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let rationale = proposal.rationale, !rationale.isEmpty {
                Divider().overlay(DS.borderSubtle)
                rationaleRow(rationale)
            }
            Divider().overlay(DS.borderSubtle)
            footer
        }
        .background(DS.surfaceCard, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(DS.borderSubtle, lineWidth: 1)
        }
        .animation(ProMotionSprings.gentle, value: proposal.status)
        .animation(ProMotionSprings.gentle, value: isStarting)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            Image(systemName: "questionmark.bubble")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(CosmoMentionColors.color(for: .connection))
                .frame(width: 32, height: 32)
                .background(CosmoMentionColors.color(for: .connection).opacity(0.12), in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.space4) {
                Text("Inquiry question")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .textCase(.uppercase)
                    .kerning(0.4)

                Text(proposal.question)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(proposal.placementLabel)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(DS.space12)
    }

    private func rationaleRow(_ rationale: String) -> some View {
        Text(rationale)
            .font(DS.subheadline)
            .foregroundStyle(DS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
    }

    @ViewBuilder
    private var footer: some View {
        switch proposal.status {
        case .pending:
            if isStarting {
                startingRow
            } else {
                decisionBar
            }
        case .started:
            startedRow
        case .dismissed:
            dismissedRow
        }
    }

    private var decisionBar: some View {
        HStack(spacing: DS.space8) {
            Text("Open a deep-dive session on this?")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)

            Spacer()

            CosmoPanePillButton(label: "Not now", icon: nil, help: "Keep developing the concept without opening an inquiry") {
                store.dismissInquiry(proposalID: proposal.id)
            }

            CosmoPanePillButton(
                label: "Start inquiry",
                icon: "arrow.right",
                help: "Open the inquiry session around this question",
                isProminent: true
            ) {
                isStarting = true
                Task {
                    await store.startInquiry(proposalID: proposal.id)
                    isStarting = false
                }
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
    }

    private var startingRow: some View {
        HStack(spacing: DS.space8) {
            ProgressView()
                .controlSize(.small)
            Text("Opening inquiry session…")
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .accessibilityElement(children: .combine)
    }

    private var startedRow: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "checkmark.circle.fill")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.green)
                .accessibilityHidden(true)

            Text("Inquiry started")
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.textSecondary)

            Spacer()

            CosmoPanePillButton(label: "Open session", icon: "arrow.up.right", help: "Jump back into this inquiry session") {
                Task { await store.startInquiry(proposalID: proposal.id) }
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
    }

    private var dismissedRow: some View {
        Text("Skipped — ask again anytime.")
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
    }
}

/// Quiet pill button for card actions: hover lift, press compress, optional
/// prominent (accent) variant for the primary verb.
private struct CosmoPanePillButton: View {
    let label: String
    let icon: String?
    let help: String
    var isProminent = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                if let icon {
                    Image(systemName: icon)
                        .font(DS.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(label)
                    .font(DS.caption.weight(.medium))
            }
            .foregroundStyle(isProminent ? DS.textOnAccent : DS.text)
            .padding(.horizontal, DS.space12)
            .frame(height: 28)
            .background(fill, in: Capsule())
            .overlay {
                if !isProminent {
                    Capsule().strokeBorder(DS.borderSubtle, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .cosmoClickCursor()
        .onHover { hovering in
            withAnimation(ProMotionSprings.snappy) { isHovered = hovering }
        }
        .help(help)
        .accessibilityLabel(label)
    }

    private var fill: AnyShapeStyle {
        if isProminent {
            return AnyShapeStyle(DS.accent)
        }
        return isHovered ? AnyShapeStyle(DS.surfaceHover) : AnyShapeStyle(DS.surface)
    }
}

private struct CosmoInlineAssistantPaneOperationRow: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let operation: CosmoAssistantProposalOperation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
            Text(operation.rationale)
                .font(DS.subheadline)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer()

            HStack(spacing: DS.space4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(statusLabel)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(statusColor)
            }
            .animation(ProMotionSprings.snappy, value: operation.status)

            if operation.isRevertable {
                Button {
                    Task { await store.revert(operationID: operation.id) }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(DS.caption.weight(.semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .cosmoClickCursor()
                .foregroundStyle(DS.textSecondary)
                .help("Revert this change")
                .accessibilityLabel("Revert this change")
            }
        }
    }

    private var statusLabel: String {
        switch operation.status {
        case .pending: return "pending"
        case .accepted, .applied: return "accepted"
        case .rejected: return "rejected"
        case .conflicted: return "conflicted"
        case .reverted: return "reverted"
        }
    }

    private var statusColor: Color {
        switch operation.status {
        case .pending: return DS.textMuted
        case .accepted, .applied: return DS.green
        case .rejected, .reverted: return DS.textSecondary
        case .conflicted: return DS.orange
        }
    }
}

private struct CosmoInlineAssistantPaneDiffHunkView: View {
    let hunk: CosmoProposalHunk

    var body: some View {
        Text(prefix + hunk.text)
            .font(DS.caption.monospaced())
            .foregroundStyle(foreground)
            .lineLimit(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(background, in: .rect(cornerRadius: 7))
            .strikethrough(hunk.kind == .removed, color: foreground)
    }

    private var prefix: String {
        switch hunk.kind {
        case .added: return "+ "
        case .removed: return "− "
        case .context: return "  "
        }
    }

    private var foreground: Color {
        switch hunk.kind {
        case .added: return DS.green
        case .removed: return DS.red
        case .context: return DS.textSecondary
        }
    }

    private var background: Color {
        switch hunk.kind {
        case .added: return DS.greenSoft
        case .removed: return DS.redSoft
        case .context: return DS.surfaceHover.opacity(0.55)
        }
    }
}

// The composer lives in CosmoInlineAssistantPaneComposer.swift — the real
// mention composer with pill @-mentions and the shared context picker.
