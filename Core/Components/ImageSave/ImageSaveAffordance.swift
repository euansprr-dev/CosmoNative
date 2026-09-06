// CosmoOS/Core/Components/ImageSave/ImageSaveAffordance.swift
// The hover-revealed save pill: the Safari Live-Text grammar — a 28pt glass
// circle that blurs into the image's bottom-trailing corner while the pointer
// is over it. Click saves to Downloads (the Dock stack bounces); ⌥-click
// asks where; right-click offers Save As… / Copy. The glyph morphs
// arrow → checkmark in place, and a click on the checkmark reveals the file.
//
// Two ways in:
//   .imageSaveAffordance(request, isHovered: hostHover)   // host already tracks hover
//   .imageSaveAffordance(request)                          // pill tracks its own hover
// plus `ImageSaveMenuItems` for surfaces that already own a context menu
// (two `.contextMenu`s on one view — the second silently wins).

import AppKit
import SwiftUI

// MARK: - Phase

enum ImageSavePhase: Equatable {
    case idle
    case saving
    case saved(URL)
    case failed

    var isBusy: Bool { self != .idle }
}

// MARK: - The pill

struct ImageSaveHoverButton: View {
    let request: ImageSaveRequest
    @Binding var phase: ImageSavePhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: primaryAction) {
            glyph
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .contextMenu { ImageSaveMenuItems(request: request, phase: $phase) }
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
        .disabled(phase == .saving)
    }

    /// One Image whose symbol changes — never a structural swap, so the
    /// glass circle keeps its identity and the symbol morphs in place.
    private var glyph: some View {
        Image(systemName: symbolName)
            .font(DS.caption.weight(.semibold))
            .foregroundStyle(phase == .failed ? DS.red : DS.inkFaded)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace.downUp))
            .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: symbolName)
            .opacity(phase == .saving ? 0 : 1)
            .overlay {
                ProgressView()
                    .controlSize(.mini)
                    .opacity(phase == .saving ? 1 : 0)
            }
    }

    private var symbolName: String {
        switch phase {
        case .idle, .saving: "arrow.down"
        case .saved: "checkmark"
        case .failed: "exclamationmark"
        }
    }

    private var helpText: String {
        switch phase {
        case .idle: "Save to Downloads (⌥-click to choose where)"
        case .saving: "Saving…"
        case .saved: "Saved to Downloads — click to show in Finder"
        case .failed: "Couldn't save this image — click to try again"
        }
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle, .failed: "Save image"
        case .saving: "Saving image"
        case .saved: "Image saved, show in Finder"
        }
    }

    private func primaryAction() {
        switch phase {
        case .saved(let url):
            ImageSaver.reveal(url)
        case .idle, .failed:
            let chooseLocation = NSEvent.modifierFlags.contains(.option)
            ImageSaveActions.perform(chooseLocation ? .saveAs : .downloads, request: request, phase: $phase)
        case .saving:
            break
        }
    }
}

// MARK: - Actions (shared by pill + menus)

enum ImageSaveAction {
    case downloads
    case saveAs
    case copy
}

@MainActor
enum ImageSaveActions {

    /// Run an action, driving an optional phase binding for in-place
    /// feedback. Without a binding (bare context menus) the Dock bounce is
    /// the confirmation, and a failure beeps like every AppKit refusal.
    static func perform(_ action: ImageSaveAction, request: ImageSaveRequest, phase: Binding<ImageSavePhase>? = nil) {
        Task { @MainActor in
            phase?.wrappedValue = .saving
            guard let payload = await ImageSaveResolver.resolve(request) else {
                fail(phase)
                return
            }
            switch action {
            case .downloads:
                settle(ImageSaver.saveToDownloads(payload), phase: phase)
            case .saveAs:
                settle(await ImageSaver.saveAs(payload), phase: phase)
            case .copy:
                if ImageSaver.copy(payload) {
                    phase?.wrappedValue = .idle
                } else {
                    fail(phase)
                }
            }
        }
    }

    private static func settle(_ outcome: ImageSaver.Outcome, phase: Binding<ImageSavePhase>?) {
        switch outcome {
        case .saved(let url):
            phase?.wrappedValue = .saved(url)
            scheduleRevert(phase, after: 2.2)
        case .cancelled:
            phase?.wrappedValue = .idle
        case .failed:
            fail(phase)
        }
    }

