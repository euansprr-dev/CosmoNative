// CosmoOS/UI/InlineAssistant/CosmoInlineAssistantPaneEmptyState.swift
// The pane's first impression: not a blank chat, but a menu of what Cosmo can
// do here — enabled skills as cards, plus starters tuned to the active surface.
// June 2026

import SwiftUI

// MARK: - Starter policy (pure, testable)

struct CosmoInlineAssistantStarterSuggestion: Equatable {
    let label: String
    let prompt: String
}

enum CosmoInlineAssistantPaneEmptyStatePolicy {
    static func starters(for kind: CosmoEditableSurfaceKind?) -> [CosmoInlineAssistantStarterSuggestion] {
        switch kind {
        case .text:
            return [
                .init(label: "Review this draft", prompt: "Give me honest feedback on this draft — what's working, what's weak?"),
                .init(label: "Tighten the opening", prompt: "Tighten the opening — keep my voice, cut the throat-clearing."),
                .init(label: "Search my brain", prompt: "What have I saved about ")
            ]
        case .structured:
            return [
                .init(label: "Review this draft", prompt: "Give me honest feedback on this draft — what's working, what's weak?"),
                .init(label: "Suggest hooks", prompt: "Suggest three sharper hooks for this, grounded in my swipes."),
                .init(label: "What's missing?", prompt: "What's missing from this before it's ready to ship?")
            ]
        case .canvas:
            return [
                .init(label: "Organize my workspace", prompt: "Organize my workspace — group everything on this thinkspace into clusters that make sense, with names and intents."),
                .init(label: "How would you organize this?", prompt: "Look at everything on this thinkspace — how would you organize it, and why?"),
                .init(label: "Find the through-line", prompt: "What connects the blocks on this canvas? Name the through-line.")
            ]
        case nil:
            return [
                .init(label: "Review this draft", prompt: "Give me honest feedback on this draft — what's working, what's weak?"),
                .init(label: "Search my brain", prompt: "What have I saved about "),
                .init(label: "Synthesize", prompt: "/Synthesize ")
            ]
        }
    }

    /// The empty state shows a curated shelf, not the whole registry.
    static let maxSkillCards = 5

    /// Surface-aware shelf: a thinkspace leads with canvas skills and hides
    /// text-editing ones; text surfaces hide canvas skills. Affinity is read
    /// from `requiredContext` — `.canvasState` marks a canvas skill.
    static func shelfSkills(
        for kind: CosmoEditableSurfaceKind?,
        from skills: [CosmoInlineSkillDefinition]
    ) -> [CosmoInlineSkillDefinition] {
        switch kind {
        case .canvas:
            let canvasSkills = skills.filter { $0.requiredContext.contains(.canvasState) }
            let universal = skills.filter {
                !$0.requiredContext.contains(.canvasState) && !$0.requiredContext.contains(.activeSurface)
            }
            return canvasSkills + universal
        default:
            return skills.filter { !$0.requiredContext.contains(.canvasState) }
        }
    }
}

// MARK: - Empty state view

struct CosmoInlineAssistantPaneEmptyState: View {
    @ObservedObject var store: CosmoInlineAssistantStore

