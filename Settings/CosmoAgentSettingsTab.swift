// CosmoOS/Settings/CosmoAgentSettingsTab.swift
// Settings tab for Cosmo Agent configuration

import SwiftUI

struct CosmoAgentSettingsTab: View {
    @StateObject private var agentService = CosmoAgentService.shared
    @StateObject private var telegramBridge = TelegramBridgeService.shared
    @StateObject private var scheduler = AgentProactiveScheduler.shared

    @State private var selectedProvider: AgentProvider = .anthropic
    @State private var agentAPIKey: String = ""
    @State private var agentModel: String = ""
    @State private var selectedOpenRouterModel: String = AgentProvider.openRouterModels[0].id
    @State private var agentBaseURL: String = ""
    @State private var telegramToken: String = ""
    @State private var whisperKey: String = ""
    @State private var isTestingConnection = false
    @State private var connectionResult: (success: Bool, message: String)?
    @State private var showTelegramInstructions = false
    @State private var isTestingTelegram = false
    @State private var telegramTestResult: (success: Bool, message: String)?

    // Collapsible sections
    @State private var isAPIExpanded = false
    @State private var isTelegramExpanded = false
    @State private var isSystemPromptExpanded = false
    @State private var isVoiceExpanded = false
    @State private var isProactiveExpanded = false
    // Custom system prompt
    @State private var customSystemPrompt: String = ""
    @State private var isSystemPromptDirty = false

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            // Section 0: Cosmo Window
            CosmoWindowSettingsSection()

            // Section 1: AI Provider
            aiProviderSection

            // Section 2: Telegram Bot
            telegramSection

            // Section 3: System Prompt
            systemPromptSection

            // Section 4: Voice Transcription
            voiceSection

            // Section 5: Proactive Intelligence
            proactiveSection

            // Section 6: Skills link
            skillsLinkRow

            // Section 7: WhatsApp (Coming Soon)
            whatsappSection

