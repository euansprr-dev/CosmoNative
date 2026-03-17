// CosmoOS/UI/CommandK/CommandKView.swift
// Main Command-K overlay view - NodeGraph OS search interface
// Glass material overlay with grouped results, custom formatters, keyboard navigation

import SwiftUI

// MARK: - CommandKView
/// Main overlay for Command-K search interface
/// Features: grouped results, type-specific formatters, keyboard nav, #prefix filtering, quick-create
public struct CommandKView: View {

    // MARK: - Tab Enum
    enum CommandKTab: CaseIterable {
        case database
        case swipeGallery
        case ideas
        case readwise
    }

    // MARK: - State
    var initialTab: CommandKTab = .database
    @StateObject private var viewModel = CommandKViewModel()
    @FocusState private var isSearchFocused: Bool
    @State private var activeTab: CommandKTab
    @Namespace private var tabNamespace

    init(initialTab: CommandKTab = .database) {
        self.initialTab = initialTab
        _activeTab = State(initialValue: initialTab)
    }

    // MARK: - Layout Constants
    private let overlayWidthPercent: CGFloat = 0.78
    private let overlayHeightPercent: CGFloat = 0.72
    private let overlayMinSize = CGSize(width: 960, height: 620)
    private let overlayMaxSize = CGSize(width: 1480, height: 940)

