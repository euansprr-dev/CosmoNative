// CosmoOS/Settings/SanctuarySettingsView.swift
// Consolidated Settings Hub — unified settings for all CosmoOS configuration
// Now presented as a floating overlay panel with Command-K aesthetic

import SwiftUI
import AppKit

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
        case .connected: return DS.green
        case .notConnected: return DS.textMuted
        }
    }
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable {
    case appearance = "Appearance"
    case accountSync = "Account & Sync"
    case connections = "Connections"
    case writingAI = "Writing & AI"
    case shortcuts = "Shortcuts"

    var icon: String {
        switch self {
        case .appearance: return "paintbrush.fill"
        case .accountSync: return "icloud.fill"
        case .connections: return "link"
        case .writingAI: return "sparkles.rectangle.stack"
        case .shortcuts: return "keyboard"
        }
    }
}

// MARK: - Shell Mode

/// The settings panel is a shell with two faces: the settings hub and the
/// Profile Studio it morphs into. One glass panel, one identity.
enum SettingsShellMode: Equatable {
    case settings
    case profileStudio
}

/// How the studio should open when the shell is presented directly into it
/// (e.g. from Idea Focus's "create profile" affordance).
enum ProfileStudioLaunch: Equatable {
    case create
    case edit(atomUUID: String)

    var atomUUID: String? {
        if case .edit(let uuid) = self { return uuid }
        return nil
    }
}

extension Notification.Name {
    /// Posted by the Profiles tab (and other entry points) to morph the
    /// settings shell into the Profile Studio. userInfo["atomUUID"] edits.
    static let openProfileStudio = Notification.Name("com.cosmo.settings.openProfileStudio")
    /// Posted after any profile save/delete so lists refresh.
    static let clientProfilesChanged = Notification.Name("com.cosmo.settings.clientProfilesChanged")
}

// MARK: - SanctuarySettingsView

