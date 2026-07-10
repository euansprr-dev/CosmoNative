// CosmoOS/Settings/ProfileStudio/ProfileStudioView.swift
// The Profile Studio dossier — one scrollable canvas the Settings panel
// morphs into. No steps: identity, documents (hero), context, and an
// optional intelligence footer, filled in any order and autosaved.

import SwiftUI

struct ProfileStudioView: View {
    @Bindable var store: ProfileStudioStore

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.space24) {
                identityStrip
                    .studioCascade(hasAppeared: hasAppeared, index: 0, reduceMotion: reduceMotion)
                ProfileDocumentSection(store: store)
                    .studioCascade(hasAppeared: hasAppeared, index: 1, reduceMotion: reduceMotion)
                ProfileContextSection(store: store)
                    .studioCascade(hasAppeared: hasAppeared, index: 2, reduceMotion: reduceMotion)
                ProfileTasteSection(store: store)
                    .studioCascade(hasAppeared: hasAppeared, index: 3, reduceMotion: reduceMotion)
                ProfileIntelligenceCard(store: store)
                    .studioCascade(hasAppeared: hasAppeared, index: 4, reduceMotion: reduceMotion)
                Spacer(minLength: DS.space24)
            }
            .padding(DS.space24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            // Flip one frame after mount so the cascade actually animates.
            Task { @MainActor in
                withAnimation(ProMotionSprings.gentle) { hasAppeared = true }
            }
        }
    }

    // MARK: - Identity strip (the hero — sits directly on the glass)

    private var identityStrip: some View {
        HStack(alignment: .center, spacing: DS.space16) {
            ProfileAvatarMark(name: store.name, size: 56)
            VStack(alignment: .leading, spacing: DS.space4) {
                nameField
                HStack(spacing: DS.space12) {
                    handleField
                    platformPills
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var nameField: some View {
        TextField("Name this voice", text: $store.name)
            .textFieldStyle(.plain)
            .font(DS.pageTitle)
            .foregroundStyle(DS.text)
            .accessibilityLabel("Profile name")
    }

    private var handleField: some View {
        TextField("@handle", text: $store.handle)
            .textFieldStyle(.plain)
            .font(DS.subheadline)
            .foregroundStyle(DS.textSecondary)
            .frame(maxWidth: 160)
            .accessibilityLabel("Social handle")
    }

    private var platformPills: some View {
        HStack(spacing: DS.space4) {
            ForEach(SocialPlatform.allCases, id: \.self) { platform in
                platformPill(platform)
            }
        }
    }

    private func platformPill(_ platform: SocialPlatform) -> some View {
        let isSelected = store.primaryPlatform == platform
        return Button {
            withAnimation(ProMotionSprings.snappy) { store.primaryPlatform = platform }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: platform.iconName)
                    .font(.system(size: 9, weight: .medium))
                if isSelected {
                    Text(platform.displayName)
                        .font(DS.caption2)
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(isSelected ? DS.accent : DS.textMuted)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(isSelected ? AnyShapeStyle(DS.accentSoft) : AnyShapeStyle(Color.clear), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? DS.accent.opacity(0.3) : DS.glassBorder, lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Primary platform: \(platform.displayName)")
        .accessibilityLabel("\(platform.displayName)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Avatar mark

/// Initials on an entity-tint wash — the studio's identity chip, also used
/// by the shell header morph and the Profiles list rows.
struct ProfileAvatarMark: View {
    let name: String
    var size: CGFloat = 40

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(DS.entityContent.opacity(0.14))
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(DS.entityContent)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.entityContent)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(DS.entityContent.opacity(0.2), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

// MARK: - Intelligence footer card

/// Optional enrichment, demoted to the footer: generate (or regenerate) the
/// voice model in the background. Never blocks creating a profile.
struct ProfileIntelligenceCard: View {
    @Bindable var store: ProfileStudioStore

    @State private var showDetails = false
    @State private var editingMetricId: UUID?
    @State private var editingMetricKey = ""
    @State private var editingMetricValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            SettingsSectionHeader(label: "INTELLIGENCE", detail: detail)
            SettingsGroupedBox {
                content
                    .padding(.horizontal, DS.space16)
                    .padding(.vertical, DS.space12)
                if showDetails, store.intelligenceModel != nil {
                    SettingsRowDivider(inset: 0)
                    modelDetails
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    /// The full model view (voice, performance, failure rules, audience,
    /// positioning) with user overrides, expanded in place.
    @ViewBuilder
    private var modelDetails: some View {
        if let model = store.intelligenceModel {
            IntelligenceModelView(
                model: Binding(
                    get: { model },
                    set: { store.intelligenceModel = $0 }
                ),
                overrides: Binding(
                    get: { store.intelligenceModel?.userOverrides ?? [] },
                    set: {
                        store.intelligenceModel?.userOverrides = $0
                        store.persistIntelligenceEdits()
                    }
                ),
                editingMetricId: $editingMetricId,
                editingMetricKey: $editingMetricKey,
                editingMetricValue: $editingMetricValue,
                showUpdateButton: false
            )
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space12)
        }
    }

    private var detail: String? {
        guard let model = store.intelligenceModel else { return "optional" }
        return "generated \(model.generatedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    @ViewBuilder
    private var content: some View {
        if store.isGenerating {
            generatingRow
        } else if let model = store.intelligenceModel {
            modelRow(model)
        } else {
            emptyRow
        }
        if let error = store.generationError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(DS.footnote)
                .foregroundStyle(DS.orange)
                .padding(.top, DS.space4)
        }
    }

    private var generatingRow: some View {
        HStack(spacing: DS.space10) {
            ProgressView()
                .controlSize(.small)
            Text("Distilling the documents into a voice model — keep working, this runs in the background.")
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)
            Spacer()
        }
    }

    private func modelRow(_ model: ClientIntelligenceModel) -> some View {
        HStack(spacing: DS.space12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 28, height: 28)
                .background(DS.accentSoft, in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Voice model ready")
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.text)
                HStack(spacing: DS.space6) {
                    if let fp = model.failureFingerprint, !fp.rules.isEmpty {
                        Text("\(fp.rules.count) failure rules")
                            .font(DS.footnote.monospacedDigit())
                            .foregroundStyle(DS.textMuted)
                    }
                    let docTotal = model.documentCount.story + model.documentCount.reels
                        + model.documentCount.threads + model.documentCount.voiceGuide
                        + model.documentCount.underperformingReels + model.documentCount.underperformingThreads
                    if docTotal > 0 {
                        Text("from \(docTotal) documents")
                            .font(DS.footnote.monospacedDigit())
                            .foregroundStyle(DS.textMuted)
                    }
                }
            }
            Spacer()
            detailsToggle
            regenerateButton
        }
        .accessibilityElement(children: .combine)
    }

    private var detailsToggle: some View {
        Button {
            withAnimation(ProMotionSprings.gentle) { showDetails.toggle() }
        } label: {
            HStack(spacing: DS.space4) {
                Text(showDetails ? "Hide details" : "Details")
                    .font(DS.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(.degrees(showDetails ? 180 : 0))
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background(DS.glassSectionFill, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Inspect and override the generated model")
    }

    private var regenerateButton: some View {
        Button {
            store.generateIntelligence()
        } label: {
            Text("Regenerate")
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.accent)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, DS.space6)
                .background(DS.accentSoft, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!store.canGenerate)
        .help("Re-analyze all documents")
    }

    private var emptyRow: some View {
        HStack(spacing: DS.space12) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .frame(width: 28, height: 28)
                .background(DS.glassSectionFill, in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Optional — distill these documents into a voice model")
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.text)
                Text(store.documents.isEmpty
                    ? "Add at least one document first."
                    : "Cosmo reads everything above and learns the voice, audience, and what works.")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
            Spacer()
            Button {
                store.generateIntelligence()
            } label: {
                Text("Generate")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(store.canGenerate ? DS.textOnAccent : DS.textMuted)
                    .padding(.horizontal, DS.space16)
                    .padding(.vertical, DS.space6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(store.canGenerate ? AnyShapeStyle(DS.accent) : AnyShapeStyle(DS.glassSectionFill))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!store.canGenerate)
            .help("Generate the voice model in the background")
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Cascade entrance

private struct StudioCascadeModifier: ViewModifier {
    let hasAppeared: Bool
    let index: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared || reduceMotion ? 0 : 10)
            .animation(
                reduceMotion ? .easeOut(duration: 0.2) : ProMotionSprings.cascade(index: index),
                value: hasAppeared
            )
    }
}

extension View {
    func studioCascade(hasAppeared: Bool, index: Int, reduceMotion: Bool) -> some View {
        modifier(StudioCascadeModifier(hasAppeared: hasAppeared, index: index, reduceMotion: reduceMotion))
    }
}
