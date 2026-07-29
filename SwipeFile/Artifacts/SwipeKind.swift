// CosmoOS/SwipeFile/Artifacts/SwipeKind.swift
// The swipe spine's vocabulary: what KIND of artifact a swipe is, what ROLE
// each of its units plays, and which LENS (form vs knowledge) a source carries.
//
// One law holds the whole design together:
//
//   A swipe is an ordered list of units. A unit has a role, verbatim copy,
//   a mechanic, and (usually) an image.
//
// A carousel's slides, a sales page's sections, a screenshot set's frames and
// a funnel's steps are all that same shape — which is why the pager, masonry,
// study bench and board plumbing carry over unchanged across kinds, and why
// retrieval can ask one question ("show me guarantee units") across every
// medium.
//
// Kept `public` because SwipeAnalysis.swift and friends are duplicated
// Mac <-> iOS (CosmoCoreKit); this file is a straight copy on that side.

import Foundation

// MARK: - Kind

/// What kind of artifact a swipe is. FIVE, CLOSED.
///
/// Long-form (podcast, webinar, VSL) is deliberately NOT a sixth case — it is
/// a `.post` whose units are chapters. Its anatomy differs from a reel's by
/// roughly a fifth, and a sixth case is a permanent tax on every menu, filter,
/// switch and card in both apps.
public enum SwipeKind: String, Codable, Sendable, CaseIterable {
    /// Reel, carousel, tweet, thread, short, YouTube — everything the swipe
    /// file held before the artifact spine. Every legacy swipe derives to this.
    case post
    /// A captured web page: sales page, landing page, pricing, opt-in,
    /// newsletter archive. Units are the page's sections, top to bottom.
    case page
    /// Screenshots / photos — one or many images, no URL required. Units are
    /// the images.
    case frame
    /// An ordered sequence of member swipes (a funnel, an email sequence).
    /// Units point at other swipes via `memberSwipeUUID`.
    case flow
    /// Raw text: a headline, a hook, a line of copy. One unit.
    case note

    public var displayName: String {
        switch self {
        case .post: return "Post"
        case .page: return "Page"
        case .frame: return "Frame"
        case .flow: return "Flow"
        case .note: return "Note"
        }
    }

    /// Plural for shelf headers and facet rows ("PAGES", "FRAMES").
    public var pluralName: String {
        switch self {
        case .post: return "Posts"
        case .page: return "Pages"
        case .frame: return "Frames"
        case .flow: return "Flows"
        case .note: return "Notes"
        }
    }

    /// SF Symbol. The card glyph and the filter row share it.
    public var iconName: String {
        switch self {
        case .post: return "rectangle.stack"
        case .page: return "doc.richtext"
        case .frame: return "photo.on.rectangle.angled"
        case .flow: return "arrow.trianglehead.branch"
        case .note: return "text.quote"
        }
    }

    /// The noun a unit of this kind is called, singular — used in counts
    /// ("14 sections", "3 images") so the UI never says "3 units".
    public var unitNoun: String {
        switch self {
        case .post: return "slide"
        case .page: return "section"
        case .frame: return "image"
        case .flow: return "step"
        case .note: return "line"
        }
    }

    public func unitCountLabel(_ count: Int) -> String {
        count == 1 ? "1 \(unitNoun)" : "\(count) \(unitNoun)s"
    }

    /// Kinds the Railway worker may process. Only `.post` — every other kind
    /// is captured and decomposed on the Mac, and the worker has no extractor
    /// for it. See the SCOPE-TWIN LAW on `SwipeProcessingService`.
    public var isCloudProcessable: Bool { self == .post }

    /// Tolerant decode: a row written by a newer build must not poison the
    /// whole artifact decode. Unknown kinds read as `.post`, the safe default
    /// (it is what every legacy swipe derives to anyway).
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SwipeKind(rawValue: raw) ?? .post
    }
}

// MARK: - Unit role

