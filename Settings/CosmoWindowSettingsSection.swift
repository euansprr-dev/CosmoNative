// CosmoOS/Settings/CosmoWindowSettingsSection.swift
// Settings UI for the global Cosmo floating window
// February 2026

import SwiftUI

struct CosmoWindowSettingsSection: View {
    @StateObject private var viewModel = CosmoWindowViewModel.shared

    @AppStorage("cosmoWindowKeybind") private var keybind = "A"
    @AppStorage("cosmoWindowAnchor") private var anchorRaw = CosmoWindowAnchor.right.rawValue
    @AppStorage("cosmoWindowEnabled") private var cosmoWindowEnabled = false

    @State private var isWindowExpanded = false
    @State private var isConversationExpanded = false
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section: Window Settings
            windowSettingsSection

            // Section: Conversation Management
            conversationSection

            // Section: Skills info
            skillsInfoRow
        }
    }

    // MARK: - Window Settings

    private var windowSettingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsibleHeader(
                title: "Cosmo Window",
                subtitle: cosmoWindowEnabled ? "Enabled" : "Disabled",
                icon: "bubble.left.and.text.bubble.right",
                isExpanded: $isWindowExpanded,
                statusColor: cosmoWindowEnabled ? .green : nil
            )

            if isWindowExpanded {
                VStack(spacing: 12) {
                    // Feature toggle
                    Toggle(isOn: $cosmoWindowEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use Global Cosmo Window")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(DS.text)
                            Text("Press Option+A from any screen to chat with Cosmo")
                                .font(.system(size: 11))
                                .foregroundColor(DS.textSecondary)
                        }
                    }
                    .toggleStyle(.switch)

                    Divider()
                        .background(DS.border)

                    // Window position
                    HStack {
                        Text("Window Position")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DS.text)

                        Spacer()

                        Picker("", selection: $anchorRaw) {
                            Text("Right").tag(CosmoWindowAnchor.right.rawValue)
                            Text("Left").tag(CosmoWindowAnchor.left.rawValue)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }

                    // Keyboard shortcut display
                    HStack {
                        Text("Toggle Shortcut")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DS.text)

                        Spacer()

                        Text("Option + A")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(DS.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(DS.surfaceElevated)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(DS.border, lineWidth: 1)
                            )
                    }
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(DS.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Conversation Section

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsibleHeader(
                title: "Conversation",
                subtitle: "\(viewModel.messages.count) messages",
                icon: "text.bubble",
                isExpanded: $isConversationExpanded
            )

            if isConversationExpanded {
                VStack(spacing: 12) {
                    // Token usage
                    HStack {
                        Text("Estimated Token Usage")
                            .font(.system(size: 13))
                            .foregroundColor(DS.textSecondary)

                        Spacer()

                        Text("\(viewModel.estimatedTokenUsage) tokens")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(DS.textSecondary)
                    }

                    // Message count
                    HStack {
                        Text("Messages")
                            .font(.system(size: 13))
                            .foregroundColor(DS.textSecondary)

                        Spacer()

                        Text("\(viewModel.messages.count)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(DS.textSecondary)
                    }

                    Divider()
                        .background(DS.border)

                    // Clear history
                    HStack(spacing: 12) {
                        Button(action: { showClearConfirmation = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                                Text("Clear History")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(DS.red.opacity(0.15)))
                            .foregroundColor(DS.red)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .alert("Clear Conversation?", isPresented: $showClearConfirmation) {
                        Button("Cancel", role: .cancel) {}
                        Button("Clear", role: .destructive) {
                            Task { await viewModel.clearConversation() }
                        }
                    } message: {
                        Text("This will permanently delete the Cosmo window conversation history.")
                    }
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(DS.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Skills Info Row

    private var skillsInfoRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 14))
                .foregroundColor(DS.accent)
                .frame(width: 20)

            Text("Learned skills are managed in Settings \u{2192} Skills & Prompts.")
                .font(.system(size: 13))
                .foregroundColor(DS.textMuted)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(DS.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.border, lineWidth: 1))
    }

    // MARK: - Collapsible Header

    @ViewBuilder
    private func collapsibleHeader(
        title: String,
        subtitle: String,
        icon: String,
        isExpanded: Binding<Bool>,
        statusColor: Color? = nil
    ) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(DS.accent)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.text)

                if let color = statusColor {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }

                Spacer()

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(DS.textMuted)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textMuted)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}
