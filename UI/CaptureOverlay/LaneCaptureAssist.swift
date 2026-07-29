// CosmoOS/UI/CaptureOverlay/LaneCaptureAssist.swift
// The lane-aware capture input — the Mac port of the iPhone's capture-lane
// highlight treatment. A resolved `Groceries:` prefix gets the soft rounded
// wash in that lane's own tint; while the typed text still prefixes a lane
// name/alias the untyped tail renders as ghost text after the caret, and a
// space (or the chip) completes it.
//
// Rendering rides TokenWashTextView — one native NSTextView that colors the
// prefix, draws its wash, and positions the ghost tail off the real caret
// rect, so wrapped lines never drift.
// July 2026 — Capture Anywhere lane highlights

import SwiftUI

// MARK: - Live lane matching (one brain for all capture inputs)

@Observable
@MainActor
final class LaneCaptureAssist {

    /// Everything typed so far is the start of a lane name or alias, so a
    /// space (or a chip click) can finish the command.
    struct Suggestion: Equatable {
        let lane: CaptureDestination
        /// The candidate being completed — the lane name or one of its aliases.
        let completion: String
        /// What the user has typed so far (the prefix of `completion`).
        let typed: String
        /// The untyped tail of the completion, shown as ghost text.
        var remainder: String { String(completion.dropFirst(typed.count)) }
    }

    /// A resolved `alias:` prefix — the lane routing will use on submit.
    struct LaneMatch: Equatable {
        let lane: CaptureDestination
        let alias: String
        /// The capture text with the alias prefix stripped.
        let remainder: String
    }

    /// Debounced resolved `alias:` hint.
    private(set) var hint: LaneMatch?
    /// Live prefix completion while no colon has been typed yet.
    private(set) var suggestion: Suggestion?

    private var lanes: [CaptureDestination] = []
    private var previousText = ""
    private var hintTask: Task<Void, Never>?

    /// Surfaces without a lane observer (the capture overlay) fetch once per session.
    func loadLanes() async {
        lanes = (try? await CaptureDestinationRepository.shared.fetchActive()) ?? []
    }

