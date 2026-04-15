// CosmoOS/UI/FocusMode/CosmoAI/CosmoAIConversationPanel.swift
// Message list component for Cosmo AI Focus Mode
// Uses CosmoMessageBubble (shared with CosmoWindow) and ToolActivityStreamView
// February 2026

import SwiftUI

struct CosmoAIConversationPanel: View {
    @ObservedObject var viewModel: CosmoAIFocusModeViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Welcome message if empty
                    if viewModel.messages.isEmpty {
                        welcomeMessage
                    }

                    ForEach(viewModel.messages) { message in
                        CosmoMessageBubble(message: message)
                            .id(message.id)
                    }

                    // Live tool activity during processing
                    if viewModel.isProcessing && (!viewModel.liveToolActivity.isEmpty || viewModel.activeToolLabel != nil) {
                        ToolActivityStreamView(
                            groups: viewModel.liveToolActivity,
                            activeLabel: viewModel.activeToolLabel
                        )
                        .padding(.horizontal, 16)
                        .transition(.opacity)
                        .id("tool-activity")
                    }

                    // Typing indicator as fallback
                    if viewModel.isProcessing && viewModel.liveToolActivity.isEmpty && viewModel.activeToolLabel == nil {
                        FocusModeTypingIndicator()
                            .id("typing")
                    }

                    // Bottom anchor for scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(20)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation(.spring(response: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.liveToolActivity.count) { _, _ in
                withAnimation(.spring(response: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Welcome Message

    private var welcomeMessage: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 60)

            ZStack {
                Circle()
                    .fill(DS.giltSoft)
                    .frame(width: 56, height: 56)
                Image(systemName: "brain")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(DS.gilt)
            }

            Text("Cosmo AI")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DS.text)

            Text("Full agent access — search, create, analyze, write.\nUse @ to reference any atom as context.")
                .font(.system(size: 13))
                .foregroundColor(DS.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()
                .frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Typing Indicator (Focus Mode version)

private struct FocusModeTypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(DS.accent.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "brain")
                    .font(.system(size: 12))
                    .foregroundColor(DS.accent)
            }

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(DS.accent)
                        .frame(width: 6, height: 6)
                        .opacity(animating ? 1 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(DS.surface))

            Spacer()
        }
        .onAppear { animating = true }
    }
}
