// CosmoOS/SwipeFile/CreatorIdentity.swift
// ONE identity for a creator across every path that touches one — the AI
// classifier, the Apify importer, Discover saves, the Study link picker and
// the repair sweep. Before this file there were five handle normalizers with
// three conventions, and a creator's "platform" was written from the capture
// channel ("clipboard"), so the importer could never find the classifier's
// creator and minted a twin. Handles normalize to one key here; platforms
// come from the post's honest source, never from how it was captured.
// September 2026

import Foundation

enum CreatorIdentity {

    /// Path segments that are never a profile handle.
    static let reservedPathSegments: Set<String> = [
        "p", "reel", "reels", "tv", "stories", "explore", "accounts", "shorts", "watch",
        "channel", "c", "user", "u", "video", "status", "i", "home", "www", "in", "posts",
    ]

    /// The comparison key: lowercase, no "@", trimmed, URL debris and a
    /// trailing "| Real Estate Investor" stripped, only the characters a handle
    /// can carry. nil when empty or a leaked numeric id.
    static func key(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }
        if value.contains("/") {
            let parts = value.split(separator: "/").map(String.init)
                .filter { !$0.isEmpty && !$0.hasSuffix(":") && !$0.contains(".") }
            value = parts.first { !reservedPathSegments.contains($0) } ?? ""
        }
        if let pipe = value.firstIndex(of: "|") { value = String(value[..<pipe]) }
        value = value.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("@") { value.removeFirst() }
        value = value.replacingOccurrences(of: " ", with: "_")
        let allowed = value.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "." || $0 == "-"
        }
        value = String(String.UnicodeScalarView(allowed))
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        guard !value.isEmpty, !value.allSatisfy(\.isNumber) else { return nil }
        return value
    }

    /// Separator-blind key: "josh_villareal" and "joshvillareal" meet here.
    /// Only the repair sweep and name-derived resolutions use it.
    static func looseKey(_ key: String) -> String {
        key.filter { $0 != "_" && $0 != "." && $0 != "-" }
    }

    static func displayHandle(_ key: String) -> String { "@" + key }

    /// True when `handle` was spelled from the author's display name rather
    /// than read off the platform — such a handle may merge with the real one.
    static func isDerivedFromDisplayName(handle: String?, atom: Atom) -> Bool {
        guard let handleKey = key(handle) else { return false }
        if let username = key(atom.richContent?.instagramData?.authorUsername), username == handleKey { return false }
        return key(atom.richContent?.author) == handleKey
    }

    // MARK: - Platform (the honest source)

    static func platform(fromSourceKey raw: String?) -> SocialPlatform? {
        guard let raw = raw?.lowercased(), !raw.isEmpty else { return nil }
        if raw.contains("instagram") || raw.contains("reel") { return .instagram }
        if raw.contains("youtube") || raw.contains("short") { return .youtube }
        if raw.contains("tiktok") { return .tiktok }
        if raw == "x" || raw.contains("x_post") || raw.contains("xpost") || raw.contains("twitter") { return .x }
        if raw.contains("threads") { return .threads }
        if raw.contains("linkedin") { return .linkedin }
        if raw.contains("substack") { return .substack }
        if raw.contains("facebook") { return .facebook }
        if raw.contains("medium") { return .medium }
        return nil
    }

    static func platform(fromURL string: String?) -> SocialPlatform? {
        guard let string, let host = URL(string: string)?.host?.lowercased() else { return nil }
        return platform(fromSourceKey: host)
    }

    /// Where a swipe honestly came from: its source type, then a platform-
    /// shaped content source ("instagram", "youtube"), then the URL host.
    /// Capture channels ("clipboard", "capture", "creator_import") read as nil.
    static func platform(for atom: Atom) -> SocialPlatform? {
        platform(fromSourceKey: atom.richContent?.sourceType?.rawValue)
            ?? platform(fromSourceKey: atom.researchMetadata?.contentSource)
            ?? platform(fromURL: atom.researchMetadata?.url)
    }

    /// A creator's stored platform, cleaned: legacy capture channels and
    /// "other"/"unknown" read as unknown.
    static func platform(fromCreatorPlatform raw: String?) -> SocialPlatform? {
        if let known = platform(fromSourceKey: raw) { return known }
        guard let raw, let value = SocialPlatform(rawValue: raw), value != .other else { return nil }
        return value
    }

    // MARK: - Author derivation (the one copy)

    struct Resolution: Equatable {
        var handle: String?
        var name: String?
        var derivedFromDisplayName: Bool
    }

    /// What a captured swipe says about its author, best source first: the
    /// platform's real username, then the AI's handle, then a handle spelled
    /// from the display name ("Josh Villareal" → josh_villareal) as a last
    /// resort. Replaces the two drifted copies in the classifier and the
    /// insight engine.
    static func effectiveCreator(aiHandle: String?, aiName: String?, atom: Atom) -> Resolution {
        let rich = atom.richContent
        let displayName = aiName ?? rich?.author?
            .components(separatedBy: "|").first?
            .trimmingCharacters(in: .whitespaces)
        if let username = key(rich?.instagramData?.authorUsername) {
            return Resolution(handle: displayHandle(username), name: displayName, derivedFromDisplayName: false)
        }
        if let ai = key(aiHandle) {
            return Resolution(handle: displayHandle(ai), name: displayName, derivedFromDisplayName: false)
        }
        if let fromAuthor = key(rich?.author) {
            return Resolution(handle: displayHandle(fromAuthor), name: displayName, derivedFromDisplayName: true)
        }
        return Resolution(handle: nil, name: displayName, derivedFromDisplayName: false)
    }

    // MARK: - Matching

    struct Indexed {
        let atom: Atom
        let key: String
        let platform: SocialPlatform?
        let hasProfile: Bool
    }

    static func index(_ creators: [Atom]) -> [Indexed] {
        creators.compactMap { atom in
            guard let meta = atom.metadataValue(as: CreatorMetadata.self), let key = key(meta.handle) else { return nil }
            let hasProfile = meta.followerCount != nil || meta.thumbnailUrl != nil || meta.profileUrl != nil || (meta.catalogPostCount ?? 0) > 0
            return Indexed(atom: atom, key: key, platform: platform(fromCreatorPlatform: meta.platform), hasProfile: hasProfile)
        }
    }

    /// The creator a handle belongs to. Exact key on the same platform wins,
    /// then an exact key anywhere (a creator whose platform was never known),
    /// then — only for a name-derived handle, or against a creator that was
    /// never imported — the separator-blind key.
    static func match(key: String, platform: SocialPlatform?, derivedFromName: Bool, in creators: [Atom]) -> Atom? {
        let indexed = index(creators)
        let exact = indexed.filter { $0.key == key }
        if let platform, let same = exact.first(where: { $0.platform == platform }) { return same.atom }
        if let unknown = exact.first(where: { $0.platform == nil }) ?? exact.first { return unknown.atom }
        let loose = looseKey(key)
        return indexed.first { candidate in
            looseKey(candidate.key) == loose
                && (platform == nil || candidate.platform == nil || candidate.platform == platform)
                && (derivedFromName || !candidate.hasProfile)
        }?.atom
    }
}
