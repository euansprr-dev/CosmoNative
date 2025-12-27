// CosmoOS/Settings/SettingsView.swift
// Beautiful settings panel styled like Command Palette
// Configurable voice keybind and other preferences

import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    @State private var selectedTab: SettingsTab = .voice
    @State private var selectedHotkeyIndex: Int = 0

    enum SettingsTab: String, CaseIterable {
        case voice = "Voice"
        case aiDiagnostics = "AI Status"
        case apiKeys = "API Keys"
        case appearance = "Appearance"
        case shortcuts = "Shortcuts"
        case about = "About"

        var icon: String {
            switch self {
            case .voice: return "waveform"
            case .aiDiagnostics: return "brain"
            case .apiKeys: return "key.fill"
            case .appearance: return "paintbrush"
            case .shortcuts: return "keyboard"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            settingsHeader

            // Subtle divider
            Rectangle()
                .fill(CosmoColors.glassGrey.opacity(0.4))
                .frame(height: 1)

            // Content
            HStack(spacing: 0) {
                // Sidebar
                settingsSidebar

                // Subtle vertical divider
                Rectangle()
                    .fill(CosmoColors.glassGrey.opacity(0.3))
                    .frame(width: 1)

                // Main content
                settingsContent
            }
        }
        .frame(width: 620, height: 480)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(CosmoColors.softWhite)
                .shadow(color: Color.black.opacity(0.08), radius: 1, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(CosmoColors.glassGrey.opacity(0.6), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 30, y: 15)
        .onAppear {
            // Find current hotkey in list
            let currentHotkey = HotkeyManager.shared.currentHotkey
            if let index = HotkeyConfig.alternativeHotkeys.firstIndex(where: { $0 == currentHotkey }) {
                selectedHotkeyIndex = index
            }
        }
        .onKeyPress(.escape) {
            withAnimation(.spring(response: 0.2)) {
                isPresented = false
            }
            return .handled
        }
    }

    // MARK: - Header
    private var settingsHeader: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(CosmoColors.cosmoAI)

                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(CosmoColors.textPrimary)
            }

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.2)) {
                    isPresented = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(CosmoColors.textTertiary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(CosmoColors.glassGrey.opacity(0.3))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Sidebar
    private var settingsSidebar: some View {
        VStack(spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(selectedTab == tab ? CosmoColors.cosmoAI : CosmoColors.textSecondary)
                            .frame(width: 20)

                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: selectedTab == tab ? .medium : .regular))
                            .foregroundColor(selectedTab == tab ? CosmoColors.textPrimary : CosmoColors.textSecondary)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedTab == tab ? CosmoColors.lavender.opacity(0.2) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(12)
        .frame(width: 160)
    }

    // MARK: - Content
    @ViewBuilder
    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch selectedTab {
                case .voice:
                    voiceSettings
                case .aiDiagnostics:
                    aiDiagnosticsSettings
                case .apiKeys:
                    apiKeysSettings
                case .appearance:
                    appearanceSettings
                case .shortcuts:
                    shortcutsSettings
                case .about:
                    aboutSettings
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Voice Settings
    private var voiceSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section header
            Text("Voice Activation")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CosmoColors.textPrimary)

            Text("Configure how you activate voice commands")
                .font(.system(size: 13))
                .foregroundColor(CosmoColors.textTertiary)

            // Keybind selector
            VStack(alignment: .leading, spacing: 12) {
                Text("Activation Keybind")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(CosmoColors.textPrimary)

                VStack(spacing: 8) {
                    ForEach(Array(HotkeyConfig.alternativeHotkeys.enumerated()), id: \.offset) { index, hotkey in
                        HotkeyOptionRow(
                            hotkey: hotkey,
                            isSelected: selectedHotkeyIndex == index,
                            onSelect: {
                                selectedHotkeyIndex = index
                                HotkeyManager.shared.currentHotkey = hotkey
                            }
                        )
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(CosmoColors.glassGrey.opacity(0.1))
            )

            // Current keybind display
            HStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 14))
                    .foregroundColor(CosmoColors.cosmoAI)

                Text("Current keybind:")
                    .font(.system(size: 13))
                    .foregroundColor(CosmoColors.textSecondary)

                Text(HotkeyManager.shared.currentHotkey.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(CosmoColors.cosmoAI)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(CosmoColors.lavender.opacity(0.2))
                    )
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - AI Diagnostics Settings
    private var aiDiagnosticsSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section header
            Text("Apple Intelligence Status")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CosmoColors.textPrimary)

            Text("Foundation Models diagnostics and status")
                .font(.system(size: 13))
                .foregroundColor(CosmoColors.textTertiary)

            // Status card
            let diagnostics = LocalLLM.shared.getDiagnostics()

            VStack(alignment: .leading, spacing: 16) {
                // Status indicator
                HStack(spacing: 12) {
                    Circle()
                        .fill(diagnostics.sessionInitialized ? Color.green : Color.orange)
                        .frame(width: 12, height: 12)

                    Text(diagnostics.availabilityStatus)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(CosmoColors.textPrimary)

                    Spacer()
                }

                Divider()

                // Info rows
                DiagnosticRow(label: "macOS Version", value: diagnostics.macOSVersion)
                DiagnosticRow(label: "Foundation Models", value: diagnostics.foundationModelsAvailable ? "Available" : "Not Available")
                DiagnosticRow(label: "Session", value: diagnostics.sessionInitialized ? "Initialized" : "Not Initialized")
                DiagnosticRow(label: "Tools Registered", value: "\(diagnostics.toolCount)")

                if let error = diagnostics.lastError {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Error")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(CosmoColors.textTertiary)
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }

                if let recovery = diagnostics.recoverySteps {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recovery Steps")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(CosmoColors.textTertiary)
                        Text(recovery)
                            .font(.system(size: 12))
                            .foregroundColor(CosmoColors.textSecondary)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(CosmoColors.glassGrey.opacity(0.1))
            )

            // Run smoke test button
            Button(action: {
                Task {
                    let (success, message, time) = await LocalLLM.shared.runSmokeTest()
                    print("🧪 Smoke Test: \(success ? "PASSED" : "FAILED")")
                    print("   Message: \(message)")
                    print("   Time: \(Int(time * 1000))ms")
                }
            }) {
                HStack {
                    Image(systemName: "testtube.2")
                    Text("Run Smoke Test")
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(CosmoColors.cosmoAI.opacity(0.15))
                )
                .foregroundColor(CosmoColors.cosmoAI)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - API Keys Settings
    private var apiKeysSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section header
            Text("API Keys")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CosmoColors.textPrimary)

            Text("Configure your API keys for AI features")
                .font(.system(size: 13))
                .foregroundColor(CosmoColors.textTertiary)

            // OpenRouter API Key (Required)
            APIKeyField(
                title: "OpenRouter API Key",
                subtitle: "Required for AI features",
                placeholder: "sk-or-v1-...",
                keyIdentifier: "openrouter",
                isRequired: true,
                getInstructions: """
                1. Visit https://openrouter.ai
                2. Sign up or log in
                3. Go to Keys section
                4. Create a new API key
                """
            )

            // YouTube API Key (Optional)
            APIKeyField(
                title: "YouTube API Key",
                subtitle: "Optional - For enhanced video metadata",
                placeholder: "AIza...",
                keyIdentifier: "youtube",
                isRequired: false,
                getInstructions: """
                1. Visit https://console.cloud.google.com
                2. Create a new project
                3. Enable YouTube Data API v3
                4. Create credentials (API Key)
                """
            )

            // Perplexity API Key (Optional)
            APIKeyField(
                title: "Perplexity API Key",
                subtitle: "Optional - For research features",
                placeholder: "pplx-...",
                keyIdentifier: "perplexity",
                isRequired: false,
                getInstructions: """
                1. Visit https://www.perplexity.ai
                2. Sign up or log in
                3. Go to API settings
                4. Generate a new API key
                """
            )

            Spacer()
        }
    }

    // MARK: - Appearance Settings
    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Appearance")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CosmoColors.textPrimary)

            Text("Customize the look and feel")
                .font(.system(size: 13))
                .foregroundColor(CosmoColors.textTertiary)

            // Placeholder for future appearance settings
            HStack(spacing: 12) {
                Image(systemName: "paintbrush.pointed")
                    .font(.system(size: 32))
                    .foregroundColor(CosmoColors.lavender)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Coming Soon")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(CosmoColors.textPrimary)

                    Text("Theme customization and visual preferences")
                        .font(.system(size: 12))
                        .foregroundColor(CosmoColors.textTertiary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(CosmoColors.glassGrey.opacity(0.1))
            )

            Spacer()
        }
    }

    // MARK: - Shortcuts Settings
    private var shortcutsSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Keyboard Shortcuts")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CosmoColors.textPrimary)

            Text("Quick reference for all shortcuts")
                .font(.system(size: 13))
                .foregroundColor(CosmoColors.textTertiary)

            VStack(spacing: 0) {
                ShortcutRow(keys: "⌘K", description: "Open Command Palette")
                ShortcutRow(keys: HotkeyManager.shared.currentHotkey.displayName, description: "Activate Voice")
                ShortcutRow(keys: "⌘N", description: "New Idea")
                ShortcutRow(keys: "⌘T", description: "New Task")
                ShortcutRow(keys: "⌘,", description: "Open Settings")
                ShortcutRow(keys: "Esc", description: "Close Panel / Cancel")
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(CosmoColors.glassGrey.opacity(0.1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Spacer()
        }
    }

    // MARK: - About Settings
    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("About Cosmo")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CosmoColors.textPrimary)

            VStack(spacing: 16) {
                // App icon and name
                VStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [CosmoColors.cosmoAI, CosmoColors.lavender],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("CosmoOS")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(CosmoColors.textPrimary)

                    Text("Your AI-powered second brain")
                        .font(.system(size: 13))
                        .foregroundColor(CosmoColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)

                // Version info
                HStack {
                    Text("Version")
                        .font(.system(size: 13))
                        .foregroundColor(CosmoColors.textSecondary)
                    Spacer()
                    Text("1.0.0 (Local First)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CosmoColors.textPrimary)
                }
                .padding(.horizontal, 16)

                HStack {
                    Text("Built for")
                        .font(.system(size: 13))
                        .foregroundColor(CosmoColors.textSecondary)
                    Spacer()
                    Text("Apple Silicon")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CosmoColors.textPrimary)
                }
                .padding(.horizontal, 16)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(CosmoColors.glassGrey.opacity(0.1))
            )

            Spacer()
        }
    }
}

