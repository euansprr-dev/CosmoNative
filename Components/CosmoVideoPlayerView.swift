// CosmoOS/Components/CosmoVideoPlayerView.swift
// A crash-safe drop-in replacement for SwiftUI's `VideoPlayer`.
//
// WHY THIS EXISTS
// SwiftUI's `VideoPlayer` is implemented in the private `_AVKit_SwiftUI`
// framework as a *generic* view. On macOS 26 / SwiftUI 7.5.3 its first-time
// generic-metadata instantiation intermittently aborts the whole app:
// `swift::fatalError` in `getSuperclassMetadata` while resolving the backing
// class's superclass by mangled name (see the swipe-open crash reports,
// bug_type 309). Mounting it eagerly — e.g. as a swipe's video appears —
// makes the abort deterministic rather than merely intermittent.
//
// `AVPlayerView` is a plain AppKit/Objective-C class in the public `AVKit`
// framework. Its metadata is fully realized at class-load time, so hosting it
// through `NSViewRepresentable` never enters the `_AVKit_SwiftUI` generic
// metadata path that fatals — and it still gives us the same standard native
// transport controls `VideoPlayer` rendered. This is the canonical workaround
// for the `VideoPlayer` metadata crash.
//
// INVARIANT: no `VideoPlayer` (SwiftUI / `_AVKit_SwiftUI`) anywhere in the
// app. Play video through `CosmoVideoPlayerView`. See [[commandk_typing_crash_fixes]].

import AVKit
import SwiftUI

/// Native AVKit video surface backed by `AVPlayerView`, safe to mount eagerly.
/// Playback is caller-driven — this view never calls `play()`/`pause()` itself;
/// it only mirrors the supplied `AVPlayer` and its presentation options.
struct CosmoVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer?
    var controlsStyle: AVPlayerViewControlsStyle = .inline
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var showsFullScreenToggleButton: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = controlsStyle
        view.videoGravity = videoGravity
        view.showsFullScreenToggleButton = showsFullScreenToggleButton
        view.allowsPictureInPicturePlayback = false
        // Let the surrounding SwiftUI layout own the background; AVPlayerView
        // paints its own black bars for letterboxing within that frame.
        view.player = player
        context.coordinator.observe(player)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        // The player is @State in most callers and can be swapped (extraction
        // finishing, refreshing an expired URL). Only reassign on identity
        // change so we don't tear down an in-flight playback each layout pass.
        if view.player !== player {
            view.player = player
        }
        context.coordinator.observe(player)
        if view.controlsStyle != controlsStyle {
            view.controlsStyle = controlsStyle
        }
        if view.videoGravity != videoGravity {
            view.videoGravity = videoGravity
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        // Detach the player so AVKit tears down its render pipeline promptly
        // when the surface leaves the hierarchy.
        view.player = nil
        coordinator.observe(nil)
    }

    /// Native playback controls can change rate and mute outside SwiftUI.
    /// Observe the actual player so every video surface yields audio focus.
    @MainActor final class Coordinator {
        private weak var player: AVPlayer?
        private var observations: [NSKeyValueObservation] = []
        private var holdsSuppression = false

        func observe(_ player: AVPlayer?) {
            // The old weak player can already be gone when SwiftUI dismantles
            // the view. Still balance its outstanding suppression in that case.
            guard self.player !== player || (player == nil && (!observations.isEmpty || holdsSuppression)) else { return }
            observations.removeAll()
            self.player = player
            if let player {
                observations = [
                    player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
                        Task { @MainActor in self?.updateSuppression() }
                    },
                    player.observe(\.isMuted, options: [.new]) { [weak self] _, _ in
                        Task { @MainActor in self?.updateSuppression() }
                    },
                    player.observe(\.volume, options: [.new]) { [weak self] _, _ in
                        Task { @MainActor in self?.updateSuppression() }
                    }
                ]
            }
            updateSuppression()
        }

        private func updateSuppression() {
            let needsSuppression = player.map {
                !$0.isMuted && $0.volume > 0 && $0.timeControlStatus != .paused
            } ?? false
            guard needsSuppression != holdsSuppression else { return }
            holdsSuppression = needsSuppression
            if needsSuppression { SoundEngine.shared.beginSuppression() }
            else { SoundEngine.shared.endSuppression() }
        }
    }
}
