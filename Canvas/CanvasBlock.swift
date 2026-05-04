// CosmoOS/Canvas/CanvasBlock.swift
// Floating block model with full entity data

import Foundation
import SwiftUI

struct CanvasBlock: Identifiable, Codable, Equatable {
    static let documentLayoutSize = CGSize(width: 680, height: 880)
    static let documentDisplayScale: CGFloat = 1.0 / 1.5
    static let documentBlockSize = CGSize(
        width: documentLayoutSize.width * documentDisplayScale,
        height: documentLayoutSize.height * documentDisplayScale
    )

    let id: String
    var position: CGPoint
    var size: CGSize
    var scale: Double
    var rotation: Double
    var isPinned: Bool
    var zIndex: Int

    // Entity reference
    var entityType: EntityType
    var entityId: Int64
    var entityUuid: String

    // Visual state
    var isSelected: Bool
    var isDragging: Bool
    var opacity: Double

    // Content preview
    var title: String
    var subtitle: String?
    var metadata: [String: String]

    // Animation state
    var targetPosition: CGPoint?
    var velocity: CGVector

    // Drag state - tracks starting position for proper drag handling
    var dragStartPosition: CGPoint?

    init(
        id: String = UUID().uuidString,
        position: CGPoint,
        size: CGSize = CGSize(width: 220, height: 310),
        scale: Double = 1.0,
        rotation: Double = 0.0,
        isPinned: Bool = false,
        zIndex: Int = 0,
        entityType: EntityType,
        entityId: Int64,
        entityUuid: String,
        title: String,
        subtitle: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.position = position
        self.size = size
        self.scale = scale
        self.rotation = rotation
        self.isPinned = isPinned
        self.zIndex = zIndex
        self.entityType = entityType
        self.entityId = entityId
        self.entityUuid = entityUuid
        self.isSelected = false
        self.isDragging = false
        self.opacity = 1.0
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
        self.targetPosition = nil
        self.velocity = .zero
    }

    /// Default (design) size for this block's entity type.
    /// Used by CosmoBlockWrapper to lay content out at a fixed reference size
    /// so that resizing the block only changes the visual scale, not the layout.
    var defaultSize: CGSize {
        switch entityType {
        case .task:       return CGSize(width: 280, height: 120)
        case .project:    return CGSize(width: 320, height: 240)
        case .research:   return CGSize(width: 320, height: 340)
        case .content:    return Self.documentLayoutSize
        case .connection: return CGSize(width: 220, height: 310)
        case .idea:       return CGSize(width: 280, height: 180)
        case .cosmoAI:    return CGSize(width: 320, height: 280)
        case .note:       return Self.documentLayoutSize
        case .calendar:   return CGSize(width: 400, height: 500)
        case .image:      return CGSize(width: 320, height: 240)
        case .stickyNote: return CGSize(width: 220, height: 220)
        case .liveQuery:  return CGSize(width: 280, height: 360)
        case .ideaBoard:  return CGSize(width: 280, height: 400)
        case .template:   return CGSize(width: 260, height: 380)
        case .deepDive:   return CGSize(width: 320, height: 280)
        case .inquirySession: return CGSize(width: 280, height: 200)
        default:          return CGSize(width: 220, height: 310)
        }
    }

    /// Placeholder block used when a block reference cannot be resolved
    static let placeholder = CanvasBlock(
        id: "placeholder",
        position: .zero,
        entityType: .note,
        entityId: -1,
        entityUuid: "",
        title: ""
    )

    // MARK: - Factory Methods (Atom-based)