struct SanctuarySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var onClose: (() -> Void)? = nil
    /// When set, the shell opens directly in the Profile Studio.
    var launchStudio: ProfileStudioLaunch? = nil
    /// Fired once when a brand-new profile materializes (used by entry points
    /// that want to bind the fresh profile, e.g. Idea Focus assignment).
    var onProfileCreated: ((Atom) -> Void)? = nil
    @State private var selectedTab: SettingsTab = .appearance
    @State private var hoveredTab: SettingsTab?

    // Shell morph
    @State private var shellMode: SettingsShellMode = .settings
    @State private var studioStore: ProfileStudioStore?
    @Namespace private var shellNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Connections — Health
    @AppStorage("healthKitEnabled") private var healthKitEnabled = false

    // Social Sync
    @ObservedObject private var socialSyncService = SocialSyncService.shared

    // Connections — Knowledge
    @AppStorage("readwiseAPIKey") private var readwiseAPIKey = ""
    @StateObject private var readwiseService = ReadwiseService.shared
    @State private var isValidatingToken = false

    // Connections — Screen Time
    @AppStorage("screenTimeEnabled") private var screenTimeEnabled = false

    // Voice
    @State private var selectedHotkeyIndex: Int = 0
    @State private var selectedCaptureHotkeyIndex: Int = 0
    @State private var captureHotkeyConflict: String?

    // API Keys
    @State private var openRouterKey: String = ""
    @State private var youtubeAPIKey: String = ""
    @State private var perplexityKey: String = ""

    // Export
    @State private var isExporting = false
    @State private var exportComplete = false

    private func performClose() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var isStudio: Bool { shellMode == .profileStudio }

    /// The shell owns its size so the glass panel can morph between faces.
    private var panelSize: CGSize {
        isStudio ? CGSize(width: 980, height: 700) : CGSize(width: 780, height: 600)
    }

    var body: some View {
        ZStack {
            settingsFace
                .opacity(isStudio ? 0 : 1)
                .scaleEffect(isStudio ? 0.98 : 1)
                .allowsHitTesting(!isStudio)

            if isStudio, let studioStore {
                studioFace(store: studioStore)
                    .transition(reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : ProMotionSprings.gentle, value: shellMode)
        .onAppear {
            let currentHotkey = HotkeyManager.shared.currentHotkey
            if let index = HotkeyConfig.alternativeHotkeys.firstIndex(where: { $0 == currentHotkey }) {
                selectedHotkeyIndex = index
            }
            let captureHotkey = HotkeyManager.shared.captureHotkey
            if let index = HotkeyConfig.captureAlternativeHotkeys.firstIndex(where: { $0 == captureHotkey }) {
                selectedCaptureHotkeyIndex = index
            }
            if let launchStudio, studioStore == nil {
                openStudio(atomUUID: launchStudio.atomUUID, animated: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openProfileStudio)) { note in
            openStudio(atomUUID: note.userInfo?["atomUUID"] as? String, animated: true)
        }
        .onKeyPress(.escape) {
            if isStudio {
                exitStudio()
                return .handled
            }
            performClose()
            return .handled
        }
    }

    // MARK: - Settings face

    private var settingsFace: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(DS.sidebarMaterialBorder.opacity(0.45))
                .frame(height: 1)
            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(DS.sidebarMaterialBorder.opacity(0.35))
                    .frame(width: 1)
                content
            }
        }
    }

    // MARK: - Studio face

    private func studioFace(store: ProfileStudioStore) -> some View {
        VStack(spacing: 0) {
            studioHeader(store: store)
            Rectangle()
                .fill(DS.sidebarMaterialBorder.opacity(0.45))
                .frame(height: 1)
            ProfileStudioView(store: store)
        }
    }

    private func studioHeader(store: ProfileStudioStore) -> some View {
        HStack(spacing: DS.space8) {
            Button(action: { exitStudio() }) {
                HStack(spacing: DS.space4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Settings")
                        .font(DS.callout)
                }
                .foregroundStyle(DS.textSecondary)
                .padding(.vertical, DS.space4)
                .padding(.trailing, DS.space6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to Settings (Esc)")

            ProfileAvatarMark(name: store.name, size: 24)
                .matchedGeometryEffect(id: "shell-mark", in: shellNamespace, isSource: isStudio)

            Text(store.trimmedName.isEmpty ? "New Profile" : store.trimmedName)
                .font(DS.headline)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer()

            studioSaveIndicator(store: store)

            FloatingOverlayCloseButton(action: {
                Task {
                    await store.finalizeOnExit()
                    performClose()
                }
            })
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space16)
    }

    @ViewBuilder
    private func studioSaveIndicator(store: ProfileStudioStore) -> some View {
        switch store.saveState {
        case .idle:
            EmptyView()
        case .saving:
            Text("Saving…")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
                .transition(.opacity)
        case .saved:
            Label("Saved", systemImage: "checkmark")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
                .transition(.opacity)
        }
    }

    // MARK: - Shell transitions

    private func openStudio(atomUUID: String?, animated: Bool) {
        let store = ProfileStudioStore(onProfileListChanged: {
            NotificationCenter.default.post(name: .clientProfilesChanged, object: nil)
        })
        store.onProfileCreated = onProfileCreated
        studioStore = store
        Task { await store.load(atomUUID: atomUUID) }
        if animated {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : ProMotionSprings.gentle) {
                shellMode = .profileStudio
            }
        } else {
            shellMode = .profileStudio
        }
    }

    private func exitStudio() {
        guard let store = studioStore else {
            shellMode = .settings
            return
        }
        Task { @MainActor in
            await store.finalizeOnExit()
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : ProMotionSprings.gentle) {
                shellMode = .settings
            }
            // Keep the store mounted through the exit transition.
            try? await Task.sleep(for: .milliseconds(450))
            if shellMode == .settings { studioStore = nil }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gearshape.fill")
                .font(DS.navTitle)
                .fontWeight(.semibold)
                .foregroundStyle(DS.accent)
                .matchedGeometryEffect(id: "shell-mark", in: shellNamespace, isSource: !isStudio)

            Text("Settings")
                .font(DS.headline)
                .foregroundStyle(DS.text)

            Spacer()

            FloatingOverlayCloseButton(action: performClose)
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space16)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                sidebarTabButton(tab)
            }
            Spacer()
        }
        .padding(DS.space8)
        .frame(width: 200)
    }

    private func sidebarTabButton(_ tab: SettingsTab) -> some View {
        Button(action: {
            withAnimation(ProMotionSprings.snappy) {
                selectedTab = tab
            }
        }) {
            let isSelected = selectedTab == tab
            let isHovered = hoveredTab == tab

            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(DS.navTitle)
                    .foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
                    .frame(width: 20)

                Text(tab.rawValue)
                    .font(DS.navTitle)
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundStyle(isSelected ? DS.text : DS.textSecondary)

                Spacer()
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space10)
            .contentShape(RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous))
            .unifiedSidebarRowChrome(
                isActive: isSelected,
                isHovered: isHovered,
                activeFill: DS.accentSoft,
                hoverFill: DS.surfaceHover,
                activeBorder: DS.sidebarMaterialBorder
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                hoveredTab = hovering ? tab : nil
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                switch selectedTab {
                case .appearance:
                    ThemePickerView()
                case .accountSync:
                    accountSyncTab
                case .connections:
                    connectionsTab
                case .writingAI:
                    WritingAISettingsTab()
                case .shortcuts:
                    shortcutsTab
                }
            }
            .padding(DS.space24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Account & Sync Tab (cloud + about + export)
    // ═══════════════════════════════════════════════════════════════

    private var accountSyncTab: some View {
        VStack(alignment: .leading, spacing: 32) {
            CloudSyncSettingsTab()

            settingsSection(
                title: "COMPANION",
                detail: "Your mark on both devices"
            ) {
                CompanionSettingsSection()
            }

            settingsSection(title: "ABOUT") {
                aboutInfoCard
            }

            settingsSection(title: "DATA EXPORT") {
                dataExportContent
            }

            Spacer(minLength: 24)
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Shortcuts Tab (reference + voice activation)
    // ═══════════════════════════════════════════════════════════════

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 32) {
            settingsSection(title: "VOICE ACTIVATION") {
                VStack(alignment: .leading, spacing: DS.space8) {
                    voiceKeybindSection
                    voiceCurrentKeybindDisplay
                }
            }

            settingsSection(title: "CAPTURE ANYWHERE") {
                VStack(alignment: .leading, spacing: DS.space8) {
                    captureKeybindSection
                }
            }

            ShortcutsSettingsTab()
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Connections Tab
    // ═══════════════════════════════════════════════════════════════

    private var connectionsTab: some View {
        VStack(alignment: .leading, spacing: 32) {
            settingsSection(title: "HEALTH") {
                healthCard
            }

            settingsSection(title: "SOCIAL PLATFORMS") {
                socialPlatformsContent
            }

            settingsSection(title: "KNOWLEDGE") {
                readwiseCard
            }

            settingsSection(title: "SCREEN TIME") {
                comingSoonCard(icon: "hourglass", name: "Screen Time", accentColor: DS.orange)
            }

            settingsSection(title: "SERVICE KEYS") {
                serviceKeysContent
            }

            Spacer(minLength: 24)
        }
    }

    @ViewBuilder
    private var socialPlatformsContent: some View {
        VStack(spacing: 8) {
            SocialPlatformConnectionCard(platform: .youtube, socialService: socialSyncService)
            SocialPlatformConnectionCard(platform: .instagram, socialService: socialSyncService)
            SocialPlatformConnectionCard(platform: .tiktok, socialService: socialSyncService)
            SocialPlatformConnectionCard(platform: .x, socialService: socialSyncService)

            if socialSyncService.hasAnyConnection {
                syncAllButton
            }
        }
    }

    private var syncAllButton: some View {
        Button(action: {
            Task { await socialSyncService.syncAll() }
        }) {
            HStack(spacing: 8) {
                if socialSyncService.isSyncing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(DS.callout)
                .fontWeight(.medium)
                }
                Text(socialSyncService.isSyncing ? "Syncing..." : "Sync All Platforms")
                    .font(DS.buttonText)
            }
            .foregroundStyle(DS.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.space10)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(DS.accentSoft)
            )
        }
        .buttonStyle(.plain)
        .disabled(socialSyncService.isSyncing)
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Voice Tab
    // ═══════════════════════════════════════════════════════════════

    private var voiceKeybindSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activation Keybind")
                .font(DS.title3)
                .foregroundStyle(DS.text)

            VStack(spacing: 8) {
                ForEach(Array(HotkeyConfig.alternativeHotkeys.enumerated()), id: \.offset) { index, hotkey in
                    hotkeyRow(hotkey: hotkey, isSelected: selectedHotkeyIndex == index) {
                        selectedHotkeyIndex = index
                        HotkeyManager.shared.currentHotkey = hotkey
                    }
                }
            }
        }
        .padding(DS.space16)
        .background(glassCard)
    }

    /// The Capture Anywhere panel's summon key — same picker grammar as the
    /// voice keybind, plus conflict rejection against the voice hotkey.
    private var captureKeybindSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open the capture panel from any app")
                .font(DS.title3)
                .foregroundStyle(DS.text)

            VStack(spacing: 8) {
                ForEach(Array(HotkeyConfig.captureAlternativeHotkeys.enumerated()), id: \.offset) { index, hotkey in
                    hotkeyRow(hotkey: hotkey, isSelected: selectedCaptureHotkeyIndex == index) {
                        guard hotkey != HotkeyManager.shared.currentHotkey else {
                            captureHotkeyConflict = "\(hotkey.displayName) is already the voice keybind — pick another"
                            return
                        }
                        captureHotkeyConflict = nil
                        selectedCaptureHotkeyIndex = index
                        HotkeyManager.shared.captureHotkey = hotkey
                    }
                }
            }

            if let conflict = captureHotkeyConflict {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DS.caption)
                        .foregroundStyle(DS.red)
                    Text(conflict)
                        .font(DS.caption)
                        .foregroundStyle(DS.red)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(DS.navTitle)
                    .foregroundStyle(DS.accent)

                Text("Current keybind:")
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)

                Text(HotkeyManager.shared.captureHotkey.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, DS.space10)
                    .padding(.vertical, DS.space4)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .fill(DS.accentSoft)
                    )
            }
            .padding(.top, DS.space8)
        }
        .padding(DS.space16)
        .background(glassCard)
    }

    private var voiceCurrentKeybindDisplay: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(DS.navTitle)
                .foregroundStyle(DS.accent)

            Text("Current keybind:")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)

            Text(HotkeyManager.shared.currentHotkey.displayName)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(DS.accent)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, DS.space4)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(DS.accentSoft)
                )
        }
        .padding(.top, DS.space8)
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - API Keys Tab
    // ═══════════════════════════════════════════════════════════════

    private var serviceKeysContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            APIKeyCard(
                title: "Anthropic Agent LLM Key",
                subtitle: "Required for Voice Variations and native craft skills",
                placeholder: "sk-ant-...",
                keyIdentifier: "agent_llm",
                isRequired: true,
                instructions: "1. Visit https://console.anthropic.com\n2. Open API Keys\n3. Create a new API key\n4. Paste it here for inline assistants and craft skills"
            )

            APIKeyCard(
                title: "OpenRouter API Key",
                subtitle: "Required for AI features",
                placeholder: "sk-or-v1-...",
                keyIdentifier: "openrouter",
                isRequired: true,
                instructions: "1. Visit https://openrouter.ai\n2. Sign up or log in\n3. Go to Keys section\n4. Create a new API key"
            )

            APIKeyCard(
                title: "YouTube API Key",
                subtitle: "Optional - For enhanced video metadata",
                placeholder: "AIza...",
                keyIdentifier: "youtube",
                isRequired: false,
                instructions: "1. Visit https://console.cloud.google.com\n2. Create a new project\n3. Enable YouTube Data API v3\n4. Create credentials (API Key)"
            )

            APIKeyCard(
                title: "Perplexity API Key",
                subtitle: "Optional - For research features",
                placeholder: "pplx-...",
                keyIdentifier: "perplexity",
                isRequired: false,
                instructions: "1. Visit https://www.perplexity.ai\n2. Sign up or log in\n3. Go to API settings\n4. Generate a new API key"
            )

            APIKeyCard(
                title: "Apify API Key",
                subtitle: "Optional - For Instagram creator import",
                placeholder: "apify_api_...",
                keyIdentifier: "apify",
                isRequired: false,
                instructions: "1. Visit https://apify.com\n2. Sign up or log in\n3. Go to Settings > Integrations\n4. Copy your Personal API token"
            )

            APIKeyCard(
                title: "Discovery API Base URL",
                subtitle: "Required for Swipe File Discover cloud feed",
                placeholder: "https://cosmonative-production.up.railway.app",
                keyIdentifier: "discovery_api_base_url",
                isRequired: false,
                instructions: "1. Open Railway\n2. Select the cloud agent service\n3. Go to Settings > Networking\n4. Copy the public .up.railway.app domain, including https://"
            )

            APIKeyCard(
                title: "Discovery API Key",
                subtitle: "Required for Swipe File Discover cloud feed",
                placeholder: "same value as DISCOVERY_API_KEY in Railway",
                keyIdentifier: "discovery_api_key",
                isRequired: false,
                instructions: "Use the exact same DISCOVERY_API_KEY value you added to Railway for the cloud agent."
            )

        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - About components (Account & Sync tab)
    // ═══════════════════════════════════════════════════════════════

    private var aboutInfoCard: some View {
        VStack(spacing: 16) {
            aboutBranding
            aboutVersionRows
        }
        .padding(DS.space16)
        .background(glassCard)
    }

    private var aboutBranding: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        colors: [DS.accent, DS.accent.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("CosmoOS")
                .font(DS.title2)
                .fontWeight(.semibold)
                .foregroundStyle(DS.text)

            Text("Your AI-powered second brain")
                .font(DS.navTitle)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space24)
    }

    private var aboutVersionRows: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Version")
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                Spacer()
                Text("1.0.0 (Local First)")
                    .font(DS.callout)
                .fontWeight(.medium)
                    .foregroundStyle(DS.text)
            }
            .padding(.horizontal, DS.space16)

            HStack {
                Text("Built for")
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                Spacer()
                Text("Apple Silicon")
                    .font(DS.callout)
                .fontWeight(.medium)
                    .foregroundStyle(DS.text)
            }
            .padding(.horizontal, DS.space16)
        }
    }

    @ViewBuilder
    private var dataExportContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export your writing engine (system prompt, swipes, client profiles) for use in Claude Projects.")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)

            dataExportButton

            if exportComplete {
                Button(action: {
                    NSWorkspace.shared.open(WritingContextExporter.exportRoot)
                }) {
                    Text("Open ~/Desktop/CosmoExport")
                        .font(DS.buttonText)
                        .foregroundStyle(DS.accent)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.space16)
        .background(glassCard)
    }

    private var dataExportButton: some View {
        Button(action: {
            isExporting = true
            exportComplete = false
            Task {
                await WritingContextExporter.exportAll()
                isExporting = false
                exportComplete = true
            }
        }) {
            HStack(spacing: 8) {
                if isExporting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: exportComplete ? "checkmark.circle.fill" : "folder.badge.gearshape")
                        .font(DS.callout)
                .fontWeight(.medium)
                }
                Text(isExporting ? "Exporting..." : exportComplete ? "Exported to Desktop" : "Export for Claude Projects")
                    .font(DS.callout)
                .fontWeight(.medium)
            }
            .foregroundStyle(exportComplete ? DS.green : DS.accent)
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space8)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill((exportComplete ? DS.green : DS.accent).opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .disabled(isExporting)
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Connection Tab Components
    // ═══════════════════════════════════════════════════════════════

    @ViewBuilder
    private func settingsSection<Content: View>(
        title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(label: title, detail: detail)
            content()
        }
    }

    private var healthCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "heart.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(DS.red)
                .frame(width: 40, height: 40)
                .background(DS.red.opacity(0.15))
                .clipShape(.rect(cornerRadius: DS.radiusSmall))

            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Health")
                    .font(DS.title3)
                    .foregroundStyle(DS.text)

                Text("HRV, sleep, heart rate, workouts")
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer()

            statusBadge(for: healthKitEnabled ? .connected : .notConnected)

            Toggle("", isOn: Binding(
                get: { healthKitEnabled },
                set: { newValue in
                    if newValue {
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
                .tint(DS.accent)
        }
        .padding(DS.space16)
        .background(glassCard)
    }

    @ViewBuilder
    private func comingSoonCard(
        icon: String,
        name: String,
        accentColor: Color
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(DS.title2)
                .foregroundStyle(accentColor.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(accentColor.opacity(0.08))
                .clipShape(.rect(cornerRadius: DS.radiusSmall))

            Text(name)
                .font(DS.title3)
                .foregroundStyle(DS.textSecondary)

            Spacer()

            Text("Coming Soon")
                .font(DS.buttonText)
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, DS.space16)
                .padding(.vertical, DS.space4)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(DS.glassInputFill)
                )
        }
        .padding(DS.space16)
        .background(glassCard)
    }

    private var readwiseCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            readwiseHeaderRow
            readwiseAPIKeyInput
            if readwiseService.isConnected {
                readwiseSyncControls
                readwiseSyncStatus
            }
            readwiseErrorDisplay
        }
        .padding(DS.space16)
        .background(glassCard)
    }

    private var readwiseHeaderRow: some View {
        HStack(spacing: 16) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(DS.entityResearch)
                .frame(width: 40, height: 40)
                .background(DS.entityResearch.opacity(0.15))
                .clipShape(.rect(cornerRadius: DS.radiusSmall))

            VStack(alignment: .leading, spacing: 2) {
                Text("Readwise")
                    .font(DS.title3)
                    .foregroundStyle(DS.text)

                Text("Import highlights and reading data")
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer()

            readwiseValidationBadge
        }
    }

    @ViewBuilder
    private var readwiseValidationBadge: some View {
        if isValidatingToken {
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
        } else if let valid = readwiseService.isTokenValid {
            HStack(spacing: 4) {
                Circle()
                    .fill(valid ? DS.green : DS.red)
                    .frame(width: 6, height: 6)
                Text(valid ? "Valid" : "Invalid")
                    .font(DS.footnote)
                    .foregroundStyle(valid ? DS.green : DS.red)
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(
                Capsule()
                    .fill((valid ? DS.green : DS.red).opacity(0.1))
            )
        } else {
            statusBadge(for: readwiseAPIKey.isEmpty ? .notConnected : .connected)
        }
    }

    private var readwiseAPIKeyInput: some View {
        SecureField("Readwise API Key", text: $readwiseAPIKey)
            .textFieldStyle(.plain)
            .font(DS.navTitle)
            .foregroundStyle(DS.text)
            .padding(DS.space8)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(DS.glassInputFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.glassBorder, lineWidth: 1)
                    )
            )
            .onSubmit {
                guard !readwiseAPIKey.isEmpty else { return }
                isValidatingToken = true
                Task {
                    _ = await readwiseService.validateToken()
                    isValidatingToken = false
                }
            }
            .onChange(of: readwiseAPIKey) { newValue in
                if newValue.isEmpty {
                    readwiseService.disconnect()
                }
            }
    }

    private var readwiseSyncControls: some View {
        HStack(spacing: 16) {
            Button(action: {
                Task {
                    do {
                        try await readwiseService.syncHighlights()
                    } catch {
                        readwiseService.syncError = error.localizedDescription
                    }
                }
            }) {
                HStack(spacing: 4) {
                    if readwiseService.isSyncing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(DS.buttonText)
                    }
                    Text(readwiseService.isSyncing ? "Syncing..." : "Sync Now")
                        .font(DS.buttonText)
                }
                .foregroundStyle(DS.entityResearch)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, DS.space6)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(DS.entityResearch.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .disabled(readwiseService.isSyncing)

            Button(action: {
                readwiseAPIKey = ""
                readwiseService.disconnect()
            }) {
                Text("Disconnect")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.red)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var readwiseSyncStatus: some View {
        HStack(spacing: 16) {
            if readwiseService.highlightCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "text.quote")
                        .font(DS.footnote)
                        .foregroundStyle(DS.textMuted)
                    Text("\(readwiseService.highlightCount) highlights")
                        .font(DS.footnote)
                        .foregroundStyle(DS.textSecondary)
                }
            }

            if let lastSync = readwiseService.lastSyncDate {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(DS.footnote)
                        .foregroundStyle(DS.textMuted)
                    Text("Last sync: \(lastSync, style: .relative) ago")
                        .font(DS.footnote)
                        .foregroundStyle(DS.textSecondary)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var readwiseErrorDisplay: some View {
        if let error = readwiseService.syncError {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(DS.footnote)
                    .foregroundStyle(DS.red)
                Text(error)
                    .font(DS.footnote)
                    .foregroundStyle(DS.red)
                    .lineLimit(2)
            }
        }
    }

    private var screenTimeCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(DS.orange)
                .frame(width: 40, height: 40)
                .background(DS.orange.opacity(0.15))
                .clipShape(.rect(cornerRadius: DS.radiusSmall))

            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Time")
                    .font(DS.title3)
                    .foregroundStyle(DS.text)

                Text("Track app usage and distraction patterns")
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer()

            statusBadge(for: screenTimeEnabled ? .connected : .notConnected)

            Toggle("", isOn: $screenTimeEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(DS.accent)
        }
        .padding(DS.space16)
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
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isSelected ? DS.accent : DS.textMuted)

                Text(hotkey.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.text)
                    .frame(width: 110, alignment: .leading)

                Text(hotkeyDescription(hotkey))
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)

                Spacer()
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space10)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(isSelected ? DS.accentSoft : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(isSelected ? DS.accent.opacity(0.3) : Color.clear, lineWidth: 1)
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
        case "\u{2325}C": return "Option + C"
        case "\u{2303}\u{21E7}C": return "Control + Shift + C"
        case "\u{21E7}\u{2325}.": return "Shift + Option + Period"
        case "Fn (experimental)": return "Fn key (may be intercepted)"
        default: return ""
        }
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
                .font(DS.footnote)
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .background(
            Capsule()
                .fill(status.color.opacity(0.1))
        )
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Glass Card Background
    // ═══════════════════════════════════════════════════════════════

    private var glassCard: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium)
            .fill(DS.glassCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(DS.glassBorder, lineWidth: 1)
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
        VStack(alignment: .leading, spacing: 8) {
            apiKeyHeader
            apiKeyInputField
            if showInstructions { apiKeyInstructions }
            apiKeySavedIndicator
        }
        .padding(DS.space16)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.glassCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .stroke(DS.glassBorder, lineWidth: 1)
                )
        )
        .onAppear {
            if let stored = storedKey, !stored.isEmpty {
                apiKey = String(repeating: "\u{2022}", count: min(stored.count, 40))
            }
        }
    }

    private var apiKeyHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(DS.title3)
                        .foregroundStyle(DS.text)

                    if isRequired {
                        Text("Required")
                            .font(DS.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(DS.textOnAccent)
                            .padding(.horizontal, DS.space6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(DS.accent)
                            )
                    }
                }

                Text(subtitle)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer()

            Button(action: { showInstructions.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle")
                        .font(DS.subheadline)
                    Text("How to get")
                        .font(DS.footnote)
                }
                .foregroundStyle(DS.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var apiKeyInputField: some View {
        HStack(spacing: 8) {
            PasteAwareAPIKeyField(
                placeholder: placeholder,
                text: $apiKey,
                isSecure: isSecure
            )
            .id(isSecure ? "secure" : "plain")
            .frame(height: 18)

            Button(action: { isSecure.toggle() }) {
                Image(systemName: isSecure ? "eye.slash" : "eye")
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)

            if !apiKey.isEmpty {
                Button(action: saveKey) {
                    Image(systemName: showSuccess ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(showSuccess ? DS.green : DS.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space10)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.glassInputFill)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.glassBorder, lineWidth: 1)
                )
        )
    }

    private var apiKeyInstructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to get your API key:")
                .font(DS.buttonText)
                .foregroundStyle(DS.text)

            Text(instructions)
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)
                .lineSpacing(4)
        }
        .padding(DS.space8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.accentSoft)
        )
    }

    @ViewBuilder
    private var apiKeySavedIndicator: some View {
        if let stored = storedKey, !stored.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.green)

                Text("API key saved")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
            }
        }
    }

    private var storedKey: String? {
        switch keyIdentifier {
        case "agent_llm": return APIKeys.agentLLM
        case "openrouter": return APIKeys.openRouter
        case "youtube": return APIKeys.youtube
        case "perplexity": return APIKeys.perplexity
        case "instagram": return APIKeys.instagram
        case "tiktok": return APIKeys.tiktok
        case "x_twitter": return APIKeys.xTwitter
        case "youtube_channel_id": return APIKeys.youtubeChannelId
        case "apify": return APIKeys.apify
        case "discovery_api_base_url": return APIKeys.discoveryApiBaseURL
        case "discovery_api_key": return APIKeys.discoveryApiKey
        default: return nil
        }
    }

    private func saveKey() {
        guard !apiKey.allSatisfy({ $0 == "\u{2022}" }) else { return }
        APIKeys.save(apiKey, identifier: keyIdentifier)
        withAnimation(ProMotionSprings.snappy) { showSuccess = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(ProMotionSprings.snappy) { showSuccess = false }
        }
    }
}

