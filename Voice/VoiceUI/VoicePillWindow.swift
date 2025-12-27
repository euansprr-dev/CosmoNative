// CosmoOS/Voice/VoiceUI/VoicePillWindow.swift
// Always-visible command bar - voice + text input (top of screen)

import SwiftUI
import AppKit

// MARK: - Command Bar Mode
enum CommandBarMode: Equatable {
    case idle       // Small bar, mic icon, hint text
    case listening  // Push-to-talk active, waveform
    case typing     // Expanded with text field
}

// MARK: - Custom Panel that can become key for text input
class VoiceKeyablePanel: NSPanel {
    var allowsKeyboardInput: Bool = false

    override var canBecomeKey: Bool {
        return allowsKeyboardInput
    }

    override var canBecomeMain: Bool {
        return false
    }
}

class VoicePillWindowController: NSWindowController, ObservableObject {
    private var pillWindow: VoiceKeyablePanel!

    // Size constants
    private let idleWidth: CGFloat = 180
    private let idleHeight: CGFloat = 36
    private let typingWidth: CGFloat = 320
    private let typingHeight: CGFloat = 44
    private let topPadding: CGFloat = 32

    private var currentMode: CommandBarMode = .idle
    private var animationToken: Int = 0
    private var keyResignObserver: NSObjectProtocol?
    private var typingActivationObserver: NSObjectProtocol?

    // Shared state for SwiftUI view
    @Published var commandBarMode: CommandBarMode = .idle

    init() {
        let defaultRect = NSRect(x: 0, y: 0, width: idleWidth, height: idleHeight)

        pillWindow = VoiceKeyablePanel(
            contentRect: defaultRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: pillWindow)

        // Configure floating panel
        pillWindow.isFloatingPanel = true
        pillWindow.level = .floating
        pillWindow.backgroundColor = .clear
        pillWindow.isOpaque = false
        pillWindow.hasShadow = true
        pillWindow.titleVisibility = .hidden
        pillWindow.titlebarAppearsTransparent = true
        pillWindow.styleMask.remove(.titled)
        pillWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Allow mouse events for click-to-type
        pillWindow.ignoresMouseEvents = false

        // Allow keyboard input when needed (for typing mode)
        pillWindow.becomesKeyOnlyIfNeeded = true

        pillWindow.isReleasedWhenClosed = false

        // Observe when panel loses key status (user clicked elsewhere)
        keyResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: pillWindow,
            queue: .main
        ) { [weak self] _ in
            self?.handleKeyResign()
        }

        // Observe Option-C hotkey to activate typing mode
        typingActivationObserver = NotificationCenter.default.addObserver(
            forName: .activateCommandBarTyping,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.activateTypingMode()
        }

        // Set content view with environment objects
        let contentView = NSHostingView(
            rootView: CommandBarView(windowController: self)
                .environmentObject(VoiceEngine.shared)
        )
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = idleHeight / 2
        contentView.layer?.masksToBounds = true
        pillWindow.contentView = contentView

