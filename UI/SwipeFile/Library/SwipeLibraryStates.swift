import SwiftUI

/// Empty states that teach the next action — never "No items yet."
struct SwipeLibraryEmptyState: View {
    let scope: SwipeLibrarySectionSelection
    let hasActiveFilters: Bool
    let onClearFilters: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "bookmark")
                .font(DS.pageTitle)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text(title)
                .font(DS.headline)
                .foregroundStyle(DS.textSecondary)
            Text(message)
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
            if hasActiveFilters {
                Button("Clear filters", action: onClearFilters)
                    .buttonStyle(.plain)
                    .font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 90)
    }

    private var title: String {
        if hasActiveFilters { return "No swipes match" }
        switch scope {
        case .board: return "This board is empty"
        case .unstudied: return "Everything is studied"
        default: return "Your swipe file is empty"
        }
    }

    private var message: String {
        if hasActiveFilters { return "Clear a filter or search another hook style." }
        switch scope {
        case .board: return "Hover any swipe and press the bookmark to file it here."
        case .unstudied: return "New captures land here until you open them in Study."
        default: return "Press ⌘K to capture a post, or save one from Discover."
        }
    }
}

struct SwipeLibraryErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(DS.title2)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text(message)
                .font(DS.subheadline)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: onRetry)
                .buttonStyle(.plain)
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(DS.accent)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 90)
    }
}
