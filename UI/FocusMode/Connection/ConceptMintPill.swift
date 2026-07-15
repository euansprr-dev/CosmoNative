// CosmoOS/UI/FocusMode/Connection/ConceptMintPill.swift
// Select → mint → hyperlink: highlight a phrase while developing a concept
// and a small pill offers ONE verb — "New concept" when the phrase has no
// page, "Add link" when it does. Minting births a wired stub beside the
// origin on the canvas; the mention lights up everywhere via the existing
// render-time linkification. The pill follows the Study reader's selection-
// pill grammar (clamped, flips below, one verb) and never fights ordinary
// copy-selection: it only appears for name-shaped selections.

import SwiftUI

// MARK: - Name policy (pure, unit-tested)

enum ConceptMintPolicy {
    /// A selection is concept-name-shaped: short, few words, no sentence
    /// punctuation. Everything else is ordinary copying — no pill.
    static func isPlausibleConceptName(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, text.count <= 60 else { return false }
        let words = text.split(whereSeparator: \.isWhitespace)
        guard (1...6).contains(words.count) else { return false }
        guard text.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?;:,\n")) == nil else { return false }
        return true
    }
}

// MARK: - Selection report (what selectable hosts publish)

/// One text selection surfaced to the mint pill. Item-text hosts carry the
/// full item as `contextSnippet` so the minted page is born a wired stub;
/// conversation hosts leave it nil (the sentence may be Cosmo's words —
/// organize-don't-author).
struct ConceptMintSelectionReport: Equatable {
    var text: String
    /// Window-global rect (SelectionAnchorSpace space).
    var anchor: CGRect
    var contextSnippet: String?
    var originSection: ConnectionSectionType?
}

extension EnvironmentValues {
    /// Selectable descendants report selections here (nil = collapsed). The
    /// `conceptMintPillHost` modifier installs it; hosts without it stay inert.
    @Entry var conceptMintReporter: ((ConceptMintSelectionReport?) -> Void)? = nil
}

// MARK: - Resolution (which verb, against which page)

@MainActor
enum ConceptMintResolver {
    struct Resolution {
        let origin: Atom
        let provider: ConnectionContextProvider
        /// Same-key sibling page, when one exists → the verb is "Add link".
        let existing: ConnectionPromotionService.ConnectionLinkRef?
    }

    /// The working concept comes from the active editable surface — the same
    /// binding the collaborator itself uses, so the pill works identically in
    /// the Connection focus mode, the pane, and the Study's Concept Desk.
    static func resolve(selection: String) async -> Resolution? {
        guard let provider = CosmoEditableSurfaceRegistry.shared.activeSurface as? ConnectionContextProvider else {
            return nil
        }
        let surfaceID = provider.surfaceID
        guard surfaceID.hasPrefix("connection:") else { return nil }
        let originUUID = String(surfaceID.dropFirst("connection:".count))
        guard let origin = try? await AtomRepository.shared.fetch(uuid: originUUID) else { return nil }

        let key = ConceptResolver.conceptKey(selection)
        guard !key.isEmpty, key != ConceptResolver.conceptKey(origin.title ?? "") else { return nil }

        var existing: ConnectionPromotionService.ConnectionLinkRef?
        if let deepDive = await CosmoInlineInquiryQuestionResolver.resolveDeepDive(for: origin),
           let siblings = try? await InquiryRepository.shared.fetchConnections(forDeepDive: deepDive),
           let match = siblings.first(where: { ConceptResolver.conceptKey($0.title ?? "") == key }) {
            existing = .init(uuid: match.uuid, title: match.title ?? selection)
        }
        return Resolution(origin: origin, provider: provider, existing: existing)
    }
}

// MARK: - Host modifier

extension View {
    /// Installs the select→mint pill over a container whose descendants
    /// report selections via `\.conceptMintReporter`.
    func conceptMintPillHost() -> some View {
        modifier(ConceptMintPillHost())
    }
}

private struct ConceptMintPillHost: ViewModifier {
    @State private var report: ConceptMintSelectionReport?
    @State private var resolution: ConceptMintResolver.Resolution?
    @State private var phase: ConceptMintPill.Phase = .idle

    func body(content: Content) -> some View {
        content
            .environment(\.conceptMintReporter) { newReport in
                if let newReport, ConceptMintPolicy.isPlausibleConceptName(newReport.text) {
                    report = newReport
                } else {
                    report = nil
                }
                resolution = nil
                phase = .idle
            }
            .overlay { pillOverlay }
            .task(id: report?.text) {
                guard let report else { return }
                // Small settle so a drag-in-progress doesn't spam resolution.
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                resolution = await ConceptMintResolver.resolve(selection: report.text)
            }
    }

