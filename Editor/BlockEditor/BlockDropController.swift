import CoreGraphics
import Foundation
import SwiftUI

enum BlockDropPosition: String, Codable, Equatable, Hashable, Sendable {
    case above
    case below
}

struct BlockDragPayload: Codable, Equatable, Hashable, Sendable {
    var blockID: UUID
    var sourcePath: BlockPath
}

/// Cross-container drop forwarding. A nested block list (a section or
/// element body, toggle children) resolves drag payloads by ID in its OWN
/// sub-document, so a block dragged in from anywhere else is invisible to it.
/// The root list installs its whole-document mover here; nested lists hand
/// over any drop they cannot resolve locally.
@MainActor
final class BlockDropRouter {
    var moveAcrossContainers: ((BlockDragPayload, BlockDropPosition, UUID) -> Void)?
}

private struct BlockDropRouterKey: EnvironmentKey {
    static let defaultValue: BlockDropRouter? = nil
}

extension EnvironmentValues {
    /// Set by the top-level BlockListView; nested lists forward foreign drops.
    var blockDropRouter: BlockDropRouter? {
        get { self[BlockDropRouterKey.self] }
        set { self[BlockDropRouterKey.self] = newValue }
    }
}

enum BlockDropController {
    static func target(for position: BlockDropPosition, path: BlockPath) -> BlockDropTarget {
        let insertionIndex: Int
        switch position {
        case .above:
            insertionIndex = path.indexInParent
        case .below:
            insertionIndex = path.indexInParent + 1
        }
        return BlockDropTarget(parent: path.parent, index: insertionIndex)
    }

    static func encodedPayload(_ payload: BlockDragPayload) -> Data {
        do {
            return try JSONEncoder().encode(payload)
        } catch {
            assertionFailure("Failed to encode block drag payload: \(error)")
            return Data()
        }
    }

    static func decodedPayload(_ data: Data) -> BlockDragPayload? {
        try? JSONDecoder().decode(BlockDragPayload.self, from: data)
    }

    static func canMove(from source: BlockPath, to target: BlockDropTarget) -> Bool {
        if target.parent == source.parent, target.index == source.indexInParent {
            return false
        }
        if target.parent == source.parent, target.index == source.indexInParent + 1 {
            return false
        }
        if let parent = target.parent, parent.indices.starts(with: source.indices) {
            return false
        }
        return true
    }
}

enum BlockInteractionPolicy {
    /// Total leading width of the block gutter: ＋ button (22) + spacing (2)
    /// + six-dot handle (24) + row gap (4). Hosts use this to align titles
    /// and metadata with the block text column.
    static let gutterWidth: CGFloat = 52

    enum VerticalAnchor: Equatable, Hashable, Sendable {
        case textBaseline
        case headingBaseline
        case center
        case cardHeader
    }

    struct HandleMetrics: Equatable, Hashable, Sendable {
        var verticalAnchor: VerticalAnchor
        var topPadding: CGFloat
        var hitSize: CGSize
    }

    struct Chrome: Equatable, Hashable, Sendable {
        var reservedLeadingWidth: CGFloat
        var handleOpacity: Double
        var dropIndicatorOpacity: Double
        var dropIndicatorHeight: CGFloat
    }

    static func handleMetrics(for kind: RichBlockKind) -> HandleMetrics {
        switch kind {
        case .heading1, .heading2, .heading3:
            return HandleMetrics(verticalAnchor: .headingBaseline, topPadding: 0, hitSize: CGSize(width: 28, height: 32))
        case .divider:
            return HandleMetrics(verticalAnchor: .center, topPadding: 0, hitSize: CGSize(width: 28, height: 28))
        case .element, .image, .sketch:
            return HandleMetrics(verticalAnchor: .cardHeader, topPadding: 8, hitSize: CGSize(width: 28, height: 32))
        case .callout, .code:
            return HandleMetrics(verticalAnchor: .cardHeader, topPadding: 8, hitSize: CGSize(width: 28, height: 32))
        case .content, .research:
            return HandleMetrics(verticalAnchor: .cardHeader, topPadding: 20, hitSize: CGSize(width: 28, height: 32))
        case .paragraph, .quote, .bulletList, .numberedList, .checklist, .toggle:
            return HandleMetrics(verticalAnchor: .textBaseline, topPadding: 0, hitSize: CGSize(width: 28, height: 24))
        case .table, .section:
            return HandleMetrics(verticalAnchor: .cardHeader, topPadding: 8, hitSize: CGSize(width: 28, height: 32))
        }
    }

    static func chrome(isHovered: Bool, isDropTarget: Bool, darkMode: Bool) -> Chrome {
        Chrome(
            reservedLeadingWidth: Self.gutterWidth,
            handleOpacity: isHovered || isDropTarget ? 1 : 0,
            dropIndicatorOpacity: isDropTarget ? (darkMode ? 0.9 : 0.75) : 0,
            dropIndicatorHeight: isDropTarget ? 2 : 0
        )
    }

    static func revealsHandleChrome(
        isHovered: Bool,
        isSelected: Bool,
        isMenuPresented: Bool,
        isDropTarget: Bool
    ) -> Bool {
        isHovered || isMenuPresented || isDropTarget
    }
}

enum BlockMotionPolicy {
    static let chromeResponse: CGFloat = 0.18
    static let chromeDampingFraction: CGFloat = 0.88
    static let dropResponse: CGFloat = 0.14
    static let dropDampingFraction: CGFloat = 0.92
}
