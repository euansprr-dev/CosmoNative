// CosmoOS/UI/CosmoWindow/CosmoMentionPillKit.swift
// Shared mention-pill rendering: the attachment + capsule cell used by the chat
// composer (typed @-mentions) and the assistant pane (document pills in answers).
// June 2026

import SwiftUI
import AppKit

/// Maps assistant source-ref kinds onto entity tints so pane document pills share
/// the composer's color language exactly.
enum CosmoMentionPillTint {
    static func entityType(forSourceKind kind: String) -> EntityType {
        switch kind {
        case "clientProfile", "client_profile": return .connection
        default: return EntityType(rawValue: kind) ?? .note
        }
    }

    static func nsColor(forSourceKind kind: String) -> NSColor {
        CosmoMentionColors.nsColor(for: entityType(forSourceKind: kind))
    }
}

/// A single, atomic mention rendered as a capsule (type icon + title) inside text
/// storage. It stores `token` — the plain-text projection (`"@<title>"`) — so the
/// composer can serialize back to a clean string for the agent and the parser.
final class CosmoMentionPillAttachment: NSTextAttachment {
    let token: String
    let title: String
    let tint: NSColor

    private init(token: String, title: String, iconName: String, tint: NSColor) {
        self.token = token
        self.title = title
        self.tint = tint
        super.init(data: nil, ofType: nil)
        self.attachmentCell = CosmoMentionPillCell(
            title: title,
            iconName: iconName,
            tint: tint
        )
    }

    convenience init(atom: Atom, token: String) {
        let entityType = EntityType(rawValue: atom.type.rawValue) ?? .note
        self.init(
            token: token,
            title: atom.title ?? "Untitled",
            iconName: atom.type.iconName,
            tint: CosmoMentionColors.nsColor(for: entityType)
        )
    }

    /// Pane answers reference documents by source ref (uuid/title/kind), not Atom.
    convenience init(sourceRef: CosmoAssistantSourceRef) {
        let title = sourceRef.title.isEmpty ? "Untitled" : sourceRef.title
        self.init(
            token: "@\(title)",
            title: title,
            iconName: sourceRef.icon,
            tint: CosmoMentionPillTint.nsColor(forSourceKind: sourceRef.kind)
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CosmoMentionPillAttachment is not archivable")
    }
}

/// Draws the capsule: tinted rounded background, type SF Symbol, and the title.
/// Property names are prefixed to avoid colliding with `NSCell`'s `title`/`font`.
final class CosmoMentionPillCell: NSTextAttachmentCell {
    private let pillTitle: String
    private let pillIcon: NSImage?
    private let pillTint: NSColor
    private let pillFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

    private let hPad: CGFloat = 8
    private let iconSize: CGFloat = 12
    private let gap: CGFloat = 5
    private let vPad: CGFloat = 2
    private let maxTitleChars = 32

    init(title: String, iconName: String, tint: NSColor) {
        self.pillTitle = title
        self.pillTint = tint
        let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
        self.pillIcon = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        super.init()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("CosmoMentionPillCell is not archivable")
    }

    private var displayTitle: String {
        guard pillTitle.count > maxTitleChars else { return pillTitle }
        return String(pillTitle.prefix(maxTitleChars - 1)) + "…"
    }

    private var titleAttributes: [NSAttributedString.Key: Any] {
        [.font: pillFont, .foregroundColor: pillTint]
    }

    private func titleSize() -> NSSize {
        (displayTitle as NSString).size(withAttributes: titleAttributes)
    }

    override func cellSize() -> NSSize {
        let titleWidth = ceil(titleSize().width)
        let width = hPad + iconSize + gap + titleWidth + hPad
        let height = ceil(pillFont.ascender - pillFont.descender) + vPad * 2
        return NSSize(width: width, height: height)
    }

    override func cellBaselineOffset() -> NSPoint {
        // Drop the capsule so the title baseline lines up with the surrounding text.
        NSPoint(x: 0, y: pillFont.descender - vPad)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let rect = cellFrame.insetBy(dx: 0.5, dy: 0.5)
        let radius = rect.height / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        pillTint.withAlphaComponent(0.12).setFill()
        path.fill()

        let midY = rect.midY
        var cursorX = rect.minX + hPad

        if let pillIcon {
            let tinted = Self.tinted(pillIcon, with: pillTint)
            let iconRect = NSRect(x: cursorX, y: midY - iconSize / 2, width: iconSize, height: iconSize)
            tinted.draw(in: iconRect)
            cursorX += iconSize + gap
        }

        let size = titleSize()
        let textRect = NSRect(x: cursorX, y: midY - size.height / 2, width: size.width, height: size.height)
        (displayTitle as NSString).draw(in: textRect, withAttributes: titleAttributes)
    }

    private static func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect)
        rect.fill(using: .sourceAtop)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }
}
