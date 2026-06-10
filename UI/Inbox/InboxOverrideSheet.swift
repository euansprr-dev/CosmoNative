// CosmoOS/UI/Inbox/InboxOverrideSheet.swift
// Override sheet for changing AI-suggested inbox action
// March 2026

import SwiftUI

struct InboxOverrideSheet: View {
    let item: InboxItem
    @Bindable var viewModel: InboxViewModel

    @State private var selectedTab: OverrideTab = .merge
    @State private var searchQuery = ""
    @State private var selectedAtomType: AtomType = .connection
    @Environment(\.dismiss) private var dismiss

    enum OverrideTab: String, CaseIterable {
        case merge = "Merge"
        case place = "Place"
        case new = "New"
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider().foregroundStyle(DS.border)

            // Tab picker
            tabPicker
                .padding(.horizontal, 20)
                .padding(.top, 16)

            // Tab content
            switch selectedTab {
            case .merge:
                mergeTab
            case .place:
                placeTab
            case .new:
                newTab
            }
        }
        .frame(width: 480, height: 500)
        .background(DS.bg)
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Change Action")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.text)
                Text(item.title ?? String(item.rawText.prefix(50)))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 28, height: 28)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(OverrideTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(3)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func tabButton(_ tab: OverrideTab) -> some View {
        Button {
            withAnimation(ProMotionSprings.snappy) { selectedTab = tab }
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .medium))
                .foregroundStyle(selectedTab == tab ? DS.text : DS.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    selectedTab == tab
                        ? RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.surfaceCard)
                        : nil
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Merge Tab

    private var mergeTab: some View {
        VStack(spacing: 12) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.textMuted)
                TextField("Search atoms to merge into...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.text)
                    .onChange(of: searchQuery) { _, query in
                        viewModel.scheduleOverrideSearch(query: query)
                    }
            }
            .padding(10)
            .background(DS.surfaceCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.border, lineWidth: 1)
            )

            // Results
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(viewModel.overrideSearchResults) { result in
                        mergeResultRow(result)
                    }
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func mergeResultRow(_ result: HybridSearchEngine.SearchResult) -> some View {
        Button {
            guard let uuid = result.entityUUID else { return }
            Task { await viewModel.overrideMerge(item: item, targetUuid: uuid) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: result.entityType.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.accent)
                    .frame(width: 24, height: 24)
                    .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                    Text(result.preview)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                let pct = Int(result.combinedScore * 100)
                Text("\(pct)%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textMuted)
            }
            .padding(10)
            .background(DS.surfaceCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DS.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Place Tab

    private var placeTab: some View {
        VStack(spacing: 12) {
            Text("Choose a thinkspace")
                .font(.system(size: 13))
                .foregroundStyle(DS.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(viewModel.thinkspaces) { ts in
                        placeThinkspaceRow(ts)
                    }
                }
            }

            atomTypePicker
        }
        .padding(20)
    }

    @ViewBuilder
    private func placeThinkspaceRow(_ ts: Thinkspace) -> some View {
        Button {
            Task { await viewModel.overridePlace(item: item, thinkspaceId: ts.id, atomType: selectedAtomType) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.accent)
                    .frame(width: 24, height: 24)
                    .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 6))

                Text(ts.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.text)

                Spacer()

                Text("\(ts.blockCount) blocks")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.textMuted)
            }
            .padding(10)
            .background(DS.surfaceCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DS.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - New Tab

    private var newTab: some View {
        VStack(spacing: 16) {
            Text("Create as a new atom")
                .font(.system(size: 13))
                .foregroundStyle(DS.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            atomTypePicker

            Spacer()

            Button {
                Task { await viewModel.overrideNew(item: item, atomType: selectedAtomType) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13))
                    Text("Create \(selectedAtomType.rawValue.capitalized)")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(DS.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(DS.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    // MARK: - Atom Type Picker

    private var atomTypePicker: some View {
        HStack(spacing: 8) {
            ForEach(atomTypeOptions, id: \.self) { type in
                atomTypeChip(type)
            }
        }
    }

    private var atomTypeOptions: [AtomType] {
        [.connection, .idea, .research, .note]
    }

    @ViewBuilder
    private func atomTypeChip(_ type: AtomType) -> some View {
        let isSelected = selectedAtomType == type
        Button {
            withAnimation(ProMotionSprings.snappy) { selectedAtomType = type }
        } label: {
            Text(type.rawValue.capitalized)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? DS.accentSoft : DS.surface,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(isSelected ? DS.accent.opacity(0.3) : DS.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