private struct PasteAwareAPIKeyField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = isSecure
            ? PasteCapturingAPIKeySecureTextField()
            : PasteCapturingAPIKeyTextField()
        configure(field, context: context)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        configure(nsView, context: context)

        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    private func configure(_ field: NSTextField, context: Context) {
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingMiddle
        field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        field.textColor = .labelColor
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            ]
        )

        let coordinator = context.coordinator
        (field as? PasteCapturingAPIKeyFieldBehavior)?.onPasteTextChanged = { [weak coordinator, weak field] in
            guard let field else { return }
            coordinator?.text.wrappedValue = field.stringValue
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

private protocol PasteCapturingAPIKeyFieldBehavior: AnyObject {
    var onPasteTextChanged: (() -> Void)? { get set }
    func pasteStringFromPasteboard() -> Bool
}

private enum APIKeyPasteCommand {
    static func isPasteKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return chars == "v" && flags == .command
    }

    static func pasteStringFromPasteboard(
        into field: NSTextField,
        onTextChanged: (() -> Void)?
    ) -> Bool {
        guard let pasted = NSPasteboard.general.string(forType: .string) else {
            return true
        }

        if let editor = field.currentEditor() as? NSTextView {
            editor.paste(nil)
            DispatchQueue.main.async {
                onTextChanged?()
            }
            return true
        }

        field.window?.makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            editor.paste(nil)
            DispatchQueue.main.async {
                onTextChanged?()
            }
        } else {
            field.stringValue = pasted
            onTextChanged?()
        }
        return true
    }
}

