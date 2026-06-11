// CosmoOS/AI/SpokesCompilerEngine.swift
// Spokes Compiler — one finished pillar asset in, a complete platform package
// out: newsletter, thread, reel script, carousel, post. Each spoke is drafted
// with format-true density rules and lands in the pipeline as a linked
// content atom on accept.

import SwiftUI

@MainActor
@Observable
final class SpokesCompilerEngine {

    // MARK: - Formats

    enum SpokeFormat: String, CaseIterable, Identifiable, Sendable {
        case newsletter
        case thread
        case reel
        case carousel
        case post

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .newsletter: return "Newsletter"
            case .thread: return "Thread"
            case .reel: return "Reel Script"
            case .carousel: return "Carousel"
            case .post: return "Post"
            }
        }

        var icon: String {
            switch self {
            case .newsletter: return "envelope"
            case .thread: return "text.alignleft"
            case .reel: return "video"
            case .carousel: return "square.stack"
            case .post: return "doc.text"
            }
        }

        var contentFormat: IdeaContentFormat {
            switch self {
            case .newsletter: return .newsletter
            case .thread: return .thread
            case .reel: return .reel
            case .carousel: return .carousel
            case .post: return .post
            }
        }
    }

    // MARK: - State

    enum SpokeState: Equatable {
        case queued
        case drafting
        case ready
        case accepted
        case failed(String)
    }

    struct Spoke: Identifiable, Equatable {
        let id: UUID
        let format: SpokeFormat
        var state: SpokeState
        var draft: String
    }

    private(set) var spokes: [Spoke] = []
    private(set) var isCompiling = false
    private(set) var pillar: Atom?

    // MARK: - Lifecycle

    func prepare(pillar: Atom) {
        self.pillar = pillar
        spokes = SpokeFormat.allCases.map {
            Spoke(id: UUID(), format: $0, state: .queued, draft: "")
        }
    }

    /// Draft the selected formats, two at a time would thrash the provider —
    /// sequential keeps quality and ordering predictable.
    func compile(formats: Set<SpokeFormat>) async {
        guard pillar != nil, !isCompiling else { return }
        isCompiling = true
        for index in spokes.indices where formats.contains(spokes[index].format) && spokes[index].state == .queued {
            await draft(at: index)
        }
        isCompiling = false
    }

    func regenerate(_ spokeId: UUID) async {
        guard let index = spokes.firstIndex(where: { $0.id == spokeId }) else { return }
        await draft(at: index)
    }

    private func draft(at index: Int) async {
        guard let pillar else { return }
        spokes[index].state = .drafting
        do {
            let prompt = Self.prompt(for: spokes[index].format, pillar: pillar)
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            spokes[index].draft = response.trimmingCharacters(in: .whitespacesAndNewlines)
            spokes[index].state = .ready
        } catch {
            spokes[index].state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Accept

    /// Accepting a spoke creates a content atom linked back to the pillar and
    /// returns it. The spoke card flags itself as landed.
    func accept(_ spokeId: UUID) async -> Atom? {
        guard let pillar,
              let index = spokes.firstIndex(where: { $0.id == spokeId }),
              spokes[index].state == .ready else { return nil }

        let spoke = spokes[index]
        let pillarTitle = pillar.title ?? "Untitled"

        let metadata = """
        {"contentFormat":"\(spoke.format.contentFormat.rawValue)","sourcePillarUUID":"\(pillar.uuid)"}
        """

        let atom = Atom.new(
            type: .content,
            title: "\(pillarTitle) — \(spoke.format.displayName)",
            body: spoke.draft,
            metadata: metadata,
            links: [
                AtomLink(
                    type: "spoke_of_content",
                    uuid: pillar.uuid,
                    entityType: AtomType.content.rawValue
                )
            ]
        )

        do {
            let created = try await AtomRepository.shared.create(atom)
            spokes[index].state = .accepted
            return created
        } catch {
            spokes[index].state = .failed(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Prompts
    // Each prompt teaches the format completely: structure, density, hook
    // discipline, and exact output markers the previews parse.

    private static func pillarBlock(_ pillar: Atom) -> String {
        """
        SOURCE MATERIAL (the pillar asset — every spoke must be faithful to it; \
        do not invent claims that are not grounded here):

        TITLE: \(pillar.title ?? "Untitled")

        BODY:
        \(pillar.body ?? "")
        """
    }

    static func prompt(for format: SpokeFormat, pillar: Atom) -> String {
        let shared = """
        You are repurposing one finished piece of long-form content into a \
        platform-native format. Keep the author's voice — direct, concrete, no \
        hype words ("game-changer", "unlock", "revolutionary" are banned). \
        Preserve the strongest specific details, numbers, and examples from the \
        source; specifics are what make the spoke worth posting.

        \(pillarBlock(pillar))
        """

        switch format {
        case .newsletter:
            return shared + """


            TASK: Write a newsletter edition from this material.

            STRUCTURE — follow exactly:
            1. First line: "Subject: <subject line>". The subject is ≤55 \
            characters, states the concrete payoff, no clickbait, no colons \
            stacked on colons.
            2. Blank line, then a 2–3 sentence lede that earns the read by \
            naming the problem the reader has and the specific insight coming.
            3. Three to five short sections. Each section: a plain-language \
            subhead on its own line (no markdown #), then 2–4 short paragraphs. \
            One idea per section. Use a concrete example or number in at least \
            two sections.
            4. Close with a 2-sentence takeaway and one clear next action.

            LENGTH: 600–900 words. Write tight; cut anything that restates.
            OUTPUT: plain text only, exactly in the structure above.
            """

        case .thread:
            return shared + """


            TASK: Write an X thread from this material.

            RULES — follow exactly:
            - 6 to 12 tweets. Each tweet ≤270 characters. One idea per tweet.
            - Tweet 1 is the hook: state the core insight concretely so a \
            reader knows exactly what they get. No "a thread 🧵", no rhetorical \
            questions, no clickbait gaps.
            - Middle tweets each carry ONE point from the source with its \
            specific detail or example. Short sentences. Line breaks inside a \
            tweet are allowed.
            - Final tweet: the takeaway in one sentence, then one call to \
            action.
            - Do NOT number the tweets. Separate tweets with a single blank \
            line. No hashtags, no emojis.

            OUTPUT: only the tweets, blank-line separated.
            """

        case .reel:
            return shared + """


            TASK: Write a 30–45 second reel script from this material.

            RULES — follow exactly:
            - 6 to 10 slides. Separate slides with a line containing only "---".
            - Exactly ONE spoken sentence per slide. This is a hard density \
            rule — a slide with two sentences is wrong.
            - Slide 1 is the spoken hook: ≤12 words, states the payoff or the \
            surprising claim directly.
            - Each middle slide advances one beat of the argument with concrete \
            language a person can say naturally on camera.
            - Last slide: one-sentence call to action.

            OUTPUT: only the slides, separated by "---" lines.
            """

        case .carousel:
            return shared + """


            TASK: Write an Instagram carousel from this material.

            RULES — follow exactly:
            - 6 to 8 slides. Separate slides with a line containing only "---".
            - Slide 1 is the title slide: a hook of ≤8 words that names the \
            concrete payoff.
            - Every other slide: roughly 4 sentences (3–5 acceptable). Each \
            slide makes ONE self-contained point with a specific example, \
            number, or step from the source — a reader who screenshots one \
            slide should still get value.
            - Final slide: summary + one call to action.

            OUTPUT: only the slides, separated by "---" lines.
            """

        case .post:
            return shared + """


            TASK: Write a single text post (LinkedIn/X long-form) from this \
            material.

            RULES — follow exactly:
            - 100–200 words total.
            - First line is the hook: one short sentence stating the concrete \
            insight. It must work standing alone above the fold.
            - Short paragraphs of 1–2 sentences with blank lines between them \
            — the post must scan in five seconds.
            - End with one question or call to action, not both.
            - No hashtags, no emojis.

            OUTPUT: only the post text.
            """
        }
    }
}