        // Start hidden, will be shown via showAlways()
        pillWindow.orderOut(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer = keyResignObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = typingActivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Handle Key Resign (blur detection)
    private func handleKeyResign() {
        // When panel loses key status while in typing mode, exit typing mode
        if currentMode == .typing {
            resizeToMode(.idle)
            // Notify SwiftUI view via published property
            commandBarMode = .idle
        }
    }

    // MARK: - External Typing Mode Trigger (Option-C)
    /// Activates typing mode from external keybind (Option-C)
    func activateTypingMode() {
        guard currentMode != .typing else { return }
        resizeToMode(.typing)
        commandBarMode = .typing
    }

    // MARK: - Always Visible (called on app start)
    func showAlways() {
        let screenFrame = positioningFrame()

        // TOP center position
        let x = screenFrame.midX - (idleWidth / 2)
        let y = screenFrame.maxY - idleHeight - topPadding

        pillWindow.setFrameOrigin(NSPoint(x: x, y: y))
        pillWindow.alphaValue = 1

        pillWindow.level = .floating
        pillWindow.orderFrontRegardless()

        print("📍 Command bar shown at top center (\(x), \(y))")
    }

    // MARK: - Show (for recording state - animate briefly)
    func show() {
        // If already visible, just ensure it's at front
        if pillWindow.isVisible {
            pillWindow.orderFrontRegardless()
            return
        }

        animationToken += 1
        let screenFrame = positioningFrame()

        // TOP center position
        let currentWidth = currentMode == .typing ? typingWidth : idleWidth
        let currentHeight = currentMode == .typing ? typingHeight : idleHeight

        let x = screenFrame.midX - (currentWidth / 2)
        let finalY = screenFrame.maxY - currentHeight - topPadding
        let startY = finalY + 24  // Start above for slide-down entrance

        pillWindow.setFrameOrigin(NSPoint(x: x, y: startY))
        pillWindow.alphaValue = 0

        pillWindow.level = .floating
        pillWindow.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)
            pillWindow.animator().setFrameOrigin(NSPoint(x: x, y: finalY))
            pillWindow.animator().alphaValue = 1
        }
    }

    // MARK: - Hide (NO-OP now - bar stays visible)
    func hide() {
        // Command bar is always visible - this is now a no-op
        // Only collapse from typing mode if active
        if currentMode == .typing {
            resizeToMode(.idle)
        }
    }

    // MARK: - Resize for Mode Changes
    func resizeToMode(_ mode: CommandBarMode) {
        guard mode != currentMode else { return }
        currentMode = mode

        animationToken += 1
        let screenFrame = positioningFrame()

        let targetWidth = mode == .typing ? typingWidth : idleWidth
        let targetHeight = mode == .typing ? typingHeight : idleHeight

        let x = screenFrame.midX - (targetWidth / 2)
        let y = screenFrame.maxY - targetHeight - topPadding

        let newFrame = NSRect(x: x, y: y, width: targetWidth, height: targetHeight)

        // Update corner radius
        if let contentView = pillWindow.contentView {
            contentView.layer?.cornerRadius = targetHeight / 2
        }

        // Enable/disable keyboard input based on mode
        if mode == .typing {
            enableKeyboardInput()
        } else {
            disableKeyboardInput()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = mode == .typing ? 0.3 : 0.2
            context.timingFunction = mode == .typing
                ? CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)  // Spring for expand
                : CAMediaTimingFunction(name: .easeOut)  // Ease for collapse
            self.pillWindow.animator().setFrame(newFrame, display: true)
        }
    }

    // MARK: - Keyboard Input Control
    func enableKeyboardInput() {
        pillWindow.allowsKeyboardInput = true
        pillWindow.makeKey()
    }

    func disableKeyboardInput() {
        pillWindow.allowsKeyboardInput = false
        pillWindow.resignKey()
    }

    private func positioningFrame() -> CGRect {
        return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}

// MARK: - Command Bar View (Voice + Text Input)
struct CommandBarView: View {
    @EnvironmentObject var voiceEngine: VoiceEngine
    @ObservedObject var windowController: VoicePillWindowController

    @State private var mode: CommandBarMode = .idle
    @State private var textInput: String = ""
    @State private var isHovering: Bool = false
    @State private var showSuccess = false
    @State private var showError = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Left: Icon
            leftIcon
                .frame(width: 20, height: 20)

            // Center: Content (hint, waveform, or text field)
            centerContent
                .frame(maxWidth: .infinity)