private final class PasteCapturingAPIKeyTextField: NSTextField, PasteCapturingAPIKeyFieldBehavior {
    var onPasteTextChanged: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if APIKeyPasteCommand.isPasteKeyEquivalent(event) {
            return pasteStringFromPasteboard()
        }

        return super.performKeyEquivalent(with: event)
    }

    func pasteStringFromPasteboard() -> Bool {
        APIKeyPasteCommand.pasteStringFromPasteboard(
            into: self,
            onTextChanged: onPasteTextChanged
        )
    }
}

private final class PasteCapturingAPIKeySecureTextField: NSSecureTextField, PasteCapturingAPIKeyFieldBehavior {
    var onPasteTextChanged: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if APIKeyPasteCommand.isPasteKeyEquivalent(event) {
            return pasteStringFromPasteboard()
        }

        return super.performKeyEquivalent(with: event)
    }

    func pasteStringFromPasteboard() -> Bool {
        APIKeyPasteCommand.pasteStringFromPasteboard(
            into: self,
            onTextChanged: onPasteTextChanged
        )
    }
}

// MARK: - Social Platform Connection Card

private struct SocialPlatformConnectionCard: View {
    let platform: SocialSyncPlatform
    @ObservedObject var socialService: SocialSyncService

    @State private var tokenInput: String = ""
    @State private var channelIdInput: String = ""
    @State private var isExpanded: Bool = false
    @State private var statusMessage: String? = nil

