// CosmoOS/Canvas/CanvasDatabasePicker.swift
// Searchable overlay menu for placing existing database items onto the canvas
// Design matches MentionMenu — warm parchment aesthetic

import SwiftUI

struct CanvasDatabasePicker: View {
    let position: CGPoint
    let onSelect: (Atom) -> Void
    let onDismiss: () -> Void

    @State private var searchQuery = ""
    @State private var results: [MentionSearchResult] = []
    @State private var selectedIndex = 0
    @State private var isLoading = true
    @State private var appearedRows: Set<String> = []
    @State private var menuAppeared = false
    @State private var searchTask: Task<Void, Never>?
    @State private var searchRequestID = UUID()
    @State private var hoveredIndex: Int?
    @FocusState private var isSearchFocused: Bool

    private let provider = MentionSearchProvider.shared
    private let menuWidth: CGFloat = 360
    private let menuHeight: CGFloat = 380

    var body: some View {
        VStack(spacing: 0) {
            header

            searchField

            Rectangle()
                .fill(DS.border)
                .frame(height: 1)

            content
        }
        .frame(width: menuWidth, height: menuHeight, alignment: .top)
        .background(CosmoColors.softWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 22, y: 10)
        .position(x: clampedPosition.x, y: clampedPosition.y)
        .scaleEffect(menuAppeared ? 1 : 0.97)
        .opacity(menuAppeared ? 1 : 0)
        .onAppear {
            withAnimation(ProMotionSprings.gentle) {
                menuAppeared = true
            }
            isSearchFocused = true
            loadResults()
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(max(0, results.count - 1), selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            selectCurrentItem()
            return .handled
        }
        .onKeyPress(.escape) {
            dismissAnimated()
            return .handled
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.accentSoft)
                    .frame(width: 30, height: 30)

                Image(systemName: "tray.full.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Database")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.text)

                Text(searchQuery.isEmpty ? "Recent items" : "Results for \"\(searchQuery)\"")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if !isLoading {
                Text("\(results.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(DS.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DS.accentSoft, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textMuted)

            TextField("Search…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(DS.text)
                .focused($isSearchFocused)
                .onChange(of: searchQuery) { _, _ in
                    appearedRows.removeAll()
                    loadResults()
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DS.bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSearchFocused ? DS.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                .animation(ProMotionSprings.hover, value: isSearchFocused)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingView
        } else if results.isEmpty {
            emptyView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            resultRow(index: index, result: result)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
                .onChange(of: selectedIndex) { _, _ in
                    withAnimation(ProMotionSprings.snappy) {
                        proxy.scrollTo(selectedIndex, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Result Row

    @ViewBuilder
    private func resultRow(index: Int, result: MentionSearchResult) -> some View {
        let entityColor = CosmoMentionColors.color(for: result.entityType)
        let isActive = index == selectedIndex || hoveredIndex == index

        Button {
            selectResult(result)
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(entityColor.opacity(isActive ? 0.16 : 0.12))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: result.entityType.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(entityColor)
                    )

                Text(result.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(result.typeLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? DS.bg : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? entityColor.opacity(0.2) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(index)
        .onHover { hovering in
            hoveredIndex = hovering ? index : nil
            if hovering {
                selectedIndex = index
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(index) * 0.015)) {
                withAnimation(ProMotionSprings.cardEntrance) {
                    _ = appearedRows.insert(result.id)
                }
            }
        }
        .opacity(appearedRows.contains(result.id) ? 1 : 0)
        .offset(y: appearedRows.contains(result.id) ? 0 : 6)
    }

    // MARK: - Loading / Empty

    private var loadingView: some View {
        VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 12) {
                    CosmicShimmer(entityColor: DS.accent, cornerRadius: 10)
                        .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 6) {
                        CosmicShimmer(entityColor: DS.accent, cornerRadius: 4)
                            .frame(width: 140, height: 14)
                        CosmicShimmer(entityColor: DS.accent, cornerRadius: 4)
                            .frame(width: 80, height: 10)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 14)
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(DS.textMuted)

            Text("No matching items")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.text)

            Text("Try a different search term.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Search

    private func loadResults() {
        searchTask?.cancel()
        let requestID = UUID()
        let query = searchQuery
        searchRequestID = requestID
        isLoading = true
        selectedIndex = 0

        searchTask = Task {
            let searchResults = await provider.search(query: query, limit: 20)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard searchRequestID == requestID else { return }
                results = searchResults
                isLoading = false
            }
        }
    }

    // MARK: - Selection

    private func selectCurrentItem() {
        guard let result = results[safe: selectedIndex] else { return }
        selectResult(result)
    }

    private func selectResult(_ result: MentionSearchResult) {
        Task {
            if let atom = try? await AtomRepository.shared.fetch(uuid: result.atomUUID) {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.12)) {
                        menuAppeared = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        onSelect(atom)
                    }
                }
            }
        }
    }

    // MARK: - Dismiss Animation

    private func dismissAnimated() {
        withAnimation(.easeOut(duration: 0.12)) {
            menuAppeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            onDismiss()
        }
    }

    // MARK: - Position Clamping

    private var clampedPosition: CGPoint {
        guard let screen = NSScreen.main else {
            return CGPoint(x: position.x + menuWidth / 2, y: position.y - menuHeight / 2)
        }
        let bounds = screen.visibleFrame
        let x = min(max(position.x + menuWidth / 2, menuWidth / 2 + 20), bounds.width - menuWidth / 2 - 20)
        let y = min(max(position.y - menuHeight / 2, menuHeight / 2 + 20), bounds.height - menuHeight / 2 - 20)
        return CGPoint(x: x, y: y)
    }
}
