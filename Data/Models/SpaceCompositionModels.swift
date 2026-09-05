import Foundation

/// Hints describe the content of a page, never the capabilities of its Space.
/// These raw values are the shared macOS / iOS persistence contract.
enum SpaceCompositionKind: String, Codable, CaseIterable, Sendable {
    case page, group, book, course, guide

    var isAuthored: Bool { self != .group }
    var title: String {
        switch self {
        case .page: return "Page"
        case .group: return "Group"
        case .book: return "Book"
        case .course: return "Course"
        case .guide: return "Guide"
        }
    }
    var symbol: String {
        switch self {
        case .page: return "doc.text"
        case .group: return "square.stack.3d.up"
        case .book: return "book.closed"
        case .course: return "play.rectangle.on.rectangle"
        case .guide: return "doc.richtext"
        }
    }
}

enum SpaceCompositionView: String, Codable, CaseIterable, Sendable {
    case canvas, grid, list, outline, write
}

struct SpaceCompositionPlacement: Codable, Equatable, Sendable, Identifiable {
    var itemUUID: String
    var x: Double
    var y: Double
    var width: Double?
    var height: Double?
    var id: String { itemUUID }

    init(itemUUID: String, x: Double, y: Double, width: Double? = nil, height: Double? = nil) {
        self.itemUUID = itemUUID
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    func validate() throws {
        guard !itemUUID.isEmpty, x.isFinite, y.isFinite,
              width.map({ $0.isFinite && $0 > 0 }) ?? true,
              height.map({ $0.isFinite && $0 > 0 }) ?? true else { throw SpaceCompositionError.invalidPlacement }
    }
}

struct SpaceSourceAnchor: Codable, Equatable, Sendable {
    var blockUUID: String?
    var pageIndex: Int?
    var timeSeconds: Double?
    var url: String?

    init(blockUUID: String? = nil, pageIndex: Int? = nil, timeSeconds: Double? = nil, url: String? = nil) {
        self.blockUUID = blockUUID
        self.pageIndex = pageIndex
        self.timeSeconds = timeSeconds
        self.url = url
    }

    func validate() throws {
        guard pageIndex.map({ $0 >= 0 && $0 < Int.max }) ?? true,
              timeSeconds.map({ $0.isFinite && $0 >= 0 && $0 < Double(Int.max / 2) }) ?? true else {
            throw SpaceCompositionError.invalidMetadata
        }
    }
}

/// The excerpt survives an unavailable original; source identity never becomes a copy.
struct SpaceCompositionReference: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var sourceUUID: String
    var sourceTitle: String?
    var excerpt: String?
    var anchor: SpaceSourceAnchor?
    var annotation: String?

    init(id: String = UUID().uuidString, sourceUUID: String, sourceTitle: String? = nil,
         excerpt: String? = nil, anchor: SpaceSourceAnchor? = nil, annotation: String? = nil) {
        self.id = id
        self.sourceUUID = sourceUUID
        self.sourceTitle = sourceTitle
        self.excerpt = excerpt
        self.anchor = anchor
        self.annotation = annotation
    }

    func validate() throws {
        guard !id.isEmpty, !sourceUUID.isEmpty else { throw SpaceCompositionError.invalidSource }
        try anchor?.validate()
    }
}

struct SpaceCompositionOrigin: Codable, Equatable, Sendable {
    var sourceUUID: String
    var sourceTitle: String?
    var sourceVersion: Int64
    var adaptedAt: String
}

/// Legacy material folders are projected once into normal group atoms. The map
/// also redirects old saved destinations without deleting their original data.
struct SpaceCompositionLegacyMigration: Codable, Equatable, Sendable {
    static let metadataKey = "spaceCompositionMigration"
    var schemaVersion: Int = 1
    var groups: [String: String] = [:]
}

