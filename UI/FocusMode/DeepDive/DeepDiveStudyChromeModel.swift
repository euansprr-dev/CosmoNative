// CosmoOS/UI/FocusMode/DeepDive/DeepDiveStudyChromeModel.swift
// The Study's chrome state, hoisted so the deep dive can be hosted two ways
// with one set of controls: as a focus overlay (its own study bar) or as a
// VIEW inside its space (the space chrome row renders the same islands).

import SwiftUI

@MainActor
@Observable
final class DeepDiveStudyChromeModel {
    var selectedTab: DeepDiveOverviewTab = .overview
    /// False while the host is opacity-0 (a kept-alive dossier behind the
    /// canvas) — gates every keyboard shortcut the islands declare.
    var isFrontmost = true
    /// Context-pill law: the title shows only when the masthead isn't.
    var showsTitle = false
    /// True while the user is down in the content — islands recede.
    var recede = false
    var isTidyingMap = false
    var title = "Deep Dive"
    var maturityLabel = ""

    struct Actions {
        var startInquiry: () -> Void = {}
        var tidyMap: () -> Void = {}
        var scrollToTop: () -> Void = {}
    }

    /// Installed by the overview view on appear; the islands call through.
    @ObservationIgnored var actions = Actions()

    func select(_ tab: DeepDiveOverviewTab) {
        guard selectedTab != tab else { return }
        withAnimation(ProMotionSprings.focusTransition) { selectedTab = tab }
    }
}
