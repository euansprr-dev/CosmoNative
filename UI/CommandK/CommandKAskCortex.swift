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

    let id = UUID()
    var question: String
    var phase: Phase = .retrieving
    var answer: String = ""
    var sources: [CommandKAskSource] = []

    static func == (lhs: CommandKAskSession, rhs: CommandKAskSession) -> Bool {
        lhs.id == rhs.id && lhs.phase == rhs.phase && lhs.answer == rhs.answer
    }
}

struct CommandKAskSource: Identifiable, Equatable {
    let index: Int
    let atomUuid: String
    let atomType: AtomType
    let title: String
    let excerpt: String

    var id: Int { index }
}

// MARK: - Engine

enum CommandKAskEngine {
    /// Hits below this blended score don't count as "knowing something".
    static let knowledgeFloor = 0.30
    static let maxSources = 8

    /// Run retrieval + synthesis, mutating the session through `update`.
    static func run(
        question: String,
        update: @MainActor @escaping (CommandKAskSession) -> Void
    ) async {
        var session = CommandKAskSession(question: question)
        await update(session)

        // 1. Retrieve from the user's own knowledge.
        let hits = await RecallEngine.shared.query(RecallQuery(
            text: question,
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
                excerpt: hit.matchedText
            )
        }
        session.phase = .answering
        await update(session)

        // 3. Synthesize, strictly grounded in the excerpts.
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

        let prompt = """
        QUESTION: \(question)

        EXCERPTS FROM THE USER'S KNOWLEDGE BASE:
        \(excerpts)
        """

        do {
            let answer = try await ResearchService.shared.analyze(
                prompt: prompt,
                systemPrompt: systemPrompt,
                tier: .strategist,
                maxTokens: 700
            )
            session.answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            session.phase = .answered
        } catch {
            session.phase = .failed(error.localizedDescription)
        }
        await update(session)
    }
}

// MARK: - Pane

struct CommandKAskPane: View {
    let session: CommandKAskSession
    /// Open an atom from a citation (routes through the standard focus opener).
    var onOpenSource: (CommandKAskSource) -> Void = { _ in }
    /// Hand the unanswerable question to the assistant instead.
    var onAskCosmo: (String) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
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
            }
            Text(session.question)
                .font(DS.spaceTitleSerif)
                .foregroundStyle(DS.text)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(source.excerpt.prefix(200)))
        .accessibilityLabel("Source \(source.index): \(source.title)")
    }
}