    private var isConnected: Bool {
        socialService.isConnected(platform)
    }

    private var syncError: String? {
        socialService.syncErrors[platform]
    }

    private var syncResult: PlatformSyncResult? {
        socialService.lastSyncResults[platform]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            if isExpanded && !isConnected { tokenInputSection }
            if isConnected, let result = syncResult { connectedInfoRow(result: result) }
            if let msg = statusMessage { statusMessageRow(msg) }
            if let error = syncError { errorRow(error) }
        }
        .padding(DS.space16)
        .background(platformGlassCard)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 16) {
            Image(systemName: platform.icon)
                .font(DS.title2)
                .foregroundStyle(isConnected ? platform.accentColor : platform.accentColor.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(platform.accentColor.opacity(isConnected ? 0.15 : 0.08))
                .clipShape(.rect(cornerRadius: DS.radiusSmall))

            VStack(alignment: .leading, spacing: 2) {
                Text(platform.displayName)
                    .font(DS.title3)
                    .foregroundStyle(isConnected ? DS.text : DS.textSecondary)

                if isConnected, let handle = syncResult?.accountHandle, !handle.isEmpty {
                    Text(handle)
                        .font(DS.footnote)
                        .foregroundStyle(DS.textMuted)
                }
            }

            Spacer()

            if isConnected {
                connectionBadge
                disconnectButton
            } else {
                connectToggleButton
            }
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(DS.green)
                .frame(width: 6, height: 6)
            Text("Connected")
                .font(DS.footnote)
                .foregroundStyle(DS.green)
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .background(
            Capsule()
                .fill(DS.green.opacity(0.1))
        )
    }

    private var disconnectButton: some View {
        Button(action: {
            socialService.disconnect(platform)
            tokenInput = ""
            channelIdInput = ""
            statusMessage = nil
        }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(DS.textMuted)
        }
        .buttonStyle(.plain)
    }

    private var connectToggleButton: some View {
        Button(action: {
            withAnimation(ProMotionSprings.snappy) {
                isExpanded.toggle()
            }
        }) {
            Text(isExpanded ? "Cancel" : "Connect")
                .font(DS.buttonText)
                .foregroundStyle(isExpanded ? DS.textMuted : platform.accentColor)
                .padding(.horizontal, DS.space16)
                .padding(.vertical, DS.space4)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(isExpanded ? DS.surface : platform.accentColor.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Token Input

    @ViewBuilder
    private var tokenInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if platform == .youtube {
                youTubeInputFields
            } else {
                singleTokenInput
            }
            saveButton
        }
    }

    @ViewBuilder
    private var youTubeInputFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YouTube API Key")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)

            SecureField("AIza...", text: $tokenInput)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(DS.text)
                .padding(DS.space8)
                .background(tokenFieldBackground)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Channel ID")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)

            TextField("UC...", text: $channelIdInput)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(DS.text)
                .padding(DS.space8)
                .background(tokenFieldBackground)
        }

        Text("Find your Channel ID at youtube.com/account_advanced")
            .font(DS.caption2)
            .foregroundStyle(DS.textMuted)
    }

    @ViewBuilder
    private var singleTokenInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tokenLabel)
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)

            SecureField(tokenPlaceholder, text: $tokenInput)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(DS.text)
                .padding(DS.space8)
                .background(tokenFieldBackground)
        }

        Text(tokenInstructions)
            .font(DS.caption2)
            .foregroundStyle(DS.textMuted)
    }

    private var saveButton: some View {
        Button(action: saveToken) {
            Text("Save & Connect")
                .font(DS.buttonText)
                .foregroundStyle(DS.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.space8)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(platform.accentColor)
                )
        }
        .buttonStyle(.plain)
        .disabled(platform == .youtube ? (tokenInput.isEmpty || channelIdInput.isEmpty) : tokenInput.isEmpty)
        .opacity(platform == .youtube ? (tokenInput.isEmpty || channelIdInput.isEmpty ? 0.5 : 1) : (tokenInput.isEmpty ? 0.5 : 1))
    }

    // MARK: - Connected Info

    @ViewBuilder
    private func connectedInfoRow(result: PlatformSyncResult) -> some View {
        HStack(spacing: 24) {
            if result.followerCount > 0 {
                metricPill(icon: "person.2.fill", value: formatNumber(result.followerCount), label: "followers")
            }
            if result.totalReach > 0 {
                metricPill(icon: "eye.fill", value: formatNumber(result.totalReach), label: "reach")
            }
            if result.engagementRate > 0 {
                metricPill(icon: "heart.fill", value: String(format: "%.1f%%", result.engagementRate), label: "engagement")
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func metricPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(DS.textMuted)
            Text(value)
                .font(DS.caption)
                .foregroundStyle(DS.text)
        }
    }

    // MARK: - Status/Error

    @ViewBuilder
    private func statusMessageRow(_ msg: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(DS.footnote)
                .foregroundStyle(DS.green)
            Text(msg)
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)
        }
    }

    @ViewBuilder
    private func errorRow(_ error: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DS.footnote)
                .foregroundStyle(DS.red)
            Text(error)
                .font(DS.footnote)
                .foregroundStyle(DS.red)
                .lineLimit(2)
        }
    }

    // MARK: - Helpers

    private var tokenLabel: String {
        switch platform {
        case .instagram: return "Instagram Access Token"
        case .tiktok: return "TikTok Access Token"
        case .x: return "X Bearer Token"
        case .youtube: return "YouTube API Key"
        }
    }

    private var tokenPlaceholder: String {
        switch platform {
        case .instagram: return "IGQVJ..."
        case .tiktok: return "act...."
        case .x: return "AAAA..."
        case .youtube: return "AIza..."
        }
    }

    private var tokenInstructions: String {
        switch platform {
        case .instagram: return "Get a long-lived token from Facebook Developer Portal"
        case .tiktok: return "Get an access token from TikTok Developer Portal"
        case .x: return "Get a Bearer token from developer.x.com"
        case .youtube: return "Get an API key from Google Cloud Console"
        }
    }

    private func saveToken() {
        if platform == .youtube {
            APIKeys.save(tokenInput, identifier: "youtube")
            APIKeys.save(channelIdInput, identifier: "youtube_channel_id")
            statusMessage = "YouTube connected"
            withAnimation { isExpanded = false }
        } else {
            Task {
                let result = await socialService.connect(platform: platform, token: tokenInput)
                statusMessage = result.message
                if result.success {
                    withAnimation { isExpanded = false }
                }
            }
        }
    }

    private var tokenFieldBackground: some View {
        RoundedRectangle(cornerRadius: DS.radiusSmall)
            .fill(DS.glassInputFill)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.glassBorder, lineWidth: 1)
            )
    }

    private var platformGlassCard: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium)
            .fill(DS.glassCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(isConnected ? platform.accentColor.opacity(0.2) : DS.glassBorder, lineWidth: 1)
            )
    }

    private func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 {
            return String(format: "%.1fM", Double(num) / 1_000_000)
        } else if num >= 1_000 {
            return String(format: "%.1fK", Double(num) / 1_000)
        }
        return "\(num)"
    }
}