/// What a single unit is DOING. One flat vocabulary across every kind, so a
/// query for "guarantee" spans a sales-page section, a carousel slide and a
/// screenshot alike.
///
/// CLOSED-VOCABULARY LAW: analyzers map to one of these or `.other`. Free-text
/// roles fragment retrieval exactly the way free-text niches did before
/// `NicheRegistry` (330 swipes produced 140 fragment labels). If a genuinely
/// new role is needed, add a case here and to the analyzer prompts together —
/// never let a model invent one.
public enum SwipeUnitRole: String, Codable, Sendable, CaseIterable {
    // Opening
    case hook, promise, problem, agitation
    // Body
    case mechanism, story, teaching, demonstration, comparison
    // Belief
    case proof, credibility, testimonial, objection, guarantee
    // Commerce
    case offer, deliverables, pricing, bonus, urgency
    // Close
    case cta, footer
    // Catch-alls
    case visual, other

    public var displayName: String {
        switch self {
        case .hook: return "Hook"
        case .promise: return "Promise"
        case .problem: return "Problem"
        case .agitation: return "Agitation"
        case .mechanism: return "Mechanism"
        case .story: return "Story"
        case .teaching: return "Teaching"
        case .demonstration: return "Demonstration"
        case .comparison: return "Comparison"
        case .proof: return "Proof"
        case .credibility: return "Credibility"
        case .testimonial: return "Testimonial"
        case .objection: return "Objection"
        case .guarantee: return "Guarantee"
        case .offer: return "Offer"
        case .deliverables: return "Deliverables"
        case .pricing: return "Pricing"
        case .bonus: return "Bonus"
        case .urgency: return "Urgency"
        case .cta: return "CTA"
        case .footer: return "Footer"
        case .visual: return "Visual"
        case .other: return "Other"
        }
    }

    public var family: SwipeUnitRoleFamily {
        switch self {
        case .hook, .promise, .problem, .agitation:
            return .opening
        case .mechanism, .story, .teaching, .demonstration, .comparison:
            return .body
        case .proof, .credibility, .testimonial, .objection, .guarantee:
            return .belief
        case .offer, .deliverables, .pricing, .bonus, .urgency:
            return .commerce
        case .cta, .footer:
            return .close
        case .visual, .other:
            return .other
        }
    }

    /// One line per role, fed VERBATIM into the analyzer prompts. The model is
    /// never asked to infer what a role means from its name — every prompt
    /// carries these definitions so "proof" and "credibility" cannot drift
    /// into each other between the frame pass and the page pass.
    public var promptDefinition: String {
        switch self {
        case .hook: return "the opening line whose only job is to stop the scroll or hold the eye"
        case .promise: return "states what the reader will get or become"
        case .problem: return "names the reader's current pain or situation"
        case .agitation: return "makes an already-named problem feel more urgent or costly"
        case .mechanism: return "explains HOW the thing works — the method, framework, or process"
        case .story: return "a narrative with a person, a sequence of events, and a turn"
        case .teaching: return "delivers usable information the reader could act on immediately"
        case .demonstration: return "shows the thing working — a walkthrough, a before/after, a live example"
        case .comparison: return "sets two options, approaches, or time periods against each other"
        case .proof: return "evidence a claim is true — numbers, screenshots, dated receipts, data"
        case .credibility: return "why THIS source is worth believing — track record, credentials, scale"
        case .testimonial: return "another customer's words or result, attributed to them"
        case .objection: return "raises a reason not to buy or believe, then answers it"
        case .guarantee: return "removes the reader's risk — refund terms, a promise, a safety net"
        case .offer: return "what is being sold, as a whole"
        case .deliverables: return "the itemised list of what is included"
        case .pricing: return "the price, payment options, or value stack arithmetic"
        case .bonus: return "an extra thrown in on top of the core offer"
        case .urgency: return "a deadline, a cap, or a reason to act now rather than later"
        case .cta: return "asks the reader to take one specific action"
        case .footer: return "legal text, contact details, small print, navigation"
        case .visual: return "carries no readable copy — the image itself IS the content"
        case .other: return "none of the above fits; use this rather than inventing a role"
        }
    }

