// CosmoOS/UI/FocusMode/Ideas/LinkSwipesOverlay.swift
// Full-screen overlay for linking swipe files to an idea
// February 2026

import SwiftUI

struct LinkSwipesOverlay: View {
    var viewModel: IdeaFocusModeViewModel
    @Binding var isPresented: Bool
    var blueprintMode: Bool = false

    @State private var searchText: String = ""
    @State private var allSwipes: [Atom] = []
    @State private var selectedUUIDs: Set<String> = []
    @State private var isLoading: Bool = true

    private let overlayWidth: CGFloat = 700
    private let overlayHeight: CGFloat = 600
    private let accentIndigo = DS.accent
    private var linkedSwipeIDs: Set<String> { Set(viewModel.idea.ideaMetadata?.linkedSwipeIds ?? []) }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.15)
                .background(.regularMaterial)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            // Container
            VStack(spacing: 0) {
                overlayHeader
                Divider().background(DS.border)
                searchField
                Divider().background(DS.border)
                swipeList
                Divider().background(DS.border)
                overlayFooter
            }
            .frame(width: overlayWidth, height: overlayHeight)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(DS.surface.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(DS.border)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [DS.border, DS.borderSubtle],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 40, y: 20)
        }
        .onAppear {
            initializeSelection()
            Task { await loadAllSwipes() }
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    // MARK: - Header

    private var overlayHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 14))
                .foregroundColor(accentIndigo)

            Text(blueprintMode ? "Select Blueprint" : "Manage Swipe Files")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DS.text)

            Spacer()

            if !selectedUUIDs.isEmpty {
                Text("\(selectedUUIDs.count) selected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(accentIndigo)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accentIndigo.opacity(0.12), in: Capsule())
            }

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.textSecondary)
                    .padding(8)
                    .background(DS.border, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(DS.textMuted)

            TextField("Search swipes by hook, topic, creator…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(DS.text)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(DS.borderSubtle)
    }

    // MARK: - Swipe List

    private var swipeList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView().tint(accentIndigo)
                    Text("Loading swipe library…")
                        .font(.system(size: 12))
                        .foregroundColor(DS.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else if filteredSwipes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundColor(DS.textMuted)
                    Text(searchText.isEmpty ? "No swipe files found" : "No swipes match '\(searchText)'")
                        .font(.system(size: 13))
                        .foregroundColor(DS.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(filteredSwipes, id: \.uuid) { swipe in
                        swipeRow(swipe)
                    }
                }
                .padding(12)
            }
        }
    }

    private var filteredSwipes: [Atom] {
        let search = searchText.lowercased().trimmingCharacters(in: .whitespaces)

        return allSwipes.filter { swipe in
            if search.isEmpty { return true }
            let title = (swipe.title ?? "").lowercased()
            let body = (swipe.body ?? "").lowercased()
            let hook = (swipe.researchMetadata?.hook ?? "").lowercased()
            return title.contains(search) || body.contains(search) || hook.contains(search)
        }.sorted { a, b in
            let aSelected = selectedUUIDs.contains(a.uuid)
            let bSelected = selectedUUIDs.contains(b.uuid)
            if aSelected != bSelected { return aSelected }
            let aLinked = linkedSwipeIDs.contains(a.uuid)
            let bLinked = linkedSwipeIDs.contains(b.uuid)
            if aLinked != bLinked { return aLinked }
            return (a.updatedAt ?? "") > (b.updatedAt ?? "")
        }
    }

    @ViewBuilder
    private func swipeRow(_ swipe: Atom) -> some View {
        let isAlreadyLinked = linkedSwipeIDs.contains(swipe.uuid)
        let isSelected = selectedUUIDs.contains(swipe.uuid)
        let analysis = swipe.swipeAnalysis
        let hookText = swipe.researchMetadata?.hook ?? analysis?.hookText ?? ""
        let hookScore = analysis?.hookScore
        let hookType = analysis?.hookType

        Button {
            if blueprintMode {
                if isSelected {
                    selectedUUIDs.remove(swipe.uuid)
                } else {
                    selectedUUIDs = [swipe.uuid]
                }
            } else if isSelected {
                selectedUUIDs.remove(swipe.uuid)
            } else {
                selectedUUIDs.insert(swipe.uuid)
            }
        } label: {
            HStack(spacing: 12) {
                // Thumbnail placeholder
                thumbnailView(for: swipe)

                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    Text(swipe.title ?? "Untitled Swipe")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.text)
                        .lineLimit(1)

                    // Hook text
                    if !hookText.isEmpty {
                        Text(String(hookText.prefix(80)))
                            .font(.system(size: 11))
                            .foregroundColor(DS.textSecondary)
                            .lineLimit(2)
                    }

                    // Badges row
                    HStack(spacing: 6) {
                        if let type = hookType {
                            hookTypeBadge(type)
                        }
                        if let score = hookScore {
                            hookScoreBadge(score)
                        }
                        if let platform = swipe.researchMetadata?.contentSource {
                            Text(platform)
                                .font(.system(size: 9))
                                .foregroundColor(DS.textMuted)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    if blueprintMode {
                        selectionIndicator(isSelected: isSelected)
                    } else {
                        selectionIndicator(isSelected: isSelected)

                        let stateText = linkStateText(isAlreadyLinked: isAlreadyLinked, isSelected: isSelected)
                        if !stateText.isEmpty {
                            Text(stateText)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(linkStateColor(isAlreadyLinked: isAlreadyLinked, isSelected: isSelected))
                        }
                    }
                }
            }
            .padding(10)
            .background(
                rowBackground(isAlreadyLinked: isAlreadyLinked, isSelected: isSelected),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        rowBorder(isAlreadyLinked: isAlreadyLinked, isSelected: isSelected),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func thumbnailView(for swipe: Atom) -> some View {
        let thumbUrl = swipe.researchMetadata?.thumbnailUrl

        if let urlStr = thumbUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(DS.border)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 12))
                            .foregroundColor(DS.textMuted)
                    )
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(DS.border)
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundColor(DS.textMuted)
                )
        }
    }

    @ViewBuilder
    private func hookTypeBadge(_ type: SwipeHookType) -> some View {
        HStack(spacing: 3) {
            Image(systemName: type.iconName)
                .font(.system(size: 7))
            Text(type.displayName)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(type.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(type.color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func hookScoreBadge(_ score: Double) -> some View {
        let color: Color = score >= 7 ? Color(hex: "22C55E") :
            score >= 5 ? Color(hex: "FBBF24") : Color(hex: "64748B")

        Text(String(format: "%.1f", score))
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Footer

    private var overlayFooter: some View {
        HStack(spacing: 12) {
            Text("\(allSwipes.count) swipes in library")
                .font(.system(size: 11))
                .foregroundColor(DS.textMuted)

            Spacer()

            Button {
                isPresented = false
            } label: {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DS.border, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    if blueprintMode {
                        if let firstUUID = selectedUUIDs.first,
                           let swipe = allSwipes.first(where: { $0.uuid == firstUUID }) {
                            viewModel.selectBlueprint(swipe)
                        } else {
                            viewModel.clearBlueprint()
                        }
                    } else {
                        let existing = linkedSwipeIDs
                        for uuid in existing.subtracting(selectedUUIDs) {
                            await viewModel.unlinkSwipe(uuid)
                        }
                        for uuid in selectedUUIDs.subtracting(existing) {
                            await viewModel.linkSwipe(uuid)
                        }
                    }
                    isPresented = false
                }
            } label: {
                Text(blueprintMode ? "Save Blueprint" : "Save Swipe Links")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.textOnAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(accentIndigo, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(blueprintMode ? false : selectedUUIDs == linkedSwipeIDs)
            .opacity(blueprintMode || selectedUUIDs != linkedSwipeIDs ? 1 : 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Data

    private func loadAllSwipes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let research = try await AtomRepository.shared.fetchAll(type: .research)
            allSwipes = research.filter { $0.isSwipeFileAtom }
        } catch {
            print("LinkSwipesOverlay: failed to load swipes: \(error)")
        }
    }

    private func initializeSelection() {
        if blueprintMode {
            if let selected = viewModel.selectedBlueprintUUID {
                selectedUUIDs = [selected]
            } else {
                selectedUUIDs.removeAll()
            }
        } else {
            selectedUUIDs = linkedSwipeIDs
        }
    }

    @ViewBuilder
    private func selectionIndicator(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 16))
            .foregroundColor(isSelected ? accentIndigo : DS.textMuted)
    }

    private func linkStateText(isAlreadyLinked: Bool, isSelected: Bool) -> String {
        if isAlreadyLinked && isSelected { return "linked" }
        if isAlreadyLinked && !isSelected { return "remove" }
        if !isAlreadyLinked && isSelected { return "add" }
        return ""
    }

    private func linkStateColor(isAlreadyLinked: Bool, isSelected: Bool) -> Color {
        if isAlreadyLinked && isSelected { return DS.green }
        if isAlreadyLinked && !isSelected { return DS.orange }
        if !isAlreadyLinked && isSelected { return accentIndigo }
        return DS.textMuted
    }

    private func rowBackground(isAlreadyLinked: Bool, isSelected: Bool) -> Color {
        if isAlreadyLinked && isSelected { return DS.green.opacity(0.06) }
        if isAlreadyLinked && !isSelected { return DS.orange.opacity(0.08) }
        if !isAlreadyLinked && isSelected { return accentIndigo.opacity(0.08) }
        return DS.borderSubtle
    }

    private func rowBorder(isAlreadyLinked: Bool, isSelected: Bool) -> Color {
        if isAlreadyLinked && isSelected { return DS.green.opacity(0.25) }
        if isAlreadyLinked && !isSelected { return DS.orange.opacity(0.3) }
        if !isAlreadyLinked && isSelected { return accentIndigo.opacity(0.3) }
        return .clear
    }
}

// MARK: - Preview

#Preview("Link Swipes Overlay") {
    @Previewable @State var isPresented = true
    let previewAtom = Atom.new(
        type: .idea,
        title: "Sample Idea for Preview",
        body: "This is a sample idea to demonstrate the link swipes overlay."
    )

    LinkSwipesOverlay(
        viewModel: IdeaFocusModeViewModel(atom: previewAtom),
        isPresented: $isPresented
    )
    .frame(width: 800, height: 700)
}
