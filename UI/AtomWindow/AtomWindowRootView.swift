// CosmoOS/UI/AtomWindow/AtomWindowRootView.swift
// Top-level SwiftUI view hosted inside the floating atom viewer NSPanel

import SwiftUI

struct AtomWindowRootView: View {
    let viewModel: AtomWindowViewModel

    var body: some View {
        VStack(spacing: 0) {
            AtomWindowHeaderBar(viewModel: viewModel)
            Divider().foregroundStyle(DS.sepiaSubtle)
            atomContent
        }
        .background(DS.vellum)
        .clipShape(.rect(cornerRadius: AtomWindowMetrics.panelCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AtomWindowMetrics.panelCornerRadius, style: .continuous)
                .stroke(DS.sepiaBorder, lineWidth: 0.5)
        )
        .compositingGroup()
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    @ViewBuilder
    private var atomContent: some View {
        ZStack {
            if let atom = viewModel.currentAtom {
                atomFocusView(atom: atom)
                    .id(atom.uuid)
            } else if viewModel.isLoading {
                loadingView
            } else {
                emptyStateView
            }

            if viewModel.isSearchVisible {
                Color.black.opacity(0.3)
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

            Text("Open any atom")
                .font(DS.title2)
                .foregroundStyle(DS.text)

            Text("Press  /  to search or  +  to create")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
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
            Text("Loading...")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bg)
    }
}

// MARK: - Header Bar

struct AtomWindowHeaderBar: View {
    @Bindable var viewModel: AtomWindowViewModel

    var body: some View {
        HStack(spacing: DS.space6) {
            navigationControls
            Spacer(minLength: 0)
            atomTitle
            Spacer(minLength: 0)
            actionControls
        }
        .padding(.horizontal, AtomWindowMetrics.contentPadding)
        .frame(height: AtomWindowMetrics.headerHeight)
    }

    // MARK: - Left: Navigation

    private var navigationControls: some View {
        HStack(spacing: 2) {
            headerButton("xmark", accessibilityLabel: "Close") {
                AtomWindowPanelController.shared.hide()
            }

            headerButton("chevron.left", accessibilityLabel: "Back") {
                Task { await viewModel.goBack() }
            }
            .disabled(!viewModel.canGoBack)
            .opacity(viewModel.canGoBack ? 1 : 0.35)
            .keyboardShortcut("[", modifiers: .command)

            headerButton("chevron.right", accessibilityLabel: "Forward") {
                Task { await viewModel.goForward() }
            }
            .disabled(!viewModel.canGoForward)
            .opacity(viewModel.canGoForward ? 1 : 0.35)
            .keyboardShortcut("]", modifiers: .command)
        }
    }

    // MARK: - Center: Title

    @ViewBuilder
    private var atomTitle: some View {
        if let atom = viewModel.currentAtom {
            HStack(spacing: DS.space6) {
                Image(systemName: atom.type.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AtomWindowViewModel.entityColor(for: atom.type))

                Text(atom.title ?? "Untitled")
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
            }
            .onTapGesture {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.isSearchVisible.toggle()
                }
            }
        } else {
            Text("Atom Window")
                .font(DS.headline)
                .foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: - Right: Actions

    private var actionControls: some View {
        HStack(spacing: 2) {
            headerButton(
                viewModel.isCurrentBookmarked ? "bookmark.fill" : "bookmark",
                accessibilityLabel: "Bookmark"
            ) {
                viewModel.toggleBookmark()
            }
            .disabled(viewModel.currentAtom == nil)
            .opacity(viewModel.currentAtom != nil ? 1 : 0.35)

            headerButton("magnifyingglass", accessibilityLabel: "Search") {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.isSearchVisible.toggle()
                }
            }

            Menu {
                Button("Idea", systemImage: AtomType.idea.iconName) {
                    Task { await viewModel.createNewAtom(type: .idea) }
                }
                Button("Note", systemImage: AtomType.note.iconName) {
                    Task { await viewModel.createNewAtom(type: .note) }
                }
                Button("Content", systemImage: AtomType.content.iconName) {
                    Task { await viewModel.createNewAtom(type: .content) }
                }
                Button("Research", systemImage: AtomType.research.iconName) {
                    Task { await viewModel.createNewAtom(type: .research) }
                }
                Button("Connection", systemImage: AtomType.connection.iconName) {
                    Task { await viewModel.createNewAtom(type: .connection) }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: AtomWindowMetrics.controlSize, height: AtomWindowMetrics.controlSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    // MARK: - Shared Button

    private func headerButton(
        _ icon: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: AtomWindowMetrics.controlSize, height: AtomWindowMetrics.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Generic View (for unsupported atom types)

struct AtomWindowGenericView: View {
    let atom: Atom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                headerSection
                if let body = atom.body, !body.isEmpty {
                    bodySection(body)
                }
                metadataSection
            }
            .padding(DS.space24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.bg)
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
