// CosmoOS/Settings/SanctuarySettingsView.swift
// Consolidated Settings Hub — unified settings for all CosmoOS configuration
// Replaces both SanctuarySettingsView (connections) and SettingsView (voice, API keys, etc.)
// Opened from SanctuaryView's gear icon as a .sheet with frame(width: 720, height: 540)

import SwiftUI

// MARK: - Connection Status

enum ConnectionStatus: String {
    case connected
    case notConnected

    var label: String {
        switch self {
        case .connected: return "Connected"
        case .notConnected: return "Not Connected"
        }
    }

    var color: Color {
        switch self {
        case .connected: return SanctuaryColors.Semantic.success
        case .notConnected: return SanctuaryColors.Text.muted
        }
    }
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable {
    case connections = "Connections"
    case voice = "Voice"
    case apiKeys = "API Keys"
    case aiStatus = "AI Status"
    case cosmoAgent = "Cosmo Agent"
    case shortcuts = "Shortcuts"
    case about = "About"

    var icon: String {
        switch self {
        case .connections: return "link"
        case .voice: return "waveform"
        case .apiKeys: return "key.fill"
        case .aiStatus: return "brain"
        case .cosmoAgent: return "sparkles.rectangle.stack"
        case .shortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

// MARK: - SanctuarySettingsView

struct SanctuarySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .connections

    // Connections — Health
    @AppStorage("healthKitEnabled") private var healthKitEnabled = false

    // Connections — Social Platforms
    @AppStorage("instagramConnected") private var instagramConnected = false
    @AppStorage("youtubeConnected") private var youtubeConnected = false
    @AppStorage("tiktokConnected") private var tiktokConnected = false
    @AppStorage("xConnected") private var xConnected = false

    // Connections — Knowledge
    @AppStorage("readwiseAPIKey") private var readwiseAPIKey = ""

    // Connections — Screen Time
    @AppStorage("screenTimeEnabled") private var screenTimeEnabled = false

    // Voice
    @State private var selectedHotkeyIndex: Int = 0

    // API Keys
    @State private var openRouterKey: String = ""
    @State private var youtubeAPIKey: String = ""
    @State private var perplexityKey: String = ""

    // AI Diagnostics
    @State private var smokeTestResult: String? = nil
    @State private var isRunningTest = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            // Divider
            Rectangle()
                .fill(SanctuaryColors.Glass.borderSubtle)
                .frame(height: 1)

            // Sidebar + Content
            HStack(spacing: 0) {
                sidebar

                Rectangle()
                    .fill(SanctuaryColors.Glass.borderSubtle)
                    .frame(width: 1)

                content
            }
        }
        .frame(width: 720, height: 540)
        .background(SanctuaryColors.Background.void)
        .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.panel))
        .onAppear {
            // Sync hotkey selection
            let currentHotkey = HotkeyManager.shared.currentHotkey
            if let index = HotkeyConfig.alternativeHotkeys.firstIndex(where: { $0 == currentHotkey }) {
                selectedHotkeyIndex = index
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(SanctuaryTypography.displaySmall)
                .foregroundColor(SanctuaryColors.Text.primary)

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.secondary)
                    .frame(width: 28, height: 28)
                    .background(SanctuaryColors.Glass.primary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SanctuaryLayout.Spacing.lg)
        .padding(.vertical, SanctuaryLayout.Spacing.md)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: SanctuaryLayout.Spacing.xs) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: SanctuaryLayout.Spacing.sm) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(selectedTab == tab ? CosmoColors.cosmoAI : SanctuaryColors.Text.secondary)
                            .frame(width: 20)

                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: selectedTab == tab ? .medium : .regular))
                            .foregroundColor(selectedTab == tab ? SanctuaryColors.Text.primary : SanctuaryColors.Text.secondary)

                        Spacer()
                    }
                    .padding(.horizontal, SanctuaryLayout.Spacing.sm)
                    .padding(.vertical, SanctuaryLayout.Spacing.sm + 2)
                    .background(
                        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                            .fill(selectedTab == tab ? CosmoColors.lavender.opacity(0.2) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(SanctuaryLayout.Spacing.sm)
        .frame(width: 160)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
                switch selectedTab {
                case .connections:
                    connectionsTab
                case .voice:
                    voiceTab
                case .apiKeys:
                    apiKeysTab
                case .aiStatus:
                    aiStatusTab
                case .cosmoAgent:
                    CosmoAgentSettingsTab()
                case .shortcuts:
                    shortcutsTab
                case .about:
                    aboutTab
                }
            }
            .padding(SanctuaryLayout.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Connections Tab
    // ═══════════════════════════════════════════════════════════════

    private var connectionsTab: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xl) {
            // Health Section
            settingsSection(title: "HEALTH", icon: "heart.fill", color: SanctuaryColors.physiological) {
                healthCard
            }

            // Social Platforms Section
            settingsSection(title: "SOCIAL PLATFORMS", icon: "globe", color: SanctuaryColors.creative) {
                VStack(spacing: SanctuaryLayout.Spacing.sm) {
                    comingSoonCard(icon: "camera.fill", name: "Instagram", accentColor: Color(hex: "E1306C"))
                    comingSoonCard(icon: "play.rectangle.fill", name: "YouTube", accentColor: Color(hex: "FF0000"))
                    comingSoonCard(icon: "music.note", name: "TikTok", accentColor: Color(hex: "00F2EA"))
                    comingSoonCard(icon: "at", name: "X", accentColor: SanctuaryColors.Text.primary)
                }
            }

            // Knowledge Section
            settingsSection(title: "KNOWLEDGE", icon: "books.vertical.fill", color: SanctuaryColors.knowledge) {
                readwiseCard
            }

            // Screen Time Section
            settingsSection(title: "SCREEN TIME", icon: "hourglass", color: SanctuaryColors.behavioral) {
                comingSoonCard(icon: "hourglass", name: "Screen Time", accentColor: SanctuaryColors.behavioral)
            }

            Spacer(minLength: SanctuaryLayout.Spacing.lg)
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Voice Tab
    // ═══════════════════════════════════════════════════════════════

    private var voiceTab: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            Text("Voice Activation")
                .font(SanctuaryTypography.titleMedium)
                .foregroundColor(SanctuaryColors.Text.primary)

            Text("Configure how you activate voice commands")
                .font(SanctuaryTypography.bodyMedium)
                .foregroundColor(SanctuaryColors.Text.tertiary)

            // Keybind selector
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
                Text("Activation Keybind")
                    .font(SanctuaryTypography.titleSmall)
                    .foregroundColor(SanctuaryColors.Text.primary)

                VStack(spacing: SanctuaryLayout.Spacing.sm) {
                    ForEach(Array(HotkeyConfig.alternativeHotkeys.enumerated()), id: \.offset) { index, hotkey in
                        hotkeyRow(hotkey: hotkey, isSelected: selectedHotkeyIndex == index) {
                            selectedHotkeyIndex = index
                            HotkeyManager.shared.currentHotkey = hotkey
                        }
                    }
                }
            }
            .padding(SanctuaryLayout.Spacing.md)
            .background(glassCard)

            // Current keybind display
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                Image(systemName: "keyboard")
                    .font(.system(size: 14))
                    .foregroundColor(CosmoColors.cosmoAI)

                Text("Current keybind:")
                    .font(SanctuaryTypography.bodySmall)
                    .foregroundColor(SanctuaryColors.Text.secondary)

                Text(HotkeyManager.shared.currentHotkey.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(CosmoColors.cosmoAI)
                    .padding(.horizontal, SanctuaryLayout.Spacing.sm + 2)
                    .padding(.vertical, SanctuaryLayout.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                            .fill(CosmoColors.lavender.opacity(0.2))
                    )
            }
            .padding(.top, SanctuaryLayout.Spacing.sm)

            Spacer()
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - API Keys Tab
    // ═══════════════════════════════════════════════════════════════

    private var apiKeysTab: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            Text("API Keys")
                .font(SanctuaryTypography.titleMedium)
                .foregroundColor(SanctuaryColors.Text.primary)

            Text("Configure your API keys for AI features")
                .font(SanctuaryTypography.bodyMedium)
                .foregroundColor(SanctuaryColors.Text.tertiary)

            // OpenRouter
            APIKeyCard(
                title: "OpenRouter API Key",
                subtitle: "Required for AI features",
                placeholder: "sk-or-v1-...",
                keyIdentifier: "openrouter",
                isRequired: true,
                instructions: "1. Visit https://openrouter.ai\n2. Sign up or log in\n3. Go to Keys section\n4. Create a new API key"
            )

            // YouTube
            APIKeyCard(
                title: "YouTube API Key",
                subtitle: "Optional - For enhanced video metadata",
                placeholder: "AIza...",
                keyIdentifier: "youtube",
                isRequired: false,
                instructions: "1. Visit https://console.cloud.google.com\n2. Create a new project\n3. Enable YouTube Data API v3\n4. Create credentials (API Key)"
            )

            // Perplexity
            APIKeyCard(
                title: "Perplexity API Key",
                subtitle: "Optional - For research features",
                placeholder: "pplx-...",
                keyIdentifier: "perplexity",
                isRequired: false,
                instructions: "1. Visit https://www.perplexity.ai\n2. Sign up or log in\n3. Go to API settings\n4. Generate a new API key"
            )

            Spacer()
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - AI Status Tab
    // ═══════════════════════════════════════════════════════════════

    private var aiStatusTab: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            Text("Apple Intelligence Status")
                .font(SanctuaryTypography.titleMedium)
                .foregroundColor(SanctuaryColors.Text.primary)

            Text("Foundation Models diagnostics and status")
                .font(SanctuaryTypography.bodyMedium)
                .foregroundColor(SanctuaryColors.Text.tertiary)

            // Diagnostics card
            aiDiagnosticsCard

            // Smoke test button
            Button(action: {
                isRunningTest = true
                smokeTestResult = nil
                Task {
                    let (success, message, time) = await LocalLLM.shared.runSmokeTest()
                    isRunningTest = false
                    smokeTestResult = "\(success ? "PASSED" : "FAILED") - \(message) (\(Int(time * 1000))ms)"
                }
            }) {
                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    if isRunningTest {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "testtube.2")
                    }
                    Text("Run Smoke Test")
                }
                .font(SanctuaryTypography.label)
                .padding(.horizontal, SanctuaryLayout.Spacing.md)
                .padding(.vertical, SanctuaryLayout.Spacing.sm + 2)
                .background(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .fill(CosmoColors.cosmoAI.opacity(0.15))
                )
                .foregroundColor(CosmoColors.cosmoAI)
            }
            .buttonStyle(.plain)
            .disabled(isRunningTest)

            if let result = smokeTestResult {
                HStack(spacing: SanctuaryLayout.Spacing.xs) {
                    Image(systemName: result.hasPrefix("PASSED") ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.hasPrefix("PASSED") ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.danger)
                    Text(result)
                        .font(SanctuaryTypography.bodySmall)
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
            }

            Spacer()
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Shortcuts Tab
    // ═══════════════════════════════════════════════════════════════

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            Text("Keyboard Shortcuts")
                .font(SanctuaryTypography.titleMedium)
                .foregroundColor(SanctuaryColors.Text.primary)

            Text("Quick reference for all shortcuts")
                .font(SanctuaryTypography.bodyMedium)
                .foregroundColor(SanctuaryColors.Text.tertiary)

            VStack(spacing: 0) {
                shortcutRow(keys: "\u{2318}K", description: "Open Command Palette")
                shortcutRow(keys: HotkeyManager.shared.currentHotkey.displayName, description: "Activate Voice")
                shortcutRow(keys: "\u{2318}N", description: "New Idea")
                shortcutRow(keys: "\u{2318}T", description: "New Task")
                shortcutRow(keys: "Esc", description: "Close Panel / Cancel")
            }
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.card)
                    .fill(SanctuaryColors.Glass.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.card)
                            .stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.card))

            Spacer()
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - About Tab
    // ═══════════════════════════════════════════════════════════════

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            Text("About Cosmo")
                .font(SanctuaryTypography.titleMedium)
                .foregroundColor(SanctuaryColors.Text.primary)

            VStack(spacing: SanctuaryLayout.Spacing.md) {
                // App branding
                VStack(spacing: SanctuaryLayout.Spacing.sm) {
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
                        .font(SanctuaryTypography.displaySmall)
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Text("Your AI-powered second brain")
                        .font(SanctuaryTypography.bodyMedium)
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SanctuaryLayout.Spacing.lg)

                // Version info
                HStack {
                    Text("Version")
                        .font(SanctuaryTypography.bodySmall)
                        .foregroundColor(SanctuaryColors.Text.secondary)
                    Spacer()
                    Text("1.0.0 (Local First)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.primary)
                }
                .padding(.horizontal, SanctuaryLayout.Spacing.md)

                HStack {
                    Text("Built for")
                        .font(SanctuaryTypography.bodySmall)
                        .foregroundColor(SanctuaryColors.Text.secondary)
                    Spacer()
                    Text("Apple Silicon")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.primary)
                }
                .padding(.horizontal, SanctuaryLayout.Spacing.md)
            }
            .padding(SanctuaryLayout.Spacing.md)
            .background(glassCard)

            Spacer()
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Connection Tab Components
    // ═══════════════════════════════════════════════════════════════

    @ViewBuilder
    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)

                Text(title)
                    .font(SanctuaryTypography.label)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1.5)
            }

            content()
        }
    }

    private var healthCard: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            Image(systemName: "heart.fill")
                .font(.system(size: 20))
                .foregroundColor(SanctuaryColors.physiological)
                .frame(width: 40, height: 40)
                .background(SanctuaryColors.physiological.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm))

            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Health")
                    .font(SanctuaryTypography.titleSmall)
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("HRV, sleep, heart rate, workouts")
                    .font(SanctuaryTypography.bodySmall)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Spacer()

            statusBadge(for: healthKitEnabled ? .connected : .notConnected)

            Toggle("", isOn: Binding(
                get: { healthKitEnabled },
                set: { newValue in
                    if newValue {
                        // Request real HealthKit authorization
                        Task {
                            await HealthKitQueryService.shared.requestAccess()
                            await MainActor.run {
                                healthKitEnabled = HealthKitQueryService.shared.hasAccess
                            }
                        }
                    } else {
                        healthKitEnabled = false
                    }
                }
            ))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(SanctuaryColors.physiological)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(glassCard)
    }

    @ViewBuilder
    private func comingSoonCard(
        icon: String,
        name: String,
        accentColor: Color
    ) -> some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(accentColor.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm))

            Text(name)
                .font(SanctuaryTypography.titleSmall)
                .foregroundColor(SanctuaryColors.Text.secondary)

            Spacer()

            Text("Coming Soon")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.muted)
                .padding(.horizontal, SanctuaryLayout.Spacing.md)
                .padding(.vertical, SanctuaryLayout.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .fill(SanctuaryColors.Glass.secondary)
                )
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(glassCard)
    }

    private var readwiseCard: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            HStack(spacing: SanctuaryLayout.Spacing.md) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 20))
                    .foregroundColor(SanctuaryColors.knowledge)
                    .frame(width: 40, height: 40)
                    .background(SanctuaryColors.knowledge.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Readwise")
                        .font(SanctuaryTypography.titleSmall)
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Text("Import highlights and reading data")
                        .font(SanctuaryTypography.bodySmall)
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }

                Spacer()

                statusBadge(for: readwiseAPIKey.isEmpty ? .notConnected : .connected)
            }

            SecureField("Readwise API Key", text: $readwiseAPIKey)
                .textFieldStyle(.plain)
                .font(SanctuaryTypography.bodyMedium)
                .foregroundColor(SanctuaryColors.Text.primary)
                .padding(SanctuaryLayout.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .fill(SanctuaryColors.Glass.secondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                .stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1)
                        )
                )
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(glassCard)
    }

    private var screenTimeCard: some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            Image(systemName: "hourglass")
                .font(.system(size: 20))
                .foregroundColor(SanctuaryColors.behavioral)
                .frame(width: 40, height: 40)
                .background(SanctuaryColors.behavioral.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm))

            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Time")
                    .font(SanctuaryTypography.titleSmall)
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("Track app usage and distraction patterns")
                    .font(SanctuaryTypography.bodySmall)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }

            Spacer()

            statusBadge(for: screenTimeEnabled ? .connected : .notConnected)

            Toggle("", isOn: $screenTimeEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(SanctuaryColors.behavioral)
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(glassCard)
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Voice Tab Components
    // ═══════════════════════════════════════════════════════════════

    @ViewBuilder
    private func hotkeyRow(hotkey: HotkeyConfig, isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? CosmoColors.cosmoAI : SanctuaryColors.Text.tertiary)

                Text(hotkey.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)
                    .frame(width: 110, alignment: .leading)

                Text(hotkeyDescription(hotkey))
                    .font(SanctuaryTypography.bodySmall)
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer()
            }
            .padding(.horizontal, SanctuaryLayout.Spacing.sm)
            .padding(.vertical, SanctuaryLayout.Spacing.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                    .fill(isSelected ? CosmoColors.lavender.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                    .stroke(isSelected ? CosmoColors.cosmoAI.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func hotkeyDescription(_ hotkey: HotkeyConfig) -> String {
        switch hotkey.displayName {
        case "\u{2325}Space": return "Option + Space (Recommended)"
        case "\u{2325}Z": return "Option + Z"
        case "\u{21E7}Space": return "Shift + Space"
        case "\u{21E7}\u{2325}Space": return "Shift + Option + Space"
        case "\u{2325}.": return "Option + Period"
        case "\u{2303}\u{21E7}S": return "Control + Shift + S"
        case "Fn (experimental)": return "Fn key (may be intercepted)"
        default: return ""
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - AI Diagnostics Components
    // ═══════════════════════════════════════════════════════════════

    private var aiDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            let diagnostics = LocalLLM.shared.getDiagnostics()

            // Status indicator
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                Circle()
                    .fill(diagnostics.sessionInitialized ? SanctuaryColors.Semantic.success : SanctuaryColors.Semantic.warning)
                    .frame(width: 12, height: 12)

                Text(diagnostics.availabilityStatus)
                    .font(SanctuaryTypography.titleSmall)
                    .foregroundColor(SanctuaryColors.Text.primary)

                Spacer()
            }

            Rectangle()
                .fill(SanctuaryColors.Glass.borderSubtle)
                .frame(height: 1)

            // Diagnostic rows
            diagnosticRow(label: "macOS Version", value: diagnostics.macOSVersion)
            diagnosticRow(label: "Foundation Models", value: diagnostics.foundationModelsAvailable ? "Available" : "Not Available")
            diagnosticRow(label: "Session", value: diagnostics.sessionInitialized ? "Initialized" : "Not Initialized")
            diagnosticRow(label: "Tools Registered", value: "\(diagnostics.toolCount)")

            if let error = diagnostics.lastError {
                Rectangle()
                    .fill(SanctuaryColors.Glass.borderSubtle)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                    Text("Last Error")
                        .font(SanctuaryTypography.caption)
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                    Text(error)
                        .font(SanctuaryTypography.caption)
                        .foregroundColor(SanctuaryColors.Semantic.danger)
                }
            }

            if let recovery = diagnostics.recoverySteps {
                Rectangle()
                    .fill(SanctuaryColors.Glass.borderSubtle)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                    Text("Recovery Steps")
                        .font(SanctuaryTypography.caption)
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                    Text(recovery)
                        .font(SanctuaryTypography.caption)
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(glassCard)
    }

    @ViewBuilder
    private func diagnosticRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(SanctuaryTypography.bodySmall)
                .foregroundColor(SanctuaryColors.Text.tertiary)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.primary)
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Shortcuts Tab Components
    // ═══════════════════════════════════════════════════════════════

    @ViewBuilder
    private func shortcutRow(keys: String, description: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(CosmoColors.cosmoAI)
                .frame(width: 100, alignment: .leading)

            Text(description)
                .font(SanctuaryTypography.bodySmall)
                .foregroundColor(SanctuaryColors.Text.secondary)

            Spacer()
        }
        .padding(.horizontal, SanctuaryLayout.Spacing.md)
        .padding(.vertical, SanctuaryLayout.Spacing.sm + 4)
        .overlay(
            Rectangle()
                .fill(SanctuaryColors.Glass.borderSubtle)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Status Badge
    // ═══════════════════════════════════════════════════════════════

    private func statusBadge(for status: ConnectionStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)

            Text(status.label)
                .font(SanctuaryTypography.caption)
                .foregroundColor(status.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(status.color.opacity(0.1))
        )
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Glass Card Background
    // ═══════════════════════════════════════════════════════════════

    private var glassCard: some View {
        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.card)
            .fill(SanctuaryColors.Glass.primary)
            .overlay(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.card)
                    .stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1)
            )
    }
}