    // MARK: - Body
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundLayer
                overlayContainer(geometry: geometry)
            }
            .ignoresSafeArea()
            .onAppear {
                isSearchFocused = true
            }
        }
        .onKeyPress(.escape) {
            if viewModel.isMultiSelectActive {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.clearSelection()
                }
            } else {
                NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.selectNext()
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.return) {
            viewModel.openSelected()
            return .handled
        }
        .onKeyPress(.tab) {
            // During unified search, Tab is a no-op (results span all sources)
            guard !viewModel.isUnifiedSearchActive else { return .handled }
            withAnimation(ProMotionSprings.snappy) {
                viewModel.clearSelection()
                switch activeTab {
                case .database: activeTab = .swipeGallery
                case .swipeGallery: activeTab = .ideas
                case .ideas: activeTab = .readwise
                case .readwise: activeTab = .database
                }
            }
            return .handled
        }
    }

    // MARK: - Background Layer
    private var backgroundLayer: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            DS.bg.opacity(0.45)
        }
        .ignoresSafeArea()
        .onTapGesture {
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
        }
    }

    // MARK: - Overlay Container
    private func overlayContainer(geometry: GeometryProxy) -> some View {
        let width = min(max(geometry.size.width * overlayWidthPercent, overlayMinSize.width), overlayMaxSize.width)
        let height = min(max(geometry.size.height * overlayHeightPercent, overlayMinSize.height), overlayMaxSize.height)

        return VStack(spacing: 0) {
            searchBarSection

            Divider()
                .background(DS.borderSubtle)

            tabBar

            Divider()
                .background(DS.borderSubtle)

            if viewModel.isUnifiedSearchActive {
                UnifiedSearchResultsView(viewModel: viewModel)
                    .transition(.opacity)
            } else {
                switch activeTab {
                case .database:
                    LibraryTab(viewModel: viewModel, searchQuery: viewModel.query)

                case .readwise:
                    ReadwiseLibraryTab(viewModel: viewModel, searchQuery: viewModel.query)

                case .swipeGallery:
                    SwipeGalleryTab(viewModel: viewModel, searchQuery: viewModel.query)

                case .ideas:
                    IdeasTab(viewModel: viewModel, searchQuery: viewModel.query)
                }
            }
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: CommandKMetrics.overlayCornerRadius, style: .continuous)
                .fill(DS.surfaceElevated)
        )
        .clipShape(RoundedRectangle(cornerRadius: CommandKMetrics.overlayCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandKMetrics.overlayCornerRadius, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsFloatingShadow()
    }

    // Glass background removed — using solid DS.surfaceElevated + DS.border overlay inline

    // MARK: - Search Bar Section
    private var searchBarSection: some View {
        HStack(spacing: 14) {
            Image(systemName: viewModel.isTaskCreationMode ? "plus.circle.fill" : "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(viewModel.isTaskCreationMode ? DS.accent : (isSearchFocused ? DS.accent : DS.textSecondary))
                .symbolEffect(.pulse, isActive: viewModel.currentPhase == .searching)
                .frame(width: 22)

            TextField(searchPlaceholder, text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(DS.text)
                .focused($isSearchFocused)
                .onSubmit {
                    viewModel.openSelected()
                }

            Spacer()

            // Type prefix indicator
            if let prefixType = viewModel.activeTypePrefix {
                typePrefixBadge(prefixType)
            }

            // Task creation hint
            if viewModel.isTaskCreationMode {
                Text("Enter to create task")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .commandKToolbarChip(
                        isActive: true,
                        activeFill: DS.accentSoft,
                        activeBorder: DS.accent.opacity(0.18)
                    )
            }

            Button {
                viewModel.isVoiceActive.toggle()
            } label: {
                Image(systemName: viewModel.isVoiceActive ? "mic.fill" : "mic")
                    .font(.system(size: 15))
                    .foregroundStyle(viewModel.isVoiceActive ? DS.accent : DS.textSecondary)
                    .frame(width: 32, height: 32)
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

            if viewModel.currentPhase == .searching {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(DS.textSecondary)
            }
        }
        .padding(.horizontal, 28)
        .frame(height: CommandKMetrics.searchBarHeight)
    }

    private var searchPlaceholder: String {
        "Search everything..."
    }

    @ViewBuilder
    private func typePrefixBadge(_ type: AtomType) -> some View {
        HStack(spacing: 4) {
            Image(systemName: iconForType(type))
                .font(.system(size: 10))
            Text(type.displayName)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(entityColor(type))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(entityColor(type).opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Tab Bar
    private var tabBar: some View {
        HStack(spacing: 6) {
            CommandKTabButton(
                title: "Database",
                icon: "tray.full.fill",
                isActive: activeTab == .database && !viewModel.isUnifiedSearchActive,
                count: viewModel.totalCount,
                namespace: tabNamespace,
                isDimmed: viewModel.isUnifiedSearchActive
            ) {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.query = ""
                    activeTab = .database
                }
            }

            CommandKTabButton(
                title: "Swipe Gallery",
                icon: "bolt.fill",
                isActive: activeTab == .swipeGallery && !viewModel.isUnifiedSearchActive,
                accentColor: DS.entitySwipe,
                count: viewModel.swipeGalleryItems.count,
                namespace: tabNamespace,
                isDimmed: viewModel.isUnifiedSearchActive
            ) {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.query = ""
                    activeTab = .swipeGallery
                }
            }

            CommandKTabButton(
                title: "Ideas",
                icon: "lightbulb.fill",
                isActive: activeTab == .ideas && !viewModel.isUnifiedSearchActive,
                accentColor: DS.entityIdea,
                count: viewModel.ideaGalleryItems.count,
                namespace: tabNamespace,
                isDimmed: viewModel.isUnifiedSearchActive
            ) {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.query = ""
                    activeTab = .ideas
                }
            }

            CommandKTabButton(
                title: "Readwise",
                icon: "books.vertical.fill",
                isActive: activeTab == .readwise && !viewModel.isUnifiedSearchActive,
                accentColor: DS.entityReadwise,
                count: ReadwiseBookStore.shared.books.count,
                namespace: tabNamespace,
                isDimmed: viewModel.isUnifiedSearchActive
            ) {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.query = ""
                    activeTab = .readwise
                }
            }

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "arrow.right.to.line.compact")
                    .font(.system(size: 10, weight: .semibold))
                Text("Tab")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(DS.textMuted)
            .commandKToolbarChip(cornerRadius: 8)
        }
        .padding(.horizontal, 20)
        .frame(height: CommandKMetrics.tabBarHeight + 4)
    }

    // MARK: - Helpers

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

// MARK: - Command-K Tab Button

private struct CommandKTabButton: View {
    let title: String
    let icon: String
    let isActive: Bool
    var accentColor: Color = DS.accent
    var count: Int = 0
    var namespace: Namespace.ID
    var isDimmed: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                tabLabel
                    .padding(.horizontal, 12)
                    .frame(height: CommandKMetrics.tabBarHeight)
                    .background(tabBackground)

                tabIndicator
            }
            .opacity(isDimmed ? 0.45 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(ProMotionSprings.snappy, value: isActive)
        .animation(ProMotionSprings.snappy, value: isDimmed)
    }

    private var tabLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? accentColor : DS.textMuted)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? DS.text : DS.textSecondary)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .contentTransition(.numericText(value: Double(count)))
                    .foregroundStyle(isActive ? accentColor : DS.textMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(isActive ? accentColor.opacity(0.12) : DS.surface)
                    )
            }
        }
    }

    @ViewBuilder
    private var tabBackground: some View {
        if isActive {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.surface)
                .matchedGeometryEffect(id: "commandKTabBg", in: namespace)
        }
    }

    @ViewBuilder
    private var tabIndicator: some View {
        if isActive {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(accentColor)
                .frame(width: 28, height: 2.5)
                .matchedGeometryEffect(id: "commandKTabLine", in: namespace)
        } else {
            Color.clear
                .frame(width: 28, height: 2.5)
        }
    }
}

// MARK: - Preview

#Preview("Command K") {
    CommandKView()
        .frame(width: 1200, height: 800)
}
