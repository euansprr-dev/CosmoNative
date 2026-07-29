// CosmoOS/SwipeFile/Artifacts/SwipeLensRouter.swift
// Which lens does this capture want — swipe (its FORM) or research (its
// CLAIMS)? And the ledger that learns the answer per domain.
//
// THE DISTINCTION, stated once: you re-open a swipe to copy HOW it is built;
// you re-open research to learn WHAT it says. The same URL can be either, which
// is exactly why guessing from the URL alone always felt arbitrary. So the
// ladder decides on STATE — which surface it arrived through, what platform it
// is, what shape the page measured, what you have decided about this domain
// before — and only falls back to reading the capture's wording last.
//
// Per feedback_no_bandaids: the prose rule is the LAST tier and never the
// mechanism. Adding a keyword fixes one capture; the tiers above it fix a class.

import Foundation

// MARK: - The verdict

struct SwipeLensVerdict: Equatable, Sendable {
    var lens: SwipeLens
    /// Shown to the user, always. A system that guesses silently reads
    /// arbitrary the first time it guesses wrong; one that shows its reasoning
    /// reads confident and tells you exactly what to correct.
    var reason: String
    /// Which tier decided — the correction ledger records this so a wrong
    /// answer can be traced to the rule that produced it.
    var tier: Tier

    enum Tier: String, Equatable, Sendable {
        case surface, platform, pageShape, domainPrior, prose, fallback
    }
}

// MARK: - Router

@MainActor
enum SwipeLensRouter {

    /// Everything the ladder can look at. A caller supplies what it has;
    /// absent signals simply skip their tier.
    struct Signals {
        /// The capture arrived through a surface that MEANS swipe (⌘⇧S, the
        /// share sheet's "Swipe file", a library drop).
        var explicitSwipeSurface = false
        var url: String?
        /// The capture's own words — prose the user typed around the link.
        var prose: String?
        /// Measured page structure, when a page was actually rendered.
        var pageShape: SwipePageShape?

        init(
            explicitSwipeSurface: Bool = false,
            url: String? = nil,
            prose: String? = nil,
            pageShape: SwipePageShape? = nil
        ) {
            self.explicitSwipeSurface = explicitSwipeSurface
            self.url = url
            self.prose = prose
            self.pageShape = pageShape
        }
    }

    static func inferLens(_ signals: Signals) -> SwipeLensVerdict {
        // 1. The surface is the strongest signal there is — the user already
        //    said what they meant by choosing where to put it.
        if signals.explicitSwipeSurface {
            return SwipeLensVerdict(lens: .swipe, reason: "You swiped it", tier: .surface)
        }

        // 2. Platform family. Nobody saves an Instagram reel for its claims.
        if let url = signals.url, let platform = platformFamily(of: url) {
            return SwipeLensVerdict(
                lens: .swipe, reason: "\(platform) post", tier: .platform
            )
        }

        // 3. Measured page shape. This is the tier that makes a sales page and
        //    a long article — the same kind of URL — land differently.
        if let shape = signals.pageShape, let verdict = verdict(for: shape) {
            return verdict
        }

        // 4. What you have decided about this domain before.
        if let host = host(of: signals.url), let verdict = SwipeDomainPrior.shared.verdict(forHost: host) {
            return verdict
        }

        // 5. The capture's own wording. LAST, and never the mechanism.
        if let prose = signals.prose, let verdict = proseVerdict(prose) {
            return verdict
        }

        // Research is the safer default for an unknown link: it costs a bit of
        // reading either way, whereas a wrongly-swiped article pollutes the
        // reference library the writing engine draws on.
        return SwipeLensVerdict(lens: .research, reason: "Unrecognised source", tier: .fallback)
    }

    // MARK: Tier 2 — platform

    static func platformFamily(of url: String) -> String? {
        let lowered = url.lowercased()
        if lowered.contains("instagram.com") { return "Instagram" }
        if lowered.contains("tiktok.com") { return "TikTok" }
        if lowered.contains("youtube.com/shorts") { return "YouTube Shorts" }
        if lowered.contains("twitter.com") || lowered.range(
            of: #"(^|/|\.)x\.com"#, options: .regularExpression
        ) != nil { return "X" }
        if lowered.contains("threads.net") { return "Threads" }
        return nil
    }

    // MARK: Tier 3 — page shape

