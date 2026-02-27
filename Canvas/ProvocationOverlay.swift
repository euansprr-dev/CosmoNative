// CosmoOS/Canvas/ProvocationOverlay.swift
// Positions provocation diamond markers relative to canvas blocks
// using CanvasBlockFrameTracker screen-space frames.
// February 2026 — WP7 Provocation Layer

import SwiftUI

struct ProvocationOverlay: View {
    @ObservedObject var provocationEngine: ProvocationEngine
    @EnvironmentObject var blockFrameTracker: CanvasBlockFrameTracker

    var body: some View {
        ZStack {
            ForEach(provocationEngine.activeProvocations) { provocation in
                ForEach(provocation.sourceAtomUUIDs, id: \.self) { uuid in
                    if let frame = blockFrameTracker.blockFrames[uuid] {
                        ProvocationMarkerView(
                            provocation: provocation,
                            onDismiss: {
                                withAnimation(ProMotionSprings.snappy) {
                                    provocationEngine.dismiss(provocationId: provocation.id)
                                }
                            },
                            onResolve: {
                                withAnimation(ProMotionSprings.snappy) {
                                    provocationEngine.resolve(provocationId: provocation.id)
                                }
                            },
                            onAcceptAsTask: {
                                Task {
                                    await provocationEngine.acceptAsTask(provocation: provocation)
                                }
                            }
                        )
                        .position(
                            x: frame.maxX - 8,
                            y: frame.minY + 8
                        )
                    }
                }
            }
        }
        .allowsHitTesting(true)
    }
}
