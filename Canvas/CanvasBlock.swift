// CosmoOS/Canvas/CanvasBlock.swift
// Floating block model with full entity data

import Foundation
import SwiftUI

struct CanvasBlock: Identifiable, Codable {
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
        size: CGSize = CGSize(width: 280, height: 200),
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
                size = CGSize(width: 340, height: 380)
            } else {
                size = CGSize(width: 320, height: 340)
            }
        case .content:
            size = CGSize(width: 300, height: 220)
        case .connection:
            size = CGSize(width: 340, height: 400)
        default:
            size = CGSize(width: 280, height: 180)
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
            metadata["url"] = researchWrapper.url ?? ""
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
        case .project:
            let projectWrapper = ProjectWrapper(atom: atom)
            metadata["status"] = projectWrapper.status
            metadata["priority"] = projectWrapper.priority
        default:
            break
        }

        return CanvasBlock(
            position: position,
            size: size,
            entityType: EntityType(rawValue: atom.type.rawValue) ?? .idea,
            entityId: atom.id ?? -1,
            entityUuid: atom.uuid,
            title: atom.title ?? "Untitled",
            subtitle: subtitle,
            metadata: metadata
        )
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
            size: CGSize(width: 320, height: 280),  // Full card size for proper editing
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