    /// A page that prices something and asks for the sale is craft reference.
    /// A page that is fifteen paragraphs with nothing to click is something to
    /// read. The thresholds are deliberately far apart — a page that is neither
    /// falls through to the tiers below rather than being forced.
    static func verdict(for shape: SwipePageShape) -> SwipeLensVerdict? {
        if shape.hasPricingTable {
            return SwipeLensVerdict(lens: .swipe, reason: "Has a pricing table", tier: .pageShape)
        }
        if shape.testimonialCount >= 2, shape.ctaCount >= 1 {
            return SwipeLensVerdict(
                lens: .swipe,
                reason: "\(shape.testimonialCount) testimonials and a call to action",
                tier: .pageShape
            )
        }
        if shape.ctaCount >= 4 {
            return SwipeLensVerdict(
                lens: .swipe, reason: "Asks \(shape.ctaCount) times", tier: .pageShape
            )
        }
        if shape.paragraphCount >= 15, shape.ctaCount == 0 {
            return SwipeLensVerdict(
                lens: .research,
                reason: "\(shape.paragraphCount) paragraphs, no call to action",
                tier: .pageShape
            )
        }
        return nil
    }

    // MARK: Tier 5 — prose

    /// Words that name the CRAFT vs words that name the CLAIM. Kept short on
    /// purpose: this is a tiebreak for captures the tiers above could not
    /// place, not a classifier. Anything ambiguous falls through.
    private static let craftWords = [
        "hook", "angle", "structure", "format", "layout", "copy", "headline",
        "funnel", "offer", "cta", "swipe", "steal", "template"
    ]
    private static let claimWords = [
        "stat", "data", "source", "study", "research", "evidence", "proof that",
        "according to", "report", "cite"
    ]

    static func proseVerdict(_ prose: String) -> SwipeLensVerdict? {
        let lowered = prose.lowercased()
        let craft = craftWords.first { lowered.contains($0) }
        let claim = claimWords.first { lowered.contains($0) }
        // Both present is genuinely ambiguous — fall through rather than
        // letting whichever list happened to be checked first decide.
        if let craft, claim == nil {
            return SwipeLensVerdict(lens: .swipe, reason: "You wrote \u{201C}\(craft)\u{201D}", tier: .prose)
        }
        if let claim, craft == nil {
            return SwipeLensVerdict(lens: .research, reason: "You wrote \u{201C}\(claim)\u{201D}", tier: .prose)
        }
        return nil
    }

    // MARK: Host

    static func host(of url: String?) -> String? {
        guard let url, let components = URLComponents(string: url.trimmingCharacters(in: .whitespaces)),
              var host = components.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host.isEmpty ? nil : host
    }

    /// Record what the user actually chose, so the domain prior learns.
    /// Called from every override, never from an accepted suggestion — the
    /// ledger is a record of CORRECTIONS and confirmations the user made, not
    /// of the router agreeing with itself.
    static func recordDecision(lens: SwipeLens, url: String?) {
        guard let host = host(of: url) else { return }
        SwipeDomainPrior.shared.record(lens: lens, host: host)
    }
}

// MARK: - Domain prior

/// What you have decided about this domain before.
///
/// A JSON ledger in App Support rather than atoms: it is per-device
/// preference, it changes on every triage, and syncing it would add churn to
/// the atom stream for no benefit (the same reasoning as `SwipePatternStore`).
@MainActor
final class SwipeDomainPrior {
    static let shared = SwipeDomainPrior()

    /// Below three decisions a host has no prior worth trusting — one
    /// accidental choice must not stamp every later capture from that domain.
    static let minimumDecisions = 3
    /// And the decisions must actually agree. A host you have split 50/50 is
    /// genuinely ambiguous and should fall through to the tiers below.
    static let agreementThreshold = 0.75

    private struct Counts: Codable {
        var swipe = 0
        var research = 0

        var total: Int { swipe + research }
    }

    private var counts: [String: Counts] = [:]

    private init() { load() }

    /// nil when the host has no confident prior — the ladder continues.
    func verdict(forHost host: String) -> SwipeLensVerdict? {
        guard let entry = counts[host], entry.total >= Self.minimumDecisions else { return nil }
        let swipeShare = Double(entry.swipe) / Double(entry.total)
        if swipeShare >= Self.agreementThreshold {
            return SwipeLensVerdict(
                lens: .swipe,
                reason: "You swipe \(host)",
                tier: .domainPrior
            )
        }
        if (1 - swipeShare) >= Self.agreementThreshold {
            return SwipeLensVerdict(
                lens: .research,
                reason: "You read \(host)",
                tier: .domainPrior
            )
        }
        return nil
    }

    func record(lens: SwipeLens, host: String) {
        var entry = counts[host] ?? Counts()
        switch lens {
        case .swipe: entry.swipe += 1
        case .research: entry.research += 1
        }
        counts[host] = entry
        save()
    }

    /// Test seam + a reset the user can reach if a prior goes wrong.
    func forget(host: String) {
        counts.removeValue(forKey: host)
        save()
    }

    func decisionCount(forHost host: String) -> Int {
        counts[host]?.total ?? 0
    }

    // MARK: Persistence

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cosmoDir = appSupport.appendingPathComponent("CosmoOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: cosmoDir, withIntermediateDirectories: true)
        return cosmoDir.appendingPathComponent("swipe_domain_priors.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Counts].self, from: data) else { return }
        counts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
