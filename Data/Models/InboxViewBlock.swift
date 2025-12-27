// CosmoOS/Data/Models/InboxViewBlock.swift
// Legacy InboxViewBlock stub - functionality moved to Plannerium

import Foundation
import SwiftUI

/// Legacy InboxViewBlock - kept as stub for compilation
/// New inbox functionality is in Plannerium
struct InboxViewBlock: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var position: CGPoint = .zero
    var config: InboxConfig = InboxConfig()

    // Layout properties
    var x: CGFloat {
        get { position.x }
        set { position.x = newValue }
    }
    var y: CGFloat {
        get { position.y }
        set { position.y = newValue }
    }
    var width: CGFloat = 280
    var height: CGFloat = 400
    var title: String = "Inbox"
    var zIndex: Int = 0

    struct InboxConfig: Codable, Equatable {
        var onlyPromoted: Bool = false
        var projectId: Int64? = nil
        var assignmentStatus: String? = nil
        var entityType: String? = nil
    }

    // Factory methods (stubs)
    static func general(at position: CGPoint) -> InboxViewBlock {
        InboxViewBlock(position: position)
    }

    static func allUncommitted(at position: CGPoint) -> InboxViewBlock {
        InboxViewBlock(position: position)
    }

    static func recentlyPromoted(at position: CGPoint) -> InboxViewBlock {
        var block = InboxViewBlock(position: position)
        block.config.onlyPromoted = true
        return block
    }

    static func projectInbox(projectId: Int64, projectName: String, at position: CGPoint) -> InboxViewBlock {
        var block = InboxViewBlock(position: position)
        block.config.projectId = projectId
        return block
    }

    static func projectInbox(projectUuid: String, projectName: String, projectIcon: String, projectColor: String?, at position: CGPoint) -> InboxViewBlock {
        var block = InboxViewBlock(position: position)
        block.title = projectName
        return block
    }

    static func typeFilter(entityType: String, at position: CGPoint) -> InboxViewBlock {
        var block = InboxViewBlock(position: position)
        block.config.entityType = entityType
        return block
    }
}

/// Legacy InboxViewBlockView stub
struct InboxViewBlockView: View {
    let block: InboxViewBlock
    var effectiveScale: CGFloat = 1.0
    var onDragStart: (() -> Void)? = nil
    var onDrag: ((CGSize) -> Void)? = nil
    var onDragEnd: (() -> Void)? = nil
    var onResize: ((CGSize) -> Void)? = nil
    var onResizeEnd: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    init(
        block: InboxViewBlock,
        effectiveScale: CGFloat = 1.0,
        onDragStart: (() -> Void)? = nil,
        onDrag: ((CGSize) -> Void)? = nil,
        onDragEnd: (() -> Void)? = nil,
        onResize: ((CGSize) -> Void)? = nil,
        onResizeEnd: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.block = block
        self.effectiveScale = effectiveScale
        self.onDragStart = onDragStart
        self.onDrag = onDrag
        self.onDragEnd = onDragEnd
        self.onResize = onResize
        self.onResizeEnd = onResizeEnd
        self.onClose = onClose
    }

    var body: some View {
        // Stub - shows nothing
        EmptyView()
    }
}

/// Legacy InboxViewSelection enum stub
enum InboxViewSelection: Equatable {
    case general
    case generalInbox
    case allUncommitted
    case recentlyPromoted
    case projectInbox(projectUuid: String, projectName: String, projectIcon: String, projectColor: String?)
    case statusFilter(status: String)
    case typeFilter(entityType: String)
    case createProject
}
