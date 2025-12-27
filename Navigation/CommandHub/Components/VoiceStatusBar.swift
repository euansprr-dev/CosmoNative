// CosmoOS/Navigation/CommandHub/Components/VoiceStatusBar.swift
// Voice Status Bar with Mini Waveform Visualization
// Shows listening state with ambient feedback

import SwiftUI

// MARK: - Voice Status Bar
struct VoiceStatusBar: View {
    let isRecording: Bool
    let isProcessing: Bool
    let audioLevels: [Float]

    @State private var statusText = "Hold Space to speak"
    @State private var showCheckmark = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            StatusIndicator(
                state: currentState,
                showCheckmark: showCheckmark
            )

            // Status text
            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(statusTextColor)

            Spacer()

            // Mini waveform (when recording)
            if isRecording {
                MiniWaveform(levels: audioLevels)
                    .transition(.scale.combined(with: .opacity))
            }

            // Keyboard hint
            if !isRecording && !isProcessing {
                KeyboardHint()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(statusBarBackground)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
        .animation(.easeInOut(duration: 0.2), value: isProcessing)
        .onChange(of: isRecording) { _, newValue in
            updateStatusText(recording: newValue, processing: isProcessing)
        }
        .onChange(of: isProcessing) { _, newValue in
            updateStatusText(recording: isRecording, processing: newValue)
        }
    }

    // MARK: - State
    private var currentState: VoiceState {
        if isProcessing {
            return .processing
        } else if isRecording {
            return .listening
        } else if showCheckmark {
            return .complete
        } else {
            return .idle
        }
    }

    private var statusTextColor: Color {
        switch currentState {
        case .idle: return CosmoColors.textTertiary
        case .listening: return CosmoColors.emerald
        case .processing: return CosmoColors.lavender
        case .complete: return CosmoColors.emerald
        }
    }

    private var statusBarBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                isRecording
                    ? CosmoColors.emerald.opacity(0.08)
                    : CosmoColors.glassGrey.opacity(0.15)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isRecording
                            ? CosmoColors.emerald.opacity(0.2)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
    }

    private func updateStatusText(recording: Bool, processing: Bool) {
        if processing {
            statusText = "Thinking..."
        } else if recording {
            statusText = "Listening..."
        } else {
            // Brief "Done" state before returning to idle
            if statusText == "Listening..." || statusText == "Thinking..." {
                showCheckmark = true
                statusText = "Done"

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        showCheckmark = false
                        statusText = "Hold Space to speak"
                    }
                }
            } else {
                statusText = "Hold Space to speak"
            }
        }
    }
}

// MARK: - Voice State
enum VoiceState {
    case idle
    case listening
    case processing
    case complete
}

// MARK: - Status Indicator
struct StatusIndicator: View {
    let state: VoiceState
    let showCheckmark: Bool

    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0

    private let indicatorSize: CGFloat = 10

    var body: some View {
        ZStack {
            // Outer ring (for listening pulse)
            if state == .listening {
                Circle()
                    .stroke(CosmoColors.emerald.opacity(0.3), lineWidth: 1.5)
                    .frame(width: indicatorSize + 8, height: indicatorSize + 8)
                    .scaleEffect(pulseScale)
                    .opacity(2 - pulseScale)
            }

            // Main indicator
            Group {
                switch state {
                case .idle:
                    Circle()
                        .fill(CosmoColors.glassGrey)
                        .frame(width: indicatorSize, height: indicatorSize)

                case .listening:
                    Circle()
                        .fill(CosmoColors.emerald)
                        .frame(width: indicatorSize, height: indicatorSize)

                case .processing:
                    // Rotating arc
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(CosmoColors.lavender, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: indicatorSize, height: indicatorSize)
                        .rotationEffect(.degrees(rotationAngle))

                case .complete:
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(CosmoColors.emerald)
                }
            }
        }
        .frame(width: 20, height: 20)
        .onAppear {
            if state == .listening {
                startPulse()
            }
            if state == .processing {
                startRotation()
            }
        }
        .onChange(of: state) { _, newState in
            if newState == .listening {
                startPulse()
            }
            if newState == .processing {
                startRotation()
            }
        }
    }

    private func startPulse() {
        pulseScale = 1.0
        withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
            pulseScale = 1.8
        }
    }

    private func startRotation() {
        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
    }
}

// MARK: - Mini Waveform
struct MiniWaveform: View {
    let levels: [Float]

    private let barCount = 5
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let maxHeight: CGFloat = 16
    private let minHeight: CGFloat = 4

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(CosmoColors.emerald)
                    .frame(width: barWidth, height: barHeight(for: index))
                    .animation(.spring(response: 0.1, dampingFraction: 0.6), value: levels)
            }
        }
        .frame(height: maxHeight)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let level: Float
        if index < levels.count {
            level = levels[index]
        } else {
            // Generate pseudo-random height based on other levels
            level = levels.isEmpty ? 0.2 : levels.reduce(0, +) / Float(levels.count) * Float.random(in: 0.5...1.5)
        }

        let normalized = CGFloat(min(max(level, 0), 1))
        return minHeight + (maxHeight - minHeight) * normalized
    }
}

// MARK: - Keyboard Hint
struct KeyboardHint: View {
    var body: some View {
        HStack(spacing: 4) {
            KeyboardKey(symbol: "space")
            Text("Voice")
                .font(.system(size: 10))
                .foregroundColor(CosmoColors.textTertiary)
        }
    }
}

// MARK: - Keyboard Key
fileprivate struct VoiceStatusKeyboardKey: View {
    let symbol: String

    var body: some View {
        Text(symbol.uppercased())
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(CosmoColors.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(CosmoColors.glassGrey.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(CosmoColors.glassGrey.opacity(0.4), lineWidth: 1)
            )
    }
}

// MARK: - Preview
#if DEBUG
struct VoiceStatusBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Idle state
            VoiceStatusBar(
                isRecording: false,
                isProcessing: false,
                audioLevels: []
            )

            // Listening state
            VoiceStatusBar(
                isRecording: true,
                isProcessing: false,
                audioLevels: [0.3, 0.7, 0.5, 0.8, 0.4]
            )

            // Processing state
            VoiceStatusBar(
                isRecording: false,
                isProcessing: true,
                audioLevels: []
            )
        }
        .padding(20)
        .background(CosmoColors.softWhite)
        .frame(width: 600, height: 200)
    }
}
#endif
