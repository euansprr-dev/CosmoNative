// CosmoOS/UI/CosmoWindow/CosmoMessageBubble.swift
// Premium message rendering for the floating Cosmo overlay
// March 2026

import SwiftUI

enum CosmoWindowMessageRenderingPolicy {
    static let allowsTimelineTextSelection = false
    static let usesLazyTimelineStack = false
}

struct CosmoMessageBubble: View {
    let message: CosmoWindowMessage
    var onEdit: ((CosmoWindowMessage) -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        switch message.type {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .system:
            timelineMarker(
                icon: "sparkles",
                title: message.content,
                tint: DS.textSecondary
            )
        case .toolResult(let name, let summary, let isError):
            toolResultRow(name: name, summary: summary, isError: isError)
        case .contextTrace(let lookups, let sections):
            legacyContextTraceCard(lookups: lookups, sections: sections)
        case .contextChange:
            // Context changes are now reflected only in the top summary card — skip rendering
            EmptyView()
        case .actionButtons(let buttons):
            actionButtonsBubble(buttons: buttons)
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 72)

            VStack(alignment: .trailing, spacing: 10) {
                inlineContentText(message.content, mentions: message.mentionedAtomInfo)
                    .font(DS.body)
                    .foregroundColor(DS.text)
                    .lineSpacing(5)
                    .cosmoWindowTimelineTextSelection()

                HStack(spacing: 8) {
                    Text("You")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.accent)

                    Text(formattedTime)
                        .font(DS.timestamp)
                        .foregroundColor(DS.textMuted)
                }
            }
            .frame(maxWidth: messageMaxWidth, alignment: .trailing)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: CosmoWindowMetrics.cardCornerRadius, style: .continuous)
                    .fill(DS.accentSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CosmoWindowMetrics.cardCornerRadius, style: .continuous)
                    .stroke(DS.accent.opacity(0.18), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if isHovering, let onEdit {
                    Button {
                        onEdit(message)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.textSecondary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(DS.glassSectionFill))
                            .overlay(Circle().stroke(DS.glassBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 10, y: -10)
                }
            }
            .onHover { hovering in
                withAnimation(ProMotionSprings.snappy) {
                    isHovering = hovering
                }
            }
        }
        .padding(.horizontal, CosmoWindowMetrics.contentPadding)
    }

    private var assistantBubble: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(DS.accentSoft)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(DS.accent)
                            )

                        Text("Cosmo")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DS.text)
                    }

                    Spacer(minLength: 0)

                    if let modelLabel = message.responseMeta?.modelLabel {
                        Text(modelLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DS.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .cosmoWindowChip()
                    }

                    Text(formattedTime)
                        .font(DS.timestamp)
                        .foregroundColor(DS.textMuted)
                }

                assistantContent

                if let responseMeta = message.responseMeta, responseMeta.hasVisibleContent {
                    ResponseProvenanceCard(meta: responseMeta)
                }
            }
            .frame(maxWidth: messageMaxWidth, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .cosmoWindowSectionChrome(cornerRadius: CosmoWindowMetrics.cardCornerRadius)

            Spacer(minLength: 72)
        }
        .padding(.horizontal, CosmoWindowMetrics.contentPadding)
    }

    @ViewBuilder
    private var assistantContent: some View {
        if message.content.isEmpty && message.isStreaming {
            // CosmoThinkingCard handles the thinking state with live tool activity —
            // no need for a duplicate indicator here.
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                CosmoMarkdownRenderer(content: message.content)

                if message.isStreaming {
                    HStack(spacing: 8) {
                        StreamingIndicator()
                        Text("Responding")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DS.textSecondary)
                    }
                }
            }
        }
    }

    private func actionButtonsBubble(buttons: [CosmoActionButton]) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                if !message.content.isEmpty {
                    CosmoMarkdownRenderer(content: message.content)
                }

                let rows = stride(from: 0, to: buttons.count, by: 3).map { start in
                    Array(buttons[start..<min(start + 3, buttons.count)])
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 8) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, button in
                                Button(button.label) {
                                    Task {
                                        await CosmoWindowViewModel.shared.sendMessage(button.action)
                                    }
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DS.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .cosmoWindowChip(isActive: true)
                            }
                        }
                    }
                }

                Text(formattedTime)
                    .font(DS.timestamp)
                    .foregroundColor(DS.textMuted)
            }
            .frame(maxWidth: messageMaxWidth, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .cosmoWindowSectionChrome(cornerRadius: CosmoWindowMetrics.cardCornerRadius)

            Spacer(minLength: 72)
        }
        .padding(.horizontal, CosmoWindowMetrics.contentPadding)
    }

    private func toolResultRow(name: String, summary: String, isError: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isError ? DS.red : DS.green)

                    Text(name.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.text)

                    Spacer(minLength: 0)

                    Text(formattedTime)
                        .font(DS.timestamp)
                        .foregroundColor(DS.textMuted)
                }

                Text(summary)
                    .font(.system(size: 12))
                    .foregroundColor(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: messageMaxWidth, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: CosmoWindowMetrics.cardCornerRadius, style: .continuous)
                    .fill(isError ? DS.redSoft.opacity(0.7) : DS.glassCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CosmoWindowMetrics.cardCornerRadius, style: .continuous)
                    .stroke(isError ? DS.red.opacity(0.18) : DS.glassBorder, lineWidth: 1)
            )

            Spacer(minLength: 72)
        }
        .padding(.horizontal, CosmoWindowMetrics.contentPadding)
    }

    private func legacyContextTraceCard(lookups: Int, sections: [ContextTraceSection]) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "eye")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.accent)

                    Text("Context Used")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.text)

                    Text("\(lookups) lookups")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .cosmoWindowChip()
                }

                ContextTraceSectionsView(sections: sections)
            }
            .frame(maxWidth: messageMaxWidth, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .cosmoWindowSectionChrome(cornerRadius: CosmoWindowMetrics.cardCornerRadius)

            Spacer(minLength: 72)
        }
        .padding(.horizontal, CosmoWindowMetrics.contentPadding)
    }

    private func timelineMarker(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(DS.glassBorder)
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(tint)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(DS.glassSectionFill)
            )
            .overlay(
                Capsule()
                    .stroke(DS.glassBorder, lineWidth: 1)
            )

            Rectangle()
                .fill(DS.glassBorder)
                .frame(height: 1)
        }
        .padding(.horizontal, CosmoWindowMetrics.contentPadding)
    }

    private func inlineContentText(_ content: String, mentions: [MentionedAtomInfo]?) -> Text {
        guard let mentions, !mentions.isEmpty else {
            return Text(content)
        }

        let hasInlineMentions = mentions.contains { mention in
            content.contains("@\(mention.title)")
        }

        guard hasInlineMentions else {
            return Text(content)
        }

        struct MentionMatch {
            let range: Range<String.Index>
            let mention: MentionedAtomInfo
        }

        var matches: [MentionMatch] = []
        for mention in mentions {
            let pattern = "@\(mention.title)"
            var searchStart = content.startIndex
            while let range = content.range(of: pattern, range: searchStart..<content.endIndex) {
                matches.append(MentionMatch(range: range, mention: mention))
                searchStart = range.upperBound
            }
        }

        matches.sort { $0.range.lowerBound < $1.range.lowerBound }

        var attributed = AttributedString(content)
        attributed.foregroundColor = DS.text

        for match in matches {
            let entityType = EntityType(rawValue: match.mention.type) ?? .idea
            if let range = Range(match.range, in: attributed) {
                attributed[range].foregroundColor = CosmoMentionColors.color(for: entityType)
                attributed[range].font = .body.bold()
            }
        }

        return Text(attributed)
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.timestamp)
    }

    private var messageMaxWidth: CGFloat {
        CosmoWindowMetrics.maxMessageWidth
    }
}

