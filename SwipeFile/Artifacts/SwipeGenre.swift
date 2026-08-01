// CosmoOS/SwipeFile/Artifacts/SwipeGenre.swift
// The browsing vocabulary: what a swipe IS to the person who collects it.
//
// KIND is structure — how an artifact decomposes (a page has sections, a flow
// has steps). GENRE is medium — what the artifact is in the collector's mental
// model ("a newsletter", "a sales page", "an ad"). The two are deliberately
// separate axes because they answer different questions: the study bench and
// the analyzers fork on KIND; the sidebar's spaces and the library's shelves
// fork on GENRE. "Newsletters" and "sales pages" are both kind `.page`, which
// is exactly why kind alone cannot organize the library — it would recreate
// the mixed-everything junk drawer one level down.
//
// CLOSED-VOCABULARY LAW (same as SwipeUnitRole): analyzers map onto one of
// these or keep the structural fallback. Free-text genres would fragment the
// sidebar the way free-text niches did before NicheRegistry.
//
// DERIVE-NEVER-MIGRATE (same as SwipeKind): `Atom.swipeGenre` resolves for
// every swipe ever captured without touching a single existing row — the
// metadata hint wins when present, then the envelope, then a total per-kind
// default. No backfill pass exists.
//
// Kept `public` because this file is duplicated Mac <-> iOS (CosmoCoreKit);
// the iOS copy must stay byte-identical in its model surface.

import Foundation

// MARK: - Genre

/// What a swipe IS, in the collector's language. TEN, CLOSED.
///
/// `.page` and `.screenshot` are the honest structural fallbacks — "captured,
/// not yet classified (or genuinely miscellaneous)". They are real spaces like
/// any other, visible only when non-empty, so nothing is ever invisible while
/// an analysis is still in flight.
public enum SwipeGenre: String, Codable, Sendable, CaseIterable {
    /// Social posts — every kind `.post` swipe, always. Posts never store a
    /// genre; the whole pre-spine library derives here.
    case post
    /// An email newsletter issue — a Substack/beehiiv page, a dragged-in
    /// email, a screenshotted edition.
    case newsletter
    /// An opt-in / lead-magnet / squeeze page: short, one ask.
    case landingPage
    /// A long-form sales page, VSL page, checkout or pricing page.
    case salesPage
    /// Paid ad creative — ad-library captures, screenshotted ads.
    case ad
    /// An ordered walk through steps — every kind `.flow` swipe.
    case funnel
    /// A full script: VSL, video, webinar — long copy with beats.
    case script
    /// Short saved copy: a headline, a hook, a line worth keeping.
    case copy
    /// Kind `.frame` fallback: screenshots not (yet) classified further.
    case screenshot
    /// Kind `.page` fallback: pages not (yet) classified further.
    case page

    public var displayName: String {
        switch self {
        case .post: return "Post"
        case .newsletter: return "Newsletter"
        case .landingPage: return "Landing Page"
        case .salesPage: return "Sales Page"
        case .ad: return "Ad"
        case .funnel: return "Funnel"
        case .script: return "Script"
        case .copy: return "Copy"
        case .screenshot: return "Screenshot"
        case .page: return "Page"
        }
    }

    /// Sidebar rows, mastheads, shelf headers.
    public var pluralName: String {
        switch self {
        case .post: return "Posts"
        case .newsletter: return "Newsletters"
        case .landingPage: return "Landing Pages"
        case .salesPage: return "Sales Pages"
        case .ad: return "Ads"
        case .funnel: return "Funnels"
        case .script: return "Scripts"
        case .copy: return "Copy"
        case .screenshot: return "Screenshots"
        case .page: return "Pages"
        }
    }

    public var iconName: String {
        switch self {
        case .post: return "rectangle.stack"
        case .newsletter: return "envelope"
        case .landingPage: return "rectangle.and.text.magnifyingglass"
        case .salesPage: return "dollarsign.square"
        case .ad: return "megaphone"
        case .funnel: return "arrow.trianglehead.branch"
        case .script: return "text.document"
        case .copy: return "text.quote"
        case .screenshot: return "photo.on.rectangle.angled"
        case .page: return "doc.richtext"
        }
    }

    /// The structural fallback for a kind. TOTAL — every swipe answers, which
    /// is what lets `Atom.swipeGenre` resolve with zero migration.
    public static func defaultGenre(for kind: SwipeKind) -> SwipeGenre {
        switch kind {
        case .post: return .post
        case .page: return .page
        case .frame: return .screenshot
        case .flow: return .funnel
        case .note: return .copy
        }
    }

    /// True when this genre is just its kind's structural fallback — the
    /// receipt and the metadata hint both treat "still the default" as
    /// "nothing decided yet".
    public func isStructuralFallback(for kind: SwipeKind) -> Bool {
        self == SwipeGenre.defaultGenre(for: kind)
    }

