// CosmoOS/UI/FocusMode/Connection/ConnectionNavigatorView.swift
// June 2026 — Connection workspace revamp.
// Left navigator: the connection's table of contents. Title, all 11 sections
// with counts + completion dots, and linked sources — everything inside the
// connection reachable in one click. Collapses to a 44pt icon rail.

import SwiftUI

struct ConnectionNavigatorView: View {
    var viewModel: ConnectionFocusModeViewModel
    var workspace: ConnectionWorkspaceModel
    @Binding var title: String
    let sources: ConnectionWorkspaceSources
    let actions: ConnectionWorkspaceActions

    private var orderedSections: [ConnectionSection] {
        viewModel.state.sections.sorted { $0.type.sortOrder < $1.type.sortOrder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
                .padding(.horizontal, DS.space16)
                .padding(.top, DS.space16)
                .padding(.bottom, DS.space12)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space20) {
                    sectionsGroup
                    ConnectionNavigatorSourcesGroup(
                        workspace: workspace,
                        sources: sources,
                        actions: actions
                    )
                }
                .padding(.horizontal, DS.space10)
                .padding(.bottom, DS.space24)
            }
        }
        .frame(width: 240)
        .background(DS.surface)
    }

    // MARK: - Title

    private var titleRow: some View {
        VStack(alignment: .leading, spacing: DS.space2) {
            TextField("Untitled Concept", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(DS.text)
                .lineLimit(1...3)
                .onSubmit { actions.onTitleCommit() }
                .accessibilityLabel("Concept title")
            Text(viewModel.state.conceptType.displayName)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - Sections

    private var sectionsGroup: some View {
        VStack(alignment: .leading, spacing: DS.space2) {
            Text("Sections")
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, DS.space8)
                .padding(.bottom, DS.space4)
            ForEach(orderedSections) { section in
                ConnectionNavigatorSectionRow(
                    section: section,
                    isSelected: isSelected(section.type),
                    isSearchMatch: workspace.isSearching && workspace.sectionMatches(section),
                    isDimmed: workspace.focusedSection.map { $0 != section.type } ?? false,
                    onTap: { workspace.toggleFocus(on: section.type) },
                    onOpen: { workspace.openSection(section.type) }
                )
            }
        }
    }

    private func isSelected(_ type: ConnectionSectionType) -> Bool {
        if workspace.pushedSection == type { return true }
        return workspace.selection == .section(type)
    }
}

// MARK: - Section row

struct ConnectionNavigatorSectionRow: View {
    let section: ConnectionSection
    let isSelected: Bool
    var isSearchMatch: Bool = false
    var isDimmed: Bool = false
    let onTap: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: section.type.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(section.type.accentColor)
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(section.type.displayName)
                .font(DS.callout)
                .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isHovered {
                Button(action: onOpen) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help("Open \(section.type.displayName)")
                .accessibilityLabel("Open \(section.type.displayName)")
            } else if section.itemCount > 0 {
                Text("\(section.itemCount)")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }

            Circle()
                .fill(section.items.isEmpty ? DS.border : section.type.accentColor.opacity(0.85))
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space6)
        .frame(minHeight: 28)
        .background(rowFill, in: .rect(cornerRadius: 7))
        .opacity(isDimmed && !isHovered ? 0.35 : 1)
        .animation(ProMotionSprings.gentle, value: isDimmed)
        .contentShape(.rect(cornerRadius: 7))
        .onTapGesture(count: 2) { onOpen() }
        .simultaneousGesture(TapGesture().onEnded { onTap() })
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.type.displayName), \(section.itemCount) items\(section.items.isEmpty ? ", empty" : "")")
    }

    private var rowFill: Color {
        if isSelected { return DS.accentSoft }
        if isSearchMatch { return section.type.accentColor.opacity(0.08) }
        if isHovered { return DS.border.opacity(0.4) }
        return .clear
    }
}

// MARK: - Sources group