private struct ResponseProvenanceCard: View {
    let meta: CosmoResponseMeta

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DS.textMuted)

                    Text("How Cosmo got here")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.text)

                    Spacer(minLength: 0)

                    if let elapsedSeconds = meta.elapsedSeconds {
                        Text("\(elapsedSeconds)s")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DS.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .cosmoWindowChip()
                    }

                    if !meta.toolRecapGroups.isEmpty {
                        Text("\(meta.toolRecapGroups.count) groups")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DS.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .cosmoWindowChip()
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if !meta.toolRecapGroups.isEmpty {
                        ToolActivityStreamView(recapGroups: meta.toolRecapGroups)
                    }

                    if !meta.contextTraceSections.isEmpty {
                        ContextTraceSectionsView(sections: meta.contextTraceSections)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .cosmoWindowGroupChrome(cornerRadius: 14)
    }
}

private struct ContextTraceSectionsView: View {
    let sections: [ContextTraceSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sections) { section in
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(DS.accentSoft)
                            .frame(width: 26, height: 26)

                        Image(systemName: section.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.text)

                        Text(section.detail)
                            .font(.system(size: 11))
                            .foregroundColor(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct CosmoMarkdownRenderer: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(CosmoMarkdownParser.parse(content).enumerated()), id: \.offset) { _, block in
                CosmoMarkdownBlockView(block: block)
            }
        }
        .cosmoWindowTimelineTextSelection()
    }
}

