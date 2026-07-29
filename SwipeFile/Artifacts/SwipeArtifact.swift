// CosmoOS/SwipeFile/Artifacts/SwipeArtifact.swift
// The artifact envelope: a swipe's ordered units, plus the Atom accessors that
// read and merge it.
//
// ENVELOPE-SIBLING LAW
// --------------------
// The artifact lives at `structured.swipeArtifact`, a SIBLING of `autoMetadata`
// and `swipeAnalysis` — never nested inside `swipeAnalysis`. The Railway
// worker's buildAnalysisJSON (cosmo-cloud-agent/src/swipes/analyze.ts) rebuilds
// the swipeAnalysis object WHOLESALE on every cloud pass, so anything nested
// there is silently wiped the next time a swipe is processed. Writes go through
// `withSwipeArtifact`, which merges key-by-key exactly like `withSwipeAnalysis`
// and `setRichContent` do, for the same reason.
//
// DERIVE-NEVER-MIGRATE LAW
// ------------------------
// `Atom.swipeKind` resolves without touching a single existing row: the stored
// envelope wins when present, otherwise the kind is derived from fields legacy
// swipes already carry. No backfill pass ever runs over the ~400 swipes that
// predate this file.

import Foundation

// MARK: - Detected source

/// A platform + handle read off a screenshot's chrome. Powers the card's
/// "looks like an @handle post — fetch the original?" upgrade offer, which
/// re-routes to the real Post pipeline while keeping the screenshot as a unit.
public struct DetectedSource: Codable, Sendable, Equatable {
    public var platform: String?
    public var handle: String?
    /// Best-effort reconstruction of the original post URL, when the chrome
    /// carried enough to build one. Never guessed from the handle alone.
    public var url: String?

    public init(platform: String? = nil, handle: String? = nil, url: String? = nil) {
        self.platform = platform
        self.handle = handle
        self.url = url
    }

    /// True only when there is something actionable to offer the user.
    public var isActionable: Bool {
        (url?.isEmpty == false) || (platform?.isEmpty == false && handle?.isEmpty == false)
    }
}

// MARK: - Unit

