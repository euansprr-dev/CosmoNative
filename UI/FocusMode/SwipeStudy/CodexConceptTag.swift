// CosmoOS/UI/FocusMode/SwipeStudy/CodexConceptTag.swift
// Interactive concept tag — tap to see Codex definition, examples, and anti-patterns.
// Drop-in replacement for static capsule labels in physics views.

import SwiftUI

extension Notification.Name {
    static let navigateToCodexElement = Notification.Name("navigateToCodexElement")
}

// MARK: - Environment Key

private struct CodexLookupKey: EnvironmentKey {
    // Computed, not stored: a stored nil of a non-Sendable type is a mutable
    // global under Swift 6 strict concurrency and breaks `swift test`.
    static var defaultValue: CodexConceptLookup? { nil }
}

extension EnvironmentValues {
    var codexLookup: CodexConceptLookup? {
        get { self[CodexLookupKey.self] }
        set { self[CodexLookupKey.self] = newValue }
    }
}

/// A tappable concept tag that shows Codex detail on tap.
/// If the concept isn't in the lookup (or no lookup in environment), renders as a plain capsule.
struct CodexConceptTag: View {
    let name: String
    let color: Color

    @Environment(\.codexLookup) private var lookup
    @State private var showPopover = false

    private var entry: CodexConceptEntry? {
        lookup?.lookup(name)
    }

    private var isInteractive: Bool {
        entry != nil
    }

    var body: some View {
        if isInteractive {
            Button {
                showPopover = true
            } label: {
                tagContent
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                if let entry {
                    CodexConceptPopover(entry: entry, accentColor: color, showPopover: $showPopover)
                }
            }
        } else {
            tagContent
        }
    }

    private var tagContent: some View {
        Text(name)
            .font(DS.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                color.opacity(isInteractive ? 0.15 : DS.opacitySubtle),
                in: Capsule()
            )
            .overlay(
                isInteractive
                    ? Capsule().stroke(color.opacity(0.3), lineWidth: 0.5)
                    : nil
            )
    }
}

/// A compact version for inline use (no label prefix)
struct CodexConceptPill: View {
    let name: String
    let label: String?
    let color: Color

    @Environment(\.codexLookup) private var lookup
    @State private var showPopover = false

    private var entry: CodexConceptEntry? {
        lookup?.lookup(name)
    }

    var body: some View {
        HStack(spacing: 4) {
            if let label {
                Text(label)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }

            if entry != nil {
                Button {
                    showPopover = true
                } label: {
                    pillContent
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                    if let entry {
                        CodexConceptPopover(entry: entry, accentColor: color, showPopover: $showPopover)
                    }
                }
            } else {
                pillContent
            }
        }
    }

    private var pillContent: some View {
        Text(name)
            .font(DS.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                color.opacity(entry != nil ? 0.15 : DS.opacitySubtle),
                in: Capsule()
            )
            .overlay(
                entry != nil
                    ? Capsule().stroke(color.opacity(0.3), lineWidth: 0.5)
                    : nil
            )
    }
}

// MARK: - Popover Content

struct CodexConceptPopover: View {
    let entry: CodexConceptEntry
    let accentColor: Color
    @Binding var showPopover: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if !entry.definition.isEmpty { definitionSection }
                if !entry.applicationRules.isEmpty { applicationRulesSection }
                if !entry.examples.isEmpty { examplesSection }
                if let where_ = entry.whereActive, !where_.isEmpty { whereActiveSection(where_) }
                if !entry.antiPatterns.isEmpty { antiPatternsSection }
                seeFullEntryButton
            }
            .padding(20)
        }
        .frame(width: 420)
        .frame(maxHeight: 480)
        .background(DS.surface)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(entry.name)
                    .font(.system(size: 15, weight: .bold, design: .default))
                    .foregroundStyle(DS.text)

                Text(entry.category)
                    .font(DS.caption2)
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(accentColor.opacity(0.12), in: Capsule())
            }

            if !entry.frequency.isEmpty {
                Text(entry.frequency)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    // MARK: - Definition

    private var definitionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.definition)
                .font(DS.caption)
                .foregroundStyle(DS.text)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Examples

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Examples from Viral Posts")
                .dsSmallCapsLabel()

            ForEach(Array(entry.examples.enumerated()), id: \.offset) { _, example in
                exampleCard(example)
            }
        }
    }

    private func exampleCard(_ example: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Extract the quoted text and source
            if let quoteEnd = example.firstIndex(of: "\""),
               let quoteStart = example.index(after: example.startIndex) == quoteEnd ? nil : example.startIndex ... quoteEnd as? ClosedRange<String.Index> {
                // Has quote — show it styled
                Text(example)
                    .font(DS.caption2)
                    .foregroundStyle(DS.text)
                    .lineSpacing(2)
            } else {
                Text(example)
                    .font(DS.caption2)
                    .foregroundStyle(DS.text)
                    .lineSpacing(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accentColor.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Where Active

    private func whereActiveSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How to Spot It (from Codex)")
                .dsSmallCapsLabel()

            Text(text)
                .font(DS.caption2)
                .foregroundStyle(DS.text)
                .italic()
                .lineSpacing(2)
        }
    }

    // MARK: - Application Rules

    private var applicationRulesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How to Use")
                .font(DS.smallCaps)
                .foregroundStyle(DS.green.opacity(0.8))

            ForEach(Array(entry.applicationRules.enumerated()), id: \.offset) { idx, rule in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(idx + 1).")
                        .font(DS.caption2)
                        .foregroundStyle(DS.green.opacity(0.6))
                        .frame(width: 14, alignment: .trailing)
                    Text(rule)
                        .font(DS.caption2)
                        .foregroundStyle(DS.text)
                        .lineSpacing(2)
                }
            }
        }
    }

    // MARK: - Anti-Patterns

    private var antiPatternsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Anti-Patterns")
                .font(DS.smallCaps)
                .foregroundStyle(DS.red.opacity(0.8))

            ForEach(Array(entry.antiPatterns.enumerated()), id: \.offset) { _, ap in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.red.opacity(0.6))
                        .padding(.top, 2)

                    Text(ap)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineSpacing(2)
                }
            }
        }
    }

    // MARK: - See Full Entry

    private var seeFullEntryButton: some View {
        Button {
            showPopover = false
            NotificationCenter.default.post(
                name: .navigateToCodexElement,
                object: nil,
                userInfo: ["canonicalName": entry.name]
            )
        } label: {
            HStack(spacing: 4) {
                Text("See Full Entry")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(accentColor.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var showPopover = true
    CodexConceptPopover(
        entry: CodexConceptEntry(
            id: "curiosity+",
            name: "CURIOSITY+",
            category: "Reader Delta",
            definition: "The reader feels an information gap they want to close. This is the most common delta and often the first one installed.",
            frequency: "Appears in 105/105 posts",
            examples: [
                "\"2020: \"Babe, I'm worried about our future…\"\" — [Post 1] Slide 1",
                "\"As a millionaire, I'm not ashamed to admit that I cheated...\" — [Post 15] Slide 1",
            ],
            whereActive: "The word 'cheated' without an object is what creates the curiosity gap",
            antiPatterns: [
                "- Generic curiosity bait without a credible anchor",
                "- \"You won't believe what happened next...\" — templated, not lived",
            ],
            applicationRules: [
                "Create an information gap by withholding the object of a verb",
                "Anchor curiosity with a credible, specific detail",
                "Resolve the gap within the same post to build trust",
            ],
            readerEffect: "Reader feels compelled to continue reading to close the gap"
        ),
        accentColor: .orange,
        showPopover: $showPopover
    )
    .padding()
}
