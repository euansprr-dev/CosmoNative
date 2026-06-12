import SwiftUI

/// Three triage chips — shortcuts into filter state — plus the conditional
/// active-filter token row. This is everything that survives of the old preset
/// strip and two-row chip wall.
struct SwipeLibraryScopeBar: View {
    @Bindable var viewModel: SwipeLibraryViewModel

    private enum Triage {
        case all, unstudied, highScore
    }

    private var currentTriage: Triage {
        if viewModel.filterState.onlyUnstudied { return .unstudied }
        if viewModel.filterState.minimumHookScore != nil { return .highScore }
        return .all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            chips
            if !viewModel.filterState.activeTokens.isEmpty {
                SwipeActiveFilterTokens(
                    tokens: viewModel.filterState.activeTokens,
                    onRemove: { viewModel.filterState.removeToken($0) },
                    onClear: { viewModel.resetFilters() }
                )
                .transition(.opacity)
            }
        }
        .animation(ProMotionSprings.snappy, value: viewModel.filterState.activeTokens.isEmpty)
    }

    private var chips: some View {
        HStack(spacing: 8) {
            SwipeScopeChip(title: "All", isSelected: currentTriage == .all) {
                apply(.all)
            }
            SwipeScopeChip(
                title: "Unstudied",
                count: viewModel.summary.unstudiedCount,
                isSelected: currentTriage == .unstudied
            ) {
                apply(.unstudied)
            }
            SwipeScopeChip(
                title: "High score",
                count: viewModel.summary.highScoreCount,
                isSelected: currentTriage == .highScore
            ) {
                apply(.highScore)
            }
            Spacer(minLength: 0)
        }
    }

    private func apply(_ triage: Triage) {
        withAnimation(ProMotionSprings.snappy) {
            switch triage {
            case .all:
                viewModel.filterState.onlyUnstudied = false
                viewModel.filterState.minimumHookScore = nil
            case .unstudied:
                viewModel.filterState.onlyUnstudied = true
                viewModel.filterState.onlyStudied = false
                viewModel.filterState.minimumHookScore = nil
            case .highScore:
                viewModel.filterState.minimumHookScore = 7.5
                viewModel.filterState.onlyUnstudied = false
            }
        }
    }
}
