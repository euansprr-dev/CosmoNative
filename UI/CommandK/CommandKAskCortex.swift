// CosmoOS/UI/CommandK/CommandKAskCortex.swift
// Ask Your Cortex — ⌘K's recall mode. A `?`-prefixed query retrieves from the
// Recall index and synthesizes an answer FROM THE USER'S OWN ATOMS, with
// numbered citations that open the source. Strictly gated: when the cortex
// has nothing relevant, it says so instead of hallucinating an answer.
// July 2026

import SwiftUI

// MARK: - Session Model

struct CommandKAskSession: Equatable {
    enum Phase: Equatable {
        case retrieving
        case answering
        case answered
        case noKnowledge
        case failed(String)
    }

    struct CompletedTurn: Equatable, Identifiable {
        let question: String
        let answer: String
        var id: String { question }
    }

    let id = UUID()
    var question: String
    var phase: Phase = .retrieving
    var answer: String = ""
    var sources: [CommandKAskSource] = []
    /// Earlier Q/A turns in this conversation (capped — see maxTurns).
    var priorTurns: [CompletedTurn] = []
    /// Human-readable scope when the question was `@kind`-scoped.
    var scopeLabel: String?

    static func == (lhs: CommandKAskSession, rhs: CommandKAskSession) -> Bool {
        lhs.id == rhs.id && lhs.phase == rhs.phase && lhs.answer == rhs.answer
            && lhs.priorTurns == rhs.priorTurns
    }
}

struct CommandKAskSource: Identifiable, Equatable {
    let index: Int
    let atomUuid: String
    let atomType: AtomType
    let title: String
    let excerpt: String
    /// PDF locator when the matched chunk came from a page-marked document.
    let page: Int?

    var id: Int { index }
}

// MARK: - Engine

enum CommandKAskEngine {
    /// Hits below this blended score don't count as "knowing something".
    static let knowledgeFloor = 0.30
    static let maxSources = 8
    /// Follow-up depth cap — past this, start a fresh question.
    static let maxTurns = 4

    /// `?@note how do hooks work` → scope retrieval to note-ish atoms.
    /// Returns the type filter (nil = everything), a display label, and the
    /// question with scope tokens stripped.
    static func parseScope(_ body: String) -> (types: Set<AtomType>?, label: String?, cleaned: String) {
        let scopeMap: [String: [AtomType]] = [
            "note": [.note, .stickyNote],
            "notes": [.note, .stickyNote],
            "idea": [.idea], "ideas": [.idea],
            "concept": [.connection], "concepts": [.connection], "connection": [.connection],
            "research": [.research, .extract], "swipe": [.research], "swipes": [.research],
            "content": [.content], "post": [.content], "posts": [.content],
        ]
        var types: [AtomType] = []
        var labels: [String] = []
        var words = body.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        while let first = words.first, first.hasPrefix("@"), first.count > 1 {
            let kind = String(first.dropFirst()).lowercased()
            guard let mapped = scopeMap[kind] else { break }
            types.append(contentsOf: mapped)
            labels.append(kind)
            words.removeFirst()
        }
        let cleaned = words.joined(separator: " ")
        guard !types.isEmpty else { return (nil, nil, body) }
        return (Set(types), labels.joined(separator: " + "), cleaned)
    }