/// Stored under `atoms.metadata.spaceComposition`. Unrelated atom metadata and
/// unknown keys inside this namespace are retained by every writer.
struct SpaceCompositionMetadata: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let metadataKey = "spaceComposition"
    var schemaVersion: Int = currentVersion
    var kind: SpaceCompositionKind
    /// One authored parent. Group membership and canvas positions are independent.
    var parentUUID: String?
    var sortOrder: Double = 0
    var includeInExport: Bool = true
    var memberUUIDs: [String] = []
    var references: [SpaceCompositionReference] = []
    var placements: [SpaceCompositionPlacement] = []
    var preferredView: SpaceCompositionView?
    var origin: SpaceCompositionOrigin?

    init(kind: SpaceCompositionKind = .page, parentUUID: String? = nil, sortOrder: Double = 0,
         includeInExport: Bool = true) {
        self.kind = kind
        self.parentUUID = parentUUID
        self.sortOrder = sortOrder
        self.includeInExport = includeInExport
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, kind, parentUUID, sortOrder, includeInExport
        case memberUUIDs, references, placements, preferredView, origin
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion == Self.currentVersion else {
            throw SpaceCompositionError.unsupportedVersion(schemaVersion)
        }
        kind = try values.decode(SpaceCompositionKind.self, forKey: .kind)
        parentUUID = try values.decodeIfPresent(String.self, forKey: .parentUUID)
        sortOrder = try values.decodeIfPresent(Double.self, forKey: .sortOrder) ?? 0
        includeInExport = try values.decodeIfPresent(Bool.self, forKey: .includeInExport) ?? true
        memberUUIDs = try values.decodeIfPresent([String].self, forKey: .memberUUIDs) ?? []
        references = try values.decodeIfPresent([SpaceCompositionReference].self, forKey: .references) ?? []
        placements = try values.decodeIfPresent([SpaceCompositionPlacement].self, forKey: .placements) ?? []
        preferredView = try values.decodeIfPresent(SpaceCompositionView.self, forKey: .preferredView)
        origin = try values.decodeIfPresent(SpaceCompositionOrigin.self, forKey: .origin)
        try validate()
    }

    func validate() throws {
        guard sortOrder.isFinite,
              Set(references.map(\.id)).count == references.count,
              Set(placements.map(\.itemUUID)).count == placements.count else { throw SpaceCompositionError.invalidMetadata }
        for reference in references { try reference.validate() }
        for placement in placements { try placement.validate() }
    }
}

enum SpaceCompositionError: Error, LocalizedError, Equatable {
    case notFound, invalidMetadata, unsupportedVersion(Int), invalidParent, cycle
    case invalidOrder, invalidPlacement, emptyTitle, conflict, invalidSource, invalidKind

    var errorDescription: String? {
        switch self {
        case .notFound: return "This item is no longer available. Refresh the Space and try again."
        case .invalidMetadata: return "This item's structure couldn't be read. Your content has been kept unchanged."
        case .unsupportedVersion: return "This structure was created in a newer version of Cosmo. Update Cosmo to edit it."
        case .invalidParent: return "Pages can only be moved inside another page in this Space."
        case .cycle: return "An item can't be placed inside itself or one of its descendants."
        case .invalidOrder: return "The structure changed. Refresh it before reordering."
        case .invalidPlacement: return "This canvas position couldn't be saved."
        case .emptyTitle: return "Give this item a name."
        case .conflict: return "This item changed elsewhere. Refresh it before trying again."
        case .invalidSource: return "Choose an available source other than this page."
        case .invalidKind: return "This action isn't available for this kind of item."
        }
    }
}

extension Atom {
    var spaceComposition: SpaceCompositionMetadata? { try? decodedSpaceComposition() }

    /// Display-only convenience. Mutations always use the throwing accessor.
    var spaceCompositionKind: SpaceCompositionKind? {
        if let value = spaceComposition { return value.kind }
        return type == .note ? .page : nil
    }

    func decodedSpaceComposition() throws -> SpaceCompositionMetadata? {
        guard let metadata, !metadata.isEmpty else { return nil }
        guard let data = metadata.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpaceCompositionError.invalidMetadata
        }
        guard let raw = object[SpaceCompositionMetadata.metadataKey] else { return nil }
        do {
            return try JSONDecoder().decode(SpaceCompositionMetadata.self,
                from: JSONSerialization.data(withJSONObject: raw))
        } catch let error as SpaceCompositionError { throw error }
        catch { throw SpaceCompositionError.invalidMetadata }
    }

    /// Replaces exactly the known composition fields, including deliberate nils.
    /// Rich text, native-media metadata and future sibling keys remain untouched.
    func replacingSpaceComposition(_ value: SpaceCompositionMetadata?) throws -> Atom {
        _ = try decodedSpaceComposition()
        var object: [String: Any] = [:]
        if let metadata, !metadata.isEmpty {
            guard let data = metadata.data(using: .utf8),
                  let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SpaceCompositionError.invalidMetadata
            }
            object = decoded
        }
        if let value {
            guard value.schemaVersion == SpaceCompositionMetadata.currentVersion else {
                throw SpaceCompositionError.unsupportedVersion(value.schemaVersion)
            }
            try value.validate()
            var namespace = object[SpaceCompositionMetadata.metadataKey] as? [String: Any] ?? [:]
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] ?? [:]
            for key in SpaceCompositionMetadata.CodingKeys.allCases { namespace[key.rawValue] = encoded[key.rawValue] }
            object[SpaceCompositionMetadata.metadataKey] = namespace
        } else {
            object.removeValue(forKey: SpaceCompositionMetadata.metadataKey)
        }
        var copy = self
        copy.metadata = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
        return copy
    }
}

