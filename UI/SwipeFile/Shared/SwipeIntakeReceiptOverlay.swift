// CosmoOS/UI/SwipeFile/Shared/SwipeIntakeReceiptOverlay.swift
// The app-level capture receipt. ⌘⇧S fires from anywhere — the canvas, a focus
// mode, the browser pane — so the confirmation cannot live on any one page's
// state the way `SwipeSaveToast` does.
//
// It says the KIND out loud ("Swiped · Page · 14 sections") because the user
// never chose it. A system that silently guesses reads arbitrary the first time
// it guesses wrong; a system that names its guess reads confident, and tells
// you exactly what to correct.

import SwiftUI

struct SwipeIntakeReceiptOverlay: View {
    @State private var center = SwipeIntakeReceiptCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            content
        }
        .padding(.bottom, DS.space24)
        .animation(reduceMotion ? .none : ProMotionSprings.bouncy, value: center.receipt)
        .animation(reduceMotion ? .none : ProMotionSprings.bouncy, value: center.errorMessage)
    }

    @ViewBuilder
    private var content: some View {
        if let error = center.errorMessage {
            capsule(icon: "exclamationmark.triangle", text: error, tint: DS.orange)
                .allowsHitTesting(false)
                .task(id: error) { await dismiss(after: .milliseconds(2600)) }
        } else if let receipt = center.receipt {
            // A dedup wears the swipe library's own identity (bronze stack),
            // never the capture-success accent — the iOS twin's law: a
            // success mark over a no-op is a lie.
            //
            // The capsule is a DOOR, not just a confirmation: clicking it
            // opens the room the capture filed into. The receipt is how the
            // user learns the spaces exist; the click is how they arrive.
            Button {
                open(receipt)
            } label: {
                capsule(
                    icon: receipt.alreadyInLibrary ? "rectangle.stack.fill" : receipt.kind.iconName,
                    text: receipt.message,
                    tint: receipt.alreadyInLibrary ? DS.entitySwipe : DS.accent
                )
            }
            .buttonStyle(.plain)
            .help("Open \((receipt.genre ?? SwipeGenre.defaultGenre(for: receipt.kind)).pluralName)")
            .task(id: receipt.id) { await dismiss(after: .milliseconds(1800)) }
        }
    }

    private func open(_ receipt: SwipeIntakeReceipt) {
        let genre = receipt.genre ?? SwipeGenre.defaultGenre(for: receipt.kind)
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openSwipeGallery,
            object: nil,
            userInfo: ["genre": genre.rawValue]
        )
        withAnimation(reduceMotion ? .none : ProMotionSprings.gentle) {
            center.receipt = nil
        }
    }

    /// One glass capsule over content — the same register as `SwipeSaveToast`,
    /// which is the app's established receipt voice. The kind glyph carries the
    /// tint; the label stays ink so it reads at a glance over any background.
    private func capsule(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: icon)
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(DS.text)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .glassEffect(.regular, in: .capsule)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    private func dismiss(after duration: Duration) async {
        try? await Task.sleep(for: duration)
        withAnimation(reduceMotion ? .none : ProMotionSprings.gentle) {
            center.receipt = nil
            center.errorMessage = nil
        }
    }
}