    private static func fail(_ phase: Binding<ImageSavePhase>?) {
        NSSound.beep()
        phase?.wrappedValue = .failed
        scheduleRevert(phase, after: 2.5)
    }

    private static func scheduleRevert(_ phase: Binding<ImageSavePhase>?, after seconds: Double) {
        guard let phase else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if phase.wrappedValue != .saving { phase.wrappedValue = .idle }
        }
    }
}

// MARK: - Menu items

/// Drop into any existing `.contextMenu` — the three verbs in Safari's order.
struct ImageSaveMenuItems: View {
    let request: ImageSaveRequest
    var phase: Binding<ImageSavePhase>? = nil

    var body: some View {
        Button("Save to Downloads", systemImage: "arrow.down.circle") {
            ImageSaveActions.perform(.downloads, request: request, phase: phase)
        }
        Button("Save As…", systemImage: "square.and.arrow.down") {
            ImageSaveActions.perform(.saveAs, request: request, phase: phase)
        }
        Button("Copy Image", systemImage: "doc.on.doc") {
            ImageSaveActions.perform(.copy, request: request, phase: phase)
        }
        if let phase, case .saved(let url) = phase.wrappedValue {
            Divider()
            Button("Show in Finder", systemImage: "magnifyingglass") { ImageSaver.reveal(url) }
        }
    }
}

// MARK: - Modifiers

extension View {
    /// Hover-revealed save pill riding the host's own hover state.
    /// `inset` keeps clear of corner chrome (resize handles sit at 14).
    func imageSaveAffordance(_ request: ImageSaveRequest?, isHovered: Bool, inset: CGFloat = 10) -> some View {
        modifier(ImageSaveAffordanceModifier(request: request, isHovered: isHovered, inset: inset))
    }

    /// Hover-revealed save pill that tracks hover itself — for surfaces with
    /// no hover state of their own.
    func imageSaveAffordance(_ request: ImageSaveRequest?, inset: CGFloat = 10) -> some View {
        modifier(SelfHoveringImageSaveModifier(request: request, inset: inset))
    }

    /// A full context menu of the save verbs — only for surfaces that don't
    /// already own one.
    func imageSaveContextMenu(_ request: ImageSaveRequest?) -> some View {
        contextMenu {
            if let request { ImageSaveMenuItems(request: request) }
        }
    }
}

struct ImageSaveAffordanceModifier: ViewModifier {
    let request: ImageSaveRequest?
    let isHovered: Bool
    let inset: CGFloat

    @State private var phase: ImageSavePhase = .idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                // Mounted on hover, not faded — the glass is the most
                // expensive view on the surface. Stays while feedback plays.
                if let request, isHovered || phase.isBusy {
                    ImageSaveHoverButton(request: request, phase: $phase)
                        .padding(inset)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.88)))
                }
            }
            .animation(reduceMotion ? nil : ProMotionSprings.hover, value: isHovered)
    }
}

struct SelfHoveringImageSaveModifier: ViewModifier {
    let request: ImageSaveRequest?
    let inset: CGFloat

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .imageSaveAffordance(request, isHovered: isHovered, inset: inset)
            .onHover { isHovered = $0 }
    }
}

// MARK: - AppKit host (TextKit editors)

/// The pill hosted inside an NSTextView over an inline attachment. Owns its
/// phase and reports busy-ness so the host doesn't tear it down mid-feedback.
struct ImageSaveFloatingPill: View {
    let request: ImageSaveRequest
    var onBusyChange: (Bool) -> Void

    @State private var phase: ImageSavePhase = .idle

    var body: some View {
        ImageSaveHoverButton(request: request, phase: $phase)
            .onChange(of: phase.isBusy) { _, busy in onBusyChange(busy) }
    }
}

final class ImageSaveHostingView: NSHostingView<ImageSaveFloatingPill> {
    static let side: CGFloat = 28
    static let inset: CGFloat = 10

    var isBusy = false

    required init(rootView: ImageSaveFloatingPill) {
        super.init(rootView: rootView)
        sizingOptions = []
        wantsLayer = true
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