/// One unit of a swipe: a carousel slide, a page section, a screenshot, a
/// funnel step. The retrievable unit of the whole reference layer — a vector
/// match points HERE, not at a whole swipe.
public struct SwipeArtifactUnit: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var index: Int
    public var role: SwipeUnitRole?
    /// The unit's own headline, verbatim from the artifact.
    public var headline: String?
    /// Verbatim on-screen copy (vision OCR) or DOM text.
    public var copy: String?
    /// One sentence: what this unit does to the reader, and the specific
    /// device it uses to do it.
    public var mechanic: String?
    /// `media_attachments.uuid` — the image behind this unit (frame images,
    /// page slices). Resolved through AttachmentCloudStore like every other
    /// attachment, so it syncs Mac <-> iPhone for free.
    public var attachmentUUID: String?
    /// Flow steps only: the member swipe this step points at.
    public var memberSwipeUUID: String?
    /// Page slices only: y-offset of this slice inside the full-page capture,
    /// in capture pixels. Drives the Study stage's scroll-to-section.
    public var pageOffset: Int?
    public var aspectRatio: Double?

    public init(
        id: String = UUID().uuidString,
        index: Int,
        role: SwipeUnitRole? = nil,
        headline: String? = nil,
        copy: String? = nil,
        mechanic: String? = nil,
        attachmentUUID: String? = nil,
        memberSwipeUUID: String? = nil,
        pageOffset: Int? = nil,
        aspectRatio: Double? = nil
    ) {
        self.id = id
        self.index = index
        self.role = role
        self.headline = headline
        self.copy = copy
        self.mechanic = mechanic
        self.attachmentUUID = attachmentUUID
        self.memberSwipeUUID = memberSwipeUUID
        self.pageOffset = pageOffset
        self.aspectRatio = aspectRatio
    }

    /// The line a unit row leads with: its own headline, else the first line
    /// of its copy, else its mechanic. Never empty for a unit that carries
    /// anything at all — a unit row must never render as a bare role chip.
    public var displayLine: String? {
        if let headline, !headline.trimmed.isEmpty { return headline.trimmed }
        if let copy {
            let firstLine = copy
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first
                .map(String.init)?
                .trimmed
            if let firstLine, !firstLine.isEmpty { return firstLine }
        }
        if let mechanic, !mechanic.trimmed.isEmpty { return mechanic.trimmed }
        return nil
    }

    /// Text this unit contributes to the recall index. Role-prefixed so a
    /// vector match knows what it matched (see RecallDocumentBuilder).
    public var indexableText: String {
        [headline, copy, mechanic]
            .compactMap { $0?.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    public var hasSubstance: Bool { !indexableText.isEmpty }
}

// MARK: - Artifact

public struct SwipeArtifact: Codable, Sendable, Equatable {
    public var kind: SwipeKind
    public var units: [SwipeArtifactUnit]
    /// What this artifact IS to the collector — the browsing axis (newsletter,
    /// sales page, ad…), orthogonal to `kind`'s structural axis. nil means
    /// "nothing decided yet"; readers fall back to the kind default through
    /// `Atom.swipeGenre`. See SwipeGenre.swift for the vocabulary laws.
    public var genre: SwipeGenre?
    /// True once the user filed this swipe by hand ("File under →"). A locked
    /// genre survives every later analyzer pass — the transcriptEditedByUser
    /// pattern: a human decision is terminal.
    public var genreLockedByUser: Bool?
    /// The structural recipe for non-post kinds: the sequence, written so
    /// someone could rebuild the artifact from it.
    public var anatomy: String?
    /// Where the capture came from — browser_pane | headless | screenshot |
    /// photo | share_sheet | clipboard | region | inbox | agent | drop.
    public var captureMode: String?
    public var capturedURL: String?
    public var pageTitle: String?
    /// Frames only: platform + handle read off the screenshot's chrome.
    public var detectedSource: DetectedSource?
    public var analyzedAt: String?
    public var artifactVersion: Int

    public static let currentVersion = 1

    public init(
        kind: SwipeKind,
        units: [SwipeArtifactUnit] = [],
        genre: SwipeGenre? = nil,
        genreLockedByUser: Bool? = nil,
        anatomy: String? = nil,
        captureMode: String? = nil,
        capturedURL: String? = nil,
        pageTitle: String? = nil,
        detectedSource: DetectedSource? = nil,
        analyzedAt: String? = nil,
        artifactVersion: Int = SwipeArtifact.currentVersion
    ) {
        self.kind = kind
        self.units = units
        self.genre = genre
        self.genreLockedByUser = genreLockedByUser
        self.anatomy = anatomy
        self.captureMode = captureMode
        self.capturedURL = capturedURL
        self.pageTitle = pageTitle
        self.detectedSource = detectedSource
        self.analyzedAt = analyzedAt
        self.artifactVersion = artifactVersion
    }

    /// Tolerant decode: `kind` and `units` are the only fields worth failing
    /// over, and both have safe defaults. A row from a newer build decodes
    /// with its unknown fields dropped rather than taking the whole swipe down.
    /// (`genre` deliberately rides `try?` — an unknown genre from a newer
    /// build decodes as nil and readers fall back to the kind default.)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decode(SwipeKind.self, forKey: .kind)) ?? .post
        units = (try? c.decode([SwipeArtifactUnit].self, forKey: .units)) ?? []
        genre = try? c.decodeIfPresent(SwipeGenre.self, forKey: .genre)
        genreLockedByUser = try? c.decodeIfPresent(Bool.self, forKey: .genreLockedByUser)
        anatomy = try? c.decodeIfPresent(String.self, forKey: .anatomy)
        captureMode = try? c.decodeIfPresent(String.self, forKey: .captureMode)
        capturedURL = try? c.decodeIfPresent(String.self, forKey: .capturedURL)
        pageTitle = try? c.decodeIfPresent(String.self, forKey: .pageTitle)
        detectedSource = try? c.decodeIfPresent(DetectedSource.self, forKey: .detectedSource)
        analyzedAt = try? c.decodeIfPresent(String.self, forKey: .analyzedAt)
        artifactVersion = (try? c.decodeIfPresent(Int.self, forKey: .artifactVersion)) ?? SwipeArtifact.currentVersion
    }

    public var orderedUnits: [SwipeArtifactUnit] {
        units.sorted { $0.index < $1.index }
    }

    public var roles: Set<SwipeUnitRole> {
        Set(units.compactMap(\.role))
    }

    /// True once a decomposition pass has actually said something about this
    /// artifact. Capture writes units with images and no roles; the analyzer
    /// fills the rest. Surfaces use this to show "reading…" rather than a
    /// misleadingly empty anatomy.
    public var isAnalyzed: Bool {
        analyzedAt != nil && units.contains { $0.role != nil || $0.mechanic?.isEmpty == false }
    }

    public func unit(withID id: String) -> SwipeArtifactUnit? {
        units.first { $0.id == id }
    }
}

