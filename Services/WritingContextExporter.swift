// CosmoOS/Services/WritingContextExporter.swift
// Exports the full writing engine context (system prompt, swipes, client profiles)
// to ~/Desktop/CosmoExport/ for use in Claude Projects.
// March 2026

import Foundation
import GRDB

@MainActor
final class WritingContextExporter {

    static let exportRoot = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CosmoExport")

    // MARK: - Public

    /// Export everything: system prompt, all swipes, all client profiles.
    /// Creates ~/Desktop/CosmoExport/ with the full folder structure.
    static func exportAll() async {
        let fm = FileManager.default
        let root = exportRoot

        // Clean previous export
        try? fm.removeItem(at: root)

        do {
            // Create folder structure
            try fm.createDirectory(at: root.appendingPathComponent("Swipes/Reels"), withIntermediateDirectories: true)
            try fm.createDirectory(at: root.appendingPathComponent("Swipes/Carousels"), withIntermediateDirectories: true)
            try fm.createDirectory(at: root.appendingPathComponent("Swipes/Threads"), withIntermediateDirectories: true)

            // Step 1: Write the master system prompt
            let systemPrompt = assembleSystemPrompt()
            try systemPrompt.write(to: root.appendingPathComponent("00_SYSTEM_PROMPT.md"), atomically: true, encoding: .utf8)
            print("WritingContextExporter: Wrote system prompt (\(systemPrompt.count) chars)")

            // Step 2: Export all swipes
            let swipeCount = try await exportSwipes(to: root.appendingPathComponent("Swipes"))
            print("WritingContextExporter: Exported \(swipeCount) swipes")

            // Step 3: Export all client profiles
            let clientCount = try await exportClients(to: root.appendingPathComponent("Clients"))
            print("WritingContextExporter: Exported \(clientCount) clients")

            // Step 4: Write README
            let readme = assembleReadme(swipeCount: swipeCount, clientCount: clientCount)
            try readme.write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

            print("WritingContextExporter: Export complete → ~/Desktop/CosmoExport/")
        } catch {
            print("WritingContextExporter: Export failed — \(error)")
        }
    }

    // MARK: - System Prompt Assembly

    private static func assembleSystemPrompt() -> String {
        let store = PromptTemplateStore.shared

        // Build methodology + modules text (same as assemblePrompt(for:))
        var methodologyText = ""
        if !store.methodology.isEmpty {
            methodologyText += "## Content Strategy & Methodology\n\n\(store.methodology)"
        }
        let enabledModules = store.modules.filter { $0.isEnabled }
        if !enabledModules.isEmpty {
            let moduleText = enabledModules.map { "## \($0.title)\n\n\($0.content)" }.joined(separator: "\n\n")
            if !methodologyText.isEmpty { methodologyText += "\n\n" }
            methodologyText += moduleText
        }

        // Start with the unified system prompt, replacing placeholders
        var prompt = store.unifiedSystemPrompt
            .replacingOccurrences(of: "{METHODOLOGY_TEXT}", with: methodologyText)
            .replacingOccurrences(of: "{PLATFORM_CONSTRAINTS}", with: store.platformConstraints)

        // Adapt tool-use instructions for conversational Claude Projects use
        prompt = adaptForConversationalUse(prompt)

        return prompt
    }

