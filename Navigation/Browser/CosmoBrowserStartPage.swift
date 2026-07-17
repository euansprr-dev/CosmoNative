// CosmoOS/Navigation/Browser/CosmoBrowserStartPage.swift
// The research launchpad: a hero query field over grouped favicon-led
// sections. One container grammar, small-caps headers with live counts,
// teaching empty states, entrance cascade.

import SwiftUI
import AppKit

struct CosmoBrowserStartPage: View {
    let favorites: [CosmoBrowserPinnedSite]
    let recentHistory: [CosmoBrowserHistoryItem]
    let onOpen: (URL, String?) -> Void
    let onOpenInSplit: (URL, String?) -> Void
    let onRename: (CosmoBrowserPinnedSite) -> Void
    let onRemove: (CosmoBrowserPinnedSite) -> Void

    @State private var query = ""
    @State private var hasAppeared = false
    @State private var showsOlderRecents = false
    @FocusState private var isQueryFocused: Bool
    @Environment(\.isPaneActive) private var isPaneActive

    /// Reading measure for the launchpad column.
    private let measure: CGFloat = 620
    private let recentCap = 8
    private let recentExpandedCap = 24

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                heroQueryField
                    .cascadeIn(hasAppeared, index: 0)
                favoritesSection
                    .cascadeIn(hasAppeared, index: 1)
                recentSection
                    .cascadeIn(hasAppeared, index: 2)
            }
            .frame(maxWidth: measure)
            .padding(.horizontal, DS.space24)
            .padding(.top, DS.space48)
            .padding(.bottom, DS.space24)
            .frame(maxWidth: .infinity)
        }
        .background(DS.bg)
        .task {
            try? await Task.sleep(for: .milliseconds(40))
            hasAppeared = true
            if isPaneActive {
                isQueryFocused = true
            }
        }
    }

    // MARK: - Hero: the query field

    private var heroQueryField: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: "magnifyingglass")
                .font(DS.callout.weight(.medium))
                .foregroundStyle(isQueryFocused ? DS.accent : DS.textMuted)
                .accessibilityHidden(true)
            TextField("Search or enter address", text: $query)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .focused($isQueryFocused)
                .onSubmit(submitQuery)
        }
        .padding(.horizontal, DS.space12)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous)
                .fill(isQueryFocused ? DS.glassInputFillFocused : DS.glassInputFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous)
                .stroke(isQueryFocused ? DS.focusRing : DS.borderSubtle, lineWidth: 1)
        )
        .animation(ProMotionSprings.focusTransition, value: isQueryFocused)
        .accessibilityLabel("Search or enter address")
    }

    private func submitQuery() {
        guard let url = CosmoBrowserURLResolver.resolve(query) else { return }
        query = ""
        onOpen(url, nil)
    }

    // MARK: - Favorites

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            CommandKSectionLabel(label: "Favorites", count: favorites.count)
            groupedContainer {
                if favorites.isEmpty {
                    teachingRow(
                        icon: "bookmark",
                        message: "Pin pages you return to — press ⌘D on any page."
                    )
                } else {
                    ForEach(Array(favorites.enumerated()), id: \.element.id) { index, favorite in
                        CosmoBrowserFavoriteStartRow(
                            favorite: favorite,
                            isLast: index == favorites.count - 1,
                            onOpen: { onOpen(favorite.url, favorite.displayName) },
                            onOpenInSplit: { onOpenInSplit(favorite.url, favorite.displayName) },
                            onRename: { onRename(favorite) },
                            onRemove: { onRemove(favorite) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Recent

    private var visibleRecents: [CosmoBrowserHistoryItem] {
        Array(recentHistory.prefix(showsOlderRecents ? recentExpandedCap : recentCap))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            CommandKSectionLabel(label: "Recent", count: recentHistory.count)
            groupedContainer {
                if recentHistory.isEmpty {
                    teachingRow(
                        icon: "clock",
                        message: "Pages you visit appear here for quick return."
                    )
                } else {
                    recentRows
                }
            }
        }
    }

    @ViewBuilder
    private var recentRows: some View {
        ForEach(Array(visibleRecents.enumerated()), id: \.element.id) { index, item in
            CosmoBrowserRecentStartRow(
                item: item,
                isLast: index == visibleRecents.count - 1 && !hasOlderRecents,
                onOpen: { onOpen(item.url, item.title) },
                onOpenInSplit: { onOpenInSplit(item.url, item.title) }
            )
        }
        if hasOlderRecents {
            olderRecentsRow
        }
    }

    private var hasOlderRecents: Bool {
        recentHistory.count > recentCap
    }

    private var olderRecentsRow: some View {
        Button {
            withAnimation(ProMotionSprings.focusTransition) {
                showsOlderRecents.toggle()
            }
        } label: {
            Text(showsOlderRecents ? "Show Fewer" : "Show Older Pages")
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsOlderRecents ? "Show fewer recent pages" : "Show older pages")
    }

    // MARK: - Shared furniture

    private func groupedContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }

    /// Empty states teach the next action — never a silent section.
    private func teachingRow(icon: String, message: String) -> some View {
        HStack(spacing: DS.space10) {
            Image(systemName: icon)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.textMuted)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            Text(message)
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Rows

/// Row press feel shared by both sections: the quiet compress.
private struct CosmoBrowserStartRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(ProMotionSprings.press, value: configuration.isPressed)
    }
}

private struct CosmoBrowserFavoriteStartRow: View {
    let favorite: CosmoBrowserPinnedSite
    let isLast: Bool
    let onOpen: () -> Void
    let onOpenInSplit: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                onOpenInSplit()
            } else {
                onOpen()
            }
        } label: {
            rowLabel
        }
        .buttonStyle(CosmoBrowserStartRowButtonStyle())
        .help(favorite.url.absoluteString)
        .contextMenu {
            Button(action: onOpen) {
                Label("Open Favorite", systemImage: "arrow.up.forward.app")
            }
            Button(action: onOpenInSplit) {
                Label("Open in Split", systemImage: "rectangle.split.2x1")
            }
            Button(action: onRename) {
                Label("Rename Favorite", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive, action: onRemove) {
                Label("Remove Favorite", systemImage: "trash")
            }
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
    }

    private var rowLabel: some View {
        HStack(spacing: DS.space10) {
            CommandKFavicon(host: favorite.host, size: 26) {
                CosmoIdentityChip(systemName: "globe", tint: DS.textMuted, size: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(favorite.displayName)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Text(favorite.host)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .contentShape(Rectangle())
        .background(isHovered ? DS.surfaceHover : .clear)
        .overlay(alignment: .bottom) {
            CosmoBrowserRowSeparator(isLast: isLast)
        }
    }
}

private struct CosmoBrowserRecentStartRow: View {
    let item: CosmoBrowserHistoryItem
    let isLast: Bool
    let onOpen: () -> Void
    let onOpenInSplit: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                onOpenInSplit()
            } else {
                onOpen()
            }
        } label: {
            rowLabel
        }
        .buttonStyle(CosmoBrowserStartRowButtonStyle())
        .help(item.url.absoluteString)
        .contextMenu {
            Button(action: onOpen) {
                Label("Open Page", systemImage: "arrow.up.forward.app")
            }
            Button(action: onOpenInSplit) {
                Label("Open in Split", systemImage: "rectangle.split.2x1")
            }
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
    }

    private var rowLabel: some View {
        HStack(spacing: DS.space10) {
            CommandKFavicon(host: CosmoBrowserPinnedSite.normalizedHost(for: item.url), size: 26) {
                CosmoIdentityChip(systemName: "globe", tint: DS.textMuted, size: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                metaLine
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .contentShape(Rectangle())
        .background(isHovered ? DS.surfaceHover : .clear)
        .overlay(alignment: .bottom) {
            CosmoBrowserRowSeparator(isLast: isLast)
        }
    }

    private var metaLine: some View {
        HStack(spacing: DS.space4) {
            Text(CosmoBrowserPinnedSite.normalizedHost(for: item.url))
            Text("·")
            Text(item.visitedAt.cosmoCompactAge)
                .monospacedDigit()
        }
        .font(DS.caption)
        .foregroundStyle(DS.textMuted)
        .lineLimit(1)
    }
}

/// Hairline separator inset to the text column (favicon 26 + gap 10 + pad 12).
private struct CosmoBrowserRowSeparator: View {
    let isLast: Bool

    var body: some View {
        if !isLast {
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 0.5)
                .padding(.leading, 48)
        }
    }
}
