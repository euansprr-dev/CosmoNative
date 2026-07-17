// CosmoOS/Navigation/Browser/CosmoBrowserCaptureBar.swift
// Selection-capture chrome — the browser's research superpower. A floating
// glass capsule with a live selection count and four flat action chips.

import SwiftUI

struct CosmoBrowserCaptureBarView: View {
    let browserState: CosmoWebBrowserState
    let onCapture: (CosmoBrowserResearchCaptureKind) -> Void
    /// The just-dispatched action morphs its glyph to a checkmark before the
    /// bar dismisses — confirmation without a toast.
    let dispatchedKind: CosmoBrowserResearchCaptureKind?

    @Environment(\.isPaneActive) private var isPaneActive

    var body: some View {
        HStack(spacing: DS.space8) {
            selectionBadge
            CosmoBrowserCaptureButton(
                title: "Quote",
                systemName: "quote.opening",
                shortcutHint: "⌘⇧1",
                showsSuccess: dispatchedKind == .quote
            ) { onCapture(.quote) }
            CosmoBrowserCaptureButton(
                title: "Research",
                systemName: "doc.text.magnifyingglass",
                shortcutHint: "⌘⇧2",
                showsSuccess: dispatchedKind == .research
            ) { onCapture(.research) }
            CosmoBrowserCaptureButton(
                title: "Swipe",
                systemName: "bolt.fill",
                shortcutHint: "⌘⇧3",
                showsSuccess: dispatchedKind == .swipe
            ) { onCapture(.swipe) }
            CosmoBrowserCaptureButton(
                title: "Ask",
                systemName: "sparkles",
                shortcutHint: "⌘⇧4",
                showsSuccess: dispatchedKind == .askCosmo
            ) { onCapture(.askCosmo) }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 22)
        .background {
            if isPaneActive {
                captureShortcuts
            }
        }
    }

    /// Small-caps voice + a count that ticks as the selection changes.
    private var selectionBadge: some View {
        HStack(spacing: DS.space6) {
            Text("Selection")
                .font(DS.smallCaps)
                .tracking(1.6)
                .foregroundStyle(DS.textMuted)
            Text("\(browserState.selectedText.count)")
                .font(DS.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(DS.textMuted)
                .contentTransition(.numericText())
                .animation(ProMotionSprings.gentle, value: browserState.selectedText.count)
        }
        .padding(.trailing, DS.space4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(browserState.selectedText.count) characters selected")
    }

    private var captureShortcuts: some View {
        Group {
            Button("") { onCapture(.quote) }
                .keyboardShortcut("1", modifiers: [.command, .shift])
            Button("") { onCapture(.research) }
                .keyboardShortcut("2", modifiers: [.command, .shift])
            Button("") { onCapture(.swipe) }
                .keyboardShortcut("3", modifiers: [.command, .shift])
            Button("") { onCapture(.askCosmo) }
                .keyboardShortcut("4", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// Flat action chip on glass: warm fill + hairline, hover lift, press
/// compress. Never nested glass.
struct CosmoBrowserCaptureButton: View {
    let title: String
    let systemName: String
    var shortcutHint: String? = nil
    var showsSuccess: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space6) {
                Image(systemName: showsSuccess ? "checkmark" : systemName)
                    .font(DS.caption.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(DS.footnote.weight(.semibold))
            }
            .foregroundStyle(showsSuccess ? DS.accent : (isHovered ? DS.text : DS.textSecondary))
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background(Capsule().fill(isHovered ? DS.surfaceHover : DS.glassInputFill))
            .overlay(Capsule().stroke(DS.glassBorder, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(shortcutHint.map { "\(title) (\($0))" } ?? title)
        .accessibilityLabel(title)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }
}