// MARK: - Atom accessors

private struct SwipeArtifactWrapper: Codable {
    var swipeArtifact: SwipeArtifact?
}

/// Decode failures for the swipeArtifact structured key.
enum SwipeArtifactDecodeError: Error {
    case structuredNotAnObject
}

// Deliberately NOT a `public extension`: `decodedSwipeArtifact` exposes the
// internal `JSONDecodeState`, exactly as `decodedSwipeAnalysis` does. Members
// are marked public individually, mirroring SwipeAnalysis.swift's shape so the
// iOS (CosmoCoreKit) copy of this file stays a straight duplicate.
extension Atom {

    /// The structured key this envelope occupies. Named once so the merge
    /// writer, the decoder and the tests can never drift apart.
    public static let swipeArtifactStructuredKey = "swipeArtifact"

    /// Decode state of the swipeArtifact key, distinguishing "absent" from
    /// "present but undecodable" — the same three-state contract
    /// `decodedSwipeAnalysis` uses, and for the same reason: a writer must
    /// refuse to stamp a fresh envelope over a corrupt one.
    var decodedSwipeArtifact: JSONDecodeState<SwipeArtifact> {
        guard type == .research else { return .absent }
        guard let structuredStr = structured, !structuredStr.isEmpty else { return .absent }

        return DecodedColumnCache.shared.value(uuid: uuid, column: .structured, source: structuredStr) {
            guard let data = structuredStr.data(using: .utf8) else { return .absent }
            guard let object = try? JSONSerialization.jsonObject(with: data),
                  let dict = object as? [String: Any] else {
                return .corrupt(SwipeArtifactDecodeError.structuredNotAnObject)
            }
            guard dict[Atom.swipeArtifactStructuredKey] != nil else { return .absent }
            do {
                let wrapper = try JSONDecoder().decode(SwipeArtifactWrapper.self, from: data)
                guard let artifact = wrapper.swipeArtifact else { return .absent }
                return .value(artifact)
            } catch {
                return .corrupt(error)
            }
        }
    }

    /// The swipe's artifact envelope, or nil when this swipe predates the
    /// spine (every legacy post) or the key is corrupt.
    public var swipeArtifact: SwipeArtifact? {
        switch decodedSwipeArtifact {
        case .absent:
            return nil
        case .value(let artifact):
            return artifact
        case .corrupt(let error):
            PersistenceHealth.note(
                .decodeFailure,
                context: "Atom.swipeArtifact(\(uuid.prefix(8)))",
                detail: error.localizedDescription
            )
            return nil
        }
    }

    public var swipeArtifactIsCorrupt: Bool { decodedSwipeArtifact.isCorrupt }