            Spacer()
        }
        }
        .onAppear {
            selectedProvider = agentService.activeProvider
            agentModel = agentService.selectedModel
            if selectedProvider == .openRouter {
                // Match saved model to OpenRouter dropdown
                if AgentProvider.openRouterModels.contains(where: { $0.id == agentModel }) {
                    selectedOpenRouterModel = agentModel
                } else {
                    selectedOpenRouterModel = agentModel // custom model typed in
                }
                if APIKeys.hasOpenRouter { agentAPIKey = String(repeating: "\u{2022}", count: 30) }
            } else {
                if APIKeys.hasAgentLLM { agentAPIKey = String(repeating: "\u{2022}", count: 30) }
            }
            if APIKeys.hasTelegramBot { telegramToken = String(repeating: "\u{2022}", count: 30) }
            if APIKeys.hasWhisper { whisperKey = String(repeating: "\u{2022}", count: 30) }
            if let url = APIKeys.agentLLMBaseURL { agentBaseURL = url }
            // Load custom system prompt
            customSystemPrompt = UserDefaults.standard.string(forKey: "agent_custom_system_prompt") ?? AgentContextAssembler.defaultIdentityPrompt
            isSystemPromptDirty = false
        }
    }

    // MARK: - AI Provider Section
    private var aiProviderSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsibleHeader(
                title: "AI Provider",
                subtitle: selectedProvider.displayName,
                icon: "cpu",
                isExpanded: $isAPIExpanded
            )

            if isAPIExpanded {
                VStack(spacing: 12) {
                    // Provider dropdown
                    HStack {
                        Text("Provider")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(SanctuaryColors.Text.primary)

                        Spacer()

                        Picker("", selection: $selectedProvider) {
                            ForEach(AgentProvider.allCases, id: \.self) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)
                        .onChange(of: selectedProvider) { newValue in
                            agentService.setProvider(newValue)
                            agentModel = newValue.defaultModel
                            agentBaseURL = newValue.defaultBaseURL
                            connectionResult = nil
                            if newValue == .openRouter {
                                agentAPIKey = APIKeys.hasOpenRouter ? String(repeating: "\u{2022}", count: 30) : ""
                                selectedOpenRouterModel = newValue.defaultModel
                            } else {
                                agentAPIKey = APIKeys.hasAgentLLM ? String(repeating: "\u{2022}", count: 30) : ""
                            }
                        }
                    }

                    // API Key (if needed)
                    if selectedProvider.requiresAPIKey {
                        agentAPIKeyField
                    }

                    // Model picker
                    if selectedProvider == .openRouter {
                        openRouterModelPicker
                    } else {
                        modelTextField
                    }

                    // Base URL (for Ollama/Custom)
                    if selectedProvider == .ollama || selectedProvider == .custom {
                        HStack {
                            Text("Base URL")
                                .font(.system(size: 13))
                                .foregroundColor(SanctuaryColors.Text.secondary)
                                .frame(width: 60, alignment: .leading)

                            TextField("http://localhost:11434", text: $agentBaseURL)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(SanctuaryColors.Text.primary)
                                .onChange(of: agentBaseURL) { newValue in
                                    APIKeys.save(newValue, identifier: "agent_llm_base_url")
                                }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(SanctuaryColors.Glass.secondary))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1))
                    }

                    // Test Connection
                    testConnectionRow
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(SanctuaryColors.Glass.primary))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var agentAPIKeyField: some View {
        HStack(spacing: 8) {
            SecureField(selectedProvider == .openRouter ? "OpenRouter API Key" : "API Key", text: $agentAPIKey)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.primary)

            if !agentAPIKey.isEmpty && !agentAPIKey.allSatisfy({ $0 == "\u{2022}" }) {
                Button(action: saveAPIKey) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(CosmoColors.cosmoAI)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(SanctuaryColors.Glass.secondary))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1))
    }

    @ViewBuilder
    private var openRouterModelPicker: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Model")
                    .font(.system(size: 13))
                    .foregroundColor(SanctuaryColors.Text.secondary)
                    .frame(width: 60, alignment: .leading)

                Picker("", selection: $selectedOpenRouterModel) {
                    ForEach(AgentProvider.openRouterModels, id: \.id) { model in
                        Text(model.label).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedOpenRouterModel) { newValue in
                    agentModel = newValue
                    agentService.setModel(newValue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(SanctuaryColors.Glass.secondary))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1))

            // Custom model override field
            HStack {
                Text("or type")
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .frame(width: 60, alignment: .leading)

                TextField("custom-model-id", text: $agentModel)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.secondary)
                    .onChange(of: agentModel) { newValue in
                        agentService.setModel(newValue)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var modelTextField: some View {
        HStack {
            Text("Model")
                .font(.system(size: 13))
                .foregroundColor(SanctuaryColors.Text.secondary)
                .frame(width: 60, alignment: .leading)

            TextField("Model name", text: $agentModel)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(SanctuaryColors.Text.primary)
                .onChange(of: agentModel) { newValue in
                    agentService.setModel(newValue)
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(SanctuaryColors.Glass.secondary))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1))
    }

    @ViewBuilder
    private var testConnectionRow: some View {
        HStack {
            Button(action: testConnection) {
                HStack(spacing: 6) {
                    if isTestingConnection {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 13))
                    }
                    Text("Test Connection")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(CosmoColors.cosmoAI.opacity(0.2)))
                .foregroundColor(CosmoColors.cosmoAI)
            }
            .buttonStyle(.plain)
            .disabled(isTestingConnection)

            if let result = connectionResult {
                HStack(spacing: 4) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? .green : .red)
                    Text(result.message)
                        .font(.system(size: 12))
                        .foregroundColor(result.success ? .green : .red)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Telegram Section
    private var telegramSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsibleHeader(
                title: "Telegram Bot",
                subtitle: telegramBridge.isConnected ? "Connected" : "Disconnected",
                icon: "paperplane.fill",
                isExpanded: $isTelegramExpanded,
                statusColor: telegramBridge.isConnected ? .green : nil
            )

            if isTelegramExpanded {
                VStack(spacing: 12) {
                    // Token input
                    HStack(spacing: 8) {
                        SecureField("Bot Token", text: $telegramToken)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(SanctuaryColors.Text.primary)

                        if !telegramToken.isEmpty && !telegramToken.allSatisfy({ $0 == "\u{2022}" }) {
                            Button(action: saveTelegramToken) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(CosmoColors.cosmoAI)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(SanctuaryColors.Glass.secondary))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1))

                    // Start/Stop + Test + Status
                    telegramControlRow

                    // Setup instructions
                    Button(action: { showTelegramInstructions.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 12))
                            Text("How to create a Telegram bot")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(CosmoColors.cosmoAI)
                    }
                    .buttonStyle(.plain)

                    if showTelegramInstructions {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. Open Telegram and search for @BotFather")
                            Text("2. Send /newbot and follow the prompts")
                            Text("3. Copy the bot token and paste it above")
                            Text("4. Start a chat with your new bot")
                            Text("5. Click 'Start Polling' to connect")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(CosmoColors.lavender.opacity(0.1)))
                    }
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(SanctuaryColors.Glass.primary))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var telegramControlRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: {
                    if telegramBridge.isConnected {
                        telegramBridge.stop()
                    } else {
                        Task { await telegramBridge.start() }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: telegramBridge.isConnected ? "stop.fill" : "play.fill")
                            .font(.system(size: 12))
                        Text(telegramBridge.isConnected ? "Stop Polling" : "Start Polling")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(
                        telegramBridge.isConnected ? CosmoColors.coral.opacity(0.2) : CosmoColors.cosmoAI.opacity(0.2)
                    ))
                    .foregroundColor(telegramBridge.isConnected ? CosmoColors.coral : CosmoColors.cosmoAI)
                }
                .buttonStyle(.plain)

                Button(action: testTelegramBot) {
                    HStack(spacing: 6) {
                        if isTestingTelegram {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 12))
                        }
                        Text("Test Bot")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(SanctuaryColors.Glass.secondary))
                    .foregroundColor(SanctuaryColors.Text.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isTestingTelegram)

                HStack(spacing: 6) {
                    Circle()
                        .fill(telegramBridge.isConnected ? Color.green : (telegramBridge.lastError != nil ? Color.red : Color.gray))
                        .frame(width: 8, height: 8)

                    Text(telegramStatusText)
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
            }

            if let result = telegramTestResult {
                HStack(spacing: 4) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? .green : .red)
                    Text(result.message)
                        .font(.system(size: 12))
                        .foregroundColor(result.success ? .green : .red)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var telegramStatusText: String {
        if telegramBridge.isConnected {
            return "Connected (\(telegramBridge.messageCount) msgs)"
        }
        return telegramBridge.lastError ?? "Disconnected"
    }

    // MARK: - Voice Section
    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice Transcription")
                .font(SanctuaryTypography.titleSmall)
                .foregroundColor(SanctuaryColors.Text.primary)

            Text("OpenAI Whisper for voice messages in Telegram")
                .font(.system(size: 13))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    SecureField("Whisper API Key (optional)", text: $whisperKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    if !whisperKey.isEmpty && !whisperKey.allSatisfy({ $0 == "\u{2022}" }) {
                        Button(action: {
                            APIKeys.save(whisperKey, identifier: "whisper_api_key")
                        }) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(CosmoColors.cosmoAI)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(SanctuaryColors.Glass.secondary))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1))

                if APIKeys.hasWhisper {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text("Whisper API key saved")
                            .font(.system(size: 12))
                            .foregroundColor(SanctuaryColors.Text.secondary)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(SanctuaryColors.Glass.primary))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1))
        }
    }

    // MARK: - Proactive Section
    private var proactiveSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Proactive Intelligence")
                .font(SanctuaryTypography.titleSmall)
                .foregroundColor(SanctuaryColors.Text.primary)

            Text("Automated briefs and alerts via Telegram")
                .font(.system(size: 13))
                .foregroundColor(SanctuaryColors.Text.tertiary)

            VStack(spacing: 12) {
                // Morning brief
                morningBriefRow

                // Weekly review
                weeklyReviewRow

                // Streak alerts
                Toggle(isOn: $scheduler.streakAlertsEnabled) {
                    Text("Streak Protection Alerts")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.primary)
                }
                .toggleStyle(.switch)

                // DND
                Toggle(isOn: $scheduler.dndEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Respect Quiet Hours")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(SanctuaryColors.Text.primary)
                        Text("Defer messages during deep work sessions")
                            .font(.system(size: 11))
                            .foregroundColor(SanctuaryColors.Text.tertiary)
                    }
                }
                .toggleStyle(.switch)

                // Heartbeat
                heartbeatRow
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(SanctuaryColors.Glass.primary))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1))
        }
    }

    @ViewBuilder
    private var heartbeatRow: some View {
        HStack {
            Toggle(isOn: $scheduler.heartbeatEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heartbeat Check-In")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.primary)
                    Text("Periodic pulse of noteworthy activity")
                        .font(.system(size: 11))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }
            .toggleStyle(.switch)

            Spacer()

            if scheduler.heartbeatEnabled {
                Picker("", selection: $scheduler.heartbeatIntervalMinutes) {
                    Text("30 min").tag(30)
                    Text("1 hr").tag(60)
                    Text("2 hr").tag(120)
                    Text("4 hr").tag(240)
                }
                .pickerStyle(.menu)
                .frame(width: 90)
            }
        }
    }

    @ViewBuilder
    private var morningBriefRow: some View {
        HStack {
            Toggle(isOn: $scheduler.morningBriefEnabled) {
                Text("Morning Brief")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }
            .toggleStyle(.switch)

            Spacer()

            if scheduler.morningBriefEnabled {
                HStack(spacing: 4) {
                    Text("\(String(format: "%02d", scheduler.morningBriefHour)):\(String(format: "%02d", scheduler.morningBriefMinute))")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Stepper("", value: $scheduler.morningBriefHour, in: 0...23)
                        .labelsHidden()
                        .frame(width: 40)
                }
            }
        }
    }

    @ViewBuilder
    private var weeklyReviewRow: some View {
        HStack {
            Toggle(isOn: $scheduler.weeklyReviewEnabled) {
                Text("Weekly Review")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }
            .toggleStyle(.switch)

            Spacer()

            if scheduler.weeklyReviewEnabled {
                Picker("", selection: $scheduler.weeklyReviewDay) {
                    Text("Sun").tag(1)
                    Text("Mon").tag(2)
                    Text("Tue").tag(3)
                    Text("Wed").tag(4)
                    Text("Thu").tag(5)
                    Text("Fri").tag(6)
                    Text("Sat").tag(7)
                }
                .pickerStyle(.menu)
                .frame(width: 70)

                Text("\(String(format: "%02d", scheduler.weeklyReviewHour)):00")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Text.primary)
            }
        }
    }

    // MARK: - System Prompt Section
    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsibleHeader(
                title: "System Prompt",
                subtitle: isSystemPromptDirty ? "Modified" : "Default",
                icon: "text.alignleft",
                isExpanded: $isSystemPromptExpanded,
                statusColor: isSystemPromptDirty ? .orange : nil
            )

            if isSystemPromptExpanded {
                VStack(spacing: 12) {
                    Text("This prompt defines Cosmo's personality and behavior. Edits persist across sessions.")
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    SystemPromptTextEditor(text: $customSystemPrompt)
                        .frame(height: 320)
                        .background(RoundedRectangle(cornerRadius: 8).fill(SanctuaryColors.Glass.secondary))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1))
                        .onChange(of: customSystemPrompt) { newValue in
                            isSystemPromptDirty = newValue != AgentContextAssembler.defaultIdentityPrompt
                        }

                    // Token estimate
                    let tokenEstimate = max(1, customSystemPrompt.count / 4)
                    Text("\(tokenEstimate) estimated tokens")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    HStack(spacing: 12) {
                        Button(action: {
                            UserDefaults.standard.set(customSystemPrompt, forKey: "agent_custom_system_prompt")
                            isSystemPromptDirty = customSystemPrompt != AgentContextAssembler.defaultIdentityPrompt
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13))
                                Text("Save")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(CosmoColors.cosmoAI.opacity(0.2)))
                            .foregroundColor(CosmoColors.cosmoAI)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            customSystemPrompt = AgentContextAssembler.defaultIdentityPrompt
                            UserDefaults.standard.removeObject(forKey: "agent_custom_system_prompt")
                            isSystemPromptDirty = false
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 13))
                                Text("Reset to Default")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(SanctuaryColors.Glass.secondary))
                            .foregroundColor(SanctuaryColors.Text.secondary)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(SanctuaryColors.Glass.primary))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Skills Link Row

    private var skillsLinkRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 14))
                .foregroundColor(CosmoColors.cosmoAI)
                .frame(width: 20)

            Text("Skills & writing modules are managed in the Skills & Prompts tab.")
                .font(.system(size: 13))
                .foregroundColor(SanctuaryColors.Text.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(SanctuaryColors.Glass.primary))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1))
    }

    // MARK: - Collapsible Header Helper

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
                    .foregroundColor(CosmoColors.cosmoAI)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SanctuaryColors.Text.primary)

                if let color = statusColor {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }

                Spacer()

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - WhatsApp Section
    private var whatsappSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("WhatsApp")
                .font(SanctuaryTypography.titleSmall)
                .foregroundColor(SanctuaryColors.Text.primary)

            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 24))
                    .foregroundColor(CosmoColors.lavender)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Coming Soon")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.primary)
                    Text("WhatsApp requires a relay server for webhook callbacks. This will be available in v2.")
                        .font(.system(size: 12))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(SanctuaryColors.Glass.primary))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1))
        }
    }

    // MARK: - Actions

    private func saveAPIKey() {
        if selectedProvider == .openRouter {
            APIKeys.save(agentAPIKey, identifier: "openrouter")
        } else {
            APIKeys.save(agentAPIKey, identifier: "agent_llm")
        }
        // Refresh the provider so it picks up the new key, preserve current model
        let currentModel = agentModel
        agentService.setProvider(selectedProvider)
        agentService.setModel(currentModel)
        agentModel = currentModel
    }

    private func saveTelegramToken() {
        let input = telegramToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = TelegramBridgeService.sanitizeToken(input) else {
            telegramTestResult = (false, "Invalid token format. Paste only the BotFather token.")
            return
        }
        APIKeys.save(token, identifier: "telegram_bot_token")
        telegramToken = String(repeating: "\u{2022}", count: 30)
        telegramTestResult = nil
    }

    private func testTelegramBot() {
        isTestingTelegram = true
        telegramTestResult = nil
        Task {
            let result = await telegramBridge.testBot()
            isTestingTelegram = false
            telegramTestResult = result
        }
    }

    private func testConnection() {
        isTestingConnection = true
        connectionResult = nil
        Task {
            let result = await agentService.testConnection()
            isTestingConnection = false
            connectionResult = result
        }
    }
}

// MARK: - System Prompt Text Editor (NSViewRepresentable)

struct SystemPromptTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = NSColor.white.withAlphaComponent(0.8)
        textView.backgroundColor = .clear
        textView.insertionPointColor = NSColor.white
        textView.textContainerInset = NSSize(width: 8, height: 8)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        textView.string = text

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            if selectedRange.location + selectedRange.length <= text.count {
                textView.setSelectedRange(selectedRange)
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

// MARK: - Preview

#Preview("Cosmo Agent Settings") {
    CosmoAgentSettingsTab()
        .frame(width: 600, height: 700)
        .padding()
}
