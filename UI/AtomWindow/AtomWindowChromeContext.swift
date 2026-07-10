// CosmoOS/UI/AtomWindow/AtomWindowChromeContext.swift
// Optional chrome handoff for focus modes rendered inside the floating Atom window.

import SwiftUI

enum AtomWindowChromeTypeColor: Equatable {
    case idea
    case content
    case research
    case connection
    case note
    case task
    case stickyNote
    case image
    case neutral

    init(atomType: AtomType) {
        switch atomType {
        case .idea:
            self = .idea
        case .content, .contentDraft:
            self = .content
        case .research:
            self = .research
        case .connection, .clientProfile:
            self = .connection
        case .note:
            self = .note
        case .task, .scheduleBlock:
            self = .task
        case .stickyNote:
            self = .stickyNote
        case .image:
            self = .image
        default:
            self = .neutral
        }
    }

    var color: Color {
        switch self {
        case .idea:
            DS.entityIdea
        case .content:
            DS.entityContent
        case .research:
            DS.entityResearch
        case .connection:
            DS.entityConnection
        case .note:
            DS.entityNote
        case .task:
            DS.entityTask
        case .stickyNote:
            DS.entityStickyNote
        case .image:
            DS.entityImage
        case .neutral:
            DS.textSecondary
        }
    }
}

struct AtomWindowChromeState: Equatable {
    var title: String
    var typeIcon: String
    var typeColor: AtomWindowChromeTypeColor
    var canGoBack: Bool
    var canGoForward: Bool
    var canBookmark: Bool
    var isBookmarked: Bool
}

struct AtomWindowChromeActions {
    var closeWindow: () -> Void
    var goBack: () -> Void
    var goForward: () -> Void
    var toggleBookmark: () -> Void
    var showSearch: () -> Void
    var createAtom: (AtomType) -> Void
    var showHistory: () -> Void = {}
}

struct AtomWindowChromePayload {
    var state: AtomWindowChromeState
    var actions: AtomWindowChromeActions
}

struct AtomWindowChromeContext: EnvironmentKey {
    static let defaultValue: AtomWindowChromePayload? = nil
}

extension EnvironmentValues {
    var atomWindowChromeContext: AtomWindowChromePayload? {
        get { self[AtomWindowChromeContext.self] }
        set { self[AtomWindowChromeContext.self] = newValue }
    }
}

// MARK: - Shared Atom Window Chrome
//
// The universal Atom-window bar grammar (one grammar per screen — peakui Law 11):
// these are *bare control rows* designed to live inside exactly ONE
// `CosmoChromeIsland` per side. The island provides the only container — the
// controls never bring their own capsule, so hosts can merge their mode tools
// into the same glass without nesting ovals inside ovals.

/// Hairline separator between control groups sharing one island.
struct AtomWindowChromeDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.glassBorder.opacity(0.9))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 2)
            .accessibilityHidden(true)
    }
}

struct AtomWindowChromeLeadingControls: View {
    let context: AtomWindowChromePayload
    var showsTitle: Bool = true

    var body: some View {
        AtomWindowChromeIconButton(
            systemName: "xmark",
            help: "Close Atom window (⌥E)",
            action: context.actions.closeWindow
        )

        AtomWindowChromeDivider()

        AtomWindowChromeIconButton(
            systemName: "chevron.left",
            help: "Back (⌘[)",
            isEnabled: context.state.canGoBack,
            action: context.actions.goBack
        )
        .keyboardShortcut("[", modifiers: .command)

        AtomWindowChromeIconButton(
            systemName: "chevron.right",
            help: "Forward (⌘])",
            isEnabled: context.state.canGoForward,
            action: context.actions.goForward
        )
        .keyboardShortcut("]", modifiers: .command)

        if showsTitle {
            AtomWindowChromeTitleButton(context: context)
        }
    }
}