    /// Process one text edit. Returns the full replacement text when a
    /// trailing space accepted the live suggestion ("g" + space →
    /// "Groceries: ") — the caller assigns it back to its field.
    @discardableResult
    func textChanged(_ text: String) -> String? {
        defer { previousText = text }
        hintTask?.cancel()

        guard text.contains(":") else {
            hint = nil
            if text == previousText + " ",
               let suggestion, suggestion.typed == previousText {
                return accept()
            }
            suggestion = Self.suggestion(for: text, in: lanes)
            return nil
        }
        suggestion = nil

        // Exact name/alias matches resolve SYNCHRONOUSLY against the
        // in-memory roster, so the highlight lands the same frame the colon
        // does — accepting "C" + space paints "Cosmo:" with zero flicker.
        // The debounced repository pass runs only for what memory can't
        // answer (normalized aliases, a roster that hasn't loaded yet).
        if let match = Self.exactMatch(for: text, in: lanes) {
            hint = match
            return nil
        }
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            let match = await Self.resolvedMatch(for: text)
            guard !Task.isCancelled else { return }
            self.hint = match
        }
        return nil
    }

    /// The in-memory mirror of the repository resolution for exact
    /// (case-insensitive) name/alias hits — no actor hop, no database.
    private static func exactMatch(
        for text: String,
        in lanes: [CaptureDestination]
    ) -> LaneMatch? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let prefix = String(text[text.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty, prefix.split(separator: " ").count <= 4 else { return nil }
        let needle = prefix.lowercased()
        for lane in lanes {
            if ([lane.name] + lane.aliases).contains(where: { $0.lowercased() == needle }) {
                let remainder = String(text[text.index(after: colon)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return LaneMatch(lane: lane, alias: prefix, remainder: remainder)
            }
        }
        return nil
    }

    /// The full resolution pass — normalized name/alias matching against the
    /// live lane roster. Used by the debounced hint and again at submit time.
    static func resolvedMatch(for text: String) async -> LaneMatch? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let prefix = String(text[text.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty, prefix.split(separator: " ").count <= 4 else { return nil }
        guard let lane = ((try? await CaptureDestinationRepository.shared.resolveCommand(prefix)) ?? nil) else { return nil }
        let remainder = String(text[text.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LaneMatch(lane: lane, alias: prefix, remainder: remainder)
    }

    /// Completes the suggested lane into a ready `alias:` command.
    func accept() -> String? {
        guard let suggestion else { return nil }
        self.suggestion = nil
        return suggestion.completion + ": "
    }

    func reset() {
        hintTask?.cancel()
        hint = nil
        suggestion = nil
        previousText = ""
    }

    /// The whole typed text must prefix a lane name or alias — anything
    /// longer than a plausible command is prose, not a lane invocation.
    /// Lanes arrive lastUsed-first, so the freshest lane wins ties.
    private static func suggestion(for text: String, in lanes: [CaptureDestination]) -> Suggestion? {
        let needle = text.lowercased()
        guard !needle.isEmpty, needle.count <= 24, !needle.contains("\n"),
              needle == needle.trimmingCharacters(in: .whitespaces) else { return nil }
        for lane in lanes {
            for candidate in [lane.name] + lane.aliases {
                if candidate.lowercased().hasPrefix(needle) {
                    return Suggestion(lane: lane, completion: candidate, typed: text)
                }
            }
        }
        return nil
    }
}

// MARK: - The highlighted field

struct LaneHighlightedCaptureField: View {
    @Binding var text: String
    var placeholder: String = "Capture a thought…"
    var font: NSFont = .systemFont(ofSize: 15, weight: .regular)
    var textColor: Color = DS.text
    var maxLines: Int? = nil
    let assist: LaneCaptureAssist
    @Binding var isFocused: Bool
    var onSubmit: () -> Void = {}
    var onShiftSubmit: (() -> Void)? = nil

    var body: some View {
        TokenWashTextView(
            text: $text,
            placeholder: placeholder,
            font: font,
            ink: NSColor(textColor),
            segments: segments,
            ghostText: ghostText,
            ghostColor: NSColor((laneColor ?? DS.textMuted).opacity(0.45)),
            maxLines: maxLines,
            isFocused: $isFocused,
            onSubmit: onSubmit,
            onShiftSubmit: onShiftSubmit
        )
    }

    private var laneColor: Color? {
        if let hint = assist.hint { return LanePalette.color(for: hint.lane) }
        if let suggestion = assist.suggestion { return LanePalette.color(for: suggestion.lane) }
        return nil
    }

    /// The resolved `alias:` prefix — start of text through the colon — but
    /// only while the hint still matches what's on screen (the hint is
    /// debounced, so it can lag a keystroke behind).
    private var segments: [TextWashSegment] {
        guard let hint = assist.hint,
              let laneColor,
              let colon = text.firstIndex(of: ":"),
              text[text.startIndex..<colon].trimmingCharacters(in: .whitespaces) == hint.alias
        else { return [] }
        let end = text.index(after: colon)
        let length = text[text.startIndex..<end].utf16.count
        return [TextWashSegment(utf16Range: 0..<length, ink: NSColor(laneColor))]
    }

    /// Ghost tail of the suggested lane ("g" shows "roceries:" ahead of the
    /// caret) — display-only, the real text and caret are untouched.
    private var ghostText: String? {
        guard let suggestion = assist.suggestion, suggestion.typed == text else { return nil }
        return suggestion.remainder + ":"
    }
}

// MARK: - The lane chip (resolved hint, or clickable completion)

struct LaneAssistChip: View {
    @Binding var text: String
    let assist: LaneCaptureAssist

    var body: some View {
        if let hint = assist.hint {
            chip(
                lane: hint.lane,
                label: "→ \(hint.lane.name)",
                accessibility: "Will capture to \(hint.lane.name)"
            )
        } else if let suggestion = assist.suggestion {
            // Click (or press space) to finish the lane command.
            Button {
                if let completed = assist.accept() {
                    text = completed
                }
            } label: {
                chip(
                    lane: suggestion.lane,
                    label: "\(suggestion.lane.name) — space completes",
                    accessibility: "Complete \(suggestion.lane.name) lane"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func chip(lane: CaptureDestination, label: String, accessibility: String) -> some View {
        let tint = LanePalette.color(for: lane)
        return HStack(spacing: DS.space6) {
            Image(systemName: lane.icon)
                .font(DS.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text(label)
                .font(DS.caption.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space4)
        .background(tint.opacity(0.12), in: .capsule)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityLabel(accessibility)
    }
}

// MARK: - Lane tint

/// Stable lane tint (iPhone parity): an explicit token wins; otherwise the
/// lane hashes into the entity palette so tints stay distinct and identical
/// across launches — and across devices.
enum LanePalette {
    private static let wheel: [Color] = [
        DS.entityIdea, DS.entityResearch, DS.entityContent, DS.entityNote,
        DS.entityConnection, DS.entitySwipe, DS.entityTask, DS.entityImage,
    ]

    static func color(for lane: CaptureDestination) -> Color {
        if let token = lane.colorAccentToken, !token.isEmpty {
            return Color(hex: token)
        }
        var hash = 0
        for scalar in lane.uuid.unicodeScalars {
            hash = (hash &* 31 &+ Int(scalar.value)) & 0xFFFF
        }
        return wheel[hash % wheel.count]
    }
}
