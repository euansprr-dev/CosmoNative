// CosmoOS/Canvas/Spaces/SpaceIdentityMark.swift
// The one identity mark for a space, everywhere a space is named (sidebar
// rows, the collapsed rail, the rename row, the composer well). Identity
// outranks type: an emoji → a client's colour dot → the kind's glyph in the
// space's accent. Fixed square frame so rows and rails stay aligned.

import SwiftUI

struct SpaceIdentityMark: View {
    let thinkspace: Thinkspace
    var size: CGFloat = 16

    var body: some View {
        SpaceIdentityMarkPreview(
            emoji: thinkspace.identityEmoji,
            kind: thinkspace.kind ?? .custom,
            accent: thinkspace.accentColor,
            size: size
        )
    }
}

/// The mark drawn from loose parts — the composer's live preview, and the
/// implementation `SpaceIdentityMark` delegates to.
struct SpaceIdentityMarkPreview: View {
    let emoji: String?
    let kind: SpaceKind
    let accent: Color
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            if let emoji {
                Text(emoji)
                    .font(Self.glyphFont(for: size))
            } else if kind == .client {
                Circle()
                    .fill(accent)
                    .frame(width: size * 0.6, height: size * 0.6)
            } else {
                Image(systemName: kind.glyph)
                    .font(Self.glyphFont(for: size).weight(.semibold))
                    .foregroundStyle(accent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// DS rungs by frame size — the mark never types a raw point size.
    static func glyphFont(for size: CGFloat) -> Font {
        switch size {
        case ..<15: return DS.caption
        case ..<20: return DS.callout
        case ..<26: return DS.headline
        case ..<34: return DS.title2
        default: return DS.pageTitle
        }
    }
}