    /// Tolerance differs from SwipeKind's on purpose: kind clamps unknowns to
    /// `.post` because that IS the safe total answer; genre has no one safe
    /// answer across kinds, so an unknown value THROWS and the envelope's
    /// `try? decodeIfPresent` turns it into nil — readers then fall back to
    /// the kind default through `Atom.swipeGenre`. A newer build's genre never
    /// poisons the enclosing artifact decode, and never masquerades as a
    /// wrong-but-confident space.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let known = SwipeGenre(rawValue: raw) ?? SwipeGenre.resolve(raw) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown SwipeGenre: \(raw)"
            ))
        }
        self = known
    }

    /// Map a model's (or an old build's) answer onto the closed vocabulary.
    /// Case- and separator-insensitive plus a short synonym net — a safety net
    /// for near-misses, NOT a classifier. Unlisted answers return nil and the
    /// caller keeps the structural default, which is a visible, fixable state.
    public static func resolve(_ raw: String?) -> SwipeGenre? {
        guard let raw else { return nil }
        let key = raw.lowercased()
            .replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression)
        guard !key.isEmpty else { return nil }
        if let exact = allCases.first(where: {
            $0.rawValue.lowercased() == key
        }) { return exact }
        switch key {
        case "socialpost", "posts", "reel", "carousel", "thread", "tweet":
            return .post
        case "email", "edition", "issue", "emailnewsletter", "newsletters":
            return .newsletter
        case "optin", "optinpage", "squeeze", "squeezepage", "leadmagnet",
             "leadcapture", "landingpages", "landing":
            return .landingPage
        case "vsl", "vslpage", "checkout", "checkoutpage", "pricing",
             "pricingpage", "salespages", "sales", "salesletter", "longformsales":
            return .salesPage
        case "advert", "advertisement", "adcreative", "creative", "paidad",
             "ads", "fbad", "metaad":
            return .ad
        case "sequence", "emailsequence", "funnels", "flow":
            return .funnel
        case "vslscript", "videoscript", "webinarscript", "scripts":
            return .script
        case "hook", "headline", "snippet", "copysnippet", "swipedcopy", "note":
            return .copy
        case "screenshots", "screengrab", "capture":
            return .screenshot
        case "webpage", "pages", "website":
            return .page
        default:
            return nil
        }
    }

    // MARK: Prompt vocabulary

    /// One line per genre, fed VERBATIM into the artifact analyzer prompt —
    /// the model is never asked to infer a genre's meaning from its name.
    public var promptDefinition: String {
        switch self {
        case .post: return "a social post — reel, carousel, tweet, thread, short"
        case .newsletter: return "an email newsletter issue — written to be read in an inbox, dated, from a named sender or publication"
        case .landingPage: return "a short page with ONE ask — capture an email, book a call, start a trial; little or no price talk"
        case .salesPage: return "a page that sells — long-form pitch, VSL page, pricing, checkout; it names a price or drives directly to one"
        case .ad: return "paid ad creative — the artifact itself is an advertisement (ad-library capture, screenshotted ad)"
        case .funnel: return "an ordered sequence of steps someone walks through"
        case .script: return "a full script meant to be performed or read aloud — VSL, video, webinar; has beats, not sections"
        case .copy: return "a short piece of saved copy — a headline, a hook, a few lines"
        case .screenshot: return "screenshots that fit none of the above — use this rather than forcing a fit"
        case .page: return "a web page that fits none of the above — use this rather than forcing a fit"
        }
    }

    /// The block the analyzer prompt embeds, mirroring
    /// `SwipeUnitRole.promptVocabulary`.
    public static var promptVocabulary: String {
        allCases.map { "  \($0.rawValue) — \($0.promptDefinition)" }.joined(separator: "\n")
    }
}

// MARK: - Capture-time seeds

/// Genre inference from what capture already knows, BEFORE any model call —
/// so a Substack link lands in Newsletters the moment it is swiped, not a
/// model-round-trip later. State before prose, always: these are host/path
/// facts, then measured page shape; the analyzer refines afterwards.
public enum SwipeGenreSeed {

    /// Host/path heuristics. Returns nil when nothing is confidently known —
    /// callers keep the kind default and let the analyzer decide.
    public static func infer(url raw: String?) -> SwipeGenre? {
        guard let raw, let components = URLComponents(string: raw.trimmingCharacters(in: .whitespaces)),
              var host = components.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        let path = components.path.lowercased()

        // Newsletter platforms. Substack/beehiiv product pages exist too, but a
        // captured PAGE from these hosts is overwhelmingly an issue or archive.
        let newsletterHosts = [
            "substack.com", "beehiiv.com", "mailchi.mp", "buttondown.com",
            "buttondown.email", "convertkit.com", "kit.com", "ghost.io"
        ]
        if newsletterHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .newsletter
        }
        if host.hasSuffix("campaign-archive.com") { return .newsletter }
        // A captured Gmail view is overwhelmingly an email being saved.
        if host == "mail.google.com" { return .newsletter }

        // Ad libraries.
        if host == "facebook.com", path.hasPrefix("/ads/library") { return .ad }
        if host == "adstransparency.google.com" { return .ad }
        if host == "linkedin.com", path.hasPrefix("/ad-library") { return .ad }

        // Commerce paths. Deliberately narrow — a blog post ABOUT pricing has
        // "/pricing" nowhere in its path; these match the page's own address.
        let salesSegments = ["/pricing", "/checkout", "/order", "/buy"]
        if salesSegments.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return .salesPage
        }

        return nil
    }

    /// Measured page shape → genre, the same far-apart-thresholds philosophy
    /// as `SwipeLensRouter.verdict(for:)`: a page that is neither falls
    /// through to the analyzer rather than being forced.
    /// Internal (not public): `SwipePageShape` only exists on the Mac — the
    /// iOS twin of this file carries the URL seed alone.
    static func infer(shape: SwipePageShape) -> SwipeGenre? {
        if shape.hasPricingTable { return .salesPage }
        if shape.ctaCount >= 1, shape.paragraphCount < 8 { return .landingPage }
        return nil
    }
}