struct ConnectionNavigatorSourcesGroup: View {
    var workspace: ConnectionWorkspaceModel
    let sources: ConnectionWorkspaceSources
    let actions: ConnectionWorkspaceActions

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space2) {
            header
            ForEach(sources.linked, id: \.uuid) { source in
                ConnectionNavigatorSourceRow(
                    source: source,
                    contributionCount: sources.contributions[source.uuid]?.count ?? 0,
                    isSelected: workspace.selection == .source(source.uuid),
                    onTap: { workspace.selection = .source(source.uuid) },
                    onOpen: { actions.onSourceTap(source.uuid) }
                )
                // A source linked mid-session (e.g. a freshly minted concept)
                // slides into the rail instead of teleporting.
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            if sources.linked.isEmpty {
                Text("Link notes, research, or ideas that feed this concept.")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .padding(.horizontal, DS.space8)
                    .padding(.vertical, DS.space4)
            }
            suggestionsBlock
        }
    }

    private var header: some View {
        HStack {
            Text("Sources")
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(DS.textMuted)
            Spacer()
            Button(action: actions.onAddSource) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Link a source (⌘K)")
            .accessibilityLabel("Link a source")
        }
        .padding(.horizontal, DS.space8)
        .padding(.bottom, DS.space4)
    }

    @ViewBuilder
    private var suggestionsBlock: some View {
        if sources.isShowingSuggestions {
            VStack(alignment: .leading, spacing: DS.space2) {
                Text("Suggested")
                    .font(DS.smallCaps)
                    .tracking(1.4)
                    .foregroundStyle(DS.textMuted)
                    .padding(.horizontal, DS.space8)
                    .padding(.top, DS.space8)
                if sources.isLoadingSuggestions {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.space8)
                }
                ForEach(sources.suggested, id: \.uuid) { source in
                    ConnectionNavigatorSuggestedRow(
                        source: source,
                        onLink: { actions.onLinkSuggestedSource(source) }
                    )
                }
            }
        } else {
            Button(action: actions.onRequestSuggestions) {
                Label("Suggest sources", systemImage: "sparkles")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DS.space8)
            .padding(.top, DS.space6)
            .help("Find related material to link")
        }
    }
}

struct ConnectionNavigatorSourceRow: View {
    let source: Atom
    let contributionCount: Int
    let isSelected: Bool
    let onTap: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: source.type.iconName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(source.title ?? "Untitled")
                .font(DS.callout)
                .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if contributionCount > 0 {
                Text("\(contributionCount)")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .help("Cited by \(contributionCount) section\(contributionCount == 1 ? "" : "s")")
            }
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space6)
        .frame(minHeight: 28)
        .background(
            isSelected ? DS.accentSoft : (isHovered ? DS.border.opacity(0.4) : .clear),
            in: .rect(cornerRadius: 7)
        )
        .contentShape(.rect(cornerRadius: 7))
        .onTapGesture(count: 2) { onOpen() }
        .simultaneousGesture(TapGesture().onEnded { onTap() })
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Source: \(source.title ?? "Untitled")")
    }
}

struct ConnectionNavigatorSuggestedRow: View {
    let source: Atom
    let onLink: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: source.type.iconName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(source.title ?? "Untitled")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: onLink) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.accent)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.6)
            .help("Link this source")
            .accessibilityLabel("Link \(source.title ?? "source")")
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }
}

// MARK: - Icon rail (collapsed)

struct ConnectionNavigatorRail: View {
    var viewModel: ConnectionFocusModeViewModel
    var workspace: ConnectionWorkspaceModel
    let onExpand: () -> Void

    private var orderedSections: [ConnectionSection] {
        viewModel.state.sections.sorted { $0.type.sortOrder < $1.type.sortOrder }
    }

    var body: some View {
        VStack(spacing: DS.space4) {
            Button(action: onExpand) {
                Image(systemName: "sidebar.squares.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Expand navigator (⌘0)")
            .accessibilityLabel("Expand navigator")
            .padding(.top, DS.space12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.space2) {
                    ForEach(orderedSections) { section in
                        railButton(section)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 44)
        .background(DS.surface)
    }

    private func railButton(_ section: ConnectionSection) -> some View {
        Button(action: { workspace.jump(to: section.type) }) {
            Image(systemName: section.type.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(section.items.isEmpty ? DS.textMuted : section.type.accentColor)
                .frame(width: 28, height: 26)
                .background(
                    workspace.selection == .section(section.type) ? DS.accentSoft : .clear,
                    in: .rect(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .help(section.type.displayName)
        .accessibilityLabel("\(section.type.displayName), \(section.itemCount) items")
    }
}
