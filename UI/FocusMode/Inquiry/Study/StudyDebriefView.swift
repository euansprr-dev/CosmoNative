// CosmoOS/UI/FocusMode/Inquiry/Study/StudyDebriefView.swift
// The Debrief's room: the teach-back interview in the Study's center column,
// fed by the thinking bar. After the wrap, the review — the understanding
// diff (built from what YOU said), the ripest seedling's invitation, and the
// quiet confirms (lexicon terms, new questions) as one-tap chips. Replaces
// the crystallize sheet: no checkboxes over machine-written pages, ever.

import SwiftUI

@MainActor
struct StudyDebriefView: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let state: InquiryWorkspaceViewModel.StudyDebriefState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space20) {
                    masthead
                    transcript
                    if state.phase != .interviewing {
                        reviewSection
                    }
                    Color.clear.frame(height: 1).id("debrief-tail")
                }
                .padding(.horizontal, DS.space32)
                .padding(.top, DS.space24)
                .padding(.bottom, StudyMetrics.panelBottomInset + DS.space24)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onChange(of: state.messages.count) {
                withAnimation(ProMotionSprings.gentle) {
                    proxy.scrollTo("debrief-tail", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text("DEBRIEF")
                .dsSmallCapsLabel()
            Text(viewModel.activeQuestionTitle)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(DS.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            ForEach(state.messages) { message in
                messageRow(message)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if state.isThinking {
                thinkingRow
            }
        }
        .animation(ProMotionSprings.gentle, value: state.messages)
    }

    @ViewBuilder
    private func messageRow(_ message: InquiryWorkspaceViewModel.StudyDebriefState.Message) -> some View {
        if message.role == .cosmo {
            Text(message.text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(DS.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(message.text)
                .font(DS.body)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space8)
                .background(DS.surfaceCard.opacity(0.9), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.borderSubtle, lineWidth: 1))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: DS.space8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
            Text("Listening…")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - Review (after the wrap)

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            if let update = state.understandingUpdate {
                understandingCard(update)
            }
            if let seedling = viewModel.debriefRipeSeedling {
                seedlingOffer(seedling)
            }
            if !viewModel.debriefFoldOffers.isEmpty {
                foldOffersCard
            }
            confirmsSection
            footerBar
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func understandingCard(_ update: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: DS.space8) {
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
                Text("Your understanding, updated")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.text)
                Spacer()
                Toggle("", isOn: acceptUnderstandingBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .accessibilityLabel("Apply understanding update")
            }
            Text(update)
                .font(.system(.body, design: .serif))
                .foregroundStyle(state.acceptUnderstanding ? DS.text : DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Built from what you just said — it becomes the question's living model.")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.accent.opacity(0.22), lineWidth: 1))
    }

    private func seedlingOffer(_ seedling: IncubatingConcept) -> some View {
        HStack(spacing: DS.space10) {
            Image(systemName: "leaf")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(seedling.name) is ripe")
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(DS.text)
                Text(ConceptRipeness.evaluate(seedling).reason ?? "\(seedling.pendingItems.count) captures waiting")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
            Spacer()
            Button {
                Task { await viewModel.developFromDebrief(seedling) }
            } label: {
                Text("Develop now · ~3 min")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, 6)
                    .background(DS.accent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Finish the debrief and pivot to the Concept Desk")
            .accessibilityLabel("Develop \(seedling.name) now")
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.borderSubtle, lineWidth: 1))
    }

    /// The consolidation offers: established seedlings whose captures the
    /// whole-session resolver filed under another concept. Sprouts folded
    /// silently at tidy time — every row here is per-fold consent.
    private var foldOffersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.space8) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
                Text("Consolidation")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.text)
                Spacer()
            }
            .padding(.bottom, DS.space8)
            ForEach(viewModel.debriefFoldOffers) { offer in
                DebriefFoldOfferRow(
                    offer: offer,
                    onFold: { Task { await viewModel.acceptDebriefFoldOffer(offer) } },
                    onDismiss: { viewModel.dismissDebriefFoldOffer(offer) }
                )
            }
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.borderSubtle, lineWidth: 1))
    }

    @ViewBuilder
    private var confirmsSection: some View {
        if let synthesis = viewModel.debriefSynthesis {
            VStack(alignment: .leading, spacing: DS.space10) {
                if !synthesis.lexiconCandidates.isEmpty {
                    chipGroup(
                        label: "Lexicon",
                        items: synthesis.lexiconCandidates.map { ($0.id, $0.term) },
                        selection: lexiconBinding
                    )
                }
                if !synthesis.newQuestions.isEmpty {
                    chipGroup(
                        label: "New questions",
                        items: synthesis.newQuestions.map { ($0.id, $0.text) },
                        selection: questionsBinding
                    )
                }
            }
        } else if state.phase == .reviewing {
            HStack(spacing: DS.space8) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Reading the session for terms and follow-up questions…")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    private func chipGroup(
        label: String,
        items: [(id: String, text: String)],
        selection: Binding<Set<String>>
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(label.uppercased())
                .dsSmallCapsLabel()
            CosmoFlowLayout(spacing: DS.space6) {
                ForEach(items, id: \.id) { item in
                    DebriefChip(
                        text: item.text,
                        isOn: selection.wrappedValue.contains(item.id)
                    ) {
                        if selection.wrappedValue.contains(item.id) {
                            selection.wrappedValue.remove(item.id)
                        } else {
                            selection.wrappedValue.insert(item.id)
                        }
                    }
                }
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: DS.space12) {
            Button("Discard debrief") {
                viewModel.cancelDebrief()
            }
            .buttonStyle(.plain)
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
            .accessibilityLabel("Discard debrief without applying")

            Spacer()

            Button {
                Task { await viewModel.applyDebrief() }
            } label: {
                HStack(spacing: 6) {
                    if state.phase == .applying {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    Text("Apply & finish")
                        .font(DS.caption.weight(.semibold))
                }
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, DS.space16)
                .padding(.vertical, 8)
                .background(DS.accent, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(state.phase == .applying)
            .keyboardShortcut(.return, modifiers: [.command])
            .accessibilityLabel("Apply debrief and finish session")
        }
        .padding(.top, DS.space8)
    }

    // MARK: - Bindings

    private var acceptUnderstandingBinding: Binding<Bool> {
        Binding(
            get: { viewModel.debrief?.acceptUnderstanding ?? false },
            set: { viewModel.debrief?.acceptUnderstanding = $0 }
        )
    }

    private var lexiconBinding: Binding<Set<String>> {
        Binding(
            get: { viewModel.debrief?.acceptedLexiconIds ?? [] },
            set: { viewModel.debrief?.acceptedLexiconIds = $0 }
        )
    }

    private var questionsBinding: Binding<Set<String>> {
        Binding(
            get: { viewModel.debrief?.acceptedQuestionIds ?? [] },
            set: { viewModel.debrief?.acceptedQuestionIds = $0 }
        )
    }
}

/// One fold offer: the seedling, where its captures were filed, and the two
/// exits — Fold (captures merge, name survives as an alias) or keep separate.
@MainActor
private struct DebriefFoldOfferRow: View {
    let offer: SeedbedFoldOffer
    let onFold: () -> Void
    let onDismiss: () -> Void

    @State private var isWorking = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fold “\(offer.seedlingName)” into “\(offer.targetName)”")
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(offer.reason)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.space8)
            if isWorking {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            } else {
                actions
            }
        }
        .padding(.vertical, DS.space6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fold \(offer.seedlingName) into \(offer.targetName): \(offer.reason)")
    }

    private var actions: some View {
        HStack(spacing: DS.space8) {
            Button("Fold") {
                isWorking = true
                onFold()
            }
            .buttonStyle(.plain)
            .font(DS.caption.weight(.semibold))
            .foregroundStyle(DS.accent)
            .help("Its captures move into \(offer.targetName); the old name still routes there")
            .accessibilityLabel("Fold \(offer.seedlingName)")

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Keep it separate — it keeps growing on its own")
            .accessibilityLabel("Keep \(offer.seedlingName) separate")
        }
    }
}

/// One quiet confirm: filled = will apply, hollow = skipped.
@MainActor
private struct DebriefChip: View {
    let text: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
                Text(text)
                    .font(DS.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? DS.accent : DS.textMuted)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, 4)
            .background(isOn ? AnyShapeStyle(DS.accentSoft) : AnyShapeStyle(DS.glassInputFill), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Will be added — click to skip" : "Skipped — click to add")
        .accessibilityLabel("\(text), \(isOn ? "will be added" : "skipped")")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
