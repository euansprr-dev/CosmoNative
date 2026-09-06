// CosmoOS/UI/AtomWindow/AtomWindowRootView.swift
// Top-level SwiftUI view hosted inside the floating atom viewer NSPanel

import SwiftUI

struct AtomWindowRootView: View {
    let viewModel: AtomWindowViewModel

    @State private var historyAtom: Atom?

    var body: some View {
        atomContent
        // The open item pauses its editing session while the switcher covers
        // it, exactly as it does while the window is ordered out.
        .environment(\.cosmoFloatingPanelIsVisible, viewModel.isPresented && !viewModel.isSwitcherVisible)
        .background(atomWindowBackdrop)
        .clipShape(.rect(cornerRadius: AtomWindowMetrics.panelCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AtomWindowMetrics.panelCornerRadius, style: .continuous)
                .stroke(DS.glassBorder.opacity(0.84), lineWidth: 0.6)
        )
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $historyAtom) { atom in
            AtomHistorySheet(atom: atom) { historyAtom = nil }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var atomContent: some View {
        let switcherVisible = viewModel.isSwitcherVisible
        ZStack {
            if let atom = viewModel.currentAtom {
                // The item stays mounted under the switcher — its scroll,
                // undo history and hydrated editors are exactly where they
                // were when Back is undone.
                atomFocusView(atom: atom)
                    .id(atom.uuid)
                    .environment(\.atomWindowChromeContext, chromePayload(for: atom))
                    .opacity(switcherVisible ? 0 : 1)
                    .allowsHitTesting(!switcherVisible)
                    .accessibilityHidden(switcherVisible)
                    .animation(ProMotionSprings.gentle, value: switcherVisible)
            } else if viewModel.isLoading {
                loadingShell
            }

            if switcherVisible {
                AtomSwitcherView(
                    model: viewModel.switcher,
                    chrome: viewModel.currentAtom.map(chromePayload(for:)) ?? emptyChromePayload,
                    onOpen: { viewModel.open($0) },
                    onOpenInMainWindow: { viewModel.openInMainWindow($0) },
                    onTogglePin: { viewModel.togglePin($0) },
                    onCreateFromQuery: { title in
                        Task { await viewModel.createNewAtom(type: .note, title: title) }
                    },
                    onReturnToOpenItem: { viewModel.dismissSwitcher() },
                    onEscape: { viewModel.escapeSwitcher() }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 10)),
                    removal: .opacity
                ))
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
        case .inquirySession:
            if atom.isSwipeLab {
                SwipeLabFocusModeView(atom: atom, onClose: handleClose)
            } else {
                InquiryWorkspaceView(sessionAtom: atom, onClose: handleClose)
            }
        case .idea:
            IdeaFocusModeView(atom: atom, onClose: handleClose)
        case .content:
            ContentFocusModeView(atom: atom, onClose: handleClose)
        case .note:
            // Back leads to the switcher; Esc still dismisses the window.
            UnifiedPageView(atom: atom, onClose: handleClose, onBack: handleBack)
        case .cosmoAI:
            CosmoAIFocusModeView(atom: atom, onClose: handleClose)
        case .extract:
            ExtractPeekView(atom: atom, onClose: handleClose)
        default:
            AtomWindowGenericView(atom: atom)
        }
    }

    private func handleClose() {
        AtomWindowPanelController.shared.hide()
    }

    private func handleBack() {
        viewModel.showSwitcher()
    }

    private func chromePayload(for atom: Atom) -> AtomWindowChromePayload {
        AtomWindowChromePayload(
            state: AtomWindowChromeState(
                title: atom.title ?? "Untitled",
                typeIcon: atom.cosmoIcon,
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
                typeIcon: .system("atom"),
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
                viewModel.toggleSwitcher()
            },
            createAtom: { type in
                Task { await viewModel.createNewAtom(type: type) }
            },
            showHistory: {
                historyAtom = viewModel.currentAtom
            }
        )
    }

    // MARK: - Loading

    private var loadingShell: some View {
        VStack(spacing: 0) {
            AtomWindowStandaloneChrome(context: emptyChromePayload)
                .padding(.horizontal, DS.space16)
                .padding(.top, DS.space12)
                .padding(.bottom, DS.space8)

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
                Image(cosmo: atom.cosmoIcon)
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