            // Right: Indicator or submit button
            rightContent
                .frame(width: 20, height: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, mode == .typing ? 10 : 8)
        .frame(height: mode == .typing ? 44 : 36)
        .background(backgroundView)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: mode)
        .onTapGesture {
            if mode == .idle && !voiceEngine.isRecording {
                enterTypingMode()
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .onChange(of: voiceEngine.isRecording) { _, isRecording in
            if isRecording {
                // Switch to listening when recording starts
                // Also clears typing mode if user presses voice keybind
                if mode == .typing {
                    isTextFieldFocused = false
                    textInput = ""
                }
                if mode != .listening {
                    mode = .listening
                    windowController.resizeToMode(.listening)
                }
            } else if mode == .listening {
                // Return to idle when recording stops
                mode = .idle
                windowController.resizeToMode(.idle)
            }
        }
        .onChange(of: voiceEngine.error) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            showError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                showError = false
            }
        }
        .onChange(of: voiceEngine.isProcessing) { _, isProcessing in
            if !isProcessing && voiceEngine.finalTranscript != nil {
                showSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showSuccess = false
                }
            }
        }
        .onKeyPress(.escape) {
            if mode == .typing {
                exitTypingMode()
                return .handled
            }
            return .ignored
        }
        .onChange(of: isTextFieldFocused) { _, isFocused in
            // Exit typing mode when text field loses focus (blur)
            if !isFocused && mode == .typing {
                exitTypingMode()
            }
        }
        .onChange(of: windowController.commandBarMode) { _, newMode in
            // Sync with window controller's mode (for blur detection from AppKit)
            if mode != newMode {
                mode = newMode
                if newMode == .idle {
                    isTextFieldFocused = false
                    textInput = ""
                }
            }
        }
    }

    // MARK: - Background
    private var backgroundView: some View {
        ZStack {
            // Apple-style dark glass base with blur
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)

            // Dark translucent overlay for depth
            Capsule()
                .fill(Color.black.opacity(0.35))

            // Subtle inner highlight for glass depth
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Subtle border
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isHovering ? 0.20 : 0.12),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )

            // Recording pulse border
            if mode == .listening {
                Capsule()
                    .strokeBorder(
                        CosmoColors.lavender.opacity(0.5),
                        lineWidth: 1.5
                    )
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }

    // MARK: - Left Icon
    @ViewBuilder
    private var leftIcon: some View {
        ZStack {
            if showError {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(CosmoColors.softRed)
                    .transition(.scale.combined(with: .opacity))
            } else if showSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(CosmoColors.emerald)
                    .transition(.scale.combined(with: .opacity))
            } else if voiceEngine.isProcessing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.5)
                    .tint(CosmoColors.textSecondary)
            } else {
                switch mode {
                case .idle:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(CosmoColors.textSecondary)
                case .listening:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(CosmoColors.lavender)
                case .typing:
                    Image(systemName: "text.cursor")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(CosmoColors.textSecondary)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    // MARK: - Center Content
    @ViewBuilder
    private var centerContent: some View {
        switch mode {
        case .idle:
            // Hint text
            Text("Space or click")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(CosmoColors.textTertiary)

        case .listening:
            // Waveform
            EnhancedWaveformView(levels: voiceEngine.audioLevels)
                .frame(height: 20)

        case .typing:
            // Text field - white text for dark glass background
            TextField("Type a command...", text: $textInput)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .focused($isTextFieldFocused)
                .onSubmit {
                    submitTextCommand()
                }
        }
    }

    // MARK: - Right Content
    @ViewBuilder
    private var rightContent: some View {
        switch mode {
        case .idle:
            // Keyboard hint
            Text("Z")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(CosmoColors.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.08))
                )

        case .listening:
            // Recording indicator
            ZStack {
                Circle()
                    .fill(CosmoColors.coral.opacity(0.2))
                    .frame(width: 12, height: 12)

                Circle()
                    .fill(CosmoColors.coral)
                    .frame(width: 6, height: 6)
            }

        case .typing:
            // Submit button
            Button {
                submitTextCommand()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(textInput.isEmpty ? CosmoColors.textTertiary : CosmoColors.lavender)
            }
            .buttonStyle(.plain)
            .disabled(textInput.isEmpty)
        }
    }

    // MARK: - Actions
    private func enterTypingMode() {
        mode = .typing
        windowController.commandBarMode = .typing
        windowController.resizeToMode(.typing)

        // Focus text field after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isTextFieldFocused = true
        }
    }

    private func exitTypingMode() {
        isTextFieldFocused = false
        textInput = ""
        mode = .idle
        windowController.commandBarMode = .idle
        windowController.resizeToMode(.idle)
    }

    private func submitTextCommand() {
        guard !textInput.isEmpty else { return }

        let command = textInput
        textInput = ""

        // Route through voice engine
        Task {
            await VoiceEngine.shared.processTextCommand(command)
        }

        // Stay in typing mode - user can continue typing
        // Only exit when: blur (click elsewhere), Escape, or voice keybind
    }
}