    /// Return a copy with the artifact merged into the structured column.
    ///
    /// Merges key-by-key so `autoMetadata`, `swipeAnalysis`, `transcriptComments`
    /// and every other sibling survive — see the ENVELOPE-SIBLING LAW at the
    /// top of this file. REFUSES to write (returns self + logs) when the
    /// existing column is non-empty but unparseable, or when the existing
    /// artifact key is corrupt: proceeding from an empty dictionary is how
    /// sibling keys get wiped, and overwriting a corrupt key destroys the only
    /// copy of a decomposition that cost real model spend.
    public func withSwipeArtifact(_ artifact: SwipeArtifact) -> Atom {
        var copy = self

        var dict: [String: Any] = [:]
        if let structuredStr = structured, !structuredStr.isEmpty {
            guard let data = structuredStr.data(using: .utf8),
                  let existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                PersistenceHealth.note(
                    .decodeFailure,
                    context: "Atom.withSwipeArtifact(\(uuid.prefix(8)))",
                    detail: "existing structured unparseable; refusing overwrite that would drop its data"
                )
                return copy
            }
            if existing[Atom.swipeArtifactStructuredKey] != nil, decodedSwipeArtifact.isCorrupt {
                PersistenceHealth.note(
                    .decodeFailure,
                    context: "Atom.withSwipeArtifact(\(uuid.prefix(8)))",
                    detail: "existing swipeArtifact key undecodable; refusing to replace it"
                )
                return copy
            }
            dict = existing
        }

        guard let artifactData = try? JSONEncoder().encode(artifact),
              let artifactObj = try? JSONSerialization.jsonObject(with: artifactData) else {
            PersistenceHealth.note(
                .writeFailure,
                context: "Atom.withSwipeArtifact(\(uuid.prefix(8)))",
                detail: "artifact encode failed; keeping existing column"
            )
            return copy
        }
        dict[Atom.swipeArtifactStructuredKey] = artifactObj

