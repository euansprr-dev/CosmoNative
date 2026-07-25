// CosmoOS/UI/Ideas/IdeaTriageSheet.swift
// "Sort sparks" — the desk's triage ritual (Phase 3 of the reinvention).
// One unassigned capture at a time, keyboard-first: 1–9 assigns it to a
// client, ⏎ keeps it a spark, D opens the bench, ⌫ archives, ←→ walk the
// queue, Esc is done anytime. The queue is a snapshot (order-locked — the
// deal doesn't reshuffle underneath you), every write is the model's own
// ⌘Z-registered verb, and clearing the tray earns the page's ONE moment of
// delight (the Things law: delight spent everywhere is delight spent nowhere).

import SwiftUI

struct IdeaTriageSheet: View {
    let model: IdeasPageModel
    let onOpenIdea: (IdeaGalleryItem) -> Void
    let onClose: () -> Void

    /// The tray at the moment the ritual began — stable while sorting.
    @State private var queue: [IdeaGalleryItem] = []
    @State private var index = 0
    @State private var handled: Set<String> = []
    @State private var sealVisible = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var current: IdeaGalleryItem? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    private var isDone: Bool { index >= queue.count }

    var body: some View {
        ZStack {
            Color.black.opacity(0.30)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            panel
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        .onAppear {
            queue = model.desk.sparks
            isFocused = true
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            CosmoSectionHeader(
                label: "New sparks",
                detail: isDone ? "\(handled.count) sorted" : "\(index + 1) of \(queue.count)"
            )
            if isDone {
                completion
            } else if let current {
                sparkStage(current)
                clientAnswers(for: current)
            }
            keyHints
        }
        .padding(DS.space20)
        .frame(width: 560)
        .background(DS.surfaceElevated)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(DS.palette.sepiaBorder, lineWidth: 0.5)
        )
        .dsFloatingShadow()
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onExitCommand(perform: onClose)
        .modifier(TriageKeys(
            isDone: isDone,
            clientCount: min(model.assignableClients.count, 9),
            onDigit: assign(toClientNumber:),
            onKeep: keep,
            onDevelop: develop,
            onArchive: archive,
            onBack: { move(-1) },
            onForward: { move(1) },
            onFinish: onClose
        ))
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(isDone ? "Sparks sorted" : "Sorting spark \(index + 1) of \(queue.count)")
    }

    // MARK: The spark on stage

    private func sparkStage(_ idea: IdeaGalleryItem) -> some View {
        HStack(alignment: .top, spacing: DS.space16) {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text(idea.hooks.first?.isEmpty == false ? idea.hooks.first! : idea.title)
                    .font(DS.heroTitleSerif)
                    .foregroundStyle(DS.text)
                    .lineSpacing(3)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let context = idea.context, !context.isEmpty {
                    Text(context)
                        .font(DS.subheadline)
                        .foregroundStyle(DS.textSecondary)
                        .lineSpacing(2)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(captureAge(idea))
                    .font(DS.caption2)
                    .monospacedDigit()
                    .foregroundStyle(DS.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let thumbs = model.inspirationThumbs[idea.atomUUID], !thumbs.isEmpty {
                IdeaInspirationThumb(
                    candidates: thumbs,
                    hairline: DS.palette.sepiaBorder,
                    width: 108,
                    height: 138
                )
            }
        }
        .frame(minHeight: 150, alignment: .topLeading)
        .id(idea.atomUUID)
        .transition(advanceTransition)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : ProMotionSprings.snappy, value: idea.atomUUID)
    }

    /// The answers: whose is it? Number-keyed client capsules.
    private func clientAnswers(for idea: IdeaGalleryItem) -> some View {
        let clients = Array(model.assignableClients.prefix(9))
        return HStack(spacing: DS.space8) {
            ForEach(Array(clients.enumerated()), id: \.element.uuid) { number, client in
                TriageClientButton(
                    number: number + 1,
                    name: client.name,
                    tint: DS.clientColor(for: client.uuid)
                ) {
                    assign(toClientNumber: number + 1)
                }
            }
        }
    }

    // MARK: Completion (the one earned delight)

    private var completion: some View {
        VStack(spacing: DS.space10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(DS.entityIdea)
                .scaleEffect(sealVisible ? 1 : (reduceMotion ? 1 : 0.4))
                .opacity(sealVisible ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : ProMotionSprings.bouncy, value: sealVisible)
                .accessibilityHidden(true)
            Text(handled.isEmpty ? "Tray's already clear" : "Tray sorted")
                .font(DS.headline)
                .foregroundStyle(DS.text)
            Text(completionLine)
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
            Button("Done", action: onClose)
                .buttonStyle(.plain)
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, DS.space16)
                .frame(height: 30)
                .background(DS.accent, in: .capsule)
                .contentShape(.capsule)
                .help("Close (⏎ or Esc)")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space24)
        .task {
            // One frame after mount, or the seal arrives already-visible
            // and the bounce never plays.
            try? await Task.sleep(for: .milliseconds(16))
            sealVisible = true
        }
        .accessibilityElement(children: .combine)
    }