// MARK: - Enhanced Waveform (24 bars, 60fps, Perlin noise, smart state detection)
struct EnhancedWaveformView: View {
    let levels: [Float]
    private let barCount = 24

    @StateObject private var animator = WaveformAnimator()

    private let barGradient = LinearGradient(
        colors: [
            CosmoColors.lavender,
            CosmoColors.skyBlue
        ],
        startPoint: .bottom,
        endPoint: .top
    )

    var body: some View {
        // PERFORMANCE: Limit to 60fps - plenty smooth for waveform, saves 50%+ CPU
        SwiftUI.TimelineView(.animation(minimumInterval: 1/60)) { timeline in
            let displayLevels = animator.computeDisplayLevels(audioLevels: levels, barCount: barCount)

            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let level = displayLevels[index]
                    let height = max(3, CGFloat(level) * 20)

                    RoundedRectangle(cornerRadius: 1)
                        .fill(barGradient)
                        .frame(width: 2, height: height)
                }
            }
        }
        .drawingGroup() // GPU-accelerate waveform rendering
    }
}

// MARK: - Waveform Animator (State management for smooth animations)
@MainActor
class WaveformAnimator: ObservableObject {
    // NOTE: idlePhase is NOT @Published to avoid "Publishing changes from within view updates" error
    // It's modified in computeDisplayLevels which is called during TimelineView body evaluation
    private var idlePhase: Double = 0
    private var barMomentum: [Float] = []
    private var perlinOffsets: [Double] = []

    // Smart state detection
    private var consecutiveActiveFrames: Int = 0
    private var consecutiveIdleFrames: Int = 0
    private var isDefinitelySpeaking: Bool = false

    init() {
        // Pre-compute Perlin noise offsets for organic motion
        perlinOffsets = (0..<24).map { Double($0) * 0.6 }
        barMomentum = Array(repeating: 0.3, count: 24)
    }

    func computeDisplayLevels(audioLevels: [Float], barCount: Int) -> [Float] {
        // Ensure momentum array matches bar count
        if barMomentum.count != barCount {
            barMomentum = Array(repeating: 0.3, count: barCount)
        }

        let isSpeaking = analyzeAudioState(levels: audioLevels)

        // Update idle phase for breathing animation
        idlePhase += 0.04
        if idlePhase > Double.pi * 2 {
            idlePhase -= Double.pi * 2
        }

        if !isSpeaking {
            // Breathing idle animation with Perlin-like noise
            return (0..<barCount).map { i in
                let offset = i < perlinOffsets.count ? perlinOffsets[i] : Double(i) * 0.6
                let wave1 = sin(idlePhase + offset)
                let wave2 = sin(idlePhase * 1.3 + offset * 0.7) * 0.5
                let combined = (wave1 + wave2) / 1.5
                return Float(0.3 + combined * 0.2)
            }
        }

        // Speaking: reactive to audio with momentum
        let step = max(1, audioLevels.count / barCount)
        var targetLevels: [Float] = []

        for i in 0..<barCount {
            let index = min(i * step, audioLevels.count - 1)
            let rawLevel = audioLevels[index]

            // Amplify and apply easing curve
            let amplified = rawLevel * 3.5
            let eased = easeOutQuad(amplified)
            let clamped = max(0.15, min(1.0, eased))
            targetLevels.append(clamped)
        }

        // Apply momentum for smooth transitions
        var result: [Float] = []
        for i in 0..<barCount {
            let target = targetLevels[i]
            let current = barMomentum[i]

            // Decay towards target (smooth interpolation)
            let decayFactor: Float = 0.25
            let newLevel = current + (target - current) * decayFactor
            result.append(newLevel)
        }

        // Update momentum state
        barMomentum = result

        return result
    }