    /// Replace tool-use references with conversational equivalents
    private static func adaptForConversationalUse(_ prompt: String) -> String {
        var p = prompt

        // Replace tool usage section
        let toolUsageOld = """
        TOOL USAGE:
        - Use tools for all changes (update_outline, write_draft, edit_section, add_hooks, set_description). Never paste content in conversational response.
        - MANDATORY FIRST RESPONSE: Think tool to analyze ALL loaded context — list swipes (hook type + score), summarize client voice/beliefs, identify relevant top performers, note failure rules.
        - Think tool before every generation: beat pattern, hook type, voice characteristics, failure rules.
        - Always reference client profile for their perspective/beliefs. If no swipes loaded, search_swipes proactively.
        """
        let toolUsageNew = """
        WORKFLOW:
        - MANDATORY FIRST RESPONSE: Write a **THINKING** section to analyze ALL loaded context — list swipes (hook type + score), summarize client voice/beliefs, identify relevant top performers, note failure rules.
        - Write a **THINKING** section before every generation: beat pattern, hook type, voice characteristics, failure rules.
        - Always reference client profile for their perspective/beliefs. Search the uploaded swipe files for relevant examples.
        - Output all drafts in structured format (see OUTPUT FORMAT below). Never describe what you'd write — write it.
        """
        p = p.replacingOccurrences(of: toolUsageOld, with: toolUsageNew)

        // Replace generation rules tool references
        p = p.replacingOccurrences(
            of: "BEFORE GENERATING: Think tool to plan",
            with: "BEFORE GENERATING: Write a **THINKING** section to plan"
        )
        p = p.replacingOccurrences(
            of: "AFTER GENERATION: Think tool self-evaluate",
            with: "AFTER GENERATION: Write a **SELF-EVALUATION** section"
        )
        p = p.replacingOccurrences(
            of: "Use the\nthink tool to verify compliance before finalizing any draft.",
            with: "Verify compliance before finalizing any draft."
        )
        p = p.replacingOccurrences(
            of: "Use the think tool to verify compliance before finalizing any draft.",
            with: "Verify compliance before finalizing any draft."
        )

        // Replace output format section
        let outputOld = """
        OUTPUT FORMAT: ALWAYS use the write_draft tool to submit content — NEVER paste draft text inline in your response.
        For the write_draft tool's content field: Carousel = JSON {"slides": [{"number": 1, "text": "..."}]}. Thread = JSON {"tweets": [...]}. Video = plaintext with [VISUAL: ...]. Long-form = Markdown.
        Your conversational response should be a brief summary of what you wrote (e.g., "Here's a 7-slide carousel draft with a curiosity gap hook. Want me to adjust anything?").
        """
        let outputNew = """
        OUTPUT FORMAT: ALWAYS output your draft in a clearly labeled **DRAFT** section using the correct format:
        - Carousel = JSON: {"slides": [{"number": 1, "text": "..."}]}
        - Thread = JSON: {"tweets": ["tweet 1 text", "tweet 2 text", ...]}
        - Reel/Video = plaintext script with [VISUAL: ...] markers per scene
        - Long-form/Newsletter = Markdown with headers and formatting

        After the draft, include a **SELF-EVALUATION** with: voice match score (1-10), format compliance score (1-10), hook strength score (1-10), and list of weak areas.

        After the self-evaluation, write a brief conversational summary (e.g., "Here's a 7-slide carousel draft with a curiosity gap hook. Want me to adjust anything?").
        """
        p = p.replacingOccurrences(of: outputOld, with: outputNew)

        // Replace remaining "think tool" references
        p = p.replacingOccurrences(of: "Use think tool first.", with: "Write a THINKING section first.")
        p = p.replacingOccurrences(of: "Think tool between sections.", with: "Write a THINKING section between major sections.")
        p = p.replacingOccurrences(of: "Think tool to plan —", with: "Write a THINKING section to plan —")

        // Replace search_swipes reference
        p = p.replacingOccurrences(
            of: "If no swipes loaded, search_swipes proactively.",
            with: "If no swipes are provided, ask which swipes to reference from the uploaded library."
        )

        // Replace save_analysis reference
        p = p.replacingOccurrences(
            of: "Use save_analysis to persist.",
            with: "Include the analysis in your response."
        )

        p = p.replacingOccurrences(
            of: "Review each dimension of the draft and revise anything weak.",
            with: "Self-score each dimension (voice match, format compliance, hook strength, structural integrity, CTA) — revise any below 7/10."
        )

        // Phase awareness cleanup
        p = p.replacingOccurrences(
            of: "BRAINSTORM: Strategy — hook selection, framework, outline, audience. Use think tool first.",
            with: "BRAINSTORM: Strategy — hook selection, framework, outline, audience. Write a THINKING section first."
        )
        p = p.replacingOccurrences(
            of: "DRAFT: Execution — voice matching, beat-by-beat, constraint compliance. Think tool between sections.",
            with: "DRAFT: Execution — voice matching, beat-by-beat, constraint compliance. Write a THINKING section between major sections."
        )

        // Learning section cleanup
        p = p.replacingOccurrences(
            of: "LEARNING: Apply learned preferences proactively. After finalized content, extract lessons (VOICE/STRUCTURE/ARGUMENT/DETAIL/REMOVAL), save actionable rules scoped to client/format/universal.",
            with: "LEARNING: After finalized content, extract lessons (VOICE/STRUCTURE/ARGUMENT/DETAIL/REMOVAL) and list them as actionable rules scoped to client/format/universal."
        )

        return p
    }

