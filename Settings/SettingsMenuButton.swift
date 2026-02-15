// CosmoOS/Settings/SettingsMenuButton.swift
// Minimal settings button for top-right corner
// On-brand with Cosmo's clean, premium aesthetic

import SwiftUI

struct SettingsMenuButton: View {
    @Binding var showSettings: Bool
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showSettings = true
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isHovered ? CosmoColors.cosmoAI : CosmoColors.textSecondary)
            }
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? CosmoColors.lavender.opacity(0.2) : CosmoColors.glassGrey.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(CosmoColors.glassGrey.opacity(isHovered ? 0.4 : 0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help("Settings (⌘,)")
    }
}

// MARK: - Settings Menu (Full dropdown variant)
struct SettingsDropdownMenu: View {
    @Binding var showSettings: Bool
    @State private var isHovered = false
    @State private var showMenu = false

    var body: some View {
        Menu {
            Button(action: {
                showSettings = true
            }) {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button(action: {
                // Request accessibility permission
                HotkeyManager.shared.requestAccessibilityPermission()
            }) {
                Label("Voice Permissions", systemImage: "waveform")
            }

            Divider()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit Cosmo", systemImage: "power")
            }
            .keyboardShortcut("Q", modifiers: .command)

        } label: {
            HStack(spacing: 6) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isHovered ? CosmoColors.cosmoAI : CosmoColors.textSecondary)
            }
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? CosmoColors.lavender.opacity(0.2) : CosmoColors.glassGrey.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(CosmoColors.glassGrey.opacity(isHovered ? 0.4 : 0.2), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Top Right Controls (combines settings + other buttons)
struct TopRightControls: View {
    @Binding var showCommandK: Bool
    @EnvironmentObject var voiceEngine: VoiceEngine

    @State private var voiceHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Voice activation: push-to-talk on press (Wispr-like), double-click toggles as fallback
            VoiceActivationButton(isHovered: $voiceHovered)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    voiceHovered = hovering
                }
            }
            .help("Hold to speak (\(HotkeyManager.shared.currentHotkey.displayName))")
        }
    }
}

// MARK: - Voice Activation Button (Toggle)
private struct VoiceActivationButton: View {
    @EnvironmentObject var voiceEngine: VoiceEngine
    @Binding var isHovered: Bool

    var body: some View {
        // Cache recording state locally to avoid crashes during re-renders
        let isRecording = voiceEngine.isRecording

        // Simple toggle button - click to start, click again to stop
        // Push-to-talk works via keyboard hotkey (Option+Z or configured key)
        Button {
            // Toggle voice recording - NO async work here to avoid crashes
            toggleVoice()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isRecording ? "waveform" : "mic")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isRecording ? CosmoColors.coral : (isHovered ? CosmoColors.cosmoAI : CosmoColors.textSecondary))

                Text(HotkeyManager.shared.currentHotkey.displayName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(isHovered ? CosmoColors.textPrimary : CosmoColors.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isRecording
                          ? CosmoColors.coral.opacity(0.15)
                          : (isHovered ? CosmoColors.lavender.opacity(0.2) : CosmoColors.glassGrey.opacity(0.15)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        isRecording
                        ? CosmoColors.coral.opacity(0.4)
                        : CosmoColors.glassGrey.opacity(isHovered ? 0.4 : 0.2),
                        lineWidth: 0.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice")
        .accessibilityHint("Click to toggle recording. Hold \(HotkeyManager.shared.currentHotkey.displayName) for push-to-talk.")
    }

    /// Toggle voice recording using DispatchQueue to avoid Swift concurrency crashes
    private func toggleVoice() {
        // Use DispatchQueue.main.async instead of Task to avoid concurrency runtime issues
        DispatchQueue.main.async {
            let engine = VoiceEngine.shared
            if engine.isRecording {
                print("🎤 Voice button: CLICK - stopping recording")
                Task { @MainActor in
                    await engine.stopRecording()
                }
            } else {
                print("🎤 Voice button: CLICK - starting recording")
                Task { @MainActor in
                    await engine.startRecording()
                }
            }
        }
    }
}

// MARK: - Preview
// #Preview {
//     HStack {
//         SettingsMenuButton(showSettings: .constant(false))
//         SettingsDropdownMenu(showSettings: .constant(false))
//     }
//     .padding()
//     .background(CosmoColors.softWhite)
// }
