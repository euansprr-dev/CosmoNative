// CosmoOS/UI/SwipeFile/Shared/SwipeLibraryDropTarget.swift
// Drag images (or a link) onto the Swipe File and they become a swipe.
//
// ONE FRONT DOOR: this modifier resolves payloads and hands them to
// SwipeIntakeRouter — it decides nothing itself. A folder of ad screenshots
// dropped together becomes ONE frame-set swipe, not N swipes, because a set is
// what the user dragged.

import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Accept images and links dropped anywhere on a swipe surface.
    func swipeLibraryDropTarget(boardIDs: [String] = []) -> some View {
        modifier(SwipeLibraryDropTarget(boardIDs: boardIDs))
    }
}

private struct SwipeLibraryDropTarget: ViewModifier {
    let boardIDs: [String]

    @State private var isTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay { dropWash }
            .onDrop(of: [.image, .fileURL, .url, .png, .jpeg, .tiff], isTargeted: targetBinding) { providers in
                Task { await handle(providers) }
                return true
            }
    }

    private var targetBinding: Binding<Bool> {
        Binding(
            get: { isTargeted },
            set: { value in withAnimation(ProMotionSprings.snappy) { isTargeted = value } }
        )
    }

    /// A tint wash and one hairline — the app's established drop treatment.
    /// No dashed border, no scrim: the page underneath stays legible, which is
    /// what tells you WHERE you are dropping.
    @ViewBuilder
    private var dropWash: some View {
        if isTargeted {
            RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous)
                .fill(DS.accentSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous)
                        .stroke(DS.accent.opacity(0.45), lineWidth: 1)
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.99)))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func handle(_ providers: [NSItemProvider]) async {
        let images = await SwipeCaptureCommands.imagePayloads(from: providers)
        if !images.isEmpty {
            await SwipeIntakeRouter.run(.images(images), boardIDs: boardIDs, captureMode: "drop")
            return
        }
        // Not images — a dragged link (a .webloc, a browser tab, a URL string)
        // goes down the same ladder ⌘⇧S uses.
        if let url = await firstURL(in: providers) {
            await SwipeIntakeRouter.run(.url(url), boardIDs: boardIDs, captureMode: "drop")
        }
    }

    private func firstURL(in providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            guard provider.canLoadObject(ofClass: URL.self) else { continue }
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { value, _ in
                    continuation.resume(returning: value)
                }
            }
            if let url, url.scheme?.hasPrefix("http") == true { return url.absoluteString }
        }
        return nil
    }
}