    /// Run retrieval + synthesis, mutating the session through `update`.
    /// Follow-ups pass the prior turns: retrieval sees the conversation's
    /// vocabulary, and the prompt carries the earlier Q/A verbatim.
    static func run(
        question: String,
        priorTurns: [CommandKAskSession.CompletedTurn] = [],
        update: @MainActor @escaping (CommandKAskSession) -> Void
    ) async {
        let scope = parseScope(question)
        let turns = Array(priorTurns.suffix(maxTurns - 1))
        var session = CommandKAskSession(question: scope.cleaned)
        session.priorTurns = turns
        session.scopeLabel = scope.label
        await update(session)

        // 1. Retrieve from the user's own knowledge. Follow-ups blend the
        // prior questions in so pronouns ("what about for carousels?") land.
        let retrievalText = (turns.map(\.question) + [scope.cleaned]).joined(separator: "\n")
        let hits = await RecallEngine.shared.query(RecallQuery(
            text: retrievalText,
            types: scope.types,
            limit: maxSources,
            minScore: 0.12
        ))

        // 2. Gate: no relevant knowledge → honest empty state, no LLM call.
        guard let best = hits.first, best.score >= knowledgeFloor else {
            session.phase = .noKnowledge
            await update(session)
            return
        }

        session.sources = hits.enumerated().map { offset, hit in
            CommandKAskSource(
                index: offset + 1,
                atomUuid: hit.atomUuid,
                atomType: hit.atomType,
                title: hit.title,
                excerpt: hit.matchedText,
                page: hit.page
            )
        }
        session.phase = .answering
        await update(session)

        // 3. Synthesize, strictly grounded in the excerpts — streamed, so the
        // answer reads as it forms.
        let excerpts = session.sources
            .map { "[\($0.index)] \($0.title)\n\($0.excerpt)" }
            .joined(separator: "\n\n---\n\n")

        let systemPrompt = """
        You answer questions using ONLY the numbered excerpts from the user's own knowledge base. \
        Rules: every claim cites its excerpt like [1] or [2][3]. If the excerpts only partially \
        answer, say what they cover and what they don't — never fill gaps from general knowledge. \
        Be concise: 2-6 sentences, no preamble, no headers. Write in the second person about \
        "your notes" / "your concepts" where natural.
        """

        var messages: [[String: Any]] = []
        for turn in turns {
            messages.append(["role": "user", "content": turn.question])
            messages.append(["role": "assistant", "content": turn.answer])
        }
        messages.append(["role": "user", "content": """
        QUESTION: \(scope.cleaned)

        EXCERPTS FROM THE USER'S KNOWLEDGE BASE:
        \(excerpts)
        """])

        do {
            let streamBox = StreamBox()
            let streamingBase = session  // immutable snapshot for the token closure
            let answer = try await ResearchService.shared.generateWithCaching(
                systemBlocks: [PromptCacheBlock(content: systemPrompt, cacheControl: false)],
                messages: messages,
                model: AgentModelTier.strategist.modelId,
                maxTokens: 700,
                temperature: 0.3,
                disableReasoning: true,  // quick lookup on Sonnet 5: thinking would eat the 700-token cap
                onToken: { token in
                    Task { @MainActor in
                        let partial = await streamBox.append(token)
                        var streaming = streamingBase
                        streaming.answer = partial
                        update(streaming)
                    }
                }
            )
            session.answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            session.phase = .answered
        } catch {
            session.phase = .failed(error.localizedDescription)
        }
        await update(session)
    }

    /// Serializes streamed tokens (onToken is @Sendable and may hop threads).
    private actor StreamBox {
        private var text = ""
        func append(_ token: String) -> String {
            text += token
            return text
        }
    }
}

// MARK: - Pane

struct CommandKAskPane: View {
    let session: CommandKAskSession
    /// Open an atom from a citation (routes through the standard focus opener).
    var onOpenSource: (CommandKAskSource) -> Void = { _ in }
    /// Hand the unanswerable question to the assistant instead.
    var onAskCosmo: (String) -> Void = { _ in }
    /// The gap becomes work: start an inquiry pre-seeded with the question.
    var onStartInquiry: ((String) -> Void)?
    /// Ask a follow-up in the same conversation.
    var onFollowUp: ((String) -> Void)?

