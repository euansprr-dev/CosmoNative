// CosmoOS/Canvas/HeartbeatAnimationModifier.swift
// Gentle breathing animation for blocks due for review
// Uses TimelineView(.animation) for ProMotion-aware rendering

import SwiftUI

struct HeartbeatAnimationModifier: ViewModifier {
    let isActive: Bool

    // Auto-disable after 30 seconds of continuous animation
    @State private var animationStart: Date?
    @State private var isExpired = false

    // Breathing: 4-second period, 0.98-1.02 scale range
    private let period: Double = 4.0
    private let amplitude: CGFloat = 0.02
    private let autoDisableSeconds: Double = 30.0

    func body(content: Content) -> some View {
        if isActive && !isExpired {
            TimelineView(.animation) { timeline in
                let elapsed = (animationStart ?? timeline.date).distance(to: timeline.date)
                let phase = elapsed / period
                let scale = 1.0 + amplitude * CGFloat(sin(phase * .pi * 2))

                content
                    .scaleEffect(scale)
                    .onChange(of: timeline.date) { _, now in
                        if animationStart == nil {
                            animationStart = now
                        }
                        if let start = animationStart,
                           now.timeIntervalSince(start) >= autoDisableSeconds {
                            withAnimation(.easeOut(duration: 0.5)) {
                                isExpired = true
                            }
                        }
                    }
            }
        } else {
            content
                .onChange(of: isActive) { _, newValue in
                    if newValue {
                        // Reset expiration when re-activated
                        isExpired = false
                        animationStart = nil
                    }
                }
        }
    }
}

extension View {
    func heartbeatAnimation(isActive: Bool) -> some View {
        modifier(HeartbeatAnimationModifier(isActive: isActive))
    }
}
