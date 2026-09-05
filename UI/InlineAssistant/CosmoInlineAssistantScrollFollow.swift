// CosmoOS/UI/InlineAssistant/CosmoInlineAssistantScrollFollow.swift
// Sticky-bottom transcript policy for the Cosmo pane. While the reader sits at
// the end of the conversation, new tokens keep the end in view; the moment
// they scroll up to read, growth happens beneath them and nothing moves. The
// old transcript scrolled to the bottom on EVERY streamed delta, fighting the
// user's own scroll gesture per token — the trigger of the mid-stream hang.
// September 2026

import Foundation
import SwiftUI

enum CosmoInlineAssistantScrollFollowPolicy {
    /// How close to the end still counts as "reading the latest" — a little
    /// slack so a wrapped last line or a chip row never breaks the follow.
    static let nearBottomTolerance: CGFloat = 56

    enum Trigger: Equatable {
        /// The user sent a message — always land on it.
        case userSubmitted
        /// A reply, receipt, or section label was appended.
        case transcriptGrew
        /// A coalesced batch of streamed tokens landed.
        case streamingTick
        /// The run started or finished.
        case runStateChanged
    }

    static func isNearBottom(visibleMaxY: CGFloat, contentHeight: CGFloat) -> Bool {
        visibleMaxY >= contentHeight - nearBottomTolerance
    }

    /// Whether an automatic scroll-to-bottom is allowed right now.
    static func shouldFollow(trigger: Trigger, isNearBottom: Bool, isPaneExpanded: Bool) -> Bool {
        guard isPaneExpanded else { return false }
        switch trigger {
        case .userSubmitted:
            return true
        case .transcriptGrew, .streamingTick, .runStateChanged:
            return isNearBottom
        }
    }

    /// The scroll anchor for content-size changes: pin the end while the
    /// reader is at the end, preserve the top offset while they read history.
    static func sizeChangeAnchor(isNearBottom: Bool) -> UnitPoint {
        isNearBottom ? .bottom : .top
    }
}

/// Bridges scroll geometry (written from event handlers) to the rows that ask
/// to follow (streaming ticks). Deliberately NOT observable: nothing here is
/// read from a `body`, so the per-tick and per-scroll writes never invalidate
/// the transcript — the same discipline as `CosmoLiveScrollMonitor`.
@MainActor
final class CosmoInlineAssistantScrollFollower {
    var isNearBottom = true
    var isPaneExpanded = true
    /// Installed by the transcript once it has a ScrollViewProxy.
    var scrollToBottom: ((_ animated: Bool) -> Void)?

    func follow(_ trigger: CosmoInlineAssistantScrollFollowPolicy.Trigger, animated: Bool) {
        guard CosmoInlineAssistantScrollFollowPolicy.shouldFollow(
            trigger: trigger,
            isNearBottom: isNearBottom,
            isPaneExpanded: isPaneExpanded
        ) else { return }
        scrollToBottom?(animated)
    }
}
