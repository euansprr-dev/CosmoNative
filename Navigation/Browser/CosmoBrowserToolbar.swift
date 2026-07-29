// CosmoOS/Navigation/Browser/CosmoBrowserToolbar.swift
// One quiet glass row: navigation, a neutral address field wearing the site's
// favicon, the bookmark toggle, and a single overflow menu. Same glass family
// as the pane tab rail and Command-K.

import SwiftUI
import AppKit

struct CosmoBrowserToolbarView: View {
    @Bindable var browserState: CosmoWebBrowserState
    let fallbackURL: URL
    let onClose: () -> Void

    @FocusState private var isAddressFieldFocused: Bool
    @Environment(\.isPaneActive) private var isPaneActive
    @Environment(\.paneDeckChrome) private var paneDeckChrome

    var body: some View {
        HStack(spacing: DS.space6) {
            deckTabStrip
            CosmoBrowserToolbarButton(icon: "xmark", help: "Close Browser", action: onClose)
            navigationCluster
            addressField
            SwipeFlowRecordingPill(size: .compact)
            swipeThisPageButton
            favoriteToggle
            CosmoBrowserOverflowMenu(browserState: browserState, fallbackURL: fallbackURL)
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space6)
        // A persistent bar attached to its pane, not a floating overlay —
        // it separates by material alone (the Safari-toolbar elevation
        // class); a cast shadow this close to the pane edges reads as smudge.
        //
        // Half the band height = a capsule (see the assistant pane's toolbar):
        // the old literal 22 clamped to 20 on a 40pt bar and only looked
        // deliberate by accident.
        .cosmoGlassPanel(
            role: .floatingAssistant,
            cornerRadius: CosmoChromeMetrics.height / 2,
            castsShadow: false
        )
        .background {
            if isPaneActive {
                shortcutLayer
            }
        }
        .onChange(of: isAddressFieldFocused) { _, focused in
            if focused {
                selectAllInAddressField()
            } else {
                browserState.restoreAddressText()
            }
        }
    }

    // MARK: - Deck tabs

    /// The deck tab strip rides the browser toolbar's leading seam when this
    /// pane is the focused deck pane and siblings exist — one row of glass,
    /// never two stacked bars.
    @ViewBuilder
    private var deckTabStrip: some View {
        if let paneDeckChrome, paneDeckChrome.tabs.count > 1 {
            // The browser bar carries a flexible address field — budget the
            // strip against the dense reserve so the field keeps its measure.
            PaneDeckTabStrip(
                context: paneDeckChrome,
                hostReserve: PaneTabStripLayoutPolicy.denseHostReserve
            )
            Divider()
                .frame(height: 18)
                .overlay(DS.borderSubtle)
                .padding(.horizontal, DS.space2)
        }
    }

    // MARK: - Navigation

    @ViewBuilder
    private var navigationCluster: some View {
        CosmoBrowserToolbarButton(
            icon: "chevron.left",
            help: "Back (⌘[)",
            isEnabled: browserState.canGoBack,
            action: browserState.goBack
        )
        CosmoBrowserToolbarButton(
            icon: "chevron.right",
            help: "Forward (⌘])",
            isEnabled: browserState.canGoForward,
            action: browserState.goForward
        )
        CosmoBrowserToolbarButton(
            icon: browserState.isLoading ? "xmark.circle" : "arrow.clockwise",
            help: browserState.isLoading ? "Stop Loading" : "Reload (⌘R)",
            action: browserState.reloadOrStop
        )
    }

    // MARK: - Address field

    private var currentHost: String {
        CosmoBrowserPinnedSite.normalizedHost(for: browserState.currentURL ?? fallbackURL)
    }