/// The window's identity: type icon + title, and the doorway to the switcher.
private struct AtomWindowChromeTitleButton: View {
    let context: AtomWindowChromePayload

    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                context.actions.showSearch()
            }
        } label: {
            HStack(spacing: DS.space6) {
                Image(systemName: context.state.typeIcon)
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(context.state.typeColor.color)
                    .accessibilityHidden(true)

                Text(context.state.title)
                    .font(DS.buttonText.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Hug short titles, truncate long ones — the outer
                    // fixedSize hands this frame a nil proposal, so it
                    // resolves to min(ideal, cap) instead of stretching.
                    .frame(maxWidth: 200, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .opacity(isHovered ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.space8)
            .frame(height: 28)
            .background(
                Capsule().fill(DS.glassCardFill.opacity(isHovered ? 0.9 : 0))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Search & switch atoms")
        .accessibilityLabel("\(context.state.title). Search and switch atoms")
    }
}

struct AtomWindowChromeTrailingControls: View {
    let context: AtomWindowChromePayload

    var body: some View {
        AtomWindowChromeIconButton(
            systemName: context.state.isBookmarked ? "bookmark.fill" : "bookmark",
            help: context.state.isBookmarked ? "Remove bookmark" : "Bookmark atom",
            isEnabled: context.state.canBookmark,
            isActive: context.state.isBookmarked,
            activeTint: context.state.typeColor.color,
            action: context.actions.toggleBookmark
        )

        AtomWindowChromeIconButton(
            systemName: "clock.arrow.circlepath",
            help: "Version history",
            action: context.actions.showHistory
        )

        AtomWindowChromeIconButton(
            systemName: "magnifyingglass",
            help: "Search atoms",
            action: {
                withAnimation(ProMotionSprings.snappy) {
                    context.actions.showSearch()
                }
            }
        )

        createMenu
    }

    private var createMenu: some View {
        Menu {
            Button("Idea", systemImage: AtomType.idea.iconName) {
                context.actions.createAtom(.idea)
            }
            Button("Note", systemImage: AtomType.note.iconName) {
                context.actions.createAtom(.note)
            }
            Button("Content", systemImage: AtomType.content.iconName) {
                context.actions.createAtom(.content)
            }
            Button("Research", systemImage: AtomType.research.iconName) {
                context.actions.createAtom(.research)
            }
            Button("Concept", systemImage: AtomType.connection.iconName) {
                context.actions.createAtom(.connection)
            }
        } label: {
            AtomWindowChromeGlyph(systemName: "plus", isHovered: isCreateHovered)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isCreateHovered = hovering }
        }
        .help("Create atom")
        .accessibilityLabel("Create atom")
    }

    @State private var isCreateHovered = false
}

/// The one universal bar for shell states (launcher, loading, generic atoms):
/// the same two islands every focus mode composes, on the shared baseline.
struct AtomWindowStandaloneChrome: View {
    let context: AtomWindowChromePayload

    var body: some View {
        CosmoChromeRow(insetsEnabled: false) {
            CosmoChromeIsland {
                AtomWindowChromeLeadingControls(context: context)
            }
        } center: {
            EmptyView()
        } trailing: {
            CosmoChromeIsland {
                AtomWindowChromeTrailingControls(context: context)
            }
        }
        .frame(height: AtomWindowMetrics.focusToolbarHeight)
    }
}

/// The shared 28pt glyph treatment: quiet at rest, a warm wash on hover —
/// every icon in the Atom bar answers the pointer (macOS manners).
private struct AtomWindowChromeGlyph: View {
    let systemName: String
    var isHovered = false
    var isActive = false
    var activeTint: Color = DS.accent

    var body: some View {
        Image(systemName: systemName)
            .font(DS.buttonText.weight(.semibold))
            .foregroundStyle(isActive ? activeTint : DS.textSecondary)
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(
                    isActive
                        ? activeTint.opacity(0.14)
                        : DS.glassCardFill.opacity(isHovered ? 0.9 : 0)
                )
            )
            .contentShape(Circle())
    }
}

private struct AtomWindowChromeIconButton: View {
    let systemName: String
    let help: String
    var isEnabled = true
    var isActive = false
    var activeTint: Color = DS.accent
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            AtomWindowChromeGlyph(
                systemName: systemName,
                isHovered: isHovered && isEnabled,
                isActive: isActive,
                activeTint: activeTint
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.34)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help(help)
        .accessibilityLabel(help)
    }
}
