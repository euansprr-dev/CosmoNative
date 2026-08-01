// CosmoOS/UI/SwipeFile/Shared/SwipeCaptureMenu.swift
// The visible front door.
//
// Every capture verb already existed — ⌘⇧S, the region grab, drops, the flow
// recorder — but every one of them was a shortcut or a hidden menu, and the
// rooms' teaching empty-states sat behind a catch-22 (a room is hidden until
// it has a capture; the room is where capture is taught). This file is the
// fix: ONE labeled control on every swipe page that names the verbs, and ONE
// guide table that the menu, the popover and the collections tile all read
// from — so the education can never drift from itself.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - The guide (single source of truth)

/// Medium → gesture, the whole capture story in one table. The empty states
/// in SwipeLibraryStates speak the same facts per-room; this is the app-wide
/// version a user can reach BEFORE any room exists.
enum SwipeCaptureGuide {
    struct Row: Identifiable {
        var id: String { medium }
        let icon: String
        let medium: String
        let gesture: String
    }

    static let rows: [Row] = [
        Row(icon: "rectangle.stack", medium: "A social post",
            gesture: "Copy the link, ⌘⇧S — or save it from Discover"),
        Row(icon: "envelope", medium: "A newsletter",
            gesture: "⌘⇧S a Substack or beehiiv issue, or drop the email in"),
        Row(icon: "dollarsign.square", medium: "A landing or sales page",
            gesture: "⌘⇧S while looking at it — the browser pane sees your session"),
        Row(icon: "arrow.trianglehead.branch", medium: "A funnel",
            gesture: "Record a Funnel, then swipe each page you walk through"),
        Row(icon: "megaphone", medium: "An ad",
            gesture: "Swipe the ad-library page, or drop ad screenshots"),
        Row(icon: "text.document", medium: "A script",
            gesture: "Copy the full text, ⌘⇧S — Cosmo splits it into beats"),
        Row(icon: "viewfinder", medium: "Anything on screen",
            gesture: "⌥⌘⇧S grabs a region"),
    ]
}

// MARK: - The menu button

/// "Swipe ▾" — rides the control bar of every swipe page, in the sort menu's
/// exact capsule chrome. The menu itself is the teaching surface: seeing
/// "Swipe This" next to its verb is how ⌘⇧S stops being secret knowledge.
struct SwipeCaptureMenuButton: View {
    @State private var showGuide = false

    var body: some View {
        Menu {
            Button("Swipe This  (⌘⇧S)") { SwipeCaptureCommands.swipeThis() }
            Button("Grab a Region…  (⌥⌘⇧S)") { SwipeCaptureCommands.swipeRegion() }
            Button("From a File…") { SwipeCaptureCommands.importFromOpenPanel() }
            Button("Record a Funnel…") {
                Task { await SwipeFlowRecorder.shared.start(named: SwipeFlowRecorder.defaultName()) }
            }
            Divider()
            Button("How capture works…") { showGuide = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "scissors")
                    .font(DS.caption.weight(.semibold))
                Text("Swipe")
                    .font(DS.subheadline.weight(.medium))
            }
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(DS.accentSoft))
            .overlay(Capsule().strokeBorder(DS.accent.opacity(0.25), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Capture anything — pages, emails, screenshots, funnels (⌘⇧S)")
        .accessibilityLabel("Capture a swipe")
        .popover(isPresented: $showGuide, arrowEdge: .bottom) {
            SwipeCaptureGuidePopover()
        }
    }
}

// MARK: - The guide popover

struct SwipeCaptureGuidePopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How capture works")
                .font(DS.headline)
                .foregroundStyle(DS.text)
                .padding(.bottom, 2)
            Text("One verb — Cosmo files each capture by what it is.")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .padding(.bottom, 10)
            ForEach(SwipeCaptureGuide.rows) { row in
                guideRow(row)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func guideRow(_ row: SwipeCaptureGuide.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: row.icon)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.medium)
                    .font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(DS.text)
                Text(row.gesture)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The collections door tile

/// The quiet trailing tile on the COLLECTIONS shelf: the door to every room
/// that doesn't exist yet. One muted tile, not nine ghost tiles — restraint,
/// but the catch-22 is dead: the room grammar is discoverable from day one.
struct SwipeCaptureGuideTile: View {
    @State private var isHovered = false
    @State private var showGuide = false

    var body: some View {
        Button { showGuide = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(DS.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .frame(height: 116)
                    .overlay(
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(DS.title2)
                            .foregroundStyle(DS.textMuted)
                            .accessibilityHidden(true)
                    )
                Text("More than posts")
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
                Text("Newsletters, funnels, sales pages…")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(width: 208, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isHovered ? 1 : 0.8)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .help("How to capture newsletters, funnels, and pages")
        .accessibilityLabel("How capture works")
        .popover(isPresented: $showGuide, arrowEdge: .bottom) {
            SwipeCaptureGuidePopover()
        }
    }
}
