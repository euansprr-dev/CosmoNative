// CosmoOS/Editor/PolishHighlightColors.swift
// Theme-aware highlight colors for the Hemingway-style writing analysis.
// Used by TextKitCoordinator, ContentDraftView, and ContentPolishView.

import SwiftUI
import AppKit

enum PolishHighlightColors {
    /// Complex sentences — warm yellow
    static var complex: NSColor {
        DS.palette.isDark
            ? NSColor(Color(hex: "FBBF24").opacity(0.20))
            : NSColor(Color(hex: "FEF3C7"))
    }
    /// Very complex sentences — warm red
    static var veryComplex: NSColor {
        DS.palette.isDark
            ? NSColor(Color(hex: "F87171").opacity(0.20))
            : NSColor(Color(hex: "FEE2E2"))
    }
    /// Passive voice — cool blue
    static var passive: NSColor {
        DS.palette.isDark
            ? NSColor(Color(hex: "60A5FA").opacity(0.20))
            : NSColor(Color(hex: "DBEAFE"))
    }
    /// Adverbs — soft purple
    static var adverb: NSColor {
        DS.palette.isDark
            ? NSColor(Color(hex: "A78BFA").opacity(0.20))
            : NSColor(Color(hex: "EDE9FE"))
    }
    /// Link color — matches DS.info
    static var link: NSColor { NSColor(DS.info) }
}
