// CosmoOS/UI/Inbox/InboxCaptureBar.swift
// Always-visible quick capture field at the top of the inbox
// March 2026

import SwiftUI

struct InboxCaptureBar: View {
    @Bindable var viewModel: InboxViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DS.space8) {
            captureIcon
            captureField
            trailingActions
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, viewModel.isCaptureExpanded ? DS.space10 : DS.space8)
        .background(DS.surfaceCard, in: RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .stroke(isFocused ? DS.accent.opacity(0.3) : DS.border, lineWidth: 1)
        )
        .dsRestingShadow()
        .animation(ProMotionSprings.snappy, value: isFocused)
        .animation(ProMotionSprings.snappy, value: viewModel.isCaptureExpanded)
    }

    // MARK: - Subviews

    private var captureIcon: some View {
        Image(systemName: viewModel.showCaptureConfirmation ? "checkmark.circle.fill" : "plus.circle")
            .font(.system(size: 16))
            .foregroundStyle(viewModel.showCaptureConfirmation ? DS.accent : DS.textMuted)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 20)
    }

    @ViewBuilder
    private var captureField: some View {
        if viewModel.isCaptureExpanded {
            expandedEditor
        } else {
            singleLineField
        }
    }

    private var singleLineField: some View {
        TextField("Capture a thought...", text: $viewModel.captureText)
            .textFieldStyle(.plain)
            .font(DS.body)
            .foregroundStyle(DS.text)
            .focused($isFocused)
            .onSubmit {
                Task { await viewModel.submitCapture() }
            }
    }

    private var expandedEditor: some View {
        TextEditor(text: $viewModel.captureText)
            .font(DS.body)
            .foregroundStyle(DS.text)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 60, maxHeight: 100)
            .focused($isFocused)
    }

    private var trailingActions: some View {
        HStack(spacing: DS.space4) {
            // Expand/collapse toggle
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.isCaptureExpanded.toggle()
                }
            } label: {
                Image(systemName: viewModel.isCaptureExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(viewModel.isCaptureExpanded ? "Collapse" : "Expand")

            // Submit button (visible when there's text)
            if !viewModel.captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    Task { await viewModel.submitCapture() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(DS.accent)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(ProMotionSprings.snappy, value: viewModel.captureText.isEmpty)
    }
}