    /// The block every analyzer prompt embeds. Keeping this in one place is
    /// what makes the frame pass and the page pass speak the same language.
    public static var promptVocabulary: String {
        SwipeUnitRoleFamily.allCases.map { family in
            let lines = allCases
                .filter { $0.family == family }
                .map { "  \($0.rawValue) — \($0.promptDefinition)" }
                .joined(separator: "\n")
            return "\(family.displayName.uppercased()):\n\(lines)"
        }.joined(separator: "\n")
    }

    /// Tolerant decode — same reasoning as `SwipeKind`. An unrecognised role
    /// reads as `.other` rather than failing the enclosing artifact decode.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SwipeUnitRole(rawValue: raw) ?? .other
    }

    /// Map a model's answer onto the closed vocabulary. Case- and
    /// separator-insensitive so `"Risk Reversal"`, `"call_to_action"` and
    /// `"CTA"` all land somewhere real instead of spawning a label.
    public static func resolve(_ raw: String?) -> SwipeUnitRole? {
        guard let raw else { return nil }
        let key = raw.lowercased()
            .replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression)
        guard !key.isEmpty else { return nil }
        if let exact = allCases.first(where: {
            $0.rawValue.replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression) == key
        }) { return exact }
        // Common synonyms the models reach for. Deliberately short: this is a
        // safety net for near-misses, NOT a general classifier. Anything not
        // listed lands on `.other`, which is a visible, fixable state.
        switch key {
        case "riskreversal", "refund", "moneyback": return .guarantee
        case "calltoaction", "buybutton", "signup": return .cta
        case "socialproof", "results", "casestudy": return .proof
        case "authority", "bio", "about": return .credibility
        case "review", "reviews", "quote": return .testimonial
        case "faq", "faqs", "objections": return .objection
        case "price", "plans", "pricingtable": return .pricing
        case "whatsincluded", "included", "features": return .deliverables
        case "scarcity", "deadline", "countdown": return .urgency
        case "headline", "opener", "openinghook": return .hook
        case "benefit", "benefits", "outcome": return .promise
        case "painpoint", "pain": return .problem
        case "howitworks", "method", "framework", "system": return .mechanism
        case "image", "photo", "graphic": return .visual
        default: return .other
        }
    }
}

/// Role grouping. Exists so filter UI shows five groups, never a wall of chips.
public enum SwipeUnitRoleFamily: String, Codable, Sendable, CaseIterable {
    case opening, body, belief, commerce, close, other

    public var displayName: String {
        switch self {
        case .opening: return "Opening"
        case .body: return "Body"
        case .belief: return "Belief"
        case .commerce: return "Commerce"
        case .close: return "Close"
        case .other: return "Other"
        }
    }

    public var roles: [SwipeUnitRole] {
        SwipeUnitRole.allCases.filter { $0.family == self }
    }
}

// MARK: - Lens

/// What a captured source is FOR. A source can carry both.
///
/// Swipe and research have always lived on the same atom type (`.research`,
/// with `metadata.isSwipeFile`), so this is naming a distinction the schema
/// already had rather than introducing one. The payoff: the same URL is never
/// captured twice, and "also keep as research" is a bit-flip plus a
/// decomposition pass — never a re-fetch, never a second row.
public enum SwipeLens: String, Codable, Sendable, CaseIterable {
    /// You care about its FORM — how it is written, laid out, or sold.
    case swipe
    /// You care about its CONTENT — what it claims, and whether that is true.
    case research

    public var displayName: String {
        switch self {
        case .swipe: return "Swipe"
        case .research: return "Research"
        }
    }

    public var iconName: String {
        switch self {
        case .swipe: return "rectangle.stack"
        case .research: return "books.vertical"
        }
    }
}
