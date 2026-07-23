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

// MARK: - Preview
// #Preview {
//     HStack {
//         SettingsMenuButton(showSettings: .constant(false))
//         SettingsDropdownMenu(showSettings: .constant(false))
//     }
//     .padding()
//     .background(CosmoColors.softWhite)
// }
