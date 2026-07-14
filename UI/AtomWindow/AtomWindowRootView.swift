// CosmoOS/UI/AtomWindow/AtomWindowRootView.swift
// Top-level SwiftUI view hosted inside the floating atom viewer NSPanel

import SwiftUI

struct AtomWindowRootView: View {
    let viewModel: AtomWindowViewModel

    @State private var historyAtom: Atom?

    var body: some View {
        atomContent
        .background(atomWindowBackdrop)
        .clipShape(.rect(cornerRadius: AtomWindowMetrics.panelCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AtomWindowMetrics.panelCornerRadius, style: .continuous)
                .stroke(DS.glassBorder.opacity(0.84), lineWidth: 0.6)
        )
        .compositingGroup()
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $historyAtom) { atom in
            AtomHistorySheet(atom: atom) { historyAtom = nil }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var atomContent: some View {
        ZStack {
            if let atom = viewModel.currentAtom {
                atomFocusView(atom: atom)
                    .id(atom.uuid)
                    .environment(\.atomWindowChromeContext, chromePayload(for: atom))
            } else if viewModel.isLoading {
                emptyShell {
                    loadingView
                }
            } else {
                emptyShell {
                    emptyStateView
                }
            }

            if viewModel.isSearchVisible {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(ProMotionSprings.snappy) {
                            viewModel.isSearchVisible = false
                        }
                    }

                AtomSearchOverlay(viewModel: viewModel)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var atomWindowBackdrop: some View {
        ZStack {
            DS.bg
            DS.glassPanelTint.opacity(0.42)
        }
    }

    // MARK: - Focus View Routing

    @ViewBuilder
    private func atomFocusView(atom: Atom) -> some View {
        let entityType = AtomWindowViewModel.entityType(for: atom.type)

        switch entityType {
        case .research:
            if atom.isSwipeFileAtom {
                SwipeStudyFocusModeView(atom: atom, onClose: handleClose)
            } else {
                ResearchFocusModeView(atom: atom, onClose: handleClose)
            }
        case .connection:
            ConnectionFocusModeView(atom: atom, onClose: handleClose)
        case .idea:
            IdeaFocusModeView(atom: atom, onClose: handleClose)
        case .content:
            ContentFocusModeView(atom: atom, onClose: handleClose)
        case .note:
            NoteFocusModeView(atom: atom, onClose: handleClose)
        case .cosmoAI:
            CosmoAIFocusModeView(atom: atom, onClose: handleClose)
        default:
            AtomWindowGenericView(atom: atom)
        }
    }

    private func handleClose() {
        viewModel.unloadCurrentSession()
    }

    private func chromePayload(for atom: Atom) -> AtomWindowChromePayload {
        AtomWindowChromePayload(
            state: AtomWindowChromeState(
                title: atom.title ?? "Untitled",
                typeIcon: atom.type.iconName,
                typeColor: AtomWindowChromeTypeColor(atomType: atom.type),
                canGoBack: viewModel.canGoBack,
                canGoForward: viewModel.canGoForward,
                canBookmark: true,
                isBookmarked: viewModel.isCurrentBookmarked
            ),
            actions: chromeActions
        )
    }

    private var emptyChromePayload: AtomWindowChromePayload {
        AtomWindowChromePayload(
            state: AtomWindowChromeState(
                title: "Atom Window",
                typeIcon: "atom",
                typeColor: .neutral,
                canGoBack: viewModel.canGoBack,
                canGoForward: viewModel.canGoForward,
                canBookmark: false,
                isBookmarked: false
            ),
            actions: chromeActions
        )
    }

    private var chromeActions: AtomWindowChromeActions {
        AtomWindowChromeActions(
            closeWindow: {
                AtomWindowPanelController.shared.hide()
            },
            goBack: {
                Task { await viewModel.goBack() }
            },
            goForward: {
                Task { await viewModel.goForward() }
            },
            toggleBookmark: {
                viewModel.toggleBookmark()
            },
            showSearch: {
                viewModel.isSearchVisible.toggle()
            },
            createAtom: { type in
                Task { await viewModel.createNewAtom(type: type) }
            },
            showHistory: {
                historyAtom = viewModel.currentAtom
            }
        )
    }

    private func emptyShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            AtomWindowStandaloneChrome(context: emptyChromePayload)
                .padding(.horizontal, DS.space16)
                .padding(.top, DS.space12)
                .padding(.bottom, DS.space8)

            content()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: DS.space24) {
            Spacer()
            emptyStateHeader
            recentAtomsList
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bg)
    }

    private var emptyStateHeader: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "atom")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)

            Text("Open any atom")
                .font(DS.title2)
                .foregroundStyle(DS.text)

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.isSearchVisible = true
                }
            } label: {
                HStack(spacing: DS.space6) {
                    Image(systemName: "magnifyingglass")
                        .font(DS.caption.weight(.semibold))
                        .accessibilityHidden(true)
                    Text("Search atoms")
                        .font(DS.buttonText.weight(.semibold))
                }
                .foregroundStyle(DS.accent)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space6)
                .background(DS.accentSoft, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Search atoms")
            .padding(.top, DS.space4)
        }
    }

    private var recentAtomsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.recentAtoms.isEmpty {
                Text("Recent")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .padding(.horizontal, DS.space16)
                    .padding(.bottom, DS.space4)

                ForEach(viewModel.recentAtoms.prefix(6)) { atom in
                    recentAtomRow(atom: atom)
                }
            }
        }
        .frame(maxWidth: 400)
    }

    private func recentAtomRow(atom: Atom) -> some View {
        Button {
            Task { await viewModel.navigate(to: atom.uuid) }
        } label: {
            HStack(spacing: DS.space10) {
                Image(systemName: atom.type.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AtomWindowViewModel.entityColor(for: atom.type))
                    .frame(width: 24, height: 24)

                Text(atom.title ?? "Untitled")
                    .font(DS.body)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(atom.type.displayName)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: DS.space12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading…")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bg)
    }
}

// MARK: - Generic View (for unsupported atom types)

struct AtomWindowGenericView: View {
    let atom: Atom
    @Environment(\.atomWindowChromeContext) private var atomChrome

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space16) {
                    headerSection
                    if let body = atom.body, !body.isEmpty {
                        bodySection(body)
                    }
                    metadataSection
                }
                .padding(DS.space24)
                .padding(.top, atomChrome == nil ? 0 : 64)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DS.bg)

            if let atomChrome {
                AtomWindowStandaloneChrome(context: atomChrome)
                    .padding(.horizontal, DS.space16)
                    .padding(.top, DS.space12)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: DS.space8) {
                Image(systemName: atom.type.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AtomWindowViewModel.entityColor(for: atom.type))

                Text(atom.type.displayName)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DS.space8)
                    .padding(.vertical, 2)
                    .background(DS.surfaceElevated, in: Capsule())
            }

            Text(atom.title ?? "Untitled")
                .font(DS.pageTitle)
                .foregroundStyle(DS.text)
        }
    }

    private func bodySection(_ text: String) -> some View {
        Text(text)
            .font(DS.body)
            .foregroundStyle(DS.text)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Divider().foregroundStyle(DS.border)

            HStack(spacing: DS.space16) {
                metadataItem(label: "Created", value: formatDate(atom.createdAt))
                metadataItem(label: "Updated", value: formatDate(atom.updatedAt))
            }
            .padding(.top, DS.space4)
        }
    }

    private func metadataItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            Text(value)
                .font(DS.subheadline)
                .foregroundStyle(DS.textSecondary)
        }
    }

    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return isoString }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }
}
