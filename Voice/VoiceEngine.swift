// CosmoOS/Voice/VoiceEngine.swift
// Voice controller - Apple Speech (SFSpeechRecognizer) streaming ASR
// Commands route through VoiceCommandPipeline (pattern matching + Claude)

import Foundation
import AVFoundation
import Combine

@MainActor
class VoiceEngine: ObservableObject {
    static let shared = VoiceEngine()

    // MARK: - Published State
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var partialTranscript: String?
    @Published var finalTranscript: String?
    @Published var audioLevels: [Float] = []
    @Published var error: String?

    // MARK: - Dependencies
    // WhisperEngine: Apple Speech Framework streaming ASR (lazy loaded)
    nonisolated(unsafe) private let whisperEngine: WhisperEngine
    nonisolated(unsafe) private let audioCapture: AudioCapture
    private let hotkeyManager: HotkeyManager
    // Command pipeline - the REAL voice processing system

    private var cancellables = Set<AnyCancellable>()
    private var streamingTask: Task<Void, Never>?
    private var clearTranscriptTask: Task<Void, Never>?
    private var safetyTimeoutTask: Task<Void, Never>?  // Force-close voice if it hangs
    private var contextSnapshot: VoiceContextSnapshot?

    private enum LifecycleState: Equatable {
        case idle
        case starting
        case recording
        case stopping
        case processing
    }

    private var lifecycleState: LifecycleState = .idle
    private var stopRequestedWhileStarting = false

    private var didInitialize = false
    private var didRegisterHotkey = false
    private var initializeTask: Task<Void, Never>?

    private init() {
        self.whisperEngine = WhisperEngine()
        self.audioCapture = AudioCapture()
        self.hotkeyManager = HotkeyManager.shared

        setupBindings()

        // Register hotkey immediately on init (doesn't require any permissions that crash)
        // This ensures the hotkey works even before full voice initialization
        registerHotkey()
    }

    // MARK: - Setup
    func initialize() async {
        if didInitialize { return }
        if let task = initializeTask {
            await task.value
            return
        }

        let task = Task { @MainActor in
            print("🎤 Initializing Voice Engine...")

            // Register global hotkey FIRST (in case it wasn't done in init)
            // This ensures hotkey works even if speech init fails
            if !didRegisterHotkey {
                registerHotkey()
            }

            nonisolated(unsafe) let whisper = self.whisperEngine
            await whisper.loadModel()

            print("✅ Voice Engine ready (ASR: Apple Speech Framework)")
            didInitialize = true
            initializeTask = nil
        }

        initializeTask = task
        await task.value
    }

    private func setupBindings() {
        // Bind audio levels
        audioCapture.$audioLevels
            .receive(on: DispatchQueue.main)
            .assign(to: &$audioLevels)
    }

    private func registerHotkey() {
        guard !didRegisterHotkey else { return }

        print("🔑 Registering voice hotkey: \(hotkeyManager.currentHotkey.displayName)")

        hotkeyManager.registerSpaceHotkey(
            onPress: { [weak self] in
                Task { @MainActor in
                    await self?.startRecording()
                }
            },
            onRelease: { [weak self] in
                Task { @MainActor in
                    await self?.stopRecording()
                }
            }
        )

        didRegisterHotkey = true
    }

    // MARK: - Recording Control
    func startRecording() async {
        print("🎬 startRecording() called - lifecycleState: \(lifecycleState), isRecording: \(isRecording)")

        // Ensure dependencies are ready (user can trigger voice before app finishes booting)
        if !didInitialize {
            await initialize()
        }

        // Debounce: ignore if already recording/starting/stopping
        if lifecycleState == .starting || lifecycleState == .recording || lifecycleState == .stopping {
            print("🎬 startRecording: SKIPPED - already in state \(lifecycleState)")
            return
        }

        print("🎬 startRecording: proceeding to start...")
        lifecycleState = .starting
        stopRequestedWhileStarting = false
        contextSnapshot = VoiceContextStore.shared.snapshot()

        // Safety timeout: force reset if recording hangs for more than 30 seconds
        safetyTimeoutTask?.cancel()
        safetyTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            if let self = self, self.lifecycleState != .idle {
                print("⚠️ Voice safety timeout triggered after 30 seconds - force resetting")
                self.forceReset()
            }
        }

        isRecording = true
        isProcessing = false
        partialTranscript = nil
        finalTranscript = nil
        error = nil
        print("🎬 startRecording: isRecording set to true")

        // Cancel any pending clear from a previous run (prevents flicker/glitch)
        clearTranscriptTask?.cancel()
        clearTranscriptTask = nil

