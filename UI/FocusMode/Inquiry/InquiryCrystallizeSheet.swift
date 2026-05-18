// CosmoOS/UI/FocusMode/Inquiry/InquiryCrystallizeSheet.swift
// Modal sheet wrapping the existing InquiryReviewView (Crystallize phase).

import SwiftUI

@MainActor
struct InquiryCrystallizeSheet: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(DS.borderSubtle)
            InquiryReviewView(viewModel: viewModel)
        }
        .frame(minWidth: 880, minHeight: 620)
        .background(DS.bg)
    }

    private var header: some View {
        HStack(spacing: DS.space12) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            Text("Crystallize")
                .font(.system(.title2, design: .serif))
                .foregroundStyle(CosmoColors.textPrimary)
            Spacer()
            Button {
                onDismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Back to Explore")
                        .font(CosmoTypography.label)
                }
                .foregroundStyle(CosmoColors.textSecondary)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, 6)
                .background(DS.surface, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Back to Explore phase")
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space16)
    }
}