private extension View {
    @ViewBuilder
    func cosmoWindowTimelineTextSelection() -> some View {
        if CosmoWindowMessageRenderingPolicy.allowsTimelineTextSelection {
            self.textSelection(.enabled)
        } else {
            self
        }
    }
}

private enum CosmoMarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet([String])
    case ordered([String])
    case quote(String)
    case code(String)
}

private enum CosmoMarkdownParser {
    static func parse(_ content: String) -> [CosmoMarkdownBlock] {
        let lines = content.components(separatedBy: .newlines)
        var blocks: [CosmoMarkdownBlock] = []
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
                if index < lines.count {
                    index += 1
                }
                blocks.append(.code(codeLines.joined(separator: "\n")))
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
                let next = lines[index]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty || isSpecialLine(nextTrimmed) {
                    break
                }
                paragraphLines.append(next)
                index += 1
            }
            blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
        }

        return blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        if line.hasPrefix("### ") {
            return (3, String(line.dropFirst(4)))
        }
        if line.hasPrefix("## ") {
            return (2, String(line.dropFirst(3)))
        }
        if line.hasPrefix("# ") {
            return (1, String(line.dropFirst(2)))
        }
        return nil
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
            || heading(from: line) != nil
            || line.hasPrefix(">")
            || bulletItem(from: line) != nil
            || orderedItem(from: line) != nil
    }
}

private struct CosmoMarkdownBlockView: View {
    let block: CosmoMarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level: level))
                .foregroundColor(DS.text)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph(let text):
            Text(.init(text))
                .font(DS.body)
                .foregroundColor(DS.text)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(DS.accent)
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)

                        Text(.init(item))
                            .font(DS.body)
                            .foregroundColor(DS.text)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .ordered(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.accent)
                            .frame(width: 20, alignment: .trailing)

                        Text(.init(item))
                            .font(DS.body)
                            .foregroundColor(DS.text)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 12) {
                Text(.init(text))
                    .font(.system(size: 14))
                    .foregroundColor(DS.textSecondary)
                    .italic()
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.glassSectionFill)
            )
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(DS.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.glassSectionFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.glassBorder, lineWidth: 1)
            )
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 21, weight: .semibold)
        case 2:
            return .system(size: 18, weight: .semibold)
        default:
            return .system(size: 16, weight: .semibold)
        }
    }
}

struct StreamingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.35)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(DS.accent)
                        .frame(width: 5, height: 5)
                        .opacity(reduceMotion ? 0.65 : (phase == index ? 1.0 : 0.25))
                }
            }
        }
    }
}

#if DEBUG
struct CosmoMessageBubble_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 16) {
                CosmoMessageBubble(message: .user("Use @Josh to turn this into a cleaner script."))
                CosmoMessageBubble(
                    message: CosmoWindowMessage.assistant(
                        "# Draft direction\n\n- Lead with the problem\n- Anchor it in the Midwest angle\n\n> You can win with a better guest experience.\n\n```swift\nprint(\"hello\")\n```",
                        responseMeta: CosmoResponseMeta(
                            elapsedSeconds: 19,
                            toolRecapGroups: [
                                CosmoToolRecapGroup(
                                    category: "Viewed",
                                    items: [
                                        CosmoToolRecapItem(icon: "doc.text", label: "Read Ben location breakdown swipe", detail: "Used structure and hook pacing", status: .done)
                                    ],
                                    isComplete: true
                                )
                            ],
                            contextTraceSections: [
                                ContextTraceSection(icon: "person.fill", label: "Client", detail: "Michael"),
                                ContextTraceSection(icon: "waveform", label: "Beat Pattern", detail: "Problem → proof → payoff")
                            ],
                            modelLabel: "Sonnet"
                        )
                    )
                )
                CosmoMessageBubble(message: .contextChange(from: "Thinkspace", to: "Content"))
            }
            .padding(.vertical, 20)
        }
        .frame(width: 520, height: 720)
        .background(DS.bg)
    }
}
#endif
