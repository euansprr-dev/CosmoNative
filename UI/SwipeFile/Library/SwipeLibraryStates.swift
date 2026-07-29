import SwiftUI

/// Empty states that teach the next action — never "No items yet."
struct SwipeLibraryEmptyState: View {
    let scope: SwipeLibrarySectionSelection
    let hasActiveFilters: Bool
    let onClearFilters: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle" : emptyIcon)
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

    private var emptyIcon: String {
        if case .genre(let genre) = scope { return genre.iconName }
        return "bookmark"
    }

    private var title: String {
        if hasActiveFilters { return "No swipes match" }
        switch scope {
        case .board: return "This board is empty"
        case .unstudied: return "Everything is studied"
        case .genre(let genre): return "No \(genre.pluralName.lowercased()) yet"
        default: return "Your swipe file is empty"
        }
    }

    /// Genre rooms teach their own front door — the empty state IS the
    /// capture education for that medium.
    private var message: String {
        if hasActiveFilters { return "Clear a filter or search another hook style." }
        switch scope {
        case .board: return "Hover any swipe and press the bookmark to file it here."
        case .unstudied: return "New captures land here until you open them in Study."
        case .genre(.newsletter):
            return "⌘⇧S any Substack or beehiiv issue — Cosmo slices and reads it."
        case .genre(.funnel):
            return "Start recording a funnel, then swipe each page you walk through — every capture becomes a step."
        case .genre(.landingPage), .genre(.salesPage):
            return "⌘⇧S while looking at any page in the browser pane captures it whole — your session, past the opt-in."
        case .genre(.ad):
            return "Swipe ad-library pages or drop ad screenshots — they file here."
        case .genre(.script):
            return "Paste a full script with ⌘⇧S — it files here once Cosmo reads it."
        case .genre(.copy):
            return "⌘⇧S with text on the clipboard saves it as swiped copy."
        case .genre(.screenshot):
            return "⌥⌘⇧S grabs a region of your screen; drops and pasted images land here too."
        case .genre:
            return "⌘⇧S captures whatever you're looking at — Cosmo files it by what it is."
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
