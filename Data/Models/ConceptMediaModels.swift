// CosmoOS/Data/Models/ConceptMediaModels.swift
// Media references on a concept board (July 2026).
// Reference-first: a media item either POINTS at an atom that already owns
// its media (swipes, research, YouTube — `atomUUID`), or OWNS a local asset
// dropped/pasted straight onto the board (`assetPath`, via MediaAssetStore).
// Detaching an atom-backed ref never touches the source atom.

import Foundation

/// One media reference on a concept board. Persisted inside the connection
/// atom's structured column (`ConnectionStructuredData.media`).
struct ConnectionMediaItem: Identifiable, Codable, Equatable, Sendable {

    /// Display hint only — rendering resolves the real shape from the source
    /// atom or asset at view time.
    enum Kind: String, Codable, Sendable {
        case image
        case video
        case carousel
    }

    let id: UUID
    var kind: Kind

    // Origin 1: atom-backed (swipe / research / YouTube). The atom owns the
    // media; this ref stores only display state.
    var atomUUID: String?

    // Origin 2: owned asset (file drop / image paste), stored by MediaAssetStore.
    var assetPath: String?
    /// Cloud mirror of the owned asset (capture-media bucket) so other
    /// devices can render it. nil until mirrored.
    var assetRemoteURL: String?
    /// Pre-generated poster frame for owned videos.
    var thumbnailAssetPath: String?
    /// Original filename / display title for owned assets.
    var assetTitle: String?

    var caption: String?
    /// nil = lives in the gallery only; set = also surfaces on that section.
    var anchorSection: ConnectionSectionType?
    /// Start moment for video media (parsed from a pasted `?t=` or pinned
    /// from the lightbox playhead).
    var timestampSeconds: Double?
    /// At most one ref per concept is the cover (enforced by the state mutator).
    var isCover: Bool
    var sortOrder: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        atomUUID: String? = nil,
        assetPath: String? = nil,
        assetRemoteURL: String? = nil,
        thumbnailAssetPath: String? = nil,
        assetTitle: String? = nil,
        caption: String? = nil,
        anchorSection: ConnectionSectionType? = nil,
        timestampSeconds: Double? = nil,
        isCover: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.atomUUID = atomUUID
        self.assetPath = assetPath
        self.assetRemoteURL = assetRemoteURL
        self.thumbnailAssetPath = thumbnailAssetPath
        self.assetTitle = assetTitle
        self.caption = caption
        self.anchorSection = anchorSection
        self.timestampSeconds = timestampSeconds
        self.isCover = isCover
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    /// True when this ref points at an atom rather than owning its file.
    var isAtomBacked: Bool { atomUUID != nil }

    /// True when the owned asset is a video file.
    var ownsVideoAsset: Bool {
        guard let assetPath else { return false }
        return MediaAssetStore.isVideoPath(assetPath)
    }

    // MARK: - Codable (tolerant: every field but id optional so refs written
    // by newer app versions never nil out the whole structured decode)

    private enum CodingKeys: String, CodingKey {
        case id, kind, atomUUID, assetPath, assetRemoteURL, thumbnailAssetPath
        case assetTitle, caption, anchorSection, timestampSeconds, isCover
        case sortOrder, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        // Unknown kind raw values (newer versions) degrade to image, never throw.
        let kindRaw = try c.decodeIfPresent(String.self, forKey: .kind) ?? Kind.image.rawValue
        self.kind = Kind(rawValue: kindRaw) ?? .image
        self.atomUUID = try c.decodeIfPresent(String.self, forKey: .atomUUID)
        self.assetPath = try c.decodeIfPresent(String.self, forKey: .assetPath)
        self.assetRemoteURL = try c.decodeIfPresent(String.self, forKey: .assetRemoteURL)
        self.thumbnailAssetPath = try c.decodeIfPresent(String.self, forKey: .thumbnailAssetPath)
        self.assetTitle = try c.decodeIfPresent(String.self, forKey: .assetTitle)
        self.caption = try c.decodeIfPresent(String.self, forKey: .caption)
        // Unknown section raw values stay unanchored, never mis-anchored.
        if let sectionRaw = try c.decodeIfPresent(String.self, forKey: .anchorSection) {
            self.anchorSection = ConnectionSectionType(rawValue: sectionRaw)
        } else {
            self.anchorSection = nil
        }
        self.timestampSeconds = try c.decodeIfPresent(Double.self, forKey: .timestampSeconds)
        self.isCover = try c.decodeIfPresent(Bool.self, forKey: .isCover) ?? false
        self.sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encodeIfPresent(atomUUID, forKey: .atomUUID)
        try c.encodeIfPresent(assetPath, forKey: .assetPath)
        try c.encodeIfPresent(assetRemoteURL, forKey: .assetRemoteURL)
        try c.encodeIfPresent(thumbnailAssetPath, forKey: .thumbnailAssetPath)
        try c.encodeIfPresent(assetTitle, forKey: .assetTitle)
        try c.encodeIfPresent(caption, forKey: .caption)
        try c.encodeIfPresent(anchorSection?.rawValue, forKey: .anchorSection)
        try c.encodeIfPresent(timestampSeconds, forKey: .timestampSeconds)
        try c.encode(isCover, forKey: .isCover)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(createdAt, forKey: .createdAt)
    }

    // MARK: - Building refs from atoms

    /// Classifies an atom's media shape into a display-hint kind.
    static func kind(for atom: Atom) -> Kind {
        switch atom.richContent?.sourceType {
        case .youtube, .youtubeShort, .instagramReel, .tiktok, .loom:
            return .video
        case .instagramCarousel:
            return .carousel
        case .instagram, .instagramPost:
            // Posts can be carousels — trust the stored items over the label.
            if let items = atom.richContent?.instagramData?.carouselItems, items.count > 1 {
                return .carousel
            }
            return .image
        default:
            if atom.richContent?.videoId != nil { return .video }
            if let items = atom.richContent?.instagramData?.carouselItems, items.count > 1 {
                return .carousel
            }
            return .image
        }
    }

    /// Start-moment parse for pasted video URLs: `?t=90`, `?t=1m30s`,
    /// `?t=1h2m3s`, `&start=90`. Returns nil when no timestamp is present.
    static func parseTimestamp(fromURL urlString: String) -> Double? {
        guard let components = URLComponents(string: urlString) else { return nil }
        let raw = components.queryItems?.first { $0.name == "t" || $0.name == "start" }?.value
        guard var value = raw?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if value.hasSuffix("s"), !value.contains("m"), !value.contains("h") {
            value = String(value.dropLast())
        }
        if let plain = Double(value) { return plain > 0 ? plain : nil }
        // h/m/s composite form
        var seconds = 0.0
        var number = ""
        for char in value {
            if char.isNumber {
                number.append(char)
            } else {
                guard let n = Double(number) else { return nil }
                switch char {
                case "h": seconds += n * 3600
                case "m": seconds += n * 60
                case "s": seconds += n
                default: return nil
                }
                number = ""
            }
        }
        if let trailing = Double(number), !number.isEmpty { seconds += trailing }
        return seconds > 0 ? seconds : nil
    }

    /// A fresh atom-backed ref for `atom`.
    static func ref(
        for atom: Atom,
        anchorSection: ConnectionSectionType? = nil,
        timestampSeconds: Double? = nil,
        sortOrder: Int = 0
    ) -> ConnectionMediaItem {
        ConnectionMediaItem(
            kind: kind(for: atom),
            atomUUID: atom.uuid,
            anchorSection: anchorSection,
            timestampSeconds: timestampSeconds,
            sortOrder: sortOrder
        )
    }
}
