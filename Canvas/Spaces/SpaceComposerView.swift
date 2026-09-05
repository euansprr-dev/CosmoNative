// CosmoOS/Canvas/Spaces/SpaceComposerView.swift
// The one creation grammar for spaces: a 480pt sheet (the workbench
// composer's register) shared by "New space" and "Space settings". The hero
// is the identity row — mark + name; the kind tiles below decide the views;
// everything else stays quiet.

import SwiftUI

struct SpaceComposerView: View {
    @Bindable var model: SpaceComposerModel
    /// Called once: with the created/saved space, or nil on cancel.
    let onDone: (Thinkspace?) -> Void

    @FocusState private var nameFocused: Bool
    @State private var attemptedCommit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SpaceComposerHeader(title: model.title, subtitle: model.subtitle)
            SpaceIdentityRow(model: model, nameFocused: $nameFocused, onSubmit: commit)
            DisclosureGroup("Appearance and location") {
                VStack(alignment: .leading, spacing: DS.space16) {
                    SpaceComposerSection(label: "Color") {
                        AccentSwatchRow(selectedHex: $model.draft.accentColorHex)
                    }
                    SpaceParentPicker(model: model)
                }
                .padding(.top, DS.space12)
            }
            .font(DS.subheadline)
            .foregroundStyle(DS.textSecondary)
            SpaceComposerFooter(
                model: model,
                showsValidation: attemptedCommit,
                onCancel: { onDone(nil) },
                onCommit: commit
            )
        }
        .padding(24)
        .frame(width: 480)
        .background(DS.bg)
        .onAppear { if model.focusesNameOnAppear { nameFocused = true } }
        .onExitCommand { onDone(nil) }
    }

    private func commit() {
        attemptedCommit = true
        guard model.validation.isValid, !model.isCommitting else { return }
        Task { @MainActor in
            if let result = await model.commit() { onDone(result) }
        }
    }
}

// MARK: - Header

struct SpaceComposerHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(DS.title2)
                .foregroundStyle(DS.text)
            Text(subtitle)
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
        }
    }
}

// MARK: - Section

/// The one section voice in the sheet: small-caps label, optional trailing
/// muted detail, content below.
struct SpaceComposerSection<Content: View>: View {
    let label: String
    var detail: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(DS.smallCaps)
                    .tracking(DS.smallCapsTracking)
                    .foregroundStyle(DS.textMuted)
                Spacer(minLength: 0)
                if let detail {
                    Text(detail)
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }
            }
            content
        }
    }
}

// MARK: - Footer

struct SpaceComposerFooter: View {
    let model: SpaceComposerModel
    let showsValidation: Bool
    let onCancel: () -> Void
    let onCommit: () -> Void

    private var message: String? {
        if let error = model.lastError { return error }
        guard showsValidation else { return nil }
        return model.validation.message
    }

    private var isDisabled: Bool {
        !model.validation.isValid || model.isCommitting
    }

    var body: some View {
        HStack(spacing: 12) {
            if let message {
                Text(message)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .keyboardShortcut(.cancelAction)
                .help("Close without saving (Esc)")
            primaryButton
        }
        .animation(ProMotionSprings.hover, value: message)
    }

    private var primaryButton: some View {
        Button(action: onCommit) {
            Text(model.primaryTitle)
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(DS.accent))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .help(model.isCreate ? "Create the space (↩)" : "Save changes (↩)")
    }
}