    /// Create a CanvasBlock from any Atom type
    static func fromAtom(_ atom: Atom, position: CGPoint) -> CanvasBlock {
        // Determine size based on type
        let size: CGSize
        switch atom.type {
        case .task:
            size = CGSize(width: 280, height: 120)
        case .project:
            size = CGSize(width: 320, height: 240)
        case .research:
            if atom.isSwipeFileAtom {
                // Detect media type for aspect ratio sizing
                let swipeMediaType = Self.detectMediaType(atom: atom)
                switch swipeMediaType {
                case .reel:
                    size = CGSize(width: 220, height: 420)     // 9:16 + transcript bar
                case .youtube:
                    size = CGSize(width: 320, height: 230)     // 16:9 + transcript bar
                case .carousel:
                    size = CGSize(width: 300, height: 350)     // 1:1 + transcript bar
                case .generic:
                    size = CGSize(width: 340, height: 380)     // Current swipe size
                }
            } else {
                // Detect media type for regular research too
                let researchMediaType = Self.detectMediaType(atom: atom)
                switch researchMediaType {
                case .reel:
                    size = CGSize(width: 220, height: 420)
                case .youtube:
                    size = CGSize(width: 320, height: 230)
                case .carousel:
                    size = CGSize(width: 300, height: 350)
                case .generic:
                    size = CGSize(width: 320, height: 340)     // Current research size
                }
            }
        case .content:
            size = Self.documentBlockSize
        case .note:
            size = Self.documentBlockSize
        case .connection:
            size = CGSize(width: 220, height: 310)
        case .deepDive:
            size = CGSize(width: 320, height: 280)
        case .inquirySession:
            size = CGSize(width: 280, height: 200)
        case .image:
            // Use stored dimensions to compute aspect-ratio-correct size
            if let meta = atom.imageMetadata,
               let w = meta.width, let h = meta.height, w > 0 && h > 0 {
                let maxWidth: CGFloat = 400
                let scale = min(maxWidth / w, 1.0)
                size = CGSize(width: w * scale, height: h * scale)
            } else {
                size = CGSize(width: 320, height: 240)
            }
        case .templateInstance, .blockTemplate:
            size = CGSize(width: 260, height: 380)
        default:
            size = CGSize(width: 220, height: 310)
        }

        // Build subtitle from body or metadata
        let subtitle = atom.body?.prefix(100).description

        // Build metadata dictionary
        var metadata: [String: String] = [
            "updated": atom.updatedAt
        ]

        // Add type-specific metadata
        switch atom.type {
        case .idea:
            let ideaWrapper = IdeaWrapper(atom: atom)
            metadata["tags"] = ideaWrapper.tagsList.joined(separator: ", ")
            if let ideaStatus = atom.ideaMetadata?.ideaStatus?.rawValue {
                metadata["ideaStatus"] = ideaStatus
            }
        case .task:
            let taskWrapper = TaskWrapper(atom: atom)
            metadata["status"] = taskWrapper.status
            metadata["priority"] = taskWrapper.priority
        case .content:
            let contentWrapper = ContentWrapper(atom: atom)
            metadata["status"] = contentWrapper.status
            // Include focus mode step info from atom metadata
            if let state = ContentFocusModeState.from(atom: atom) {
                metadata["currentStep"] = state.currentStep.rawValue
            }
        case .research:
            let researchWrapper = ResearchWrapper(atom: atom)
            metadata["type"] = researchWrapper.researchType ?? ""

            // Extract URL with fallback to structured JSON fields
            var resolvedURL = researchWrapper.url ?? ""
            if resolvedURL.isEmpty,
               let structuredStr = atom.structured,
               let structuredData = structuredStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: structuredData) as? [String: Any] {
                resolvedURL = json["url"] as? String
                    ?? json["source_url"] as? String
                    ?? json["resolvedURL"] as? String
                    ?? ""
            }
            metadata["url"] = resolvedURL

            // Extract platform, author, thumbnail from structured autoMetadata
            if let structuredStr = atom.structured,
               let structuredData = structuredStr.data(using: .utf8),
               let outer = try? JSONSerialization.jsonObject(with: structuredData) as? [String: Any],
               let autoMetaStr = outer["autoMetadata"] as? String,
               let autoMetaData = autoMetaStr.data(using: .utf8),
               let autoMeta = try? JSONSerialization.jsonObject(with: autoMetaData) as? [String: Any] {
                if let platform = autoMeta["sourceType"] as? String, !platform.isEmpty {
                    metadata["platform"] = platform
                }
                if let author = autoMeta["author"] as? String, !author.isEmpty {
                    metadata["author"] = author
                }
            }

            // Fallback platform to contentSource from research metadata
            if metadata["platform"] == nil || metadata["platform"]?.isEmpty == true {
                if let contentSource = researchWrapper.contentSource, !contentSource.isEmpty {
                    metadata["platform"] = contentSource
                }
            }

            // Thumbnail from research metadata
            if let thumbnail = atom.thumbnailUrl, !thumbnail.isEmpty {
                metadata["thumbnail"] = thumbnail
            }

            if atom.isSwipeFileAtom {
                metadata["isSwipeFile"] = "true"
                if let hookType = atom.swipeAnalysis?.hookType?.rawValue {
                    metadata["hookType"] = hookType
                }
                if let score = atom.swipeAnalysis?.hookScore {
                    metadata["hookScore"] = String(format: "%.1f", score)
                }
            }
        case .connection:
            metadata["type"] = "connection"
        case .image:
            if let imageMeta = atom.imageMetadata {
                metadata["imagePath"] = imageMeta.imagePath
            }
        case .project:
            let projectWrapper = ProjectWrapper(atom: atom)
            metadata["status"] = projectWrapper.status
            metadata["priority"] = projectWrapper.priority
        case .note:
            metadata["title"] = atom.title ?? ""
            metadata["content"] = atom.body ?? ""

            if let atomMetadata = atom.metadata,
               let data = atomMetadata.data(using: .utf8),
               let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in [RichDocumentMetadataKeys.titleDocument, RichDocumentMetadataKeys.bodyDocument] {
                    guard let value = decoded[key],
                          let jsonData = try? JSONSerialization.data(withJSONObject: value),
                          let jsonString = String(data: jsonData, encoding: .utf8) else {
                        continue
                    }
                    metadata[key] = jsonString
                }
            }
        case .templateInstance:
            if let templateData = atom.templateInstanceData {
                metadata["templateUUID"] = templateData.templateUUID
                metadata["instanceStatus"] = templateData.instanceStatus ?? "active"
            }
        default:
            break
        }

        return CanvasBlock(
            position: position,
            size: size,
            entityType: Self.entityType(for: atom.type),
            entityId: atom.id ?? -1,
            entityUuid: atom.uuid,
            title: atom.title ?? "Untitled",
            subtitle: subtitle,
            metadata: metadata
        )
    }

    /// Map AtomType to EntityType, handling cases where raw values differ
    private static func entityType(for atomType: AtomType) -> EntityType {
        switch atomType {
        case .templateInstance, .blockTemplate:
            return .template
        default:
            return EntityType(rawValue: atomType.rawValue) ?? .idea
        }
    }

    // MARK: - Legacy Convenience Methods (using AtomWrappers)

    static func fromIdea(_ ideaWrapper: IdeaWrapper, position: CGPoint) -> CanvasBlock {
        return fromAtom(ideaWrapper.atom, position: position)
    }

    static func fromContent(_ contentWrapper: ContentWrapper, position: CGPoint) -> CanvasBlock {
        return fromAtom(contentWrapper.atom, position: position)
    }

    static func fromTask(_ taskWrapper: TaskWrapper, position: CGPoint) -> CanvasBlock {
        return fromAtom(taskWrapper.atom, position: position)
    }

    static func fromConnection(_ connectionWrapper: ConnectionWrapper, position: CGPoint) -> CanvasBlock {
        return fromAtom(connectionWrapper.atom, position: position)
    }

    static func fromResearch(_ researchWrapper: ResearchWrapper, position: CGPoint) -> CanvasBlock {
        return fromAtom(researchWrapper.atom, position: position)
    }

    static func fromProject(_ projectWrapper: ProjectWrapper, position: CGPoint) -> CanvasBlock {
        return fromAtom(projectWrapper.atom, position: position)
    }

    // MARK: - New Block Types

    /// Create a Cosmo AI block for live AI assistance
    /// - Parameters:
    ///   - position: Position on canvas
    ///   - query: Optional initial query (auto-executed if provided)
    ///   - mode: Optional mode ("research" to auto-start research)
    static func cosmoAIBlock(position: CGPoint, query: String? = nil, mode: String? = nil) -> CanvasBlock {
        var metadata: [String: String] = [
            "mode": mode ?? "idle",
            "created": ISO8601DateFormatter().string(from: Date())
        ]

        // Add query to metadata for auto-execution
        if let query = query, !query.isEmpty {
            metadata["query"] = query
        }

        return CanvasBlock(
            position: position,
            size: CGSize(width: 320, height: 280),  // Larger for AI content
            entityType: .cosmoAI,
            entityId: -1,  // Not linked to database entity initially
            entityUuid: UUID().uuidString,
            title: "Cosmo AI",
            subtitle: query ?? "Ask me anything...",
            metadata: metadata
        )
    }

    /// Create a freeform note block
    static func noteBlock(position: CGPoint, content: String = "") -> CanvasBlock {
        return CanvasBlock(
            position: position,
            size: Self.documentBlockSize,
            entityType: .note,
            entityId: -1,
            entityUuid: UUID().uuidString,
            title: "Note",
            subtitle: nil,
            metadata: [
                "content": content,
                "created": ISO8601DateFormatter().string(from: Date())
            ]
        )
    }

    /// Create a freeform sticky note block (warm yellow paper, no chrome)
    static func stickyNoteBlock(position: CGPoint, content: String = "") -> CanvasBlock {
        return CanvasBlock(
            position: position,
            size: CGSize(width: 220, height: 220),
            entityType: .stickyNote,
            entityId: -1,
            entityUuid: UUID().uuidString,
            title: "",
            subtitle: nil,
            metadata: [
                "content": content,
                "created": ISO8601DateFormatter().string(from: Date())
            ]
        )
    }

    /// Create a calendar/scheduler block for viewing the Scheduler
    static func calendarBlock(position: CGPoint) -> CanvasBlock {
        return CanvasBlock(
            position: position,
            size: CGSize(width: 400, height: 500),  // Larger for scheduler view
            entityType: .calendar,
            entityId: -1,
            entityUuid: UUID().uuidString,
            title: "Scheduler",
            subtitle: "Plan & Today Mode",
            metadata: [
                "created": ISO8601DateFormatter().string(from: Date())
            ]
        )
    }

    // MARK: - Preview Factory Methods

    /// Create a preview idea block (for SwiftUI previews)
    static func previewIdeaBlock(position: CGPoint = CGPoint(x: 200, y: 200)) -> CanvasBlock {
        return CanvasBlock(
            position: position,
            size: CGSize(width: 280, height: 180),
            entityType: .idea,
            entityId: -1,
            entityUuid: UUID().uuidString,
            title: "Brilliant idea for a new feature",
            subtitle: "This could revolutionize how users interact with the app...",
            metadata: [
                "tags": "innovation, product, ux",
                "updated": ISO8601DateFormatter().string(from: Date())
            ]
        )
    }

    /// Create a preview content block (for SwiftUI previews)
    static func previewContentBlock(position: CGPoint = CGPoint(x: 200, y: 200)) -> CanvasBlock {
        return CanvasBlock(
            position: position,
            size: Self.documentBlockSize,
            entityType: .content,
            entityId: -1,
            entityUuid: UUID().uuidString,
            title: "How to Build Better Habits",
            subtitle: "A guide to sustainable behavior change...",
            metadata: [
                "status": "draft",
                "currentStep": "brainstorm",
                "updated": ISO8601DateFormatter().string(from: Date())
            ]
        )
    }

    /// Create a preview task block (for SwiftUI previews)
    static func previewTaskBlock(position: CGPoint = CGPoint(x: 200, y: 200)) -> CanvasBlock {
        return CanvasBlock(
            position: position,
            size: CGSize(width: 280, height: 120),
            entityType: .task,
            entityId: -1,
            entityUuid: UUID().uuidString,
            title: "Review pull request",
            subtitle: "Check the new authentication flow implementation",
            metadata: [
                "status": "pending",
                "priority": "high",
                "updated": ISO8601DateFormatter().string(from: Date())
            ]
        )
    }

    /// Create a preview connection block (for SwiftUI previews)
    static func previewConnectionBlock(position: CGPoint = CGPoint(x: 200, y: 200)) -> CanvasBlock {
        return CanvasBlock(
            position: position,
            size: CGSize(width: 340, height: 400),
            entityType: .connection,
            entityId: -1,
            entityUuid: UUID().uuidString,
            title: "Design System Principles",
            subtitle: "Core concepts linking visual hierarchy, spacing, and typography...",
            metadata: [
                "type": "connection",
                "updated": ISO8601DateFormatter().string(from: Date())
            ]
        )
    }

    /// Create a preview research block (for SwiftUI previews)
    static func previewResearchBlock(position: CGPoint = CGPoint(x: 200, y: 200), isSwipeFile: Bool = false) -> CanvasBlock {
        var metadata: [String: String] = [
            "type": "article",
            "url": "https://example.com/article",
            "updated": ISO8601DateFormatter().string(from: Date())
        ]
        if isSwipeFile {
            metadata["isSwipeFile"] = "true"
            metadata["hookType"] = "curiosity"
            metadata["hookScore"] = "8.5"
        }
        return CanvasBlock(
            position: position,
            size: isSwipeFile ? CGSize(width: 340, height: 380) : CGSize(width: 320, height: 340),
            entityType: .research,
            entityId: -1,
            entityUuid: UUID().uuidString,
            title: isSwipeFile ? "Viral Marketing Breakdown" : "The Future of AI Interfaces",
            subtitle: "Key insights and patterns to study...",
            metadata: metadata
        )
    }
}

