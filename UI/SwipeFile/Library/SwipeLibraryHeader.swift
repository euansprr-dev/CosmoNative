import SwiftUI

/// One calm masthead: title + counts on the left; sort, search, display mode, and
/// the single Filters affordance on the right. Everything else the old chrome
/// stack carried (stat tiles, preset strip, chip walls) lives in the popover now.
struct SwipeLibraryHeader: View {
    @Bindable var viewModel: SwipeLibraryViewModel
    let title: String
    var searchFocused: FocusState<Bool>.Binding
    @Binding var showFilters: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            titleBlock
            Spacer(minLength: DS.space16)
            controls
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DS.pageTitle)
                .foregroundStyle(DS.text)
            Text(subtitle)
                .font(DS.subheadline.monospacedDigit())
                .foregroundStyle(DS.textMuted)
        }
    }

    private var subtitle: String {
        var parts = ["\(viewModel.summary.totalCount) swipes"]
        if viewModel.summary.unstudiedCount > 0 {
            parts.append("\(viewModel.summary.unstudiedCount) unstudied")
        }
        if viewModel.summary.filteredCount != viewModel.summary.totalCount {
            parts.append("\(viewModel.summary.filteredCount) shown")
        }
        return parts.joined(separator: " · ")
    }

    private var controls: some View {
        HStack(spacing: 8) {
            sortMenu
            SwipeLibrarySearchField(text: $viewModel.query, isFocused: searchFocused)
            displayModeToggle
            SwipeLibraryFiltersButton(
                activeCount: viewModel.filterState.activeTokens.count,
                isOpen: $showFilters
            )
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SwipeSortMode.allCases, id: \.rawValue) { mode in
                Button {
                    viewModel.sortMode = mode
                } label: {
                    if viewModel.sortMode == mode {
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(DS.caption.weight(.semibold))
                Text(viewModel.sortMode.displayName)
                    .font(DS.subheadline.weight(.medium))
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(DS.glassInputFill))
            .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Sort swipes")
        .accessibilityLabel("Sort: \(viewModel.sortMode.displayName)")
    }

    private var displayModeToggle: some View {
        HStack(spacing: 2) {
            displayModeButton(.grid, icon: "square.grid.2x2", help: "Grid")
            displayModeButton(.compact, icon: "list.bullet", help: "List")
        }
        .padding(2)
        .background(Capsule().fill(DS.glassInputFill))
        .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
    }

    private func displayModeButton(_ mode: SwipeLibraryMode, icon: String, help: String) -> some View {
        Button {
            withAnimation(ProMotionSprings.snappy) { viewModel.displayMode = mode }
        } label: {
            Image(systemName: icon)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(viewModel.displayMode == mode ? DS.accent : DS.textMuted)
                .frame(width: 30, height: 26)
                .background(Capsule().fill(viewModel.displayMode == mode ? DS.accentSoft : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel("\(help) view")
        .accessibilityAddTraits(viewModel.displayMode == mode ? .isSelected : [])
    }
}

// MARK: - Search field

struct SwipeLibrarySearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var placeholder = "Find in swipes"

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DS.subheadline)
                .foregroundStyle(DS.text)
                .focused(isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 220, height: 32)
        .dsGlassInput(isFocused: isFocused.wrappedValue, cornerRadius: 16)
        .help("Find in swipes (⌘F)")
    }
}

// MARK: - Filters button

struct SwipeLibraryFiltersButton: View {
    let activeCount: Int
    @Binding var isOpen: Bool

    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(ProMotionSprings.bouncy) { isOpen.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(DS.caption.weight(.semibold))
                Text("Filters")
                    .font(DS.subheadline.weight(.medium))
                if activeCount > 0 {
                    Text("\(activeCount)")
                        .font(DS.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(DS.textOnAccent)
                        .frame(width: 17, height: 17)
                        .background(DS.accent, in: Circle())
                }
            }
            .foregroundStyle(isOpen || hovering ? DS.text : DS.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(isOpen ? DS.glassInputFillFocused : DS.glassInputFill))
            .overlay(Capsule().strokeBorder(isOpen ? DS.glassBorderFocused : DS.glassBorder, lineWidth: isOpen ? 1 : 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { value in withAnimation(ProMotionSprings.hover) { hovering = value } }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SwipeFilterAnchorKey.self,
                    value: proxy.frame(in: .named("swipePage"))
                )
            }
        )
        .help("Filters")
        .accessibilityLabel(activeCount > 0 ? "Filters, \(activeCount) active" : "Filters")
    }
}