        // Notify UI to show voice pill
        NotificationCenter.default.post(
            name: .voiceRecordingStateChanged,
            object: nil,
            userInfo: ["isRecording": true]
        )

        // Start streaming transcription for real-time feedback
        startStreamingTranscription()

        do {
            // Start capture with VAD for visualization only (no auto-stop)
            nonisolated(unsafe) let whisperEngine = self.whisperEngine

            try await audioCapture.startCapture(
                enableVAD: true,  // Keep VAD for waveform visualization
                onSilenceDetected: nil,  // Disable auto-stop - only manual stop via hotkey release
                onAudioBuffer: { @Sendable buffer in
                    whisperEngine.feedAudioBuffer(buffer)
                }
            )
            NSLog("🎬 startRecording: audioCapture.startCapture() returned successfully")
            lifecycleState = .recording
            NSLog("🎬 startRecording: lifecycleState now .recording")
            print("🎤 Recording started (VAD for visualization only, manual stop)")
            fflush(stdout)  // Force flush to ensure logs appear

            // If user released key during startup, stop immediately once capture is live
            print("🎬 startRecording: checking stopRequestedWhileStarting = \(stopRequestedWhileStarting)")
            if stopRequestedWhileStarting {
                print("🎬 startRecording: stopRequestedWhileStarting was true, calling stopRecording()")
                stopRequestedWhileStarting = false
                await stopRecording()
            }
        } catch {
            print("❌ startRecording: CAUGHT ERROR: \(error)")
            self.error = "Failed to start recording: \(error.localizedDescription)"
            isRecording = false
            isProcessing = false
            lifecycleState = .idle
            stopRequestedWhileStarting = false

            // Cancel safety timeout since we're handling the error
            safetyTimeoutTask?.cancel()
            safetyTimeoutTask = nil

            // Clean up ASR streams
            streamingTask?.cancel()
            streamingTask = nil
            whisperEngine.stopStreamingTranscription()

            NotificationCenter.default.post(
                name: .voiceRecordingStateChanged,
                object: nil,
                userInfo: ["isRecording": false]
            )
        }
        print("🎬 startRecording: function completed, lifecycleState = \(lifecycleState)")
    }

    // MARK: - Streaming Transcription
    private func startStreamingTranscription() {
        // Cancel any existing streaming task
        streamingTask?.cancel()
        streamingTask = nil

        Task {
            await startWhisperStreamingWithLoad()
        }
    }

    /// Load WhisperEngine if needed, then start streaming
    private func startWhisperStreamingWithLoad() async {
        // Ensure WhisperEngine is loaded before streaming
        await whisperEngine.loadModel()
        startWhisperStreaming()
    }

    private func startWhisperStreaming() {
        streamingTask = Task { @MainActor in
            let stream = whisperEngine.startStreamingTranscription()

            for await token in stream {
                if !token.isFinal {
                    // Update partial transcript for live feedback
                    partialTranscript = token.text
                } else {
                    // Final result from streaming
                    finalTranscript = token.text
                }
            }
        }
    }

    func stopRecording() async {
        print("🛑 stopRecording() called - lifecycleState: \(lifecycleState), isRecording: \(isRecording)")

        // If stop requested during startup, remember it and return.
        if lifecycleState == .starting {
            print("🛑 stopRecording: state is .starting, setting stopRequestedWhileStarting = true")
            stopRequestedWhileStarting = true
            return
        }

        // Safety: if we're idle but isRecording is somehow still true, force reset UI
        if lifecycleState == .idle && isRecording {
            print("🛑 stopRecording: SAFETY RESET - lifecycle is idle but isRecording was true")
            isRecording = false
            isProcessing = false
            NotificationCenter.default.post(
                name: .voiceRecordingStateChanged,
                object: nil,
                userInfo: ["isRecording": false]
            )
            return
        }

        guard lifecycleState == .recording else {
            print("🛑 stopRecording: SKIPPED - lifecycleState is \(lifecycleState), not .recording")
            return
        }

        print("🛑 stopRecording: proceeding to stop...")
        lifecycleState = .stopping

        isRecording = false
        isProcessing = true
        print("🛑 stopRecording: isRecording set to false")

        // Capture the last partial transcript before stopping (streaming may not send final)
        let lastPartialTranscript = partialTranscript

        // Stop streaming transcription
        streamingTask?.cancel()
        whisperEngine.stopStreamingTranscription()

        // Notify UI
        NotificationCenter.default.post(
            name: .voiceRecordingStateChanged,
            object: nil,
            userInfo: ["isRecording": false]
        )

        do {
            let audioData = try await audioCapture.stopCapture()
            print("🎤 Recording stopped, processing...")

            // Determine the best transcript to use (in priority order):
            // 1. Final transcript from streaming (isFinal: true)
            // 2. Last partial transcript (the most recent streaming text)
            let transcriptToUse = finalTranscript.flatMap { $0.isEmpty ? nil : $0 }
                ?? lastPartialTranscript.flatMap { $0.isEmpty ? nil : $0 }

            if let transcript = transcriptToUse {
                // Filter out WhisperKit special tokens that indicate no speech
                let filteredTranscript = Self.filterWhisperSpecialTokens(transcript)

                if filteredTranscript.isEmpty {
                    print("📝 No speech detected (filtered WhisperKit token)")
                } else {
                    print("📝 Using transcript: \"\(filteredTranscript)\"")
                    lifecycleState = .processing
                    await routeCommand(filteredTranscript)
                }
                isProcessing = false
                lifecycleState = .idle
            } else if audioData.count > 0 {
                // Fallback: Transcribe the full audio (only if we have audio data)
                print("📝 No streaming transcript, falling back to full transcription...")
                lifecycleState = .processing
                let samples = convertToFloat32(audioData)
                await transcribeAudio(samples)
            } else {
                // No audio captured - silent completion
                print("📝 No audio captured - silent completion")
                isProcessing = false
                lifecycleState = .idle
            }

        } catch {
            self.error = "Failed to process audio: \(error.localizedDescription)"
            isProcessing = false
            lifecycleState = .idle
        }

        // Clear after a delay
        clearTranscriptTask?.cancel()
        clearTranscriptTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            partialTranscript = nil
            finalTranscript = nil
        }

        // Cancel safety timeout since we stopped successfully
        safetyTimeoutTask?.cancel()
        safetyTimeoutTask = nil
    }

    // MARK: - Transcription (fallback when streaming doesn't provide final result)
    private func transcribeAudio(_ samples: [Float]) async {
        var fullTranscript = ""

        for await token in whisperEngine.transcribe(samples) {
            if token.isFinal {
                fullTranscript = token.text
            } else {
                partialTranscript = token.text
            }
        }

        finalTranscript = fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        // Silent success if no speech - don't show error or route command
        if finalTranscript == nil || finalTranscript!.isEmpty {
            print("📝 No speech detected - silent completion")
            isProcessing = false
            lifecycleState = .idle
            return
        }

        print("📝 Transcription: \(finalTranscript ?? "")")

        // Route the command only if we have a transcript
        await routeCommand(finalTranscript!)

        isProcessing = false
        lifecycleState = .idle
    }

    private func routeCommand(_ transcript: String) async {
        // Clipboard capture commands — intercept before pipeline routing
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "swipe" || normalized == "swipe file" || normalized == "swipe this" {
            print("📋 Voice command: clipboard capture as swipe")
            await SwipeFileEngine.shared.captureFromClipboard(asSwipe: true)
            return
        }
        if normalized == "research" || normalized == "research this" || normalized == "save research" {
            print("📋 Voice command: clipboard capture as research")
            await SwipeFileEngine.shared.captureFromClipboard(asSwipe: false)
            return
        }

        // Convert NavigationSection to AppSection
        let section: AppSection = {
            switch contextSnapshot?.selectedSection {
            case .today: return .today
            case .ideas: return .ideas
            case .projects: return .projects
            case .research: return .research
            case .canvas: return .focus
            case .home: return .home
            case .content, .connections, .calendar, .library, .cosmo, .none:
                return .today
            }
        }()

        // Build VoiceContext from snapshot
        // Note: EntitySelection uses id not uuid - use navigationId as string identifier
        let context = VoiceContext(
            section: section,
            editingAtomUuid: contextSnapshot?.focusedEntity?.navigationId,
            selectedAtomUuids: contextSnapshot?.selectedEntity.map { [$0.navigationId] } ?? [],
            recentAtomUuids: [],
            currentProjectUuid: nil,
            currentDate: Date()
        )

        // Route through the REAL voice command pipeline
        let result = await VoiceCommandPipeline.shared.process(transcript, context: context)

        if result.success {
            print("✅ Command processed: tier=\(result.tier.rawValue), duration=\(result.durationMs)ms")
            if !result.atoms.isEmpty {
                print("   Created \(result.atoms.count) atom(s): \(result.atoms.map { $0.title ?? "untitled" }.joined(separator: ", "))")
            }
        } else {
            print("❌ Command failed: \(result.error ?? "Unknown error")")
            self.error = result.error
        }
    }

    // MARK: - Text Command Input (from command bar)
    /// Process a text command entered via the command bar (same routing as voice)
    /// Also handles URLs - if input is a URL, creates a research atom instead of voice command
    func processTextCommand(_ text: String) async {
        guard !text.isEmpty else { return }

        print("⌨️ Processing text command: \"\(text)\"")
        isProcessing = true

        // Clipboard capture commands — "swipe" or "research" grabs clipboard
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "swipe" || normalized == "swipe file" || normalized == "swipe this" {
            print("📋 Text command: clipboard capture as swipe")
            await SwipeFileEngine.shared.captureFromClipboard(asSwipe: true)
            isProcessing = false
            return
        }
        if normalized == "research" || normalized == "research this" || normalized == "save research" {
            print("📋 Text command: clipboard capture as research")
            await SwipeFileEngine.shared.captureFromClipboard(asSwipe: false)
            isProcessing = false
            return
        }

        // Check if input is a URL - if so, process as quick capture (research atom)
        if QuickCaptureProcessor.shared.isURL(text) {
            print("🔗 Detected URL input, routing to QuickCaptureProcessor")
            let wasProcessed = await QuickCaptureProcessor.shared.processInput(text)
            if wasProcessed {
                print("✅ URL processed as research atom")
                isProcessing = false
                return
            }
            // If URL processing failed, fall through to voice command
            print("⚠️ URL processing failed, falling back to voice command")
        }

        // Capture context before routing
        contextSnapshot = VoiceContextStore.shared.snapshot()

        await routeCommand(text)

        isProcessing = false
    }

    // MARK: - WhisperKit Token Filtering
    /// Filter out WhisperKit special tokens that don't represent actual speech
    /// These tokens are output by Whisper when it doesn't detect intelligible audio
    private static func filterWhisperSpecialTokens(_ transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        // WhisperKit special tokens that indicate no speech or hallucinations
        let specialTokens = [
            "[BLANK_AUDIO]",
            "[NO_SPEECH]",
            "[MUSIC]",
            "[APPLAUSE]",
            "[LAUGHTER]",
            "(music)",
            "(applause)",
            "(laughter)",
            "[inaudible]",
            "(inaudible)",
            "[ Silence ]",
            "[Silence]",
            "(silence)",
            "...",  // Whisper sometimes outputs just ellipsis for silence
        ]

        // Check if the transcript is only a special token
        for token in specialTokens {
            if trimmed.caseInsensitiveCompare(token) == .orderedSame {
                return ""
            }
        }

        // Also filter if transcript contains only special tokens with whitespace
        var filtered = trimmed
        for token in specialTokens {
            filtered = filtered.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }
        filtered = filtered.trimmingCharacters(in: .whitespacesAndNewlines)

        return filtered
    }

    // MARK: - Audio Conversion
    private func convertToFloat32(_ data: Data) -> [Float] {
        // Convert audio data to Float32 array for Whisper
        let int16Array = data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Int16.self))
        }

        return int16Array.map { Float($0) / Float(Int16.max) }
    }

    // MARK: - Error Recovery

    /// Force reset all voice engine state. Call this to recover from catastrophic failures.
    /// This will close the voice pill and reset all internal state.
    func forceReset() {
        print("⚠️ VoiceEngine.forceReset() called - resetting all state")

        // Cancel any ongoing tasks
        streamingTask?.cancel()
        streamingTask = nil
        clearTranscriptTask?.cancel()
        clearTranscriptTask = nil
        safetyTimeoutTask?.cancel()
        safetyTimeoutTask = nil

        // Reset ASR state
        whisperEngine.stopStreamingTranscription()

        // Stop audio capture (ignore errors)
        Task {
            _ = try? await audioCapture.stopCapture()
        }

        // Reset all state
        lifecycleState = .idle
        stopRequestedWhileStarting = false
        isRecording = false
        isProcessing = false
        partialTranscript = nil
        finalTranscript = nil
        error = nil
        contextSnapshot = nil

        // Notify UI to close voice pill
        NotificationCenter.default.post(
            name: .voiceRecordingStateChanged,
            object: nil,
            userInfo: ["isRecording": false]
        )

        print("✅ VoiceEngine force reset complete")
    }

    // MARK: - Cleanup
    deinit {
        // Schedule cleanup on main actor since hotkeyManager is MainActor isolated
        Task { @MainActor in
            HotkeyManager.shared.unregister()
        }
    }
}

// MARK: - Transcription Token
struct TranscriptionToken {
    let text: String
    let isFinal: Bool
    let timestamp: TimeInterval?

    init(text: String, isFinal: Bool, timestamp: TimeInterval? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.timestamp = timestamp
    }
}