    /// Loaded once on appear — registry reads hit GRDB, and the empty state
    /// re-evaluates on every composer keystroke.
    @State private var shelfSkills: [CosmoInlineSkillDefinition] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            heading
            skillShelf
            starterRow
        }
        .frame(maxWidth: 460, alignment: .leading)
        .onAppear { reloadShelf() }
        .onChange(of: store.activeSurfaceKind) { _, _ in reloadShelf() }
        .accessibilityElement(children: .contain)
    }

    /// The shelf follows the scope: a thinkspace shows canvas skills, a
    /// document shows writing skills.
    private func reloadShelf() {
        shelfSkills = Array(
            CosmoInlineAssistantPaneEmptyStatePolicy.shelfSkills(
                for: store.activeSurfaceKind,
                from: CosmoInlineSkillRegistry().enabledSkills
            )
            .prefix(CosmoInlineAssistantPaneEmptyStatePolicy.maxSkillCards)
        )
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Image(systemName: "sparkle")
                .font(DS.title2.weight(.semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 36, height: 36)
                .background(DS.accentSoft, in: Circle())
                .accessibilityHidden(true)

            // The pane names its scope in ONE voice — the same switcher pill
            // the header wears (clickable here too: "nothing in focus" is
            // exactly when you'd reach for the list of open documents).
            CosmoScopeSwitcherPill(store: store)

            VStack(alignment: .leading, spacing: DS.space4) {
                if isCanvasScope {
                    Text("This is a thinkspace — I can see every block and cluster on it.")
                    Text("Ask how to organize it, or just say \"organize my workspace\".")
                    Text("Canvas changes stage as a reviewable plan — nothing moves until you approve.")
                } else {
                    Text("Select a sentence and tell me what to do with it — \"shorten this\" just works.")
                    Text("Edits stage as reviewable diffs in place; formatting too (\"bold the headers\").")
                    Text("Answers cite your documents as pills you can open.")
                }
            }
            .font(DS.subheadline)
            .italic()
            .foregroundStyle(DS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isCanvasScope: Bool {
        store.activeSurfaceKind == .canvas
    }

    private var skillShelf: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text("Skills")
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .textCase(.uppercase)
                .kerning(0.4)

            ForEach(Array(shelfSkills.enumerated()), id: \.element.id) { index, skill in
                CosmoInlineAssistantSkillCard(skill: skill, appearIndex: index) {
                    store.composerText = "/\(skill.name) "
                }
            }
        }
    }

    private var starterRow: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text("Or start with")
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .textCase(.uppercase)
                .kerning(0.4)

            HStack(spacing: DS.space6) {
                ForEach(
                    CosmoInlineAssistantPaneEmptyStatePolicy.starters(for: store.activeSurfaceKind),
                    id: \.label
                ) { starter in
                    CosmoInlineAssistantStarterChip(label: starter.label) {
                        store.composerText = starter.prompt
                    }
                }
            }
        }
    }
}

/// One enabled skill as a quiet, clickable row-card: icon in a route-tinted
/// well, name + summary, slash hint on hover. Click stages the slash command.
private struct CosmoInlineAssistantSkillCard: View {
    let skill: CosmoInlineSkillDefinition
    let appearIndex: Int
    let action: () -> Void

    @State private var isHovered = false
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var routeTint: Color {
        skill.route == .action ? DS.green : DS.info
    }

    var body: some View {
        card
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 6)
            .onAppear {
                guard !reduceMotion else {
                    hasAppeared = true
                    return
                }
                guard !hasAppeared else { return }
                withAnimation(ProMotionSprings.cascade(index: min(appearIndex, 8))) {
                    hasAppeared = true
                }
            }
    }

    private var card: some View {
        Button(action: action) {
            HStack(spacing: DS.space8) {
                Image(systemName: skill.icon)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(routeTint)
                    .frame(width: 28, height: 28)
                    .background(routeTint.opacity(0.12), in: .rect(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(skill.name)
                        .font(DS.callout.weight(.semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                    Text(skill.summary)
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text("/\(skill.name)")
                    .font(DS.caption2.weight(.medium))
                    .foregroundStyle(DS.textMuted)
                    .opacity(isHovered ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.space8)
            .frame(height: 44)
            .background(isHovered ? AnyShapeStyle(DS.surfaceHover) : AnyShapeStyle(Color.clear), in: .rect(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cosmoClickCursor()
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Start \(skill.name): \(skill.summary)")
        .accessibilityLabel("Use skill \(skill.name): \(skill.summary)")
    }
}

/// Starter prompt chip — capsule, accent on hover.
struct CosmoInlineAssistantStarterChip: View {
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(isHovered ? DS.accent : DS.textSecondary)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space6)
                .background(isHovered ? AnyShapeStyle(DS.accentSoft) : AnyShapeStyle(DS.surface), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(isHovered ? DS.accent.opacity(0.3) : DS.borderSubtle, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .cosmoClickCursor()
        .onHover { hovering in
            withAnimation(ProMotionSprings.snappy) { isHovered = hovering }
        }
        .help("Start with this prompt")
        .accessibilityLabel("Use starter prompt: \(label)")
    }
}
