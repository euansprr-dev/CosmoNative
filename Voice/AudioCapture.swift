// CosmoOS/Voice/AudioCapture.swift
// AVAudioEngine-based audio capture with level monitoring

import Foundation
import AVFoundation
import Combine
import CoreAudio

class AudioCapture: ObservableObject {
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 60)
    @Published var isSpeaking: Bool = false

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioBuffer: AVAudioPCMBuffer?
    private var recordedData: Data = Data()

    // MARK: - Health / Debug
    private var framesReceived: Int = 0
    private var lastReportedFrames: Int = 0
    private var lastFrameAt: Date?
    private var healthTimer: DispatchSourceTimer?
    private var captureInputFormat: AVAudioFormat?

    // MARK: - Voice Activity Detection (VAD)
    private var silenceStartTime: Date?
    private var hasSpeechStarted: Bool = false
    private var onSilenceDetected: (() -> Void)?

    /// VAD Configuration
    struct VADConfig {
        /// Amplitude threshold below which is considered silence
        let silenceThreshold: Float = 0.02

        /// Duration of silence (seconds) before triggering auto-stop
        let silenceDuration: TimeInterval = 1.5

        /// Minimum speech duration before allowing silence detection
        let minSpeechDuration: TimeInterval = 0.3

        /// Initial grace period before silence detection starts
        let initialGracePeriod: TimeInterval = 0.5

        /// Audio gain to apply to quiet microphones (1.0 = no gain, 10.0 = 10x amplification)
        /// Set higher if RMS values are consistently below 0.02 during speech
        let audioGain: Float = 8.0
    }

    private let vadConfig = VADConfig()
    private var recordingStartTime: Date?

    /// Callback for streaming transcription - called with each audio buffer
    private var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    // MARK: - Start Capture
    /// Start audio capture with optional Voice Activity Detection and streaming
    /// - Parameters:
    ///   - enableVAD: Whether to enable automatic silence detection
    ///   - onSilenceDetected: Callback when prolonged silence is detected (auto-stop trigger)
    ///   - onAudioBuffer: Callback for each audio buffer (for streaming transcription)
    func startCapture(
        enableVAD: Bool = true,
        onSilenceDetected: (() -> Void)? = nil,
        onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)? = nil
    ) async throws {
        // Request microphone permission
        let authorized = await requestMicrophonePermission()
        guard authorized else {
            throw AudioCaptureError.permissionDenied
        }

        // Reset VAD state
        self.onSilenceDetected = enableVAD ? onSilenceDetected : nil
        self.silenceStartTime = nil
        self.hasSpeechStarted = false
        self.recordingStartTime = Date()

        // Store audio buffer callback for streaming transcription
        self.onAudioBuffer = onAudioBuffer

        // Setup audio engine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw AudioCaptureError.engineInitFailed
        }

        inputNode = engine.inputNode
        guard let input = inputNode else {
            throw AudioCaptureError.noInputDevice
        }

        recordedData = Data()

        // Use the input node's native format instead of forcing a specific format
        let inputFormat = input.outputFormat(forBus: 0)
        captureInputFormat = inputFormat

        // Log the audio device being used for diagnostics
        if let audioUnit = input.audioUnit {
            var deviceID: AudioDeviceID = 0
            var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
            let status = AudioUnitGetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                &propSize
            )
            if status == noErr {
                var deviceName: CFString?
                var nameSize = UInt32(MemoryLayout<CFString?>.size)
                var nameAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyDeviceNameCFString,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                _ = withUnsafeMutablePointer(to: &deviceName) { ptr in
                    AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, ptr)
                }
                let name = (deviceName as String?) ?? "Unknown"
                print("🎙️ Audio input device: \(name) (ID: \(deviceID))")
            }
        }

        // Reset health counters
        framesReceived = 0
        lastReportedFrames = 0
        lastFrameAt = nil
        conversionSuccessCount = 0
        conversionFailCount = 0

        // Create a converter format if needed (for Whisper compatibility)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        // Install tap with the input's native format to avoid crashes
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, targetFormat: targetFormat)
        }

        // Start engine
        try engine.start()
        startHealthTimer()
        print("🎤 Audio capture started (VAD: \(enableVAD ? "enabled" : "disabled"))")
        print("   🎚️ Input format: \(inputFormat.sampleRate)Hz, ch=\(inputFormat.channelCount), \(inputFormat.commonFormat)")
        NSLog("🎤 AudioCapture.startCapture() RETURNING NOW")
    }

    // MARK: - Stop Capture
    func stopCapture() async throws -> Data {
        guard let engine = audioEngine, let input = inputNode else {
            throw AudioCaptureError.notRecording
        }

        // Remove tap and stop engine
        input.removeTap(onBus: 0)
        engine.stop()
        stopHealthTimer()

        let capturedData = recordedData
        recordedData = Data()

        // Keep audio engine and input node for next recording
        // audioEngine = nil
        // inputNode = nil

        // Clear audio levels
        nonisolated(unsafe) let capture = self
        Task { @MainActor in
            capture.audioLevels = Array(repeating: 0, count: 60)
        }

        print("🎤 Audio capture stopped, captured \(capturedData.count) bytes")
        print("   📊 Conversion stats: \(conversionSuccessCount) succeeded, \(conversionFailCount) failed, \(framesReceived) total frames")
        return capturedData
    }

    // MARK: - Audio Processing
    private var conversionSuccessCount = 0
    private var conversionFailCount = 0

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        framesReceived += 1
        lastFrameAt = Date()

        // Convert to target format (16kHz mono) for daemon ASR
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            conversionFailCount += 1
            if conversionFailCount <= 3 {
                print("⚠️ AudioCapture: Could not create converter (fail #\(conversionFailCount))")
            }
            processBufferDirectly(buffer)
            return
        }

        // Create output buffer for converted audio
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            conversionFailCount += 1
            if conversionFailCount <= 3 {
                print("⚠️ AudioCapture: Could not create output buffer (fail #\(conversionFailCount))")
            }
            return
        }

        var error: NSError?
        // Use nonisolated(unsafe) since AVAudioConverterInputBlock requires @Sendable
        // but this is actually a synchronous callback that doesn't cross isolation domains
        nonisolated(unsafe) var inputConsumed = false
        nonisolated(unsafe) let capturedBuffer = buffer
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return capturedBuffer
        }

        let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        // Status can be .haveData (0) or .inputRanDry (1) - both are success when we have output frames
        // .inputRanDry just means the converter consumed all input, which is expected
        let isSuccess = (status == .haveData || status == .inputRanDry) && error == nil && convertedBuffer.frameLength > 0

        if isSuccess {
            conversionSuccessCount += 1

            // Apply audio gain to boost quiet microphones
            if vadConfig.audioGain != 1.0, let channelData = convertedBuffer.floatChannelData?[0] {
                let frameLength = Int(convertedBuffer.frameLength)
                for i in 0..<frameLength {
                    // Apply gain with soft clipping to avoid harsh distortion
                    let amplified = channelData[i] * vadConfig.audioGain
                    // Soft clip using tanh to prevent harsh clipping artifacts
                    channelData[i] = tanh(amplified)
                }
            }

            // Feed CONVERTED 16kHz buffer to streaming transcription
            // This is what daemon L1 ASR expects
            onAudioBuffer?(convertedBuffer)
            processConvertedBuffer(convertedBuffer)
        } else {
            conversionFailCount += 1
            if conversionFailCount <= 5 {
                print("⚠️ AudioCapture: Conversion failed - status=\(status.rawValue), error=\(error?.localizedDescription ?? "nil"), frames=\(convertedBuffer.frameLength)")
            }
            // Conversion failed — still keep levels/data flowing for UI
            processBufferDirectly(buffer)
        }
    }

    private func processBufferDirectly(_ buffer: AVAudioPCMBuffer) {
        // Handle different audio formats
        if buffer.format.commonFormat == .pcmFormatFloat32 {
            guard let channelData = buffer.floatChannelData else { return }
            let channelDataPointer = channelData.pointee
            let frameLength = Int(buffer.frameLength)

            // Convert Float32 to Int16 for storage
            var int16Data = [Int16]()
            int16Data.reserveCapacity(frameLength)
            for i in 0..<frameLength {
                let sample = channelDataPointer[i]
                let clampedSample = max(-1.0, min(1.0, sample))
                int16Data.append(Int16(clampedSample * Float(Int16.max)))
            }

            let data = Data(bytes: int16Data, count: frameLength * MemoryLayout<Int16>.size)
            recordedData.append(data)

            // Calculate audio level
            let level = calculateAudioLevelFloat32(channelDataPointer, frameLength: frameLength)
            updateAudioLevel(level)
        } else if buffer.format.commonFormat == .pcmFormatInt16 {
            guard let channelData = buffer.int16ChannelData else { return }
            let channelDataPointer = channelData.pointee
            let frameLength = Int(buffer.frameLength)

            let data = Data(bytes: channelDataPointer, count: frameLength * MemoryLayout<Int16>.size)
            recordedData.append(data)

            let level = calculateAudioLevel(channelDataPointer, frameLength: frameLength)
            updateAudioLevel(level)
        }
    }

    private func processConvertedBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelDataPointer = channelData.pointee
        let frameLength = Int(buffer.frameLength)

        // Convert Float32 to Int16 for storage
        var int16Data = [Int16]()
        int16Data.reserveCapacity(frameLength)
        for i in 0..<frameLength {
            let sample = channelDataPointer[i]
            let clampedSample = max(-1.0, min(1.0, sample))
            int16Data.append(Int16(clampedSample * Float(Int16.max)))
        }

        let data = Data(bytes: int16Data, count: frameLength * MemoryLayout<Int16>.size)
        recordedData.append(data)

        // Calculate audio level
        let level = calculateAudioLevelFloat32(channelDataPointer, frameLength: frameLength)
        updateAudioLevel(level)
    }

    private func updateAudioLevel(_ level: Float) {
        // Apply noise gate - only show levels above threshold for clear visual feedback
        // This makes the waveform flat when silent and reactive when speaking
        let gatedLevel = level > vadConfig.silenceThreshold ? level : 0.0

        // Update audio levels for visualization - must run on MainActor
        nonisolated(unsafe) let capture = self
        Task { @MainActor in
            capture.audioLevels.removeFirst()
            capture.audioLevels.append(gatedLevel)
            capture.isSpeaking = level > capture.vadConfig.silenceThreshold
        }

        // Voice Activity Detection (use raw level for accurate detection)
        processVAD(level: level)
    }

    // MARK: - Voice Activity Detection Processing
    private func processVAD(level: Float) {
        guard onSilenceDetected != nil else { return }
        guard let startTime = recordingStartTime else { return }

        let timeSinceStart = Date().timeIntervalSince(startTime)

        // Initial grace period - don't detect silence yet
        if timeSinceStart < vadConfig.initialGracePeriod {
            return
        }

        let isSilent = level < vadConfig.silenceThreshold

        if isSilent {
            // Silence detected
            if silenceStartTime == nil {
                silenceStartTime = Date()
            }

            // Check if we've had speech first and silence is long enough
            if hasSpeechStarted,
               let silenceStart = silenceStartTime,
               Date().timeIntervalSince(silenceStart) >= vadConfig.silenceDuration {

                print("🔇 VAD: Silence detected for \(vadConfig.silenceDuration)s - triggering auto-stop")

                // Trigger callback on main thread
                nonisolated(unsafe) let callback = onSilenceDetected
                DispatchQueue.main.async {
                    callback?()
                }

                // Reset to prevent multiple triggers
                onSilenceDetected = nil
            }
        } else {
            // Speech detected
            silenceStartTime = nil

            // Mark that speech has started (after min speech duration)
            if !hasSpeechStarted && timeSinceStart >= vadConfig.minSpeechDuration {
                hasSpeechStarted = true
                print("🎙️ VAD: Speech detected")
            }
        }
    }

    private func calculateAudioLevelFloat32(_ samples: UnsafePointer<Float>, frameLength: Int) -> Float {
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += abs(samples[i])
        }
        return min(sum / Float(frameLength), 1.0)
    }

    private func calculateAudioLevel(_ samples: UnsafePointer<Int16>, frameLength: Int) -> Float {
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = Float(samples[i]) / Float(Int16.max)
            sum += abs(sample)
        }
        return min(sum / Float(frameLength), 1.0)
    }

    // MARK: - Permissions
    private func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Health Timer
    private func startHealthTimer() {
        stopHealthTimer()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let fps = self.framesReceived - self.lastReportedFrames
            self.lastReportedFrames = self.framesReceived

            // Only warn when it's truly dead (helps diagnose "mic receives nothing")
            if fps == 0 {
                let format = self.captureInputFormat
                print("⚠️  AudioCapture: 0 buffers/sec (no audio frames received)")
                if let format {
                    print("   🎚️ Input format: \(format.sampleRate)Hz, ch=\(format.channelCount), \(format.commonFormat)")
                }
            }
        }
        healthTimer = timer
        timer.activate()
    }

    private func stopHealthTimer() {
        healthTimer?.cancel()
        healthTimer = nil
    }
}

// MARK: - Errors
enum AudioCaptureError: LocalizedError {
    case permissionDenied
    case engineInitFailed
    case noInputDevice
    case notRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied. Please enable in System Settings."
        case .engineInitFailed:
            return "Failed to initialize audio engine"
        case .noInputDevice:
            return "No audio input device found"
        case .notRecording:
            return "Not currently recording"
        }
    }
}
