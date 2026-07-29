import SwiftUI

// MARK: - Section header

struct SwipeFilterSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(DS.caption.weight(.bold))
            .foregroundStyle(DS.textSecondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

// MARK: - Checkbox / radio glyphs

struct SwipeFilterCheckbox: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(isOn ? DS.accent : DS.glassBorder, lineWidth: 1.5)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(DS.accent)
                .opacity(isOn ? 1 : 0)
            Image(systemName: "checkmark")
                .font(DS.caption2.weight(.bold))
                .foregroundStyle(DS.textOnAccent)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

struct SwipeFilterRadio: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle().stroke(isOn ? DS.accent : DS.glassBorder, lineWidth: 1.5)
            Circle()
                .fill(DS.accent)
                .frame(width: 10, height: 10)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

// MARK: - Rows

struct SwipeFilterCheckRow: View {
    let title: String
    var systemImage: String?
    /// Raw platform key — when set, renders the honest vector mark
    /// (SwipePlatformGlyph) instead of the SF symbol.
    var platformKey: String?
    var iconTint: Color = DS.textMuted
    /// Live count for the facet, trailing and muted (the ledger voice).
    /// Nil keeps the row exactly as it was before counts existed.
    var trailingCount: Int?
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SwipeFilterCheckbox(isOn: isOn)
                if let platformKey {
                    SwipePlatformGlyph(source: platformKey)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(iconTint)
                        .frame(width: 20)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(DS.callout.weight(.semibold))
                        .foregroundStyle(iconTint)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.text)
                Spacer(minLength: 0)
                if let trailingCount {
                    Text("\(trailingCount)")
                        .font(DS.caption.monospacedDigit())
                        .foregroundStyle(DS.textMuted)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? DS.glassInputFill : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in withAnimation(ProMotionSprings.hover) { hovering = value } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(trailingCount.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct SwipeFilterRadioRow: View {
    let title: String
    var systemImage: String?
    var iconTint: Color = DS.textMuted
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(DS.callout.weight(.semibold))
                        .foregroundStyle(isOn ? iconTint : DS.textMuted)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(DS.callout.weight(isOn ? .semibold : .medium))
                    .foregroundStyle(isOn ? DS.text : DS.textSecondary)
                Spacer(minLength: 8)
                SwipeFilterRadio(isOn: isOn)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? DS.glassInputFill : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in withAnimation(ProMotionSprings.hover) { hovering = value } }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Segment chip (multi-select flow chips inside the popover)

struct SwipeFilterSegmentChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(DS.subheadline.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(isSelected ? DS.accentSoft : Color.clear))
                .overlay(Capsule().strokeBorder(isSelected ? DS.accent.opacity(0.42) : DS.glassBorder, lineWidth: isSelected ? 1 : 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Scope chip (the page-level capsule row)

struct SwipeScopeChip: View {
    let title: String
    var count: Int?
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(DS.subheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? DS.text : (hovering ? DS.textSecondary : DS.textMuted))
                if let count {
                    Text("\(count)")
                        .font(DS.caption.monospacedDigit())
                        .foregroundStyle(isSelected ? DS.textSecondary : DS.textMuted)
                        .contentTransition(.numericText())
                        .animation(ProMotionSprings.gentle, value: count)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(Capsule().fill(isSelected ? DS.accentSoft : (hovering ? DS.glassInputFill : Color.clear)))
            .overlay(Capsule().strokeBorder(isSelected ? DS.accent.opacity(0.42) : DS.glassBorder, lineWidth: isSelected ? 1 : 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { value in withAnimation(ProMotionSprings.hover) { hovering = value } }
        .animation(ProMotionSprings.snappy, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Active filter tokens

struct SwipeFilterToken: Identifiable, Equatable {
    let id: String
    let label: String
}

/// The only persistent evidence of filtering — rendered solely when filters are active.
struct SwipeActiveFilterTokens: View {
    let tokens: [SwipeFilterToken]
    let onRemove: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tokens) { token in
                tokenChip(token)
            }
            Button("Clear filters", action: onClear)
                .buttonStyle(.plain)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.textMuted)
                .help("Remove all filters")
            Spacer(minLength: 0)
        }
        .animation(ProMotionSprings.snappy, value: tokens)
    }

    private func tokenChip(_ token: SwipeFilterToken) -> some View {
        Button {
            onRemove(token.id)
        } label: {
            HStack(spacing: 5) {
                Text(token.label)
                    .font(DS.caption.weight(.medium))
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.semibold))
            }
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(DS.accentSoft))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Remove filter")
        .accessibilityLabel("Remove filter \(token.label)")
        .transition(.opacity)
    }
}

// MARK: - Library filter state ⇄ tokens

extension SwipeLibraryFilterState {
    var activeTokens: [SwipeFilterToken] {
        var tokens: [SwipeFilterToken] = []
        if smartPreset != .all {
            tokens.append(.init(id: "preset", label: smartPreset.title))
        }
        for platform in platforms.sorted() {
            tokens.append(.init(id: "platform:\(platform)", label: platform))
        }
        for hookType in hookTypes.sorted(by: { $0.rawValue < $1.rawValue }) {
            tokens.append(.init(id: "hook:\(hookType.rawValue)", label: hookType.displayName))
        }
        for narrative in narratives.sorted(by: { $0.rawValue < $1.rawValue }) {
            tokens.append(.init(id: "narrative:\(narrative.rawValue)", label: narrative.displayName))
        }
        for format in formats.sorted(by: { $0.rawValue < $1.rawValue }) {
            tokens.append(.init(id: "format:\(format.rawValue)", label: format.displayName))
        }
        if let creator { tokens.append(.init(id: "creator", label: creator)) }
        if let niche { tokens.append(.init(id: "niche", label: niche)) }
        if onlyStudied { tokens.append(.init(id: "studied", label: "Studied")) }
        if onlyUnstudied { tokens.append(.init(id: "unstudied", label: "Unstudied")) }
        if let minimumHookScore {
            tokens.append(.init(id: "score", label: "Score \(Int(minimumHookScore))+"))
        }
        return tokens
    }

    mutating func removeToken(_ id: String) {
        switch id {
        case "preset": smartPreset = .all
        case "creator": creator = nil
        case "niche": niche = nil
        case "studied": onlyStudied = false
        case "unstudied": onlyUnstudied = false
        case "score": minimumHookScore = nil
        default:
            if id.hasPrefix("platform:") {
                platforms.remove(String(id.dropFirst("platform:".count)))
            } else if id.hasPrefix("hook:") {
                if let value = SwipeHookType(rawValue: String(id.dropFirst("hook:".count))) {
                    hookTypes.remove(value)
                }
            } else if id.hasPrefix("narrative:") {
                if let value = NarrativeStyle(rawValue: String(id.dropFirst("narrative:".count))) {
                    narratives.remove(value)
                }
            } else if id.hasPrefix("format:") {
                if let value = ContentFormat(rawValue: String(id.dropFirst("format:".count))) {
                    formats.remove(value)
                }
            }
        }
    }
}