    private var addressField: some View {
        HStack(spacing: DS.space8) {
            CommandKFavicon(host: currentHost, size: 16) {
                Image(systemName: "globe")
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
            }
            addressFieldText
        }
        .padding(.horizontal, DS.space10)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous))
        .onTapGesture { isAddressFieldFocused = true }
        .background(addressFieldBackground)
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .stroke(isAddressFieldFocused ? DS.focusRing : DS.borderSubtle, lineWidth: 1)
        )
        .animation(ProMotionSprings.focusTransition, value: isAddressFieldFocused)
    }

    /// One line, two states: page title + muted host at rest; the editable
    /// URL when focused. The field stays mounted so focus always lands.
    private var addressFieldText: some View {
        ZStack(alignment: .leading) {
            restingLabel
                .opacity(isAddressFieldFocused ? 0 : 1)
            TextField("Search or enter address", text: $browserState.addressText)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .focused($isAddressFieldFocused)
                .opacity(isAddressFieldFocused ? 1 : 0)
                .onSubmit {
                    browserState.commitAddressText()
                    isAddressFieldFocused = false
                }
                .onKeyPress(.escape) {
                    guard isAddressFieldFocused else { return .ignored }
                    isAddressFieldFocused = false
                    return .handled
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var restingLabel: some View {
        if browserState.showsStartPage {
            Text("Search or enter address")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
        } else {
            HStack(spacing: DS.space6) {
                Text(browserState.displayTitle)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Text(currentHost)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
    }

    /// Loading progress lives inside the field: an accent wash fills from the
    /// leading edge and fades on completion — no separate progress bar.
    private var addressFieldBackground: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .fill(isAddressFieldFocused ? DS.glassInputFillFocused : DS.glassInputFill)
            GeometryReader { geo in
                Rectangle()
                    .fill(DS.accent.opacity(0.10))
                    .frame(width: geo.size.width * browserState.estimatedProgress)
            }
            .opacity(browserState.isLoading ? 1 : 0)
            .animation(ProMotionSprings.gentle, value: browserState.estimatedProgress)
            .animation(ProMotionSprings.gentle, value: browserState.isLoading)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous))
    }

    // MARK: - Swipe this page

    /// The page you are LOOKING at — your session, your scroll, past the
    /// opt-in. This is the whole reason page capture reads a live webview
    /// rather than re-fetching the URL anonymously: the funnels worth swiping
    /// are the ones you had to sign up to see.
    @ViewBuilder
    private var swipeThisPageButton: some View {
        if browserState.currentURL != nil, !browserState.showsStartPage {
            CosmoBrowserToolbarButton(
                icon: SwipeKind.page.iconName,
                help: "Swipe this page (⌘⇧S)"
            ) {
                SwipeCaptureCommands.swipeThis()
            }
            .accessibilityLabel("Swipe this page")
        }
    }

    // MARK: - Favorite toggle

    private var favoriteToggle: some View {
        CosmoBrowserToolbarButton(
            icon: browserState.isCurrentSitePinned ? "bookmark.fill" : "bookmark",
            help: browserState.isCurrentSitePinned ? "Remove Favorite (⌘D)" : "Add Favorite (⌘D)",
            tint: browserState.isCurrentSitePinned ? DS.accent : nil,
            action: browserState.toggleCurrentFavorite
        )
    }

    // MARK: - Keyboard

    /// Pane-scoped shortcuts, registered only while this pane is active so
    /// multiple mounted browser panes never compete.
    private var shortcutLayer: some View {
        Group {
            Button("") { isAddressFieldFocused = true }
                .keyboardShortcut("l", modifiers: .command)
            Button("") { browserState.reload() }
                .keyboardShortcut("r", modifiers: .command)
            Button("") { browserState.goBack() }
                .keyboardShortcut("[", modifiers: .command)
            Button("") { browserState.goForward() }
                .keyboardShortcut("]", modifiers: .command)
            Button("") { browserState.toggleCurrentFavorite() }
                .keyboardShortcut("d", modifiers: .command)
            Button("") { NSWorkspace.shared.open(browserState.currentURL ?? fallbackURL) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func selectAllInAddressField() {
        DispatchQueue.main.async {
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }
}

// MARK: - Overflow menu

/// Profile, recent pages, and page actions consolidated into one trailing
/// menu. A non-standard profile surfaces its own glyph so Research/Private
/// state stays visible without a permanent pill.
struct CosmoBrowserOverflowMenu: View {
    let browserState: CosmoWebBrowserState
    let fallbackURL: URL

    var body: some View {
        Menu {
            Picker("Profile", selection: profileBinding) {
                ForEach(CosmoBrowserProfile.builtIns) { profile in
                    Label(profile.title, systemImage: profile.systemImage)
                        .tag(profile.id)
                }
            }
            .pickerStyle(.inline)
            Section("Recent Pages") {
                recentPageItems
            }
            Section {
                Button {
                    NSWorkspace.shared.open(browserState.currentURL ?? fallbackURL)
                } label: {
                    Label("Open in Safari", systemImage: "safari")
                }
                Button {
                    let target = browserState.currentURL ?? fallbackURL
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(target.absoluteString, forType: .string)
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            }
        } label: {
            Image(systemName: menuGlyph)
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(menuHelp)
        .accessibilityLabel(menuHelp)
    }

    @ViewBuilder
    private var recentPageItems: some View {
        if browserState.recentHistory.isEmpty {
            Text("No Recent Pages")
        } else {
            ForEach(browserState.recentHistory.prefix(10)) { item in
                Button(item.title) {
                    browserState.load(item.url)
                }
            }
        }
    }

    private var menuGlyph: String {
        browserState.profile == .standard ? "ellipsis.circle" : browserState.profile.systemImage
    }

    private var menuHelp: String {
        browserState.profile == .standard
            ? "Profile, recent pages, and page actions"
            : "Profile: \(browserState.profile.title)"
    }

    private var profileBinding: Binding<String> {
        Binding(
            get: { browserState.profile.id },
            set: { newId in
                guard let profile = CosmoBrowserProfile.builtIns.first(where: { $0.id == newId }) else { return }
                Task { await browserState.switchProfile(profile) }
            }
        )
    }
}

// MARK: - Button factory

/// Flat toolbar button on glass: no boxes, no strokes — a hover wash and the
/// text ladder carry state (the Connection-workspace grammar).
struct CosmoBrowserToolbarButton: View {
    let icon: String
    let help: String
    var isEnabled: Bool = true
    var tint: Color? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(glyphColor)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                        .fill(isHovered && isEnabled ? DS.surfaceHover : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }

    private var glyphColor: Color {
        guard isEnabled else { return DS.textMuted.opacity(0.55) }
        if let tint { return tint }
        return isHovered ? DS.text : DS.textSecondary
    }
}