    private var completionLine: String {
        let skipped = queue.count - handled.count
        if handled.isEmpty { return "Nothing waiting to be sorted." }
        if skipped > 0 { return "\(handled.count) sorted · \(skipped) left for later." }
        return "Every capture has a home."
    }

    // MARK: Key hints (teach shortcuts in place — the Raycast footer)

    private var keyHints: some View {
        HStack(spacing: DS.space12) {
            if isDone {
                hint("⏎", "Done")
            } else {
                hint("1–\(min(model.assignableClients.count, 9))", "Assign")
                hint("⏎", "Keep")
                hint("D", "Develop")
                hint("⌫", "Archive")
                hint("← →", "Walk")
            }
            Spacer(minLength: 0)
            hint("esc", isDone ? "Close" : "Done")
        }
        .accessibilityHidden(true)
    }

    private func hint(_ key: String, _ verb: String) -> some View {
        HStack(spacing: DS.space4) {
            Text(key)
                .font(DS.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, DS.space6)
                .frame(height: 18)
                .background(DS.glassSectionFill, in: .rect(cornerRadius: 5, style: .continuous))
            Text(verb)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: Verbs

    private func assign(toClientNumber number: Int) {
        guard let current, model.assignableClients.indices.contains(number - 1) else { return }
        model.assignClient(current, to: model.assignableClients[number - 1].uuid, quiet: true)
        advance(handling: current)
    }

    private func keep() {
        guard let current else { return }
        advance(handling: current)
    }

    private func archive() {
        guard let current else { return }
        model.pass(current, quiet: true)
        advance(handling: current)
    }

    private func develop() {
        guard let current else { return }
        onClose()
        onOpenIdea(current)
    }

    private func advance(handling idea: IdeaGalleryItem) {
        handled.insert(idea.atomUUID)
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : ProMotionSprings.snappy) {
            index += 1
        }
    }

    private func move(_ step: Int) {
        let next = index + step
        guard next >= 0, next <= queue.count else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : ProMotionSprings.snappy) {
            index = next
        }
    }

    private var advanceTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    private func captureAge(_ idea: IdeaGalleryItem) -> String {
        guard let date = ISO8601.date(from: idea.createdAt) else { return "Unsorted capture" }
        return "Captured \(date.cosmoCompactAge) back"
    }
}

// MARK: - Key routing

/// The ritual's whole keyboard, one modifier: digits assign, ⏎ keeps (or
/// closes when done), D develops, ⌫ archives, arrows walk.
private struct TriageKeys: ViewModifier {
    let isDone: Bool
    let clientCount: Int
    let onDigit: (Int) -> Void
    let onKeep: () -> Void
    let onDevelop: () -> Void
    let onArchive: () -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    let onFinish: () -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(.return) {
                isDone ? onFinish() : onKeep()
                return .handled
            }
            .onKeyPress(.delete) {
                guard !isDone else { return .ignored }
                onArchive()
                return .handled
            }
            .onKeyPress(.leftArrow) {
                guard !isDone else { return .ignored }
                onBack()
                return .handled
            }
            .onKeyPress(.rightArrow) {
                guard !isDone else { return .ignored }
                onForward()
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "dD123456789")) { press in
                guard !isDone else { return .ignored }
                let char = press.characters.lowercased()
                if char == "d" {
                    onDevelop()
                    return .handled
                }
                if let digit = Int(char), digit >= 1, digit <= clientCount {
                    onDigit(digit)
                    return .handled
                }
                return .ignored
            }
    }
}

// MARK: - Client answer capsule

private struct TriageClientButton: View {
    let number: Int
    let name: String
    let tint: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space6) {
                Text("\(number)")
                    .font(DS.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 18, height: 18)
                    .background(DS.glassSectionFill, in: .circle)
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(name)
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.space12)
            .frame(height: 38)
            .background(DS.glassCardFill)
            .clipShape(.capsule)
            .overlay(Capsule().strokeBorder(DS.palette.sepiaBorder, lineWidth: 0.5))
            .contentShape(.capsule)
        }
        .buttonStyle(IdeaCardPressStyle())
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .help("Assign to \(name) (\(number))")
        .accessibilityLabel("Assign to \(name), key \(number)")
    }
}
