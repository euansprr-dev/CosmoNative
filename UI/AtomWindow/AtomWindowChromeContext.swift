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
    var unloadAtom: () -> Void
    var goBack: () -> Void
    var goForward: () -> Void
    var toggleBookmark: () -> Void
    var showSearch: () -> Void
    var createAtom: (AtomType) -> Void
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

struct AtomWindowChromeLeadingControls: View {
    let context: AtomWindowChromePayload
    var showsTitle: Bool = true

    var body: some View {
        HStack(spacing: DS.space4) {
            AtomWindowChromeIconButton(
                systemName: "xmark",
                help: "Close Atom window",
                action: context.actions.closeWindow
            )

            chromeDivider

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
                titlePill
            }
        }
        .padding(.horizontal, DS.space6)
        .padding(.vertical, DS.space4)
        .background(DS.glassCardFill.opacity(0.52), in: Capsule())
        .overlay(
            Capsule()
                .stroke(DS.glassBorder.opacity(0.82), lineWidth: 0.5)
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private var chromeDivider: some View {
        Rectangle()
            .fill(DS.glassBorder.opacity(0.75))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 1)
    }

    private var titlePill: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: context.state.typeIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(context.state.typeColor.color)
                .accessibilityHidden(true)

            Text(context.state.title)
                .font(DS.buttonText.weight(.semibold))
                .foregroundStyle(DS.text)
                .lineLimit(1)
                .frame(maxWidth: 190, alignment: .leading)
        }
        .padding(.leading, DS.space4)
        .padding(.trailing, DS.space8)
        .frame(height: 28)
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(ProMotionSprings.snappy) {
                context.actions.showSearch()
            }
        }
        .help("Search atoms")
    }
}

struct AtomWindowChromeTrailingControls: View {
    let context: AtomWindowChromePayload
    var showsAtomClose: Bool = true

    var body: some View {
        HStack(spacing: DS.space4) {
            AtomWindowChromeIconButton(
                systemName: context.state.isBookmarked ? "bookmark.fill" : "bookmark",
                help: context.state.isBookmarked ? "Remove bookmark" : "Bookmark atom",
                isEnabled: context.state.canBookmark,
                isActive: context.state.isBookmarked,
                activeTint: context.state.typeColor.color,
                action: context.actions.toggleBookmark
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

            if showsAtomClose {
                AtomWindowChromeIconButton(
                    systemName: "xmark.circle",
                    help: "Close current atom",
                    action: context.actions.unloadAtom
                )
            }
        }
        .padding(.horizontal, DS.space6)
        .padding(.vertical, DS.space4)
        .background(DS.glassCardFill.opacity(0.52), in: Capsule())
        .overlay(
            Capsule()
                .stroke(DS.glassBorder.opacity(0.82), lineWidth: 0.5)
        )
        .fixedSize(horizontal: true, vertical: false)
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
            Button("Connection", systemImage: AtomType.connection.iconName) {
                context.actions.createAtom(.connection)
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Create atom")
        .accessibilityLabel("Create atom")
    }
}

struct AtomWindowStandaloneChrome: View {
    let context: AtomWindowChromePayload
    var showsAtomClose: Bool = true

    var body: some View {
        HStack(spacing: DS.space10) {
            AtomWindowChromeLeadingControls(context: context)
            Spacer(minLength: DS.space12)
            AtomWindowChromeTrailingControls(context: context, showsAtomClose: showsAtomClose)
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 24)
    }
}

private struct AtomWindowChromeIconButton: View {
    let systemName: String
    let help: String
    var isEnabled = true
    var isActive = false
    var activeTint: Color = DS.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.34)
        .help(help)
        .accessibilityLabel(help)
    }

    private var foreground: Color {
        isActive ? activeTint : DS.textSecondary
    }
}