    private func analyzeAudioState(levels: [Float]) -> Bool {
        guard !levels.isEmpty else { return false }

        // Calculate running average of recent samples
        let recentSamples = levels.suffix(10)
        let average = recentSamples.reduce(0, +) / Float(recentSamples.count)

        // Track if audio is above or below threshold
        if average > 0.03 {
            consecutiveActiveFrames += 1
            consecutiveIdleFrames = 0

            // After 3 consecutive active frames, definitely speaking
            if consecutiveActiveFrames >= 3 {
                isDefinitelySpeaking = true
            }
        } else if average < 0.01 {
            consecutiveIdleFrames += 1
            consecutiveActiveFrames = 0

            // After 10 consecutive idle frames, definitely idle
            if consecutiveIdleFrames >= 10 {
                isDefinitelySpeaking = false
            }
        }

        return isDefinitelySpeaking
    }

    // Ease out quadratic for smoother visual response
    private func easeOutQuad(_ value: Float) -> Float {
        let t = min(1.0, max(0.0, value))
        return t * (2.0 - t)
    }
}

// MARK: - Thinking Dots Animation
struct ThinkingDotsView: View {
    @State private var dotOpacity: [Double] = [0.3, 0.3, 0.3]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white)
                    .frame(width: 4, height: 4)
                    .opacity(dotOpacity[index])
            }
        }
        .onAppear {
            animateDots()
        }
    }

    private func animateDots() {
        for i in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.4)
                .repeatForever(autoreverses: true)
                .delay(Double(i) * 0.15)
            ) {
                dotOpacity[i] = 1.0
            }
        }
    }
}

// MARK: - Legacy Minimal Waveform (kept for compatibility)
struct MinimalWaveformView: View {
    let levels: [Float]
    private let barCount = 12

    private var displayLevels: [Float] {
        if levels.isEmpty {
            return (0..<barCount).map { i in
                Float(0.2 + 0.15 * sin(Double(i) * 0.6 + Date().timeIntervalSince1970 * 2))
            }
        }

        let step = max(1, levels.count / barCount)
        var sampled: [Float] = []
        for i in 0..<barCount {
            let index = min(i * step, levels.count - 1)
            let rawLevel = levels[index]
            let smoothed = max(0.15, min(1.0, rawLevel * 1.5))
            sampled.append(smoothed)
        }
        return sampled
    }

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                CosmoColors.cosmoAI,
                                CosmoColors.lavender
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(
                        width: 2.5,
                        height: max(4, CGFloat(displayLevels[index]) * 16)
                    )
                    .animation(.easeOut(duration: 0.06), value: displayLevels[index])
            }
        }
    }
}

// MARK: - Shimmer Loading Animation
struct ShimmerView: View {
    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.2),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .offset(x: shimmerOffset * geometry.size.width)
                )
                .mask(RoundedRectangle(cornerRadius: 4))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                shimmerOffset = 2
            }
        }
    }
}

// MARK: - Command Bar Notifications
extension Notification.Name {
    /// Activate command bar typing mode (Option-C hotkey)
    static let activateCommandBarTyping = Notification.Name("activateCommandBarTyping")
}