// MARK: - Media Type Detection

extension CanvasBlock {
    /// Media type for aspect-ratio-aware block sizing
    enum MediaType {
        case reel       // 9:16 (Instagram Reel, TikTok)
        case youtube    // 16:9 (YouTube, generic video)
        case carousel   // 1:1 (Instagram Carousel)
        case generic    // No specific media (article, note)
    }

    /// Detect media type from an Atom's structured JSON and URL
    static func detectMediaType(atom: Atom) -> MediaType {
        // Check structured JSON for source type and slides
        guard let structured = atom.structured,
              let data = structured.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Fall back to URL-based detection
            let url = atom.url ?? ""
            return detectMediaTypeFromURL(url)
        }

        let sourceType = json["source_type"] as? String ?? json["platform"] as? String ?? ""

        // Carousel detection
        if json["instagramSlides"] != nil || json["slides"] != nil {
            return .carousel
        }

        // Reel detection
        if sourceType == "instagram_reel" || sourceType == "tiktok" {
            return .reel
        }

        // URL-based detection
        let url = json["url"] as? String ?? json["resolvedURL"] as? String ?? json["source_url"] as? String ?? atom.url ?? ""
        return detectMediaTypeFromURL(url)
    }

    /// Detect media type from a URL string alone
    static func detectMediaTypeFromURL(_ url: String) -> MediaType {
        let lower = url.lowercased()
        if lower.contains("youtube.com") || lower.contains("youtu.be") {
            return .youtube
        }
        if lower.contains("tiktok.com") {
            return .reel
        }
        if lower.contains("instagram.com") {
            return .reel  // Default IG to reel unless carousel detected above
        }
        return .generic
    }
}