// MARK: - API Key Card

private struct APIKeyCard: View {
    let title: String
    let subtitle: String
    let placeholder: String
    let keyIdentifier: String
    let isRequired: Bool
    let instructions: String

    @State private var apiKey: String = ""
    @State private var isSecure: Bool = true
    @State private var showInstructions: Bool = false
    @State private var showSuccess: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                    HStack(spacing: SanctuaryLayout.Spacing.sm) {
                        Text(title)
                            .font(SanctuaryTypography.titleSmall)
                            .foregroundColor(SanctuaryColors.Text.primary)

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
                        .font(SanctuaryTypography.caption)
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }

                Spacer()

                Button(action: { showInstructions.toggle() }) {
                    HStack(spacing: SanctuaryLayout.Spacing.xs) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 12))
                        Text("How to get")
                            .font(SanctuaryTypography.caption)
                    }
                    .foregroundColor(CosmoColors.cosmoAI)
                }
                .buttonStyle(.plain)
            }

            // Input field
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $apiKey)
                    } else {
                        TextField(placeholder, text: $apiKey)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.primary)

                Button(action: { isSecure.toggle() }) {
                    Image(systemName: isSecure ? "eye.slash" : "eye")
                        .font(.system(size: 13))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
                .buttonStyle(.plain)

                if !apiKey.isEmpty {
                    Button(action: saveKey) {
                        Image(systemName: showSuccess ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(showSuccess ? SanctuaryColors.Semantic.success : CosmoColors.cosmoAI)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, SanctuaryLayout.Spacing.sm)
            .padding(.vertical, SanctuaryLayout.Spacing.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                    .fill(SanctuaryColors.Glass.secondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                            .stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1)
                    )
            )

            // Expandable instructions
            if showInstructions {
                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
                    Text("How to get your API key:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Text(instructions)
                        .font(SanctuaryTypography.caption)
                        .foregroundColor(SanctuaryColors.Text.secondary)
                        .lineSpacing(4)
                }
                .padding(SanctuaryLayout.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .fill(CosmoColors.lavender.opacity(0.1))
                )
            }

            // Saved status indicator
            if let stored = storedKey, !stored.isEmpty {
                HStack(spacing: SanctuaryLayout.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.Semantic.success)

                    Text("API key saved")
                        .font(SanctuaryTypography.caption)
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.card)
                .fill(SanctuaryColors.Glass.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.card)
                        .stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1)
                )
        )
        .onAppear {
            if let stored = storedKey, !stored.isEmpty {
                apiKey = String(repeating: "\u{2022}", count: min(stored.count, 40))
            }
        }
    }

    private var storedKey: String? {
        switch keyIdentifier {
        case "openrouter": return APIKeys.openRouter
        case "youtube": return APIKeys.youtube
        case "perplexity": return APIKeys.perplexity
        default: return nil
        }
    }

    private func saveKey() {
        guard !apiKey.allSatisfy({ $0 == "\u{2022}" }) else { return }
        APIKeys.save(apiKey, identifier: keyIdentifier)
        withAnimation(.easeInOut(duration: 0.2)) { showSuccess = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) { showSuccess = false }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SanctuarySettingsView()
        .preferredColorScheme(.dark)
}
#endif