        if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            copy.structured = jsonStr
        }

        // The kind is denormalised into metadata so scope checks and SQL
        // filters can read it without decoding the structured column. Both
        // sides of the SCOPE-TWIN read THIS, not the envelope.
        copy = copy.withSwipeKindMetadata(artifact.kind)
        return copy
    }

    // MARK: Kind

    /// What kind of artifact this swipe is.
    ///
    /// DERIVE-NEVER-MIGRATE: the stored envelope wins when present; otherwise
    /// the kind is derived from what legacy rows already carry. The derivation
    /// must stay total — every swipe answers, and the fallback is `.post`,
    /// which is what the entire pre-spine library is.
    public var swipeKind: SwipeKind {
        guard isSwipeFileAtom else { return .post }
        // 1. The denormalised metadata hint — cheapest, and the only thing the
        //    worker-scope check can see. Written beside every stored envelope.
        if let raw = researchMetadata?.swipeKind, let kind = SwipeKind(rawValue: raw) {
            return kind
        }
        // 2. The envelope itself (covers rows whose metadata hint was lost to
        //    a partial merge from an older build).
        if let artifact = swipeArtifact { return artifact.kind }
        // 3. Legacy derivation. A swipe with no link and no image, but with a
        //    body, is text someone pasted — `swipeFromRawText`'s shape.
        let meta = researchMetadata
        let hasURL = meta?.url?.trimmed.isEmpty == false
        let hasThumbnail = (meta?.thumbnailUrl?.trimmed.isEmpty == false)
            || (richContent?.thumbnailUrl?.trimmed.isEmpty == false)
        let hasBody = body?.trimmed.isEmpty == false
        if !hasURL && !hasThumbnail && hasBody { return .note }
        // 4. Everything else is a post — which is every other legacy swipe.
        return .post
    }

    /// Copy with `metadata.swipeKind` set. `.post` clears the key rather than
    /// writing it: legacy rows have no hint and must keep deriving, so the
    /// absence of the key has to stay meaningful.
    public func withSwipeKindMetadata(_ kind: SwipeKind) -> Atom {
        var copy = self
        copy.updateResearchMetadata { $0.swipeKind = (kind == .post) ? nil : kind.rawValue }
        return copy
    }

    // MARK: Genre

    /// What this swipe IS to the collector — the browsing axis. TOTAL and
    /// derive-never-migrate, exactly like `swipeKind`:
    ///   1. the denormalised metadata hint (cheapest; what sidebar counts read),
    ///   2. the envelope's stored genre,
    ///   3. the kind's structural default — which is what every legacy swipe
    ///      and every unclassified capture answers.
    public var swipeGenre: SwipeGenre {
        guard isSwipeFileAtom else { return .post }
        if let raw = researchMetadata?.swipeGenre, let genre = SwipeGenre.resolve(raw) {
            return genre
        }
        if let genre = swipeArtifact?.genre { return genre }
        return SwipeGenre.defaultGenre(for: swipeKind)
    }

    /// True when the user filed this swipe by hand — a locked genre survives
    /// every later analyzer pass.
    public var swipeGenreIsLocked: Bool {
        swipeArtifact?.genreLockedByUser == true
    }

    /// Copy with the genre written to BOTH homes: the envelope (durable,
    /// syncs inside `structured`) and the metadata hint (cheap reads).
    ///
    /// The hint mirrors `withSwipeKindMetadata`'s absence rule: a genre equal
    /// to the kind's structural default CLEARS the key, so "nothing decided"
    /// stays distinguishable from "decided, and it happens to match".
    /// Posts have no envelope (DERIVE-NEVER-MIGRATE forbids minting one just
    /// to carry a genre) — for kind `.post` this writes the hint alone.
    public func withSwipeGenre(_ genre: SwipeGenre, lockedByUser: Bool = false) -> Atom {
        var copy = self
        if var artifact = swipeArtifact {
            artifact.genre = genre
            if lockedByUser { artifact.genreLockedByUser = true }
            copy = copy.withSwipeArtifact(artifact)
        }
        copy.updateResearchMetadata { meta in
            meta.swipeGenre = genre.isStructuralFallback(for: swipeKind) ? nil : genre.rawValue
        }
        return copy
    }

    /// The swipe's units, in order — the envelope's when it has one.
    /// Post swipes keep reading their transcript through the existing
    /// resolution ladder; this is deliberately NOT a shim over that.
    public var swipeArtifactUnits: [SwipeArtifactUnit] {
        swipeArtifact?.orderedUnits ?? []
    }

    // MARK: Lens

    /// True when this source carries the swipe lens — you care about its FORM.
    /// Exactly the historical meaning of `isSwipeFile`, renamed at the call
    /// sites that reason about lenses rather than about swipe-ness.
    public var hasSwipeLens: Bool { isSwipeFileAtom }

    /// True when this source carries the research lens — you care about what
    /// it CLAIMS. A source can carry both; it then appears in both libraries
    /// as one row with one uuid.
    public var hasResearchLens: Bool {
        guard type == .research else { return false }
        guard let meta = researchMetadata else { return false }
        if meta.researchLens == true { return true }
        // Legacy: a research atom that was never a swipe has always been a
        // research-lens source. Deriving it keeps every pre-lens row correct
        // without a migration.
        if meta.isSwipeFile != true { return true }
        return false
    }

    public var swipeLenses: Set<SwipeLens> {
        var lenses: Set<SwipeLens> = []
        if hasSwipeLens { lenses.insert(.swipe) }
        if hasResearchLens { lenses.insert(.research) }
        return lenses
    }

    /// Copy with a lens added. Additive by design — adding the swipe lens to a
    /// research source never removes the research lens, because the whole
    /// point is that one capture serves both.
    public func addingLens(_ lens: SwipeLens) -> Atom {
        var copy = self
        copy.updateResearchMetadata { meta in
            switch lens {
            case .swipe: meta.isSwipeFile = true
            case .research: meta.researchLens = true
            }
        }
        return copy
    }

    /// Copy with a lens removed. Refuses to remove the last lens — a source
    /// with neither lens is invisible in every library, which is data loss
    /// wearing a toggle's clothes.
    public func removingLens(_ lens: SwipeLens) -> Atom {
        guard swipeLenses.subtracting([lens]).isEmpty == false else { return self }
        var copy = self
        copy.updateResearchMetadata { meta in
            switch lens {
            case .swipe: meta.isSwipeFile = false
            case .research: meta.researchLens = false
            }
        }
        return copy
    }
}

// MARK: - Small shared helper

extension String {
    /// Local convenience; the codebase trims in a dozen idioms and this file
    /// leans on it enough to be worth naming.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