    @ViewBuilder
    private var pillOverlay: some View {
        if let report, let resolution {
            GeometryReader { geo in
                let host = geo.frame(in: .global)
                ConceptMintPill(
                    anchor: report.anchor.offsetBy(dx: -host.minX, dy: -host.minY),
                    container: geo.size,
                    label: resolution.existing.map { "Add link: \($0.title)" }
                        ?? "New concept: \(report.text.trimmingCharacters(in: .whitespacesAndNewlines))",
                    isCreate: resolution.existing == nil,
                    phase: phase
                ) {
                    Task { await perform(report: report, resolution: resolution) }
                }
            }
            .allowsHitTesting(true)
        }
    }

    private func perform(report: ConceptMintSelectionReport, resolution: ConceptMintResolver.Resolution) async {
        guard phase == .idle else { return }
        phase = .working
        let name = report.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = resolution.existing {
            resolution.provider.addReferenceRow(uuid: existing.uuid, title: existing.title)
            NotificationCenter.default.post(
                name: CosmoNotification.Connection.referencesChanged,
                object: nil,
                userInfo: ["originUUID": resolution.origin.uuid, "connectionUUID": existing.uuid]
            )
        } else if let minted = await ConnectionPromotionService.shared.mintConcept(
            named: name,
            fromOrigin: resolution.origin,
            contextSnippet: report.contextSnippet,
            originSection: report.originSection
        ) {
            resolution.provider.addReferenceRow(uuid: minted.connectionUUID, title: name)
        } else {
            phase = .idle
            return
        }
        phase = .done
        try? await Task.sleep(for: .milliseconds(900))
        self.report = nil
        self.resolution = nil
        phase = .idle
    }
}

// MARK: - The pill

/// The reader pill's positioning grammar (clamp horizontally, sit above the
/// selection, flip below without headroom), one verb, three beats:
/// idle → working → ✓ done.
struct ConceptMintPill: View {
    enum Phase: Equatable { case idle, working, done }

    let anchor: CGRect
    let container: CGSize
    let label: String
    let isCreate: Bool
    let phase: Phase
    let onTap: () -> Void

    @State private var pillSize: CGSize = .zero
    @State private var isHovered = false

    private var effectivePillSize: CGSize {
        pillSize == .zero ? CGSize(width: 160, height: 36) : pillSize
    }

    private var resolvedPosition: CGPoint {
        let pad: CGFloat = CosmoMenuChrome.shadowClearance
        let gap: CGFloat = 10
        let size = effectivePillSize
        let half = size.width / 2

        let x: CGFloat
        if container.width < size.width + pad * 2 {
            x = container.width / 2
        } else {
            x = min(max(anchor.midX, half + pad), container.width - half - pad)
        }
        let fitsAbove = anchor.minY - size.height - gap >= 0
        let y = fitsAbove
            ? anchor.minY - size.height / 2 - gap
            : min(anchor.maxY + size.height / 2 + gap, container.height - size.height / 2 - pad)
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.space6) {
                pillIcon
                Text(phase == .done ? (isCreate ? "Created" : "Linked") : label)
                    .font(DS.caption.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(phase == .done ? DS.green : (isHovered ? CosmoMentionColors.connection : DS.textSecondary))
            .padding(.horizontal, DS.space12)
            .frame(height: 36)
            .frame(maxWidth: 320)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(phase != .idle)
        .cosmoMenuChrome(cornerRadius: 18)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newValue in
            pillSize = newValue
        }
        .position(resolvedPosition)
        .animation(ProMotionSprings.snappy, value: anchor)
        .animation(ProMotionSprings.gentle, value: phase)
        .help(isCreate
              ? "Create this concept, add it to References, and hyperlink its mentions"
              : "Add this concept to References")
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var pillIcon: some View {
        switch phase {
        case .idle:
            Image(systemName: isCreate ? "plus.diamond" : "point.3.connected.trianglepath.dotted")
                .font(DS.caption2.weight(.semibold))
                .accessibilityHidden(true)
        case .working:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
        case .done:
            Image(systemName: "checkmark")
                .font(DS.caption2.weight(.bold))
                .accessibilityHidden(true)
        }
    }
}
