// CosmoOS/UI/FocusMode/Inquiry/InquiryCrystallizeSheet.swift
// Modal sheet wrapping the Inquiry crystallization review. Thin shell —
// the review owns the masthead, content, and sticky action bar.

import SwiftUI

@MainActor
struct InquiryCrystallizeSheet: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let onDismiss: () -> Void

    var body: some View {
        InquiryCrystallizationReviewV2(viewModel: viewModel, onDismiss: onDismiss)
            .frame(minWidth: 880, minHeight: 620)
            .background(DS.bg)
            .background(
                // Esc returns to Explore without promoting anything.
                Button("", action: onDismiss)
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.plain)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            )
    }
}
