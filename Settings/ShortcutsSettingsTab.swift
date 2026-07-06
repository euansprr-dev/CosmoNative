// CosmoOS/Settings/ShortcutsSettingsTab.swift
// Complete keyboard shortcuts reference for Sanctuary Settings

import SwiftUI

struct ShortcutsSettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Keyboard Shortcuts")
                .font(DS.title2)
                .foregroundStyle(DS.text)

            Text("Quick reference for all shortcuts")
                .font(DS.navTitle)
                .foregroundStyle(DS.textMuted)

            generalSection
            navigationSection
            voiceSection
            canvasSection
            editingSection
            aiWritingSection
            commandKSection
            menusSection

            Spacer()
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "GENERAL", icon: "command.square.fill", color: DS.accent)

            VStack(spacing: 0) {
                shortcutRow(keys: "\u{2318}K", description: "Open Command Palette")
                shortcutRow(keys: HotkeyManager.shared.captureHotkey.displayName, description: "Capture Anywhere (from any app)")
                shortcutRow(keys: "\u{2318},", description: "Settings")
                shortcutRow(keys: "\u{2318}N", description: "New Idea")
                shortcutRow(keys: "\u{2318}T", description: "New Task")
                shortcutRow(keys: "Esc", description: "Close Panel / Dismiss")
                shortcutRow(keys: "\u{2318}Q", description: "Quit Cosmo")
            }
            .background(glassCard)
            .clipShape(.rect(cornerRadius: DS.radiusMedium))
        }
    }

    // MARK: - Navigation

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "NAVIGATION", icon: "arrow.triangle.turn.up.right.diamond.fill", color: DS.green)

            VStack(spacing: 0) {
                shortcutRow(keys: "P", description: "Command Center (when not typing)")
                shortcutRow(keys: "T", description: "Thinkspace (when not typing)")
                shortcutRow(keys: "L", description: "Library (when not typing)")
                shortcutRow(keys: "N", description: "Quick-add Task (Command Center)")
                shortcutRow(keys: "S", description: "Start Deep Work Session (Command Center)")
                shortcutRow(keys: "\u{2318}\\", description: "Toggle Sidebar")
                shortcutRow(keys: "\u{2318}\u{21E7}C", description: "Open Command Bar")
            }
            .background(glassCard)
            .clipShape(.rect(cornerRadius: DS.radiusMedium))
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "VOICE", icon: "waveform", color: DS.orange)

            VStack(spacing: 0) {
                shortcutRow(keys: HotkeyManager.shared.currentHotkey.displayName, description: "Activate Voice")
                shortcutRow(keys: "\u{2318}\u{21E7}S", description: "Swipe File Capture")
                shortcutRow(keys: "\u{2325}A", description: "Toggle Cosmo Window")
            }
            .background(glassCard)
            .clipShape(.rect(cornerRadius: DS.radiusMedium))
        }
    }

    // MARK: - Canvas

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "CANVAS", icon: "rectangle.on.rectangle.angled", color: DS.info)

            VStack(spacing: 0) {
                shortcutRow(keys: "\u{2318}\u{21E7}H", description: "Toggle Crystallization Heatmap")
                shortcutRow(keys: "\u{2318}\u{21E7}K", description: "Toggle Knowledge Panel")
                shortcutRow(keys: "\u{2318}\u{21E7}P", description: "Provocation Scan")
                shortcutRow(keys: "\u{2318}[", description: "Previous Concept")
                shortcutRow(keys: "\u{2318}]", description: "Next Concept")
                shortcutRow(keys: "+ / =", description: "Zoom In")
                shortcutRow(keys: "-", description: "Zoom Out")
                shortcutRow(keys: "\u{2318}0", description: "Reset Zoom")
            }
            .background(glassCard)
            .clipShape(.rect(cornerRadius: DS.radiusMedium))
        }
    }

    // MARK: - Editing

    private var editingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "EDITING", icon: "pencil.and.outline", color: DS.accent)

            VStack(spacing: 0) {
                shortcutRow(keys: "\u{2318}B", description: "Bold")
                shortcutRow(keys: "\u{2318}I", description: "Italic")
                shortcutRow(keys: "\u{2318}U", description: "Underline")
                shortcutRow(keys: "\u{2318}1", description: "Heading 1")
                shortcutRow(keys: "\u{2318}2", description: "Heading 2")
                shortcutRow(keys: "\u{2318}Z", description: "Undo")
                shortcutRow(keys: "\u{2318}\u{21E7}Z", description: "Redo")
                shortcutRow(keys: "\u{2318}X", description: "Cut")
                shortcutRow(keys: "\u{2318}C", description: "Copy")
                shortcutRow(keys: "\u{2318}V", description: "Paste")
                shortcutRow(keys: "\u{2318}A", description: "Select All")
            }
            .background(glassCard)
            .clipShape(.rect(cornerRadius: DS.radiusMedium))
        }
    }

    // MARK: - AI Writing

    private var aiWritingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "AI WRITING", icon: "sparkles", color: DS.green)

            VStack(spacing: 0) {
                shortcutRow(keys: "\u{2318}\u{21E7}E", description: "Expand Selection")
                shortcutRow(keys: "\u{2318}\u{21E7}C", description: "Condense Selection")
                shortcutRow(keys: "\u{2318}\u{21E7}R", description: "Rephrase Selection")
                shortcutRow(keys: "\u{2318}\u{21E7}\u{21A9}", description: "Continue Writing")
                shortcutRow(keys: "\u{2318}\u{21A9}", description: "Send AI Message")
            }
            .background(glassCard)
            .clipShape(.rect(cornerRadius: DS.radiusMedium))
        }
    }

    // MARK: - Command-K

    private var commandKSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "COMMAND-K", icon: "magnifyingglass", color: DS.info)

            VStack(spacing: 0) {
                shortcutRow(keys: "\u{2191} / \u{2193}", description: "Navigate Results")
                shortcutRow(keys: "\u{21A9}", description: "Open Selected")
                shortcutRow(keys: "\u{21E5}", description: "Switch Tabs")
                shortcutRow(keys: "Esc", description: "Close")
            }
            .background(glassCard)
            .clipShape(.rect(cornerRadius: DS.radiusMedium))
        }
    }

    // MARK: - Menus & Popups

    private var menusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "MENUS & POPUPS", icon: "contextualmenu.and.cursorarrow", color: DS.orange)

            VStack(spacing: 0) {
                shortcutRow(keys: "\u{2191} / \u{2193}", description: "Navigate Items")
                shortcutRow(keys: "\u{21A9}", description: "Select Item")
                shortcutRow(keys: "Esc", description: "Close Menu")
                shortcutRow(keys: "\u{21E5}", description: "Next Item")
            }
            .background(glassCard)
            .clipShape(.rect(cornerRadius: DS.radiusMedium))
        }
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(DS.sectionLabel)
                .foregroundStyle(color)

            Text(title)
                .dsSmallCapsLabel()
        }
    }

    @ViewBuilder
    private func shortcutRow(keys: String, description: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(DS.accent)
                .frame(width: 140, alignment: .leading)

            Text(description)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)

            Spacer()
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
        .overlay(
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var glassCard: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium)
            .fill(DS.glassCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(DS.glassBorder, lineWidth: 1)
            )
    }
}
