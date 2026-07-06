// CosmoOS/Settings/ProfileStudio/ProfileContextSection.swift
// The CONTEXT section of the Profile Studio — the fields every writing engine
// reads (audience, niche, angle, signature phrases, beliefs, notes) that the
// old wizard never exposed. Fields drafted by the background extraction carry
// a quiet "suggested" tag until the user touches them.

import SwiftUI

struct ProfileContextSection: View {
    @Bindable var store: ProfileStudioStore

    private var filledCount: Int {
        [!store.targetAudience.isEmpty, !store.niche.isEmpty, !store.uniqueAngle.isEmpty,
         !store.signaturePhrases.isEmpty, !store.coreBeliefs.isEmpty, !store.notes.isEmpty]
            .count(where: { $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            SettingsSectionHeader(label: "CONTEXT", detail: contextDetail)
            SettingsGroupedBox {
                contextField(
                    icon: "person.2", title: "Audience",
                    prompt: "Who does this voice speak to?",
                    text: $store.targetAudience, suggested: .targetAudience
                )
                SettingsRowDivider()
                contextField(
                    icon: "scope", title: "Niche",
                    prompt: "The lane in a few words",
                    text: $store.niche, suggested: .niche
                )
                SettingsRowDivider()
                contextField(
                    icon: "sparkle", title: "Unique angle",
                    prompt: "What makes this perspective different?",
                    text: $store.uniqueAngle, suggested: .uniqueAngle
                )
                SettingsRowDivider()
                ProfileChipEditorRow(
                    icon: "quote.opening", title: "Signature phrases",
                    prompt: "Recurring openers, catchphrases",
                    chips: $store.signaturePhrases,
                    isSuggested: store.suggestedFields.contains(.signaturePhrases),
                    onEdited: { store.clearSuggestion(.signaturePhrases) }
                )
                SettingsRowDivider()
                ProfileChipEditorRow(
                    icon: "heart.text.square", title: "Core beliefs",
                    prompt: "Convictions the content stands on",
                    chips: $store.coreBeliefs,
                    isSuggested: false,
                    onEdited: {}
                )
                SettingsRowDivider()
                contextField(
                    icon: "note.text", title: "Notes",
                    prompt: "Anything else Cosmo should know",
                    text: $store.notes, suggested: nil, axis: .vertical
                )
            }
            if store.isSuggestingContext {
                suggestingHint
            }
        }
    }

    private var contextDetail: String {
        filledCount == 0 ? "every draft gets sharper" : "\(filledCount) of 6"
    }

    private var suggestingHint: some View {
        HStack(spacing: DS.space6) {
            ProgressView()
                .controlSize(.mini)
            Text("Reading the documents to suggest audience and niche…")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
        }
        .padding(.leading, DS.space4)
    }

    // MARK: - Text field row

    @ViewBuilder
    private func contextField(
        icon: String,
        title: String,
        prompt: String,
        text: Binding<String>,
        suggested: ProfileStudioStore.SuggestedField?,
        axis: Axis = .horizontal
    ) -> some View {
        let isSuggested = suggested.map { store.suggestedFields.contains($0) } ?? false

        HStack(alignment: axis == .vertical ? .top : .center, spacing: DS.space12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 28, height: 28)
                .background(DS.accentSoft, in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.space6) {
                    Text(title)
                        .font(DS.callout.weight(.medium))
                        .foregroundStyle(DS.text)
                    if isSuggested {
                        suggestedTag
                    }
                }
                TextField(prompt, text: text, axis: axis)
                    .textFieldStyle(.plain)
                    .font(DS.callout)
                    .foregroundStyle(isSuggested ? DS.textSecondary : DS.text)
                    .lineLimit(axis == .vertical ? 1...4 : 1...1)
                    .onChange(of: text.wrappedValue) { _, _ in
                        if let suggested { store.clearSuggestion(suggested) }
                    }
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var suggestedTag: some View {
        Text("suggested — tap to edit")
            .font(DS.caption2)
            .foregroundStyle(DS.gilt)
    }
}

// MARK: - Chip editor row

/// A row that edits a list of short phrases as removable chips with an
/// inline "add" field.
struct ProfileChipEditorRow: View {
    let icon: String
    let title: String
    let prompt: String
    @Binding var chips: [String]
    let isSuggested: Bool
    let onEdited: () -> Void

    @State private var draft = ""

    var body: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 28, height: 28)
                .background(DS.accentSoft, in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.space6) {
                HStack(spacing: DS.space6) {
                    Text(title)
                        .font(DS.callout.weight(.medium))
                        .foregroundStyle(DS.text)
                    if isSuggested {
                        Text("suggested — tap to edit")
                            .font(DS.caption2)
                            .foregroundStyle(DS.gilt)
                    }
                }
                chipFlow
                addField
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var chipFlow: some View {
        if !chips.isEmpty {
            CodexFlowLayout(spacing: DS.space4) {
                ForEach(chips, id: \.self) { chip in
                    chipView(chip)
                }
            }
        }
    }

    private func chipView(_ chip: String) -> some View {
        HStack(spacing: DS.space4) {
            Text(chip)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    chips.removeAll { $0 == chip }
                    onEdited()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(chip)")
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .background(DS.glassSectionFill, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(DS.glassBorder, lineWidth: 1))
    }

    private var addField: some View {
        TextField(prompt, text: $draft)
            .textFieldStyle(.plain)
            .font(DS.footnote)
            .foregroundStyle(DS.text)
            .onSubmit {
                let trimmed = draft.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !chips.contains(trimmed) else { return }
                withAnimation(ProMotionSprings.cardEntrance) {
                    chips.append(trimmed)
                    onEdited()
                }
                draft = ""
            }
    }
}