    @State private var followUpText = ""
    @FocusState private var followUpFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                priorTurnStack
                header
                content
                if session.phase == .answered, let onFollowUp,
                   session.priorTurns.count < CommandKAskEngine.maxTurns - 1 {
                    followUpField(onFollowUp)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    /// Earlier turns read as quiet transcript above the live question.
    @ViewBuilder
    private var priorTurnStack: some View {
        if !session.priorTurns.isEmpty {
            VStack(alignment: .leading, spacing: DS.space12) {
                ForEach(session.priorTurns) { turn in
                    VStack(alignment: .leading, spacing: DS.space4) {
                        Text(turn.question)
                            .font(DS.caption.weight(.semibold))
                            .foregroundStyle(DS.textMuted)
                        Text(turn.answer)
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().overlay(DS.borderSubtle)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            HStack(spacing: DS.space6) {
                Image(systemName: "circle.hexagongrid.circle")
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.gilt)
                    .accessibilityHidden(true)
                Text("FROM YOUR CORTEX")
                    .font(DS.smallCaps)
                    .tracking(1.4)
                    .foregroundStyle(DS.textMuted)
                if let scope = session.scopeLabel {
                    Text("· \(scope) only")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
            }
            Text(session.question)
                .font(DS.spaceTitleSerif)
                .foregroundStyle(DS.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func followUpField(_ submit: @escaping (String) -> Void) -> some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "arrow.turn.down.right")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            TextField("Follow up…", text: $followUpText)
                .textFieldStyle(.plain)
                .font(DS.caption)
                .focused($followUpFocused)
                .onSubmit {
                    let text = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    followUpText = ""
                    submit(text)
                }
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space6)
        .background(DS.surfaceHover, in: Capsule())
        .frame(maxWidth: 420)
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .retrieving:
            progressRow("Searching your knowledge…")
        case .answering:
            VStack(alignment: .leading, spacing: DS.space12) {
                progressRow("Reading \(session.sources.count) sources…")
                sourceList
            }
        case .answered:
            VStack(alignment: .leading, spacing: DS.space16) {
                Text(session.answer)
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                sourceList
            }
        case .noKnowledge:
            noKnowledgeState
        case .failed(let message):
            VStack(alignment: .leading, spacing: DS.space8) {
                Label("Couldn't synthesize an answer", systemImage: "exclamationmark.triangle")
                    .font(DS.callout)
                    .foregroundStyle(DS.orange)
                Text(message)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(3)
            }
        }
    }

    private func progressRow(_ label: String) -> some View {
        HStack(spacing: DS.space8) {
            ProgressView()
                .controlSize(.small)
            Text(label)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var noKnowledgeState: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            Text("Nothing in your cortex covers this yet.")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
            Text("Your saved notes, concepts, and research don't have a confident answer — that's a gap worth filling, not one to paper over.")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.space8) {
                if let onStartInquiry {
                    Button {
                        onStartInquiry(session.question)
                    } label: {
                        Label("Start an inquiry", systemImage: "arrow.triangle.branch")
                            .font(DS.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Open an inquiry session seeded with this question")
                }
                Button {
                    onAskCosmo(session.question)
                } label: {
                    Label("Ask Cosmo instead", systemImage: "sparkles")
                        .font(DS.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text("SOURCES")
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(DS.textMuted)
            ForEach(session.sources) { source in
                sourceRow(source)
            }
        }
    }

    private func sourceRow(_ source: CommandKAskSource) -> some View {
        Button {
            onOpenSource(source)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
                Text("[\(source.index)]")
                    .font(DS.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(DS.gilt)
                Image(systemName: source.atomType.iconName)
                    .font(DS.caption2)
                    .foregroundStyle(cortexEntityAccent(source.atomType))
                    .accessibilityHidden(true)
                Text(source.title)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                if let page = source.page {
                    Text("p. \(page)")
                        .font(DS.caption2.monospacedDigit())
                        .foregroundStyle(DS.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(source.excerpt.prefix(200)))
        .accessibilityLabel(
            source.page.map { "Source \(source.index): \(source.title), page \($0)" }
                ?? "Source \(source.index): \(source.title)"
        )
    }
}
