// CosmoOS/UI/InlineAssistant/CosmoAssistantMenuKit.swift
// The inline assistant's menu grammar — the Notes slash-menu language
// (dense ink rows, small-caps sections, keyboard footer) shared by the
// @ context picker and the / skills picker.
// July 2026

import AppKit
import Foundation
import SwiftUI

// MARK: - Section header

/// Small-caps section header, the one header voice (SlashCommandMenu recipe).
struct CosmoAssistantMenuSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(DS.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(DS.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.space12)
            .padding(.top, DS.space8)
            .padding(.bottom, DS.space2)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Dense row

/// One ~34pt menu row: 20pt icon slot, medium title, optional trailing mono
/// hint, optional checkmark for already-attached items. Highlight is a soft
/// accent wash + hairline — never a solid fill, never a per-row card.
struct CosmoAssistantMenuRow: View {
    let icon: String
    /// nil = ink (textSecondary); set for entity tints. The tint lives on the
    /// glyph only — no icon tile backgrounds in this grammar.
    var iconTint: Color?
    let title: String
    var trailingHint: String?
    var showsCheckmark: Bool = false
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: icon)
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(iconColor)
                .frame(width: 20, alignment: .center)
                .accessibilityHidden(true)

            Text(title)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let trailingHint {
                Text(trailingHint)
                    .font(DS.caption.monospaced())
                    .foregroundStyle(DS.textMuted.opacity(0.8))
                    .lineLimit(1)
            }

            if showsCheckmark {
                Image(systemName: "checkmark")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, DS.space10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHighlighted ? DS.accentSoft : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isHighlighted ? DS.accent.opacity(0.22) : Color.clear, lineWidth: 1)
                )
                .padding(.horizontal, DS.space6)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(rowTraits)
    }

    private var iconColor: Color {
        if let iconTint { return iconTint }
        return isHighlighted ? DS.accent : DS.textSecondary
    }

    private var rowTraits: AccessibilityTraits {
        showsCheckmark ? [.isButton, .isSelected] : .isButton
    }
}

// MARK: - Detail strip

/// One-line strip between the list and the keyboard footer: the highlighted
/// row's summary, so dense rows never have to carry their own subtitle.
struct CosmoAssistantMenuDetailStrip: View {
    let icon: String
    let text: String
    var trailing: String?

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DS.sepiaBorder.opacity(0.7))
                .frame(height: 1)

            HStack(spacing: DS.space6) {
                Image(systemName: icon)
                    .font(DS.caption2.weight(.medium))
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
                Text(text)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing)
                        .font(DS.caption.monospaced())
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space6)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Keyboard routing policy

enum CosmoAssistantMenuKeyAction: Equatable {
    case moveUp
    case moveDown
    case commit
    case passthrough
}

/// Pure key-routing policy for the assistant menus: while a menu is visible,
/// ↑↓ move the highlight and Return/Tab commit it — Return must never fall
/// through to submit the raw composer text. With no menu open every key
/// passes through (the ghost-chip Tab and Return-to-send keep working).
enum CosmoAssistantMenuKeyRouter {
    static let upArrowKeyCode: UInt16 = 126
    static let downArrowKeyCode: UInt16 = 125
    static let returnKeyCode: UInt16 = 36
    static let tabKeyCode: UInt16 = 48

    static func action(keyCode: UInt16, isMenuVisible: Bool) -> CosmoAssistantMenuKeyAction {
        guard isMenuVisible else { return .passthrough }
        switch keyCode {
        case upArrowKeyCode: return .moveUp
        case downArrowKeyCode: return .moveDown
        case returnKeyCode, tabKeyCode: return .commit
        default: return .passthrough
        }
    }
}

/// Highlight index math shared by both menus: clamped, never wrapping
/// (the SlashCommandMenu feel — the top and bottom are hard stops).
enum CosmoAssistantMenuHighlightPolicy {
    static func moved(_ index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + delta, 0), count - 1)
    }

    static func clamped(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}

// MARK: - Composer token washes

/// Which intent token gets a wash in the composer text.
enum CosmoInlineComposerWashKind: Equatable {
    /// An active kind-scope token ("@idea …") — washed in the kind's entity tint.
    case scope(CosmoInlineContextScope)
    /// An armed skill token ("/Content Review") — washed in the accent.
    case skill
}

struct CosmoInlineComposerTokenWash: Equatable {
    let range: NSRange
    let kind: CosmoInlineComposerWashKind
}

/// Pure policy computing the intent-token washes for a composer's plain text —
/// the Mac port of the iOS task composer's token highlight.
enum CosmoInlineComposerTokenWashPolicy {
    static func washes(
        text: String,
        selection: NSRange,
        armedSkillName: String?
    ) -> [CosmoInlineComposerTokenWash] {
        var washes: [CosmoInlineComposerTokenWash] = []

        if let mention = MentionComposerMentionParser.activeMention(in: text, selectedRange: selection) {
            let parse = CosmoInlineContextScopeParser.parse(mention.query)
            if let scope = parse.scope {
                // "@" + the scope token itself, not the remainder query.
                let tokenRange = NSRange(
                    location: mention.range.location,
                    length: 1 + parse.scopeTokenLength
                )
                washes.append(CosmoInlineComposerTokenWash(range: tokenRange, kind: .scope(scope)))
            }
        }

        if let armedSkillName, !armedSkillName.isEmpty {
            washes.append(contentsOf: skillTokenWashes(text: text, skillName: armedSkillName))
        }

        return washes
    }

    /// Ready-to-stamp washes for the composer: policy ranges mapped to their
    /// NSColors. Shared by the bar and the pane composer.
    static func rendered(
        text: String,
        selection: NSRange,
        armedSkillName: String?
    ) -> [MentionComposerTokenWash] {
        washes(text: text, selection: selection, armedSkillName: armedSkillName).map { wash in
            MentionComposerTokenWash(range: wash.range, color: color(for: wash.kind))
        }
    }

    static func color(for kind: CosmoInlineComposerWashKind) -> NSColor {
        switch kind {
        case .scope(let scope): return CosmoMentionColors.nsColor(for: scope.entityType)
        case .skill: return NSColor(DS.accent)
        }
    }

    private static func skillTokenWashes(text: String, skillName: String) -> [CosmoInlineComposerTokenWash] {
        let nsText = text as NSString
        let token = "/\(skillName)"
        var washes: [CosmoInlineComposerTokenWash] = []
        var searchStart = 0

        while searchStart < nsText.length {
            let found = nsText.range(
                of: token,
                options: [.caseInsensitive],
                range: NSRange(location: searchStart, length: nsText.length - searchStart)
            )
            guard found.location != NSNotFound else { break }
            searchStart = found.location + found.length

            // Token boundaries: preceded by start/whitespace, followed by
            // end/whitespace — "/review" inside a URL never washes.
            if found.location > 0 {
                let before = nsText.substring(with: NSRange(location: found.location - 1, length: 1))
                guard before.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else { continue }
            }
            let after = found.location + found.length
            if after < nsText.length {
                let next = nsText.substring(with: NSRange(location: after, length: 1))
                guard next.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else { continue }
            }

            washes.append(CosmoInlineComposerTokenWash(range: found, kind: .skill))
        }

        return washes
    }
}