// MARK: - Hotkey Option Row
struct HotkeyOptionRow: View {
    let hotkey: HotkeyConfig
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                // Radio button
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? CosmoColors.cosmoAI : CosmoColors.textTertiary)

                // Keybind display
                Text(hotkey.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(CosmoColors.textPrimary)
                    .frame(width: 80, alignment: .leading)

                // Description
                Text(descriptionForHotkey(hotkey))
                    .font(.system(size: 12))
                    .foregroundColor(CosmoColors.textTertiary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? CosmoColors.lavender.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? CosmoColors.cosmoAI.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func descriptionForHotkey(_ hotkey: HotkeyConfig) -> String {
        switch hotkey.displayName {
        case "⌥Z": return "Option + Z (Recommended)"
        case "⇧Space": return "Shift + Space"
        case "⇧⌥Space": return "Shift + Option + Space"
        case "⌥.": return "Option + Period"
        case "⌃⇧S": return "Control + Shift + S"
        default: return ""
        }
    }
}

// MARK: - Shortcut Row
struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(CosmoColors.cosmoAI)
                .frame(width: 80, alignment: .leading)

            Text(description)
                .font(.system(size: 13))
                .foregroundColor(CosmoColors.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.clear)
        .overlay(
            Rectangle()
                .fill(CosmoColors.glassGrey.opacity(0.3))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - API Key Field
struct APIKeyField: View {
    let title: String
    let subtitle: String
    let placeholder: String
    let keyIdentifier: String
    let isRequired: Bool
    let getInstructions: String

    @State private var apiKey: String = ""
    @State private var isSecure: Bool = true
    @State private var showInstructions: Bool = false
    @State private var showSuccess: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(CosmoColors.textPrimary)

                        if isRequired {
                            Text("Required")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(CosmoColors.cosmoAI)
                                )
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(CosmoColors.textTertiary)
                }

                Spacer()

                Button(action: {
                    showInstructions.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 12))
                        Text("How to get")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(CosmoColors.cosmoAI)
                }
                .buttonStyle(.plain)
            }

            // Input field
            HStack(spacing: 8) {
                if isSecure {
                    SecureField(placeholder, text: $apiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(CosmoColors.textPrimary)
                } else {
                    TextField(placeholder, text: $apiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(CosmoColors.textPrimary)
                }

                Button(action: {
                    isSecure.toggle()
                }) {
                    Image(systemName: isSecure ? "eye.slash" : "eye")
                        .font(.system(size: 13))
                        .foregroundColor(CosmoColors.textSecondary)
                }
                .buttonStyle(.plain)

                if !apiKey.isEmpty {
                    Button(action: saveAPIKey) {
                        Image(systemName: showSuccess ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(showSuccess ? .green : CosmoColors.cosmoAI)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(CosmoColors.glassGrey.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(CosmoColors.glassGrey.opacity(0.3), lineWidth: 1)
            )

            // Instructions
            if showInstructions {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to get your API key:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(CosmoColors.textPrimary)

                    Text(getInstructions)
                        .font(.system(size: 11))
                        .foregroundColor(CosmoColors.textSecondary)
                        .lineSpacing(4)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(CosmoColors.lavender.opacity(0.1))
                )
            }

            // Status indicator
            if let stored = getStoredKey(), !stored.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)

                    Text("API key saved")
                        .font(.system(size: 12))
                        .foregroundColor(CosmoColors.textSecondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(CosmoColors.glassGrey.opacity(0.1))
        )
        .onAppear {
            // Load existing key (masked)
            if let stored = getStoredKey(), !stored.isEmpty {
                // Show masked version
                apiKey = String(repeating: "•", count: min(stored.count, 40))
            }
        }
    }

    private func getStoredKey() -> String? {
        switch keyIdentifier {
        case "openrouter":
            return APIKeys.openRouter
        case "youtube":
            return APIKeys.youtube
        case "perplexity":
            return APIKeys.perplexity
        default:
            return nil
        }
    }

    private func saveAPIKey() {
        // Don't save if it's the masked version
        if apiKey.allSatisfy({ $0 == "•" }) {
            return
        }

        // Save to keychain
        APIKeys.save(apiKey, identifier: keyIdentifier)

        // Show success
        withAnimation(.easeInOut(duration: 0.2)) {
            showSuccess = true
        }

        // Hide success after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showSuccess = false
            }
        }
    }
}

// MARK: - Diagnostic Row
struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(CosmoColors.textTertiary)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(CosmoColors.textPrimary)
        }
    }
}

// MARK: - Preview
// #Preview {
//     SettingsView(isPresented: .constant(true))
// }