struct SpaceCompositionSection: Identifiable, Sendable {
    var atom: Atom
    var depth: Int
    var id: String { atom.uuid }
}

/// One immutable read supplies navigation, local views and export. Sorting is
/// stable even when two offline devices assign the same position.
struct SpaceCompositionSnapshot: Sendable {
    let spaceID: String
    let atomsByUUID: [String: Atom]
    let metadataByUUID: [String: SpaceCompositionMetadata]
    let legacyGroupMapping: [String: String]
    private let childrenByParent: [String: [Atom]]
    let roots: [Atom]

    init(spaceID: String, atoms: [Atom], legacyGroupMapping: [String: String] = [:]) throws {
        self.spaceID = spaceID
        self.legacyGroupMapping = legacyGroupMapping
        let active = atoms.filter { !$0.isDeleted }
        var byUUID: [String: Atom] = [:]
        var metadata: [String: SpaceCompositionMetadata] = [:]
        for atom in active {
            byUUID[atom.uuid] = atom
            if let value = try atom.decodedSpaceComposition() { metadata[atom.uuid] = value }
        }
        self.atomsByUUID = byUUID
        self.metadataByUUID = metadata
        func order(_ a: Atom, _ b: Atom) -> Bool {
            let lhs = metadata[a.uuid]?.sortOrder ?? 0, rhs = metadata[b.uuid]?.sortOrder ?? 0
            return lhs == rhs ? a.uuid < b.uuid : lhs < rhs
        }
        var children: [String: [Atom]] = [:]
        let navigable = active.filter { metadata[$0.uuid] != nil || $0.type == .note }
        for atom in navigable {
            if let parent = metadata[atom.uuid]?.parentUUID, byUUID[parent] != nil {
                children[parent, default: []].append(atom)
            }
        }
        for key in children.keys { children[key]?.sort(by: order) }
        childrenByParent = children
        // Cross-device moves can temporarily form a cycle. Expose one stable
        // root in each cycle without rewriting synced data or hiding the work.
        let groupedIDs = Set(metadata.values.filter { $0.kind == .group }.flatMap(\.memberUUIDs))
        var rootIDs = Set(navigable.filter {
            guard !groupedIDs.contains($0.uuid) else { return false }
            guard let parent = metadata[$0.uuid]?.parentUUID else { return true }
            return byUUID[parent] == nil
        }.map(\.uuid))
        var reachable = Set<String>()
        func markReachable(_ root: String) {
            var pending = [root]
            while let uuid = pending.popLast() {
                guard reachable.insert(uuid).inserted else { continue }
                pending.append(contentsOf: children[uuid, default: []].map(\.uuid))
                if metadata[uuid]?.kind == .group {
                    pending.append(contentsOf: metadata[uuid]?.memberUUIDs ?? [])
                }
            }
        }
        for root in rootIDs { markReachable(root) }
        for atom in navigable.sorted(by: { $0.uuid < $1.uuid }) where !reachable.contains(atom.uuid) {
            rootIDs.insert(atom.uuid)
            markReachable(atom.uuid)
        }
        roots = navigable.filter { rootIDs.contains($0.uuid) }.sorted(by: order)
    }

    static func empty(spaceID: String) -> Self { try! Self(spaceID: spaceID, atoms: []) }

    func children(of parentUUID: String) -> [Atom] { childrenByParent[parentUUID] ?? [] }
    func members(of groupUUID: String) -> [Atom] {
        var seen = Set<String>()
        return (metadataByUUID[groupUUID]?.memberUUIDs ?? []).compactMap {
            seen.insert($0).inserted ? atomsByUUID[$0] : nil
        }
    }
    func orderedSections(of rootUUID: String, includedOnly: Bool = true) -> [SpaceCompositionSection] {
        var output: [SpaceCompositionSection] = [], visited = Set<String>()
        func visit(_ uuid: String, depth: Int) {
            guard visited.insert(uuid).inserted, let atom = atomsByUUID[uuid],
                  metadataByUUID[uuid]?.kind.isAuthored ?? (atom.type == .note) else { return }
            // Inclusion describes a section's contribution to its parent.
            // Explicitly exporting that section still includes its own body.
            if includedOnly && depth > 0 && metadataByUUID[uuid]?.includeInExport == false { return }
            output.append(SpaceCompositionSection(atom: atom, depth: depth))
            for child in children(of: uuid) { visit(child.uuid, depth: depth + 1) }
        }
        visit(rootUUID, depth: 0)
        return output
    }
    func breadcrumbs(to uuid: String) -> [Atom] {
        var path: [Atom] = [], visited = Set<String>(), cursor: String? = uuid
        while let id = cursor, visited.insert(id).inserted, let atom = atomsByUUID[id] {
            path.append(atom)
            cursor = metadataByUUID[id]?.parentUUID
        }
        return path.reversed()
    }
}