    // MARK: - Swipe Export

    /// Export all swipe atoms, organized into Reels/Carousels/Threads folders.
    /// Returns the total number of swipes exported.
    private static func exportSwipes(to folder: URL) async throws -> Int {
        let db = CosmoDatabase.shared
        let allResearch: [Atom] = try await db.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.research.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .order(Atom.CodingKeys.updatedAt.desc)
                .fetchAll(db)
        }

        let swipes = allResearch.filter { $0.isSwipeFileAtom }
        var reelIdx = 1
        var carouselIdx = 1
        var threadIdx = 1

        for swipe in swipes {
            let analysis = swipe.swipeAnalysis
            let format = analysis?.swipeContentFormat ?? guessFormat(from: swipe)
            let title = sanitizeFilename(swipe.title ?? "untitled")

            let content = formatSwipeFile(atom: swipe, analysis: analysis)

            let (subfolder, idx): (String, Int) = {
                switch format {
                case .voiceoverReel, .oneSliderReel, .multiSliderReel, .twoStepCTA, .reel:
                    return ("Reels", reelIdx)
                case .carousel:
                    return ("Carousels", carouselIdx)
                case .thread, .tweet:
                    return ("Threads", threadIdx)
                default:
                    // Default to Reels for unknown formats
                    return ("Reels", reelIdx)
                }
            }()

            let filename = String(format: "swipe_%03d_%@.md", idx, title)
            let filePath = folder.appendingPathComponent(subfolder).appendingPathComponent(filename)
            try content.write(to: filePath, atomically: true, encoding: .utf8)

            switch format {
            case .voiceoverReel, .oneSliderReel, .multiSliderReel, .twoStepCTA, .reel:
                reelIdx += 1
            case .carousel:
                carouselIdx += 1
            case .thread, .tweet:
                threadIdx += 1
            default:
                reelIdx += 1
            }
        }

