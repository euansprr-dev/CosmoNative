// CosmoOS/Navigation/PeekOverlay.swift
// Peek — the Quick Look idiom, app-wide. Anything peekable opens as a floating
// glass panel first: read it, then dismiss (nothing polluted) or promote it to
// a real pane / focus mode. Pane clutter dies at the source.

import SwiftUI

// MARK: - Peek Controller

@MainActor
@Observable
final class PeekController {

    static let shared = PeekController()

    enum Target: Equatable {
        case entity(EntitySelection)

        var entitySelection: EntitySelection? {
            guard case .entity(let selection) = self else { return nil }
            return selection
        }
    }

    private(set) var target: Target?
    /// Window-space rect of the trigger, when known — the panel grows from it.
    private(set) var anchor: CGRect?

    var isPresented: Bool { target != nil }

    func peek(_ target: Target, from anchor: CGRect? = nil) {
        self.anchor = anchor
        self.target = target
    }

    func dismiss() {
        target = nil
        anchor = nil
    }
}

// MARK: - Peek Overlay

/// Mounted once in MainView's top ZStack. Scrim + floating glass panel.
/// Esc or click-out dismisses; Cmd+Return promotes to a pane; "Open" replaces
/// the peek with the full focus mode.
struct PeekOverlayView: View {
    let onOpenFocus: (EntitySelection) -> Void
    let onOpenPane: (EntitySelection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    private var controller: PeekController { .shared }

    var body: some View {
        GeometryReader { geo in
            if let target = controller.target {
                scrim
                peekPanel(for: target, in: geo.size)
            }
        }
        .onChange(of: controller.isPresented) { _, presented in
            if presented {
                expanded = false
                withAnimation(reduceMotion ? .linear(duration: 0.01) : ProMotionSprings.bouncy) {
                    expanded = true
                }
            } else {
                expanded = false
            }
        }
    }

    // MARK: Scrim

    private var scrim: some View {
        Color.black.opacity(0.06)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }
            .transition(.opacity)
    }

    // MARK: Panel

    @ViewBuilder
    private func peekPanel(for target: PeekController.Target, in size: CGSize) -> some View {
        let panelSize = CGSize(width: size.width * 0.64, height: size.height * 0.78)
        let finalCenter = CGPoint(x: size.width / 2, y: size.height / 2)
        let transform = entranceTransform(panelSize: panelSize, finalCenter: finalCenter)

        PeekPanelContent(
            target: target,
            onOpenFocus: { entity in
                dismiss()
                onOpenFocus(entity)
            },
            onOpenPane: { entity in
                dismiss()
                onOpenPane(entity)
            },
            onClose: { dismiss() }
        )
        .frame(width: panelSize.width, height: panelSize.height)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 24)
        .scaleEffect(expanded ? 1 : transform.scale, anchor: .center)
        .offset(expanded ? .zero : transform.offset)
        .opacity(expanded ? 1 : 0)
        .position(finalCenter)
    }

    /// Grow from the trigger: scale + offset that map the final panel rect
    /// back onto the anchor rect (content lays out once, at final size).
    private func entranceTransform(panelSize: CGSize, finalCenter: CGPoint) -> (scale: CGFloat, offset: CGSize) {
        guard let anchor = controller.anchor, panelSize.width > 0 else {
            return (0.92, .zero)
        }
        let scale = max(0.08, min(anchor.width / panelSize.width, 0.5))
        let offset = CGSize(
            width: anchor.midX - finalCenter.x,
            height: anchor.midY - finalCenter.y
        )
        return (scale, offset)
    }

    private func dismiss() {
        withAnimation(reduceMotion ? .linear(duration: 0.01) : ProMotionSprings.snappy) {
            controller.dismiss()
        }
    }
}

// MARK: - Panel Content

private struct PeekPanelContent: View {
    let target: PeekController.Target
    let onOpenFocus: (EntitySelection) -> Void
    let onOpenPane: (EntitySelection) -> Void
    let onClose: () -> Void

    @State private var title = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            body_
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Header (inner chrome — flat warm fills on glass)

    private var header: some View {
        HStack(spacing: 10) {
            if let entity = target.entitySelection {
                Image(systemName: entity.type.icon)
                    .font(DS.subheadline)
                    .foregroundStyle(entity.type.color)
            }

            Text(title)
                .font(DS.headline)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer(minLength: 16)

            if let entity = target.entitySelection {
                actionCluster(for: entity)
            }

            closeButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .task(id: target) {
            guard let entity = target.entitySelection else { return }
            title = await PaneSpineInfo.title(for: .entity(entity))
        }
    }

    private func actionCluster(for entity: EntitySelection) -> some View {
        HStack(spacing: 8) {
            Button {
                onOpenPane(entity)
            } label: {
                Text("Open in Pane")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(DS.glassCardFill))
                    .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Open in a pane (⌘⏎)")
            .keyboardShortcut(.return, modifiers: [.command])

            Button {
                onOpenFocus(entity)
            } label: {
                Text("Open")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(DS.accent))
            }
            .buttonStyle(.plain)
            .help("Open in focus mode (⏎)")
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(DS.glassCardFill))
                .overlay(Circle().strokeBorder(DS.glassBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Close (esc)")
        .accessibilityLabel("Close peek")
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.borderSubtle)
            .frame(height: 1)
    }

    // MARK: Body

    @ViewBuilder
    private var body_: some View {
        switch target {
        case .entity(let entity):
            PaneContentView(
                content: .entity(entity),
                isActive: true,
                isContextOwner: false,
                onClose: onClose
            )
            .environment(\.isPeekContext, true)
        }
    }
}
