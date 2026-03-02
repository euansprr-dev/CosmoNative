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

    init(initialTab: CommandKTab = .database) {
        self.initialTab = initialTab
        _activeTab = State(initialValue: initialTab)
    }

    // MARK: - Layout Constants
    private let overlayWidthPercent: CGFloat = 0.75
    private let overlayHeightPercent: CGFloat = 0.70
    private let overlayMinSize = CGSize(width: 900, height: 600)
    private let overlayMaxSize = CGSize(width: 1400, height: 900)
    private let cornerRadius: CGFloat = 24

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
        DS.bg.opacity(0.7)
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
                .background(DS.borderActive)

            tabBar

            Divider()
                .background(DS.borderActive)

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
        .frame(width: width, height: height)
        .background(DS.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsFloatingShadow()
    }

    // Glass background removed — using solid DS.surfaceElevated + DS.border overlay inline

    // MARK: - Search Bar Section
    private var searchBarSection: some View {
        HStack(spacing: 16) {
            Image(systemName: viewModel.isTaskCreationMode ? "plus.circle.fill" : "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(viewModel.isTaskCreationMode ? DS.accent : DS.textSecondary)

            TextField(searchPlaceholder, text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(DS.text)
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DS.accentSoft)
                    .clipShape(Capsule())
            }

            Button {
                viewModel.isVoiceActive.toggle()
            } label: {
                Image(systemName: viewModel.isVoiceActive ? "mic.fill" : "mic")
                    .font(.system(size: 15))
                    .foregroundColor(viewModel.isVoiceActive ? DS.accent : DS.textSecondary)
            }
            .buttonStyle(.plain)

            if viewModel.currentPhase == .searching {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(DS.textSecondary)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
    }

    private var searchPlaceholder: String {
        switch activeTab {
        case .database: return "Search your database..."
        case .readwise: return "Search your reading..."
        case .swipeGallery: return "Search your swipes..."
        case .ideas: return "Search your ideas..."
        }
    }

    @ViewBuilder
    private func typePrefixBadge(_ type: AtomType) -> some View {
        HStack(spacing: 4) {
            Image(systemName: iconForType(type))
                .font(.system(size: 10))
            Text(type.displayName)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(entityColor(type))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(entityColor(type).opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Tab Bar
    private var tabBar: some View {
        HStack(spacing: 0) {
            CommandKTabButton(
                title: "Database",
                icon: "tray.full.fill",
                isActive: activeTab == .database
            ) {
                withAnimation(ProMotionSprings.snappy) {
                    activeTab = .database
                }
            }

            CommandKTabButton(
                title: "Swipe Gallery",
                icon: "bolt.fill",
                isActive: activeTab == .swipeGallery,
                accentColor: DS.entitySwipe
            ) {
                withAnimation(ProMotionSprings.snappy) {
                    activeTab = .swipeGallery
                }
            }

            CommandKTabButton(
                title: "Ideas",
                icon: "lightbulb.fill",
                isActive: activeTab == .ideas,
                accentColor: DS.entityIdea
            ) {
                withAnimation(ProMotionSprings.snappy) {
                    activeTab = .ideas
                }
            }

            CommandKTabButton(
                title: "Readwise",
                icon: "books.vertical.fill",
                isActive: activeTab == .readwise,
                accentColor: DS.entityReadwise
            ) {
                withAnimation(ProMotionSprings.snappy) {
                    activeTab = .readwise
                }
            }

            Spacer()

            Text("\u{21E5} Tab")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.textMuted)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 24)
        .frame(height: 40)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(isActive ? DS.text : DS.textMuted)

                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? accentColor : Color.clear)
                    .frame(width: 24, height: 2)
            }
            .frame(height: 36)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .animation(ProMotionSprings.snappy, value: isActive)
    }
}

// MARK: - Preview

#Preview("Command K") {
    CommandKView()
        .frame(width: 1200, height: 800)
}