        return swipes.count
    }

    /// Guess format from research metadata when SwipeAnalysis doesn't have it
    private static func guessFormat(from atom: Atom) -> ContentFormat {
        if let meta = atom.researchMetadata {
            let source = (meta.contentSource ?? "").lowercased()
            if source.contains("reel") || source.contains("video") { return .reel }
            if source.contains("carousel") { return .carousel }
            if source.contains("thread") { return .thread }
        }
        // Check body length heuristic: short = reel, long = carousel
        let bodyLen = (atom.body ?? "").count
        if bodyLen < 500 { return .reel }
        return .carousel
    }

    /// Format a single swipe atom as markdown
    private static func formatSwipeFile(atom: Atom, analysis: SwipeAnalysis?) -> String {
        let title = atom.title ?? "Untitled Swipe"
        let hookText = analysis?.hookText ?? atom.researchMetadata?.hook ?? ""
        let hookType = analysis?.hookType?.displayName ?? "Unknown"
        let hookScore = analysis?.hookScore.map { String(format: "%.1f", $0) } ?? "N/A"
        let framework = analysis?.frameworkType?.displayName ?? "N/A"

        let format: String = {
            if let cf = analysis?.swipeContentFormat { return cf.displayName }
            let guess = guessFormat(from: atom)
            return guess.displayName
        }()

        // Build beat pattern from sections
        let beatPattern: String = {
            if let beats = analysis?.normalizedBeats, !beats.isEmpty {
                return beats.joined(separator: " > ")
            }
            if let sections = analysis?.sections, !sections.isEmpty {
                return sections.map { $0.label }.joined(separator: " > ")
            }
            return "N/A"
        }()

        // Section transitions
        let transitions: String = {
            if let sections = analysis?.sections, !sections.isEmpty {
                return sections.enumerated().map { (i, s) in
                    "\(i + 1). **\(s.label)**: \(s.purpose)"
                }.joined(separator: "\n")
            }
            return "N/A"
        }()

        // CTA (last section usually)
        let cta: String = {
            if let sections = analysis?.sections, let last = sections.last,
               last.label.lowercased().contains("cta") {
                return last.purpose
            }
            return "See full transcript"
        }()

        // Full body
        let body = atom.body ?? ""

        let kind = atom.swipeKind
        var md = """
        # \(title)
        **Type**: SWIPE EXAMPLE (reference content from another creator's library)
        **Kind**: \(kind.displayName)
        **Format**: \(format)
        **Hook Type**: \(hookType)
        **Hook Score**: \(hookScore)/10

        ## Hook
        \(hookText)

        ## Beat Pattern
        \(beatPattern)

        ## Section-by-Section Breakdown
        \(transitions)

        ## CTA
        \(cta)

        ## Framework
        \(framework)
        """

        if let insight = analysis?.keyInsight, !insight.isEmpty {
            md += "\n\n## Key Insight\n\(insight)"
        }

        if let fp = analysis?.beatFingerprint, !fp.isEmpty {
            md += "\n\n## Beat Fingerprint\n\(fp)"
        }

        // Artifact anatomy + units: a page's or a screenshot set's substance
        // lives here, not in `body`. Without this block a captured sales page
        // exports as a title and a hook — which is exactly the "wider library,
        // no more usable" failure the reference layer exists to prevent.
        if let artifact = atom.swipeArtifact, !artifact.units.isEmpty {
            if let anatomy = artifact.anatomy, !anatomy.isEmpty {
                md += "\n\n## Anatomy\n\(anatomy)"
            }
            let units = artifact.orderedUnits.filter(\.hasSubstance)
            if !units.isEmpty {
                let noun = kind.unitNoun.capitalized
                let rendered = units.map { unit -> String in
                    var line = "### \(noun) \(unit.index + 1)"
                    if let role = unit.role { line += " — \(role.displayName)" }
                    if let mechanic = unit.mechanic, !mechanic.isEmpty {
                        line += "\n*\(mechanic)*"
                    }
                    if let copy = unit.copy, !copy.isEmpty {
                        line += "\n\(copy)"
                    }
                    return line
                }.joined(separator: "\n\n")
                md += "\n\n## \(noun)-by-\(noun) Breakdown\n\(rendered)"
            }
        }

        if !body.isEmpty {
            md += "\n\n## Full Transcript\n\(body)"
        }

        return md
    }

    // MARK: - Client Export

    /// Export all client profile atoms with intelligence models, failure fingerprints, and top posts.
    /// Returns the number of clients exported.
    private static func exportClients(to folder: URL) async throws -> Int {
        let fm = FileManager.default
        let db = CosmoDatabase.shared

        let clientAtoms: [Atom] = try await db.asyncRead { db in
            try Atom
                .filter(Atom.CodingKeys.type == AtomType.clientProfile.rawValue)
                .filter(Atom.CodingKeys.isDeleted == false)
                .fetchAll(db)
        }

        for client in clientAtoms {
            guard let meta = client.metadataValue(as: ClientProfileMetadata.self) else { continue }

            let clientName = sanitizeFilename(meta.clientName.isEmpty ? "Unknown" : meta.clientName)
            let clientDir = folder.appendingPathComponent(clientName)
            try fm.createDirectory(at: clientDir, withIntermediateDirectories: true)

            // 1. Profile (intelligence model + brand context)
            let profileContent = formatClientProfile(client: client, meta: meta)
            try profileContent.write(to: clientDir.appendingPathComponent("profile.md"), atomically: true, encoding: .utf8)

            // 2. Failure fingerprint
            let fpContent = formatFailureFingerprint(meta: meta)
            if !fpContent.isEmpty {
                try fpContent.write(to: clientDir.appendingPathComponent("failure_fingerprint.md"), atomically: true, encoding: .utf8)
            }

            // 3. Top posts (from profile documents)
            let topPostsDir = clientDir.appendingPathComponent("top_posts")
            let docs = meta.documents ?? []
            let topDocs = docs.filter { $0.category.isHighPerformer }
            if !topDocs.isEmpty {
                try fm.createDirectory(at: topPostsDir, withIntermediateDirectories: true)
                for (i, doc) in topDocs.enumerated() {
                    let postContent = formatTopPost(doc: doc, index: i + 1)
                    let postFilename = String(format: "post_%03d_%@.md", i + 1, sanitizeFilename(doc.title))
                    try postContent.write(to: topPostsDir.appendingPathComponent(postFilename), atomically: true, encoding: .utf8)
                }
            }
        }

        return clientAtoms.count
    }

    /// Format the full client profile as markdown
    private static func formatClientProfile(client: Atom, meta: ClientProfileMetadata) -> String {
        var md = "# Client Profile: \(meta.clientName)\n\n"

        // Basic info
        if let handle = meta.handle, !handle.isEmpty { md += "**Handle**: \(handle)\n" }
        if let niche = meta.niche, !niche.isEmpty { md += "**Niche**: \(niche)\n" }
        if !meta.platforms.isEmpty { md += "**Platforms**: \(meta.platforms.map { $0.rawValue }.joined(separator: ", "))\n" }
        if let industry = meta.industry, !industry.isEmpty { md += "**Industry**: \(industry)\n" }
        if let audience = meta.targetAudience, !audience.isEmpty { md += "**Target Audience**: \(audience)\n" }
        md += "\n"

        // Intelligence Model (from ClientIntelligenceEngine.getModelForDrafting)
        let modelText = ClientIntelligenceEngine.shared.getModelForDrafting(profile: client)
        if !modelText.isEmpty {
            md += "---\n\n"
            md += "# Intelligence Model\n\n"
            md += modelText
            md += "\n\n"
        }

        // Brand context (supplements the intelligence model)
        var brandSection = ""
        if let story = meta.brandStory, !story.isEmpty {
            brandSection += "## Brand Story\n\(story)\n\n"
        }
        if let vision = meta.brandVision, !vision.isEmpty {
            brandSection += "## Brand Vision\n\(vision)\n\n"
        }
        if let beliefs = meta.coreBeliefs, !beliefs.isEmpty {
            brandSection += "## Core Beliefs\n"
            for belief in beliefs { brandSection += "- \(belief)\n" }
            brandSection += "\n"
        }
        if let voice = meta.voiceNotes, !voice.isEmpty {
            brandSection += "## Voice Notes\n\(voice)\n\n"
        }
        if let angle = meta.uniqueAngle, !angle.isEmpty {
            brandSection += "## Unique Angle\n\(angle)\n\n"
        }
        if let phrases = meta.signaturePhrases, !phrases.isEmpty {
            brandSection += "## Signature Phrases\n"
            for phrase in phrases { brandSection += "- \"\(phrase)\"\n" }
            brandSection += "\n"
        }

        if !brandSection.isEmpty {
            md += "---\n\n# Brand Context\n\n" + brandSection
        }

        // Voice guide documents
        let docs = meta.documents ?? []
        let voiceGuides = docs.filter { $0.category == .voiceGuide }
        if !voiceGuides.isEmpty {
            md += "---\n\n# Voice Guides\n\n"
            for guide in voiceGuides {
                md += "## \(guide.title)\n\(guide.content)\n\n"
            }
        }

        // Brand story documents
        let storyDocs = docs.filter { $0.category == .story }
        if !storyDocs.isEmpty {
            md += "---\n\n# Brand Story Documents\n\n"
            for doc in storyDocs {
                md += "## \(doc.title)\n\(doc.content)\n\n"
            }
        }

        return md
    }

    /// Format failure fingerprint as a standalone file
    private static func formatFailureFingerprint(meta: ClientProfileMetadata) -> String {
        guard let model = meta.intelligenceModel else { return "" }

        var md = "# Failure Fingerprint: \(meta.clientName)\n\n"
        md += "Rules extracted by comparing top performers vs underperformers. Follow these to avoid common mistakes.\n\n"

        var hasContent = false

        if let fp = model.failureFingerprint, !fp.rules.isEmpty {
            md += "## Overall (\(fp.topPerformerCount) top vs \(fp.underperformerCount) under)\n\n"
            md += formatFailureRules(fp)
            hasContent = true
        }

        if let fp = model.reelFailureFingerprint, !fp.rules.isEmpty {
            md += "\n## Reels\n\n"
            md += formatFailureRules(fp)
            hasContent = true
        }

        if let fp = model.threadFailureFingerprint, !fp.rules.isEmpty {
            md += "\n## Threads / Carousels\n\n"
            md += formatFailureRules(fp)
            hasContent = true
        }

        return hasContent ? md : ""
    }

    private static func formatFailureRules(_ fp: FailureFingerprint) -> String {
        var text = ""
        let highRules = fp.rules(severity: .high)
        let mediumRules = fp.rules(severity: .medium)
        let lowRules = fp.rules(severity: .low)

        for rule in highRules {
            text += "- **[HIGH]** \(rule.rule)\n"
        }
        for rule in mediumRules {
            text += "- [MEDIUM] \(rule.rule)\n"
        }
        for rule in lowRules {
            text += "- [LOW] \(rule.rule)\n"
        }
        return text
    }

    /// Format a client's top-performing post as markdown
    private static func formatTopPost(doc: ProfileDocument, index: Int) -> String {
        let format: String = {
            switch doc.category {
            case .reel, .underperformingReel: return "Reel"
            case .thread, .underperformingThread: return "Carousel / Thread"
            default: return "Post"
            }
        }()

        var engagement: [String] = []
        if let likes = doc.likes, likes > 0 { engagement.append("\(formatNumber(likes)) likes") }
        if let shares = doc.shares, shares > 0 { engagement.append("\(formatNumber(shares)) shares") }
        if let saves = doc.saves, saves > 0 { engagement.append("\(formatNumber(saves)) saves") }
        if let comments = doc.comments, comments > 0 { engagement.append("\(formatNumber(comments)) comments") }
        if let leads = doc.leads, leads > 0 { engagement.append("\(formatNumber(leads)) leads") }

        let engagementStr = engagement.isEmpty ? "N/A" : engagement.joined(separator: ", ")

        var md = """
        # \(doc.title)
        **Type**: CLIENT TOP POST (this is the client's OWN content — not a swipe)
        **Format**: \(format)
        **Engagement**: \(engagementStr)
        """

        if let platform = doc.platform, !platform.isEmpty {
            md += "\n**Platform**: \(platform)"
        }

        md += "\n\n## Full Transcript\n\(doc.content)"

        return md
    }

    // MARK: - README

    private static func assembleReadme(swipeCount: Int, clientCount: Int) -> String {
        return """
        # CosmoOS Writing Engine Export

        Exported: \(Date().formatted(date: .abbreviated, time: .shortened))
        Swipes: \(swipeCount) | Clients: \(clientCount)

        ## How to use with Claude Projects (claude.ai)

        ### Step 1: Create a new Project
        Go to claude.ai → Projects → New Project

        ### Step 2: Set Project Instructions
        Open `00_SYSTEM_PROMPT.md` and paste its ENTIRE contents into the Project's **Custom Instructions** field.

        ### Step 3: Upload Swipe Files
        Upload the contents of `Swipes/Reels/` and `Swipes/Carousels/` to **Project Knowledge**.
        You can upload all files at once — Claude will search them when writing.

        ### Step 4: Upload Client Files
        For each client you want to write for, upload their folder contents:
        - `Clients/{Name}/profile.md` — their voice, audience, positioning
        - `Clients/{Name}/failure_fingerprint.md` — what NOT to do
        - `Clients/{Name}/top_posts/*.md` — their best content for voice matching

        ### Step 5: Start Writing
        Open a new chat in the project and provide your brief:

        ```
        Write a carousel for [Client Name].

        Topic: [your idea]
        Framework: [optional — e.g., PAS, AIDA, Escalation Arc]
        Reference swipes: [optional — name specific swipes to use as blueprints]
        ```

        Claude will follow the full methodology: think first, find blueprint swipes,
        extract structure, write in client voice, self-evaluate, and output in the
        correct format.

        ## File Organization

        - `Swipes/Reels/` — Reel swipes (reference examples from other creators)
        - `Swipes/Carousels/` — Carousel swipes
        - `Swipes/Threads/` — Thread swipes
        - `Clients/{Name}/profile.md` — Intelligence model + brand context
        - `Clients/{Name}/failure_fingerprint.md` — Anti-patterns to avoid
        - `Clients/{Name}/top_posts/` — Client's own best content (for voice matching)

        **Important**: Swipes are reference examples from OTHER creators' libraries.
        Client top posts are the CLIENT'S OWN content. Claude uses swipes for structure
        and top posts for voice matching.
        """
    }

    // MARK: - Helpers

    private static func sanitizeFilename(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "|", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = String(cleaned.prefix(60))
        return truncated.isEmpty ? "untitled" : truncated
    }

    private static func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

