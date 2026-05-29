// CosmoOS/UI/CommandK/CortexSearchBar.swift
// Shared search bar for all Cortex modes — compact, search results, and expanded domain

import SwiftUI

struct CortexSearchBar: View {
    @ObservedObject var viewModel: CommandKViewModel
    var isSearchFocused: FocusState<Bool>.Binding
    var expandedTab: CommandKTab?
    var onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            leadingIcon
            searchField
            Spacer()
            trailingControls
        }
        .padding(.horizontal, DS.space24)
        .frame(height: CommandKMetrics.searchBarHeight)
    }

    // MARK: - Leading Icon

    @ViewBuilder
    private var leadingIcon: some View {
        if let tab = expandedTab {
            backButton(tab: tab)
        } else {
            searchIcon
        }
    }

    private var searchIcon: some View {
        Image(systemName: viewModel.isTaskCreationMode ? "plus.circle.fill" : "magnifyingglass")
            .font(DS.title2)
            .foregroundStyle(viewModel.isTaskCreationMode ? DS.accent : (isSearchFocused.wrappedValue ? DS.accent : DS.textSecondary))
            .frame(width: 22)
    }

    private func backButton(tab: CommandKTab) -> some View {
        HStack(spacing: DS.space8) {
            Button {
                onBack?()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(DS.commandChromeControlFill, in: Circle())
                    .overlay(Circle().stroke(DS.commandChromeControlBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Image(systemName: tab.icon)
                .font(DS.headline)
                .foregroundStyle(tab.accentColor)

            Text(tab.title)
                .font(DS.title3)
                .foregroundStyle(DS.text)
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        TextField(
            placeholder,
            text: Binding(
                get: { viewModel.query },
                set: { viewModel.updateQuery($0) }
            )
        )
            .textFieldStyle(.plain)
            .font(DS.title2)
            .foregroundStyle(DS.text)
            .focused(isSearchFocused)
            .onSubmit {
                viewModel.openSelected()
            }
    }

    private var placeholder: String {
        expandedTab?.searchPlaceholder ?? "Search everything..."
    }

    // MARK: - Trailing Controls

    @ViewBuilder
    private var trailingControls: some View {
        if let prefixType = viewModel.activeTypePrefix {
            typePrefixBadge(prefixType)
        }

        if viewModel.isTaskCreationMode {
            Text("Enter to create task")
                .font(DS.caption)
                .foregroundStyle(DS.accent)
                .commandKToolbarChip(
                    isActive: true,
                    activeFill: DS.accentSoft,
                    activeBorder: DS.accent.opacity(0.18)
                )
        }

        voiceButton

    }

    private var voiceButton: some View {
        Button {
            viewModel.isVoiceActive.toggle()
        } label: {
            Image(systemName: viewModel.isVoiceActive ? "mic.fill" : "mic")
                .font(DS.headline)
                .foregroundStyle(viewModel.isVoiceActive ? DS.accent : DS.textSecondary)
                .frame(width: DS.space32, height: DS.space32)
                .background(
                    Circle()
                        .fill(viewModel.isVoiceActive ? DS.accentSoft : DS.surface)
                )
                .overlay(
                    Circle()
                        .stroke(viewModel.isVoiceActive ? DS.accent.opacity(0.18) : DS.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func typePrefixBadge(_ type: AtomType) -> some View {
        HStack(spacing: DS.space4) {
            Image(systemName: iconForType(type))
                .font(DS.caption2)
            Text(type.displayName)
                .font(DS.caption)
        }
        .foregroundStyle(entityColor(type))
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .background(entityColor(type).opacity(0.15))
        .clipShape(Capsule())
    }

    private func entityColor(_ type: AtomType) -> Color {
        switch type {
        case .idea: return DS.entityIdea
        case .task: return DS.entityTask
        case .content: return DS.entityContent
        case .research: return DS.entityResearch
        case .connection: return DS.entityConnection
        case .project: return DS.entityIdea
        default: return DS.textSecondary
        }
    }

    private func iconForType(_ type: AtomType) -> String {
        switch type {
        case .idea: return "lightbulb.fill"
        case .task: return "checkmark.circle.fill"
        case .research: return "book.fill"
        case .content: return "doc.text.fill"
        case .connection: return "doc.fill"
        case .project: return "folder.fill"
        default: return "circle.fill"
        }
    }
}