// MARK: - Block Gestures
extension CanvasBlock {
    mutating func startDrag() {
        isDragging = true
        isSelected = true
        zIndex = 1000  // Bring to front
        dragStartPosition = position  // Store initial position for proper drag tracking
    }

    /// Update position using total translation from drag start (not delta)
    /// This fixes the DPI/sensitivity issue where blocks would fly away
    mutating func updateDrag(translation: CGSize) {
        guard let start = dragStartPosition else { return }
        position = CGPoint(
            x: start.x + translation.width,
            y: start.y + translation.height
        )
    }

    mutating func endDrag() {
        isDragging = false
        zIndex = 0
        dragStartPosition = nil  // Clear start position
    }

    mutating func animateTo(position: CGPoint, duration: Double = 0.3) {
        self.targetPosition = position

        // Calculate velocity for smooth animation
        let dx = position.x - self.position.x
        let dy = position.y - self.position.y
        self.velocity = CGVector(dx: dx / duration, dy: dy / duration)
    }

    mutating func updateAnimation(deltaTime: Double) {
        guard let target = targetPosition else { return }

        // Spring physics
        let springConstant: Double = 10.0
        let damping: Double = 0.8

        let dx = target.x - position.x
        let dy = target.y - position.y

        let distance = sqrt(dx * dx + dy * dy)

        if distance < 1.0 {
            // Snap to target
            position = target
            targetPosition = nil
            velocity = .zero
        } else {
            // Apply spring force
            let force = CGVector(
                dx: dx * springConstant,
                dy: dy * springConstant
            )

            velocity.dx = velocity.dx * damping + force.dx * deltaTime
            velocity.dy = velocity.dy * damping + force.dy * deltaTime

            position.x += velocity.dx * deltaTime
            position.y += velocity.dy * deltaTime
        }
    }
}
