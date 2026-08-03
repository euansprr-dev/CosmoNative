// CosmoOS/CosmoGlass/GeminiThinkingOverlay.swift
// Apple Intelligence-style edge glow indicator for Gemini processing
// Non-intrusive visual feedback that allows continued interaction

import SwiftUI

// MARK: - Thinking Overlay View

/// Edge glow indicator shown while Gemini is processing
/// Mimics Apple Intelligence's subtle edge animation
struct GeminiThinkingOverlay: View {
    @ObservedObject private var state = GeminiThinkingState.shared

    var body: some View {
        GeometryReader { geometry in
            if state.isThinking {
                ZStack {
                    // Left edge glow
                    EdgeGlow(edge: .leading)
                        .frame(width: 80)
                        .position(x: 40, y: geometry.size.height / 2)

                    // Right edge glow
                    EdgeGlow(edge: .trailing)
                        .frame(width: 80)
                        .position(x: geometry.size.width - 40, y: geometry.size.height / 2)

                    // Top edge glow (subtle)
                    EdgeGlow(edge: .top)
                        .frame(height: 60)
                        .position(x: geometry.size.width / 2, y: 30)

                    // Bottom edge glow (subtle)
                    EdgeGlow(edge: .bottom)
                        .frame(height: 60)
                        .position(x: geometry.size.width / 2, y: geometry.size.height - 30)
                }
                .allowsHitTesting(false) // Don't block interaction
                .transition(.opacity.animation(.easeInOut(duration: 0.4)))
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Edge Glow Component

struct EdgeGlow: View {
    let edge: Edge
    @State private var pulsing = false

    var body: some View {
        GeometryReader { geometry in
            // Static content under the blur — it rasterizes once; the breathing
            // pulse lives on the layer's compositor-only opacity below. Drawing
            // the animated phase inside the Canvas re-blurred every frame.
            Canvas { context, size in
                let startPoint: CGPoint
                let endPoint: CGPoint

                // Purple/lavender gradient (Cosmo's AI color) at peak glow
                let gradient = Gradient(colors: [
                    .clear,
                    CosmoColors.lavender.opacity(0.25),
                    CosmoColors.cosmoAI.opacity(0.40),
                    CosmoColors.lavender.opacity(0.25),
                    .clear
                ])

                switch edge {
                case .leading:
                    startPoint = CGPoint(x: size.width, y: 0)
                    endPoint = CGPoint(x: 0, y: 0)
                case .trailing:
                    startPoint = CGPoint(x: 0, y: 0)
                    endPoint = CGPoint(x: size.width, y: 0)
                case .top:
                    startPoint = CGPoint(x: 0, y: size.height)
                    endPoint = CGPoint(x: 0, y: 0)
                case .bottom:
                    startPoint = CGPoint(x: 0, y: 0)
                    endPoint = CGPoint(x: 0, y: size.height)
                }

                let rect = CGRect(origin: .zero, size: size)
                context.fill(
                    Path(rect),
                    with: .linearGradient(
                        gradient,
                        startPoint: startPoint,
                        endPoint: endPoint
                    )
                )
            }
            .blur(radius: 20)
            .opacity(pulsing ? 1.0 : 0.25)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Thinking State Manager

/// Global state for Gemini thinking indicator
@MainActor
class GeminiThinkingState: ObservableObject {
    static let shared = GeminiThinkingState()

    @Published var isThinking: Bool = false
    @Published var query: String = ""

    private init() {
        setupObservers()
    }

    private func setupObservers() {
        // Listen for Gemini processing started
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.AI.geminiProcessingStarted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.isThinking = true
                self?.query = notification.userInfo?["query"] as? String ?? ""
            }
        }

        // Listen for Gemini processing completed
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.AI.geminiProcessingCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isThinking = false
            }
        }

        // Listen for Gemini processing failed
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.AI.geminiProcessingFailed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isThinking = false
            }
        }
    }

    /// Manually start thinking indicator
    func startThinking(query: String = "") {
        isThinking = true
        self.query = query
    }

    /// Manually stop thinking indicator
    func stopThinking() {
        isThinking = false
        query = ""
    }
}

// MARK: - Edge Enum

fileprivate enum OverlayEdge {
    case leading, trailing, top, bottom
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.opacity(0.9)

        Text("Content here")
            .foregroundStyle(.white)

        GeminiThinkingOverlay()
    }
    .frame(width: 800, height: 600)
    .onAppear {
        GeminiThinkingState.shared.startThinking(query: "Test query")
    }
}