// MARK: - Elements Settings

struct ElementsSettingsTab: View {
    private var store: DocumentElementStore { DocumentElementStore.shared }
    @State private var newTitle = ""
    @State private var newIcon = "square.dashed"
    @State private var errorMessage: String?

    private var activeDefinitions: [DocumentElementDefinition] {
        store.activeDefinitions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Elements")
                    .font(DS.title2)
                    .foregroundStyle(DS.text)

                Text("Reusable rounded blocks for notes, focus documents, and canvas note blocks.")
                    .font(DS.navTitle)
                    .foregroundStyle(DS.textMuted)
            }

            createElementCard

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Saved Elements")
                        .font(DS.title3)
                        .foregroundStyle(DS.text)
                    Spacer()
                    Text("\(activeDefinitions.count)")
                        .font(DS.footnote)
                        .foregroundStyle(DS.textMuted)
                }

                if activeDefinitions.isEmpty {
                    emptyElementsView
                } else {
                    VStack(spacing: 8) {
                        ForEach(activeDefinitions) { definition in
                            ElementDefinitionSettingsRow(
                                definition: definition,
                                onSave: updateElement,
                                onDisable: disableElement
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 24)
        }
    }

    private var createElementCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: sanitizedNewIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 7).fill(DS.accentSoft))

                Text("Create Element")
                    .font(DS.title3)
                    .foregroundStyle(DS.text)

                Spacer()
            }

            HStack(spacing: 10) {
                TextField("Name", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(DS.navTitle)
                    .foregroundStyle(DS.text)
                    .padding(DS.space8)
                    .background(fieldBackground)

                TextField("SF Symbol", text: $newIcon)
                    .textFieldStyle(.plain)
                    .font(DS.navTitle)
                    .foregroundStyle(DS.text)
                    .frame(width: 160)
                    .padding(DS.space8)
                    .background(fieldBackground)

                Button(action: createElement) {
                    Image(systemName: "plus")
                        .font(DS.buttonText)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.accent)
                .background(RoundedRectangle(cornerRadius: 7).fill(DS.accentSoft))
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(DS.footnote)
                    .foregroundStyle(DS.red)
            }
        }
        .padding(DS.space16)
        .background(cardBackground)
    }

    private var emptyElementsView: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.dashed")
                .font(DS.title2)
                .foregroundStyle(DS.textMuted)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 7).fill(DS.glassInputFill))

            Text("No elements yet")
                .font(DS.navTitle)
                .foregroundStyle(DS.textSecondary)

            Spacer()
        }
        .padding(DS.space16)
        .background(cardBackground)
    }

    private var sanitizedNewIcon: String {
        let trimmed = newIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "square.dashed" : trimmed
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: DS.radiusSmall)
            .fill(DS.glassInputFill)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.glassBorder, lineWidth: 1)
            )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium)
            .fill(DS.glassCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(DS.glassBorder, lineWidth: 1)
            )
    }

    private func createElement() {
        do {
            _ = try store.createDefinition(title: newTitle, systemIcon: sanitizedNewIcon)
            newTitle = ""
            newIcon = "square.dashed"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateElement(id: UUID, title: String, icon: String) {
        do {
            _ = try store.updateDefinition(id: id, title: title, systemIcon: icon)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disableElement(id: UUID) {
        do {
            try store.disableDefinition(id: id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ElementDefinitionSettingsRow: View {
    let definition: DocumentElementDefinition
    let onSave: (UUID, String, String) -> Void
    let onDisable: (UUID) -> Void

    @State private var title: String
    @State private var icon: String

    init(
        definition: DocumentElementDefinition,
        onSave: @escaping (UUID, String, String) -> Void,
        onDisable: @escaping (UUID) -> Void
    ) {
        self.definition = definition
        self.onSave = onSave
        self.onDisable = onDisable
        _title = State(initialValue: definition.title)
        _icon = State(initialValue: definition.systemIcon)
    }

    private var sanitizedIcon: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "square.dashed" : trimmed
    }

    private var hasChanges: Bool {
        title != definition.title || sanitizedIcon != definition.systemIcon
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sanitizedIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 7).fill(DS.accentSoft))

            TextField("Name", text: $title)
                .textFieldStyle(.plain)
                .font(DS.navTitle)
                .foregroundStyle(DS.text)
                .padding(DS.space8)
                .background(fieldBackground)

            TextField("SF Symbol", text: $icon)
                .textFieldStyle(.plain)
                .font(DS.navTitle)
                .foregroundStyle(DS.text)
                .frame(width: 150)
                .padding(DS.space8)
                .background(fieldBackground)

            Button(action: save) {
                Image(systemName: "checkmark")
                    .font(DS.buttonText)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(hasChanges ? DS.accent : DS.textMuted)
            .background(RoundedRectangle(cornerRadius: 7).fill(hasChanges ? DS.accentSoft : DS.glassInputFill))
            .disabled(!hasChanges)

            Button(role: .destructive) {
                onDisable(definition.id)
            } label: {
                Image(systemName: "archivebox")
                    .font(DS.buttonText)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.red)
            .background(RoundedRectangle(cornerRadius: 7).fill(DS.red.opacity(0.10)))
        }
        .padding(DS.space12)
        .background(rowBackground)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: DS.radiusSmall)
            .fill(DS.glassInputFill)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.glassBorder, lineWidth: 1)
            )
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium)
            .fill(DS.glassCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(DS.glassBorder, lineWidth: 1)
            )
    }

    private func save() {
        onSave(definition.id, title, sanitizedIcon)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SanctuarySettingsView()
}
#endif
