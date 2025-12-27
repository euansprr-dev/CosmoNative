// CosmoOS/UI/LevelSystem/CanvasLevelOrbView.swift
// Canvas Level Orb - Compact floating orb for the top-left corner of the canvas
// Tapping opens the full Sanctuary view with the specified animation sequence

import SwiftUI

/// Compact level orb that sits in the top-left corner of the canvas
/// Shows current Cosmo Index level and XP progress
/// Tapping triggers the Sanctuary entry animation
public struct CanvasLevelOrbView: View {

    @StateObject private var dataProvider = SanctuaryDataProvider()
    @State private var isHovered = false
    @State private var breathingScale: CGFloat = 1.0
    @State private var innerRotation: Double = 0
    @State private var outerRotation: Double = 0

    let onTap: () -> Void

    private let orbSize: CGFloat = 56
    private let glowColors: [Color] = [
        Color(hex: "#6366F1"),
        Color(hex: "#8B5CF6"),
        Color(hex: "#A855F7")
    ]

    /// Convenience accessor for current state
    private var cosmoState: CosmoIndexState? {
        dataProvider.state?.cosmoIndex
    }

    public init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            ZStack {
                // Outer glow rings (subtle)
                ForEach(0..<2, id: \.self) { ring in
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: glowColors + [glowColors[0]],
                                center: .center,
                                startAngle: .degrees(outerRotation + Double(ring * 120)),
                                endAngle: .degrees(outerRotation + Double(ring * 120) + 360)
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: orbSize + CGFloat(ring * 12), height: orbSize + CGFloat(ring * 12))
                        .opacity(isHovered ? 0.5 - Double(ring) * 0.2 : 0.3 - Double(ring) * 0.15)
                        .scaleEffect(breathingScale + CGFloat(ring) * 0.02)
                }

                // Main orb body
                ZStack {
                    // Gradient fill
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color(hex: "#6366F1").opacity(0.85),
                                    Color(hex: "#4338CA").opacity(0.95)
                                ],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: orbSize
                            )
                        )

                    // Inner glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: orbSize * 0.35
                            )
                        )

                    // Surface detail (animated)
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.clear,
                                    Color.white.opacity(0.15),
                                    Color.clear
                                ],
                                center: .center,
                                startAngle: .degrees(innerRotation),
                                endAngle: .degrees(innerRotation + 360)
                            ),
                            lineWidth: 2
                        )
                        .blur(radius: 1)
                }
                .frame(width: orbSize, height: orbSize)
                .scaleEffect(breathingScale)
                .shadow(color: Color(hex: "#6366F1").opacity(isHovered ? 0.6 : 0.4), radius: isHovered ? 20 : 12, x: 0, y: 0)

                // Level display
                VStack(spacing: 1) {
                    Text("CI")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))

                    if let state = cosmoState {
                        Text("\(state.level)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)

                        // XP progress ring
                        Circle()
                            .trim(from: 0, to: CGFloat(state.xpProgress))
                            .stroke(
                                LinearGradient(
                                    colors: [Color(hex: "#22C55E"), Color(hex: "#10B981")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                            )
                            .frame(width: 42, height: 42)
                            .rotationEffect(.degrees(-90))
                    } else {
                        Text("--")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .frame(width: orbSize + 24, height: orbSize + 24)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.08 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            startAnimations()
            dataProvider.startLiveUpdates()
        }
        .onDisappear {
            dataProvider.stopLiveUpdates()
        }
        .accessibilityLabel("Cosmo Index Level \(cosmoState?.level ?? 0). Tap to open Sanctuary.")
        .accessibilityHint("Opens the neural dashboard with dimension details and insights")
    }

    // MARK: - Animations

    private func startAnimations() {
        // Breathing animation (subtle)
        withAnimation(
            .easeInOut(duration: 3.5)
            .repeatForever(autoreverses: true)
        ) {
            breathingScale = 1.03
        }

        // Inner rotation (slow)
        withAnimation(.linear(duration: 25).repeatForever(autoreverses: false)) {
            innerRotation = 360
        }

        // Outer rotation (slower, opposite)
        withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) {
            outerRotation = -360
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        CosmoColors.softWhite.ignoresSafeArea()

        VStack {
            HStack {
                CanvasLevelOrbView {
                    print("Tapped!")
                }
                .padding(20)

                Spacer()
            }
            Spacer()
        }
    }
}
