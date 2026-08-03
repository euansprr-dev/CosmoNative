// CosmoOS/UI/FocusMode/Connection/ConnectionEditableSurface.swift
// Connection focus mode as an inline-assistant editable surface.
// Serializes the 11 sections into a canonical text snapshot the assistant can
// stage reviewed diffs against, and maps accepted operations back onto
// ConnectionFocusModeState through the view model.
// June 2026 — Concept skill foundation.

import SwiftUI

// MARK: - Serialized surface model

/// The canonical text form of a Connection plus a line map that ties every
/// character range back to the section/item it came from. Both the snapshot
/// and `apply(operation:)` re-derive this from live state so locate and apply
/// can never disagree about what a range means.
struct ConnectionSurfaceModel {
    enum LineKind: Equatable {
        case title
        case meta
        case blank
        case header(ConnectionSectionType)
        case item(ConnectionSectionType, UUID)
        case itemContinuation(ConnectionSectionType, UUID)
        case empty(ConnectionSectionType)
    }

    struct Line {
        let kind: LineKind
        /// Range of the line's content within `text`, excluding the trailing newline.
        let range: Range<String.Index>
    }

    let text: String
    let lines: [Line]
    let anchors: [CosmoEditableAnchor]

    /// The line an insertion point belongs to: the last line that starts at or
    /// before `index`. An index sitting on the newline between two lines is
    /// attributed to the line it terminates.
    func line(at index: String.Index) -> Line? {
        lines.last { $0.range.lowerBound <= index }
    }

    /// All lines whose content overlaps `range`. For an empty range this is
    /// the single line containing the insertion point.
    func lines(intersecting range: Range<String.Index>) -> [Line] {
        if range.isEmpty {
            return line(at: range.lowerBound).map { [$0] } ?? []
        }
        return lines.filter { line in
            line.range.lowerBound < range.upperBound && range.lowerBound < line.range.upperBound
        }
    }
}

// MARK: - Serializer

enum ConnectionSurfaceSerializer {
    static let emptySectionMarker = "(empty)"

    static func headerLine(for type: ConnectionSectionType) -> String {
        "## \(type.displayName)"
    }

    static func anchorID(for type: ConnectionSectionType) -> String {
        "section:\(type.rawValue)"
    }

    /// Builds the canonical text + line map for the given connection state.
    /// Sections render in `sortOrder` with one blank line between them so the
    /// woven diff stays readable; multi-line items indent continuation lines
    /// by two spaces and are re-joined on parse.
    static func serialize(
        title: String,
        conceptType: ConceptFrameworkType,
        sections: [ConnectionSection],
        media: [ConnectionMediaItem] = [],
        mediaAtoms: [String: Atom] = [:]
    ) -> ConnectionSurfaceModel {
        var rendered: [(text: String, kind: ConnectionSurfaceModel.LineKind)] = []
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        rendered.append(("# \(trimmedTitle.isEmpty ? "Untitled Concept" : trimmedTitle)", .title))
        rendered.append(("Type: \(conceptType.displayName)", .meta))

        let ordered = sections.sorted { $0.type.sortOrder < $1.type.sortOrder }
        for section in ordered {
            rendered.append(("", .blank))
            rendered.append((headerLine(for: section.type), .header(section.type)))
            if section.items.isEmpty {
                rendered.append((emptySectionMarker, .empty(section.type)))
            } else {
                for item in section.items {
                    let pieces = item.resolvedPlainText
                        .replacingOccurrences(of: "\r\n", with: "\n")
                        .components(separatedBy: "\n")
                    for (index, piece) in pieces.enumerated() {
                        if index == 0 {
                            rendered.append(("- \(piece)", .item(section.type, item.id)))
                        } else {
                            rendered.append(("  \(piece)", .itemContinuation(section.type, item.id)))
                        }
                    }
                    // A handled objection's response rides along as a
                    // READ-ONLY meta line (`↳` is never a bullet marker, so
                    // parse/apply paths can't stage or edit it). The model
                    // sees which objections are resolved and with what.
                    if item.isHandled, let handling = item.handling {
                        rendered.append((handlingLine(handling, sections: sections), .meta))
                    }
                }
            }
        }

        // READ-ONLY media block: the skill SEES the board's visuals but can
        // never insert into them — lines render as `.meta` (no anchor, no
        // section), and the `▸` glyph keeps parseItems from ever treating
        // one as a bullet. Media enters only through the attach flows.
        if !media.isEmpty {
            rendered.append(("", .blank))
            rendered.append(("## Gallery (read-only media on this board)", .meta))
            for item in media.sorted(by: { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }) {
                rendered.append((mediaLine(for: item, atom: item.atomUUID.flatMap { mediaAtoms[$0] }), .meta))
            }
        }

        let text = rendered.map(\.text).joined(separator: "\n")
        var lines: [ConnectionSurfaceModel.Line] = []
        var cursor = text.startIndex
        for (offset, entry) in rendered.enumerated() {
            let end = text.index(cursor, offsetBy: entry.text.count)
            lines.append(ConnectionSurfaceModel.Line(kind: entry.kind, range: cursor..<end))
            if offset < rendered.count - 1 {
                cursor = text.index(after: end) // skip the joining newline
            }
        }

        var anchors: [CosmoEditableAnchor] = []
        for line in lines {
            switch line.kind {
            case .title:
                anchors.append(anchor(id: "title", label: "Title", range: line.range, in: text))
            case .header(let type):
                anchors.append(anchor(id: anchorID(for: type), label: type.displayName, range: line.range, in: text))
            default:
                break
            }
        }

        return ConnectionSurfaceModel(text: text, lines: lines, anchors: anchors)
    }

    /// The handled-objection meta line, e.g.
    /// `  ↳ handled: We measure it weekly (answered by Examples: "The IKEA study…")`
    static func handlingLine(_ handling: ObjectionHandling, sections: [ConnectionSection]) -> String {
        var line = "  ↳ handled"
        let text = handling.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            line += ": \(text.replacingOccurrences(of: "\n", with: " "))"
        }
        let resolvedLinks: [String] = handling.linkedRefs.compactMap { ref in
            guard let sectionType = ref.section else { return nil }
            let linked = sections.first { $0.type == sectionType }?
                .items.first { $0.id == ref.itemID }
            guard let linked else { return "\(sectionType.displayName) (missing entry)" }
            let snippet = String(linked.resolvedPlainText.prefix(48))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(sectionType.displayName): \"\(snippet)\""
        }
        if !resolvedLinks.isEmpty {
            line += " (answered by \(resolvedLinks.joined(separator: "; ")))"
        }
        return line
    }

    /// One legible line per media ref, e.g.
    /// `▸ [video] "Hormozi hook breakdown" (Instagram Reel · 0:42 · shown on Examples) — caption`
    static func mediaLine(for item: ConnectionMediaItem, atom: Atom?) -> String {
        var pieces: [String] = []
        if let sourceType = atom?.richContent?.sourceType {
            pieces.append(sourceType.displayName.replacingOccurrences(of: "_", with: " "))
        } else if item.atomUUID == nil {
            pieces.append(item.ownsVideoAsset ? "video file" : "image file")
        }
        if let moment = item.timestampSeconds, moment > 0 {
            let total = Int(moment.rounded())
            pieces.append(String(format: "moment %d:%02d", total / 60, total % 60))
        }
        if let anchor = item.anchorSection {
            pieces.append("shown on \(anchor.displayName)")
        }
        if item.isCover {
            pieces.append("cover")
        }
        let title = atom?.title ?? item.assetTitle ?? "Untitled media"
        var line = "▸ [\(item.kind.rawValue)] \"\(title)\""
        if !pieces.isEmpty {
            line += " (\(pieces.joined(separator: " · ")))"
        }
        if let caption = item.caption, !caption.isEmpty {
            line += ", caption: \(caption)"
        }
        return line
    }

    private static func anchor(
        id: String,
        label: String,
        range: Range<String.Index>,
        in text: String
    ) -> CosmoEditableAnchor {
        let start = range.lowerBound.utf16Offset(in: text)
        let end = range.upperBound.utf16Offset(in: text)
        return CosmoEditableAnchor(id: id, label: label, utf16Start: start, utf16Length: end - start)
    }

    /// Parses proposed text into item strings for `targetSection`.
    /// Bullet markers (-, •, *) start a new item; unmarked lines continue the
    /// current item; a leading header for the target section is dropped.
    /// Returns nil when the text names a *different* section header — the
    /// model must stage one operation per section.
    static func parseItems(
        from proposedText: String,
        targetSection: ConnectionSectionType
    ) -> [String]? {
        var items: [String] = []
        var current: String?

        for rawLine in proposedText.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line == emptySectionMarker { continue }
            if line.hasPrefix("#") {
                let headerName = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if headerName.caseInsensitiveCompare(targetSection.displayName) == .orderedSame {
                    continue
                }
                let namesOtherSection = ConnectionSectionType.allCases.contains {
                    headerName.caseInsensitiveCompare($0.displayName) == .orderedSame
                }
                if namesOtherSection { return nil }
                // A heading that isn't a section name is just item content.
            }
            if let marker = ["- ", "• ", "* "].first(where: { line.hasPrefix($0) }) {
                if let finished = current?.trimmingCharacters(in: .whitespacesAndNewlines), !finished.isEmpty {
                    items.append(finished)
                }
                current = String(line.dropFirst(marker.count))
            } else if current != nil {
                current! += "\n\(line)"
            } else {
                current = line
            }
        }
        if let finished = current?.trimmingCharacters(in: .whitespacesAndNewlines), !finished.isEmpty {
            items.append(finished)
        }
        // AI-staged bullets must never carry em dashes — the user wants commas /
        // periods / semicolons instead. This is the choke point for every
        // propose_workspace_edit insertion (preview AND apply); manual quick-add
        // typing bypasses parseItems, so the user's own dashes are untouched.
        return items.map(removeEmDashes)
    }

    /// Replaces em dashes (and the spaced en dash used as one) with a comma, so
    /// AI-authored concept text reads in plain punctuation. Leaves tight en
    /// dashes (numeric ranges like "3–5") alone.
    static func removeEmDashes(_ text: String) -> String {
        text
            .replacingOccurrences(of: " — ", with: ", ")
            .replacingOccurrences(of: " – ", with: ", ")
            .replacingOccurrences(of: "—", with: ", ")
    }

    // MARK: - Pending-insert resolution (read-only twin of apply)

    /// Resolves a staged insertion operation to the section it targets and the
    /// bullet strings it would add — the read-only twin of
    /// `ConnectionContextProvider.applyInsertion`, used to render pending
    /// inserts inside the board/outline section (ghost rows) instead of the
    /// full-screen text diff. Uses the exact same anchor logic as apply, so the
    /// preview and the eventual accept can never disagree about the target.
    /// Returns nil for operations that don't cleanly target one section
    /// (replacements, format marks, multi-section text, unlocatable anchors).
    static func pendingInsert(
        for operation: CosmoAssistantProposalOperation,
        in model: ConnectionSurfaceModel
    ) -> (section: ConnectionSectionType, bullets: [String], revisesText: String?, afterText: String?)? {
        guard let proposed = operation.proposedText,
              !proposed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        switch operation.kind {
        case .textInsertion:
            guard let type = targetSection(for: operation, in: model),
                  let bullets = parseItems(from: proposed, targetSection: type),
                  !bullets.isEmpty else {
                return nil
            }
            // Ghost rows preview mention tokens as their "@Title" projection —
            // the raw @[Title](connection:<uuid>) form is an apply-time detail.
            return (
                type,
                bullets.map { ConceptMentionToken.displayText($0) },
                nil,
                anchorBulletText(for: operation, in: model)
            )
        case .textReplacement, .structuredFieldReplacement:
            // A revision of existing bullet line(s): locate the original the
            // same way the apply path will, so the ghost row and the eventual
            // replaceSectionLines can never disagree. Title/type edits keep
            // their Manuscript-diff review — only bullet revisions render as
            // section ghost rows.
            let original = operation.originalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !original.isEmpty,
                  let range = CosmoInlineDiffLocator.range(of: operation.originalText ?? "", in: model.text) else {
                return nil
            }
            let touched = model.lines(intersecting: range).filter {
                if case .blank = $0.kind { return false }
                return true
            }
            var section: ConnectionSectionType?
            for line in touched {
                switch line.kind {
                case .item(let type, _), .itemContinuation(let type, _):
                    if section == nil { section = type }
                    guard section == type else { return nil }
                default:
                    return nil
                }
            }
            guard let section,
                  let bullets = parseItems(from: proposed, targetSection: section),
                  !bullets.isEmpty else {
                return nil
            }
            return (
                section,
                bullets.map { ConceptMentionToken.displayText($0) },
                ConceptMentionToken.displayText(strippingBulletPrefix(original)),
                nil
            )
        default:
            return nil
        }
    }

    /// The bullet an item-anchored insertion follows — display copy for the
    /// ghost row's placement caption. Header/empty anchors return nil (the
    /// bullets land at the top of the section; no caption needed).
    private static func anchorBulletText(
        for operation: CosmoAssistantProposalOperation,
        in model: ConnectionSurfaceModel
    ) -> String? {
        let anchorText = operation.originalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !anchorText.isEmpty,
              let range = CosmoInlineDiffLocator.range(of: anchorText, in: model.text),
              let line = model.line(at: range.upperBound) else {
            return nil
        }
        switch line.kind {
        case .item, .itemContinuation:
            return ConceptMentionToken.displayText(strippingBulletPrefix(String(model.text[line.range])))
        default:
            return nil
        }
    }

    private static func strippingBulletPrefix(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("- ") else { return trimmed }
        return String(trimmed.dropFirst(2))
    }

    /// The section an operation anchors to: prefer the verbatim `originalText`
    /// (matched against the live surface), then the structured
    /// `anchorID` ("section:<rawValue>"). Mirrors `locateAnchorLine`.
    static func targetSection(
        for operation: CosmoAssistantProposalOperation,
        in model: ConnectionSurfaceModel
    ) -> ConnectionSectionType? {
        let anchorText = operation.originalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !anchorText.isEmpty,
           let range = CosmoInlineDiffLocator.range(of: anchorText, in: model.text),
           let line = model.line(at: range.upperBound) {
            switch line.kind {
            case .header(let type), .empty(let type),
                 .item(let type, _), .itemContinuation(let type, _):
                return type
            case .title, .meta, .blank:
                return nil
            }
        }
        if let anchorID = operation.anchorID, anchorID.hasPrefix("section:") {
            return ConnectionSectionType(rawValue: String(anchorID.dropFirst("section:".count)))
        }
        return nil
    }

    // MARK: - Stage-time gate (guard-twin of apply)

    /// Model-facing guidance for edits that touch a handled objection's
    /// read-only `↳ handled:` line — shared verbatim by the stage-time gate
    /// and the apply path so the two can never explain the refusal
    /// differently.
    static let handledLineGuidance = "the '↳ handled:' line under an objection is read-only. To add or change how an objection is handled, call handle_objection quoting the objection's bullet text verbatim (a still-staged objection must be accepted onto the board first). To insert new bullets after a handled objection, anchor the objection's own bullet line, never its handling line."

    /// Issues for operations this surface's apply would deterministically
    /// refuse (read-only lines, unlocatable anchors, cross-section spans) —
    /// the guard-twin of `ConnectionContextProvider.applyInsertion` /
    /// `applyReplacement`; change both together. The executor runs this while
    /// the model is still in the tool loop, so a doomed operation bounces
    /// back as a structured error instead of entering pending state, where
    /// the receipt banner would count it while the board ghost-renders it
    /// nowhere. Operations that pass may still skip ghost rows (title/type
    /// edits review in the Manuscript diff) — legitimate pending state,
    /// never bounced here.
    static func stagingIssues(
        operations: [CosmoAssistantProposalOperation],
        in model: ConnectionSurfaceModel
    ) -> [String] {
        var issues: [String] = []
        for (index, operation) in operations.enumerated() {
            if let issue = stagingIssue(for: operation, in: model) {
                issues.append("Operation \(index + 1): \(issue)")
            }
        }
        return issues
    }

    private static func stagingIssue(
        for operation: CosmoAssistantProposalOperation,
        in model: ConnectionSurfaceModel
    ) -> String? {
        switch operation.kind {
        case .textInsertion:
            return insertionStagingIssue(for: operation, in: model)
        case .textReplacement, .structuredFieldReplacement:
            return replacementStagingIssue(for: operation, in: model)
        case .formatMarks, .canvasPlan:
            // Apply handles these honestly (skip / conflict) and they never
            // count as board captures — not this gate's concern.
            return nil
        }
    }

    private static func insertionStagingIssue(
        for operation: CosmoAssistantProposalOperation,
        in model: ConnectionSurfaceModel
    ) -> String? {
        let proposed = operation.proposedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !proposed.isEmpty else { return "proposedText is empty — nothing to insert." }

        // Mirror locateAnchorLine: verbatim originalText first, then the
        // structured section anchorID.
        let anchorText = operation.originalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var anchorLine: ConnectionSurfaceModel.Line?
        if !anchorText.isEmpty,
           let range = CosmoInlineDiffLocator.range(of: operation.originalText ?? "", in: model.text) {
            anchorLine = model.line(at: range.upperBound)
        } else if let anchorID = operation.anchorID, anchorID.hasPrefix("section:"),
                  let type = ConnectionSectionType(rawValue: String(anchorID.dropFirst("section:".count))) {
            anchorLine = model.lines.first {
                if case .header(let lineType) = $0.kind { return lineType == type }
                return false
            }
        }
        guard let anchorLine else {
            return "the insertion anchor matches nothing on the board. Set originalText to a section header or an existing bullet copied verbatim, or pass anchorID \"section:<sectionID>\"."
        }
        switch anchorLine.kind {
        case .header(let type), .empty(let type), .item(let type, _), .itemContinuation(let type, _):
            guard let items = parseItems(from: proposed, targetSection: type) else {
                return "the proposed text names another section — stage one operation per section."
            }
            guard !items.isEmpty else { return "no bullet content found in proposedText." }
            return nil
        case .title, .meta, .blank:
            if isHandledObjectionLine(anchorLine, in: model) { return handledLineGuidance }
            return "the anchor lands on a read-only line — insertions must anchor a section header or a bullet line."
        }
    }

    private static func replacementStagingIssue(
        for operation: CosmoAssistantProposalOperation,
        in model: ConnectionSurfaceModel
    ) -> String? {
        let original = operation.originalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !original.isEmpty else {
            return "replacements need originalText copied verbatim from the board."
        }
        guard let range = CosmoInlineDiffLocator.range(of: operation.originalText ?? "", in: model.text) else {
            return "originalText matches nothing on the board — copy the target line(s) verbatim from the surface text."
        }
        let touched = model.lines(intersecting: range).filter {
            if case .blank = $0.kind { return false }
            return true
        }
        guard !touched.isEmpty else { return "the located range covers no editable line." }

        if touched.allSatisfy({ if case .title = $0.kind { return true }; return false }) {
            return nil // Title edit — reviewed in the Manuscript diff.
        }
        if touched.allSatisfy({ if case .meta = $0.kind { return true }; return false }) {
            if touched.allSatisfy({ isConceptTypeLine($0, in: model) }) { return nil } // Type edit.
            if touched.contains(where: { isHandledObjectionLine($0, in: model) }) { return handledLineGuidance }
            return "that line is read-only board metadata and can't be edited."
        }

        var sectionTypes = Set<ConnectionSectionType>()
        var coversHeader = false
        for line in touched {
            switch line.kind {
            case .header(let type):
                coversHeader = true
                sectionTypes.insert(type)
            case .empty(let type), .item(let type, _), .itemContinuation(let type, _):
                sectionTypes.insert(type)
            case .title, .meta, .blank:
                if isHandledObjectionLine(line, in: model) { return handledLineGuidance }
                return "edits can't span the title or metadata lines together with section content — quote only the bullet line(s) being rewritten."
            }
        }
        guard sectionTypes.count == 1, let type = sectionTypes.first else {
            return "the quoted lines span multiple sections — stage one operation per section."
        }
        guard let items = parseItems(from: operation.proposedText ?? "", targetSection: type) else {
            return "the proposed text names another section — stage one operation per section."
        }
        if coversHeader, items.isEmpty || !(operation.proposedText ?? "").localizedCaseInsensitiveContains(type.displayName) {
            return "section headers can't be renamed or removed — quote only the bullets, not the '## \(type.displayName)' header line."
        }
        return nil
    }

    /// True for a handled objection's `↳ handled:` rebuttal line.
    static func isHandledObjectionLine(
        _ line: ConnectionSurfaceModel.Line,
        in model: ConnectionSurfaceModel
    ) -> Bool {
        String(model.text[line.range]).trimmingCharacters(in: .whitespaces).hasPrefix("↳ handled")
    }

    /// True for the one `.meta` line that IS editable: the `Type:` line.
    static func isConceptTypeLine(
        _ line: ConnectionSurfaceModel.Line,
        in model: ConnectionSurfaceModel
    ) -> Bool {
        String(model.text[line.range]).hasPrefix("Type:")
    }

    // MARK: - Render-time placement (the receipt's honesty)

    /// Where one still-reviewable operation renders for review against the
    /// given live model — the ONE verdict behind the board's ghost rows, the
    /// receipt's counts, and the orphan list, so no consumer can disagree
    /// with another (or with apply, whose refusals `stagingIssue` mirrors).
    private enum ResolvedCapture {
        case section(ConnectionPendingInsert)
        case manuscript
        case orphaned(ConnectionOrphanedCapture)
    }

    private static func resolveCapture(
        _ operation: CosmoAssistantProposalOperation,
        proposalID: UUID,
        in model: ConnectionSurfaceModel
    ) -> ResolvedCapture {
        if let resolved = pendingInsert(for: operation, in: model) {
            return .section(ConnectionPendingInsert(
                proposalID: proposalID,
                operationID: operation.id,
                section: resolved.section,
                bullets: resolved.bullets,
                revisesText: resolved.revisesText,
                afterText: resolved.afterText
            ))
        }
        if stagingIssue(for: operation, in: model) != nil {
            return .orphaned(ConnectionOrphanedCapture(
                proposalID: proposalID,
                operationID: operation.id,
                summary: orphanSummary(for: operation)
            ))
        }
        return .manuscript
    }

    /// First line of the capture's content, mention tokens projected to their
    /// "@Title" form — a dismiss must be an informed one, so the orphan row
    /// shows WHAT would be let go.
    private static func orphanSummary(for operation: CosmoAssistantProposalOperation) -> String {
        let firstLine = (operation.proposedText ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard !firstLine.isEmpty else { return operation.rationale }
        return ConceptMentionToken.displayText(strippingBulletPrefix(firstLine))
    }

    /// Classifies a proposal's still-reviewable operations for the pane
    /// receipt: how many ghost-render in sections, how many review in the
    /// Manuscript woven diff, and which resolve NOWHERE because the board
    /// changed under them after staging. Same resolution as `stagedInserts`.
    static func captureReceiptState(
        operations: [CosmoAssistantProposalOperation],
        proposalID: UUID,
        in model: ConnectionSurfaceModel
    ) -> ConnectionCaptureReceiptState {
        var state = ConnectionCaptureReceiptState()
        for operation in operations
        where operation.status == .pending || operation.status == .conflicted {
            switch resolveCapture(operation, proposalID: proposalID, in: model) {
            case .section: state.sectionCount += 1
            case .manuscript: state.manuscriptCount += 1
            case .orphaned(let capture): state.orphans.append(capture)
            }
        }
        return state
    }

    /// Shared by every host that renders a connection's staged edits (the
    /// Connection focus mode and the Study's Concept Desk): filters the store's
    /// proposals to this connection, resolves still-pending operations into
    /// per-section ghost rows against the LIVE serialized surface — so
    /// accepting one and re-resolving the rest can never disagree with the
    /// apply path — and returns the last matching proposal for the
    /// Manuscript's full-screen diff. Operations that stopped resolving
    /// (the board changed under them) come back as `orphaned` so a host can
    /// settle them — they must never be silently dropped while the receipt
    /// still counts them.
    @MainActor
    static func stagedInserts(
        from proposals: [CosmoAssistantProposal],
        atomUUID: String,
        title: String,
        conceptType: ConceptFrameworkType,
        sections: [ConnectionSection]
    ) -> (
        manuscript: CosmoAssistantProposal?,
        bySection: [ConnectionSectionType: [ConnectionPendingInsert]],
        orphaned: [ConnectionOrphanedCapture]
    ) {
        let matching = proposals.filter { proposal in
            proposal.hasReviewableOperations && proposal.matches(
                surfaceID: "connection:\(atomUUID)",
                targetID: ConnectionContextProvider.targetID(for: atomUUID),
                activeAtomUUID: atomUUID
            )
        }
        let model = serialize(title: title, conceptType: conceptType, sections: sections)
        var grouped: [ConnectionSectionType: [ConnectionPendingInsert]] = [:]
        var orphaned: [ConnectionOrphanedCapture] = []
        for proposal in matching {
            for operation in proposal.operations
            where operation.status == .pending || operation.status == .conflicted {
                switch resolveCapture(operation, proposalID: proposal.id, in: model) {
                case .section(let insert):
                    grouped[insert.section, default: []].append(insert)
                case .orphaned(let capture):
                    orphaned.append(capture)
                case .manuscript:
                    break
                }
            }
        }
        return (matching.last, grouped, orphaned)
    }
}

// MARK: - Orphaned captures + receipt truth

/// A staged capture that no longer resolves ANYWHERE on the board — the user
/// edited or deleted the line its anchor quoted while it was still pending.
/// It renders in the pane receipt (content visible, individually dismissible)
/// instead of silently inflating the "captures waiting" count while the board
/// ghost-renders nothing.
struct ConnectionOrphanedCapture: Identifiable, Equatable {
    let proposalID: UUID
    let operationID: UUID
    /// First line of the capture's content, so dismissing is an informed act.
    let summary: String

    var id: UUID { operationID }
}

/// Render-time truth for one proposal's receipt, resolved against the live
/// board.
struct ConnectionCaptureReceiptState: Equatable {
    var sectionCount: Int = 0
    var manuscriptCount: Int = 0
    var orphans: [ConnectionOrphanedCapture] = []

    /// Operations that still render somewhere reviewable.
    var placedCount: Int { sectionCount + manuscriptCount }
}

/// The concept receipt's wording, derived from where its operations actually
/// review right now — never from the raw pending count alone. Pure so tests
/// can pin every bucket's copy.
struct ConceptCaptureReceiptCopy: Equatable {
    var headline: String
    var subtitle: String?
    /// Caption above the orphan rows when placeable captures also exist
    /// (when nothing is placeable, the headline itself carries the news).
    var orphanNotice: String?
    var showsAcceptAll: Bool
    var showsDismissAll: Bool

    /// `state` is nil when the board surface isn't open to resolve against —
    /// the stage-time gate vouched for these once, so the historical
    /// review-in-sections copy is the honest default there.
    static func make(
        pendingCount: Int,
        resolvedCount: Int,
        state: ConnectionCaptureReceiptState?
    ) -> ConceptCaptureReceiptCopy {
        guard pendingCount > 0 else {
            return ConceptCaptureReceiptCopy(
                headline: resolvedCount > 0 ? "Added to your board" : "Nothing captured",
                subtitle: nil,
                orphanNotice: nil,
                showsAcceptAll: false,
                showsDismissAll: false
            )
        }
        guard let state else {
            return ConceptCaptureReceiptCopy(
                headline: waitingHeadline(pendingCount),
                subtitle: "Review each in its section, then ✓ or ✗ there.",
                orphanNotice: nil,
                showsAcceptAll: true,
                showsDismissAll: true
            )
        }
        let orphanCount = state.orphans.count
        if state.placedCount == 0, orphanCount > 0 {
            return ConceptCaptureReceiptCopy(
                headline: orphanCount == 1
                    ? "1 capture can't be placed"
                    : "\(orphanCount) captures can't be placed",
                subtitle: orphanCount == 1
                    ? "The board changed under it. Dismiss it, or ask me to restage."
                    : "The board changed under them. Dismiss them, or ask me to restage.",
                orphanNotice: nil,
                showsAcceptAll: false,
                showsDismissAll: true
            )
        }
        let subtitle: String
        if state.manuscriptCount == 0 {
            subtitle = "Review each in its section, then ✓ or ✗ there."
        } else if state.sectionCount == 0 {
            subtitle = "Review in the Manuscript view, then ✓ or ✗ there."
        } else {
            subtitle = "Review in the sections and the Manuscript, then ✓ or ✗ there."
        }
        return ConceptCaptureReceiptCopy(
            headline: waitingHeadline(state.placedCount),
            subtitle: subtitle,
            orphanNotice: orphanCount == 0 ? nil : orphanCount == 1
                ? "1 more can't be placed: the board changed under it."
                : "\(orphanCount) more can't be placed: the board changed under them.",
            showsAcceptAll: true,
            showsDismissAll: true
        )
    }

    private static func waitingHeadline(_ count: Int) -> String {
        count == 1 ? "1 capture waiting in your board" : "\(count) captures waiting in your board"
    }
}

// MARK: - Cosmo Context Provider + Editable Surface

@MainActor
final class ConnectionContextProvider: CosmoContextProvider, CosmoEditableSurfaceProvider {
    private let atom: Atom
    private weak var viewModel: ConnectionFocusModeViewModel?
    private let titleProvider: () -> String

    init(
        atom: Atom,
        viewModel: ConnectionFocusModeViewModel,
        titleProvider: (() -> String)? = nil
    ) {
        self.atom = atom
        self.viewModel = viewModel
        self.titleProvider = titleProvider ?? { atom.title ?? "Untitled Concept" }
    }

    var contextType: CosmoContextType { .connectionFocusMode }

    var surfaceID: String { "connection:\(atom.uuid)" }

    /// Concept boards live in the concept skill: no writing/review skill may
    /// auto-route here — only an explicit slash/picker choice can.
    var residentSkillID: String? { CosmoInlineAssistantSkillID.concept.rawValue }

    static func targetID(for atomUUID: String) -> String {
        "connection:\(atomUUID):sections"
    }

    /// Concept minting: the working page's References row goes through the
    /// LIVE editing session — the mint service never writes the open origin
    /// atom (its editing lock is held here). Deduped by link target.
    func addReferenceRow(uuid: String, title: String) {
        guard let viewModel, uuid != atom.uuid else { return }
        let alreadyLinked = viewModel.state.sections.contains { section in
            section.items.contains { $0.linkedConnectionUUID == uuid }
        }
        guard !alreadyLinked else { return }
        viewModel.attachItem(
            ConnectionItem(content: title, linkedConnectionUUID: uuid),
            toSection: .references
        )
    }

    var contextSummary: String {
        "Connection: \(atom.title ?? "Untitled")"
    }

    var contextData: CosmoContextData {
        var viewData: [String: String] = [:]

        if let vm = viewModel {
            let sections = vm.state.sections
            let totalItems = sections.reduce(0) { $0 + $1.items.count }
            let filledSections = sections.filter { !$0.items.isEmpty }
            viewData["sectionCount"] = "\(sections.count)"
            viewData["filledSections"] = "\(filledSections.count)"
            viewData["totalItems"] = "\(totalItems)"
            viewData["conceptType"] = vm.state.conceptType.displayName
            if !filledSections.isEmpty {
                viewData["populatedSections"] = filledSections
                    .map { $0.type.displayName }
                    .joined(separator: ", ")
            }
        }

        return CosmoContextData(
            currentAtomUUID: atom.uuid,
            currentAtomType: "connection",
            currentAtomTitle: atom.title,
            viewSpecificData: viewData
        )
    }

    // MARK: - Editable surface

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        let model = currentModel()
        return CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: Self.targetID(for: atom.uuid),
            kind: .structured,
            title: titleProvider(),
            text: model.text,
            sourceHash: CosmoEditableSurfaceHasher.hash(model.text),
            anchors: model.anchors,
            // Concept boards live in the concept skill: no writing/review skill
            // may auto-route here — only an explicit slash/picker choice can.
            residentSkillID: CosmoInlineAssistantSkillID.concept.rawValue
        )
    }

    /// Stage-time gate for `propose_workspace_edit`: issues for operations
    /// this surface's apply would deterministically refuse. Read-only —
    /// resolves against the LIVE board, never mutates.
    func stagingIssues(for operations: [CosmoAssistantProposalOperation]) -> [String] {
        ConnectionSurfaceSerializer.stagingIssues(operations: operations, in: currentModel())
    }

    /// Render-time truth for the pane receipt: where each still-reviewable
    /// operation reviews RIGHT NOW (section ghost rows, the Manuscript diff,
    /// or nowhere because the board changed under it since staging).
    /// Read-only — resolves against the same live model the stage gate and
    /// apply use, never mutates.
    func captureReceiptState(for proposal: CosmoAssistantProposal) -> ConnectionCaptureReceiptState {
        ConnectionSurfaceSerializer.captureReceiptState(
            operations: proposal.operations,
            proposalID: proposal.id,
            in: currentModel()
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        guard let viewModel else {
            return result(operation, .conflicted, "Connection editor is unavailable")
        }
        let model = currentModel()

        switch operation.kind {
        case .textInsertion:
            return applyInsertion(operation, model: model, viewModel: viewModel)
        case .textReplacement, .structuredFieldReplacement:
            return applyReplacement(operation, model: model, viewModel: viewModel)
        case .formatMarks:
            // Connection sections are structured plain-text fields — no rich
            // marks to apply. Honest skip, never a blocking conflict.
            return result(operation, .rejected, "Formatting doesn't apply to connection sections — skipped")
        case .canvasPlan:
            return result(operation, .conflicted, "Canvas plans don't apply to a connection")
        }
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        result(operation, .rejected, "Rejected")
    }

    // MARK: - Insertion

    private func applyInsertion(
        _ operation: CosmoAssistantProposalOperation,
        model: ConnectionSurfaceModel,
        viewModel: ConnectionFocusModeViewModel
    ) -> CosmoEditableOperationResult {
        guard let proposed = operation.proposedText,
              !proposed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return result(operation, .conflicted, "Nothing to insert")
        }
        guard let anchorLine = locateAnchorLine(for: operation, in: model) else {
            return result(operation, .conflicted, "Couldn't find the anchor line — anchor a section header or an existing bullet")
        }

        switch anchorLine.kind {
        case .header(let type), .empty(let type):
            return insertItems(from: proposed, into: type, afterItemID: nil, operation: operation, viewModel: viewModel)
        case .item(let type, let itemID), .itemContinuation(let type, let itemID):
            return insertItems(from: proposed, into: type, afterItemID: itemID, operation: operation, viewModel: viewModel)
        case .title, .meta, .blank:
            return result(operation, .conflicted, "Insertions must anchor a section header or a bullet line")
        }
    }

    /// Resolves the operation's anchor to a line, preferring the verbatim
    /// originalText, then the structured anchorID ("section:<rawValue>").
    /// Deliberately does NOT fall back to appending at the end of the text —
    /// that would silently dump items into the last section.
    private func locateAnchorLine(
        for operation: CosmoAssistantProposalOperation,
        in model: ConnectionSurfaceModel
    ) -> ConnectionSurfaceModel.Line? {
        let anchorText = operation.originalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !anchorText.isEmpty,
           let range = CosmoInlineDiffLocator.range(of: anchorText, in: model.text) {
            return model.line(at: range.upperBound)
        }
        if let anchorID = operation.anchorID,
           let type = sectionType(fromAnchorID: anchorID) {
            return model.lines.first {
                if case .header(let lineType) = $0.kind { return lineType == type }
                return false
            }
        }
        return nil
    }

    private func sectionType(fromAnchorID anchorID: String) -> ConnectionSectionType? {
        guard anchorID.hasPrefix("section:") else { return nil }
        return ConnectionSectionType(rawValue: String(anchorID.dropFirst("section:".count)))
    }

    private func insertItems(
        from proposedText: String,
        into type: ConnectionSectionType,
        afterItemID: UUID?,
        operation: CosmoAssistantProposalOperation,
        viewModel: ConnectionFocusModeViewModel
    ) -> CosmoEditableOperationResult {
        guard let items = ConnectionSurfaceSerializer.parseItems(from: proposedText, targetSection: type) else {
            return result(operation, .conflicted, "Proposed text spans multiple sections — stage one operation per section")
        }
        guard !items.isEmpty else {
            return result(operation, .conflicted, "No items found in the proposed text")
        }

        var previousID = afterItemID
        for itemText in items {
            // Staged @[Title](connection:<uuid>) tokens resolve into mention
            // inlines; an item that IS one connection mention lands as a
            // first-class link row.
            let parsed = ConceptMentionToken.parse(itemText)
            let inserted = viewModel.insertItem(
                document: parsed.document,
                plainText: parsed.plainText,
                inSection: type,
                afterItemID: previousID,
                linkedConnectionUUID: parsed.soleConnectionLink?.entityUUID
            )
            previousID = inserted?.id ?? previousID
        }
        let noun = items.count == 1 ? "item" : "items"
        return result(operation, .applied, "Added \(items.count) \(noun) to \(type.displayName)")
    }

    // MARK: - Replacement

    private func applyReplacement(
        _ operation: CosmoAssistantProposalOperation,
        model: ConnectionSurfaceModel,
        viewModel: ConnectionFocusModeViewModel
    ) -> CosmoEditableOperationResult {
        let original = operation.originalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !original.isEmpty else {
            return result(operation, .conflicted, "Replacements need the original text copied verbatim")
        }
        guard let range = CosmoInlineDiffLocator.range(of: operation.originalText ?? "", in: model.text) else {
            return result(operation, .conflicted, "Original text not found — it may have changed since the draft was staged")
        }

        let touched = model.lines(intersecting: range).filter {
            if case .blank = $0.kind { return false }
            return true
        }
        guard !touched.isEmpty else {
            return result(operation, .conflicted, "The located range doesn't cover any editable line")
        }

        let proposed = operation.proposedText ?? ""

        if touched.allSatisfy({ if case .title = $0.kind { return true }; return false }) {
            return replaceTitle(with: proposed, operation: operation, viewModel: viewModel)
        }
        if touched.allSatisfy({ if case .meta = $0.kind { return true }; return false }) {
            // `.meta` carries more than the Type line (handling rebuttals,
            // gallery rows) — only the Type line may route to a type edit,
            // or a staged rebuttal rewrite whose text happens to contain a
            // framework name would silently change the concept type.
            guard touched.allSatisfy({ ConnectionSurfaceSerializer.isConceptTypeLine($0, in: model) }) else {
                let reason = touched.contains(where: { ConnectionSurfaceSerializer.isHandledObjectionLine($0, in: model) })
                    ? "Can't edit that line — \(ConnectionSurfaceSerializer.handledLineGuidance)"
                    : "That line is read-only board metadata and can't be edited"
                return result(operation, .conflicted, reason)
            }
            return replaceConceptType(with: proposed, operation: operation, viewModel: viewModel)
        }
        return replaceSectionLines(touched, with: proposed, operation: operation, viewModel: viewModel)
    }

    private func replaceTitle(
        with proposed: String,
        operation: CosmoAssistantProposalOperation,
        viewModel: ConnectionFocusModeViewModel
    ) -> CosmoEditableOperationResult {
        var newTitle = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        if newTitle.hasPrefix("#") {
            newTitle = newTitle.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        }
        guard !newTitle.isEmpty else {
            return result(operation, .conflicted, "The proposed title is empty")
        }
        viewModel.updateTitle(newTitle)
        return result(operation, .applied, "Renamed the connection to “\(newTitle)”")
    }

    private func replaceConceptType(
        with proposed: String,
        operation: CosmoAssistantProposalOperation,
        viewModel: ConnectionFocusModeViewModel
    ) -> CosmoEditableOperationResult {
        let name = proposed
            .replacingOccurrences(of: "Type:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = ConceptFrameworkType.allCases.first(where: {
            $0.displayName.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            let options = ConceptFrameworkType.allCases.map(\.displayName).joined(separator: ", ")
            return result(operation, .conflicted, "Unknown concept type — use one of: \(options)")
        }
        viewModel.updateConceptType(match)
        return result(operation, .applied, "Set the concept type to \(match.displayName)")
    }

    /// Replaces a run of lines inside one section: covered items are replaced
    /// in place by the proposed bullets (first bullet edits the first item,
    /// extras insert after it, leftover covered items are deleted; zero
    /// bullets deletes them all). Header lines are immutable.
    private func replaceSectionLines(
        _ touched: [ConnectionSurfaceModel.Line],
        with proposed: String,
        operation: CosmoAssistantProposalOperation,
        viewModel: ConnectionFocusModeViewModel
    ) -> CosmoEditableOperationResult {
        var sectionTypes = Set<ConnectionSectionType>()
        var coveredItemIDs: [UUID] = []
        var coversHeader = false
        var coversEmptyMarker = false

        for line in touched {
            switch line.kind {
            case .header(let type):
                coversHeader = true
                sectionTypes.insert(type)
            case .empty(let type):
                coversEmptyMarker = true
                sectionTypes.insert(type)
            case .item(let type, let id), .itemContinuation(let type, let id):
                sectionTypes.insert(type)
                if !coveredItemIDs.contains(id) { coveredItemIDs.append(id) }
            case .title, .meta, .blank:
                return result(operation, .conflicted, "Edits can't span the title or metadata lines together with section content")
            }
        }
        guard sectionTypes.count == 1, let type = sectionTypes.first else {
            return result(operation, .conflicted, "Edits can't span multiple sections — stage one operation per section")
        }
        guard let items = ConnectionSurfaceSerializer.parseItems(from: proposed, targetSection: type) else {
            return result(operation, .conflicted, "Proposed text spans multiple sections — stage one operation per section")
        }
        if coversHeader {
            let preservesHeader = proposed.localizedCaseInsensitiveContains(type.displayName)
            guard preservesHeader else {
                return result(operation, .conflicted, "Section headers can't be renamed or removed")
            }
        }
        if coversEmptyMarker || coveredItemIDs.isEmpty {
            // Replacing the "(empty)" marker (or just the header) is an insertion.
            guard !items.isEmpty else {
                return result(operation, .conflicted, "No items found in the proposed text")
            }
            var previousID: UUID? = nil
            for itemText in items {
                let parsed = ConceptMentionToken.parse(itemText)
                let inserted = viewModel.insertItem(
                    document: parsed.document,
                    plainText: parsed.plainText,
                    inSection: type,
                    afterItemID: previousID,
                    linkedConnectionUUID: parsed.soleConnectionLink?.entityUUID
                )
                previousID = inserted?.id ?? previousID
            }
            return result(operation, .applied, "Added \(items.count) item\(items.count == 1 ? "" : "s") to \(type.displayName)")
        }

        guard let section = viewModel.state.section(for: type) else {
            return result(operation, .conflicted, "Section \(type.displayName) is missing")
        }

        var remainingItems = items
        var editedCount = 0
        var previousID: UUID? = nil

        for itemID in coveredItemIDs {
            guard var existing = section.items.first(where: { $0.id == itemID }) else { continue }
            if remainingItems.isEmpty {
                viewModel.deleteItem(itemID, fromSection: type)
            } else {
                let newText = remainingItems.removeFirst()
                existing.applyDocument(ConceptMentionToken.parse(newText).document)
                viewModel.editItem(existing, inSection: type)
                editedCount += 1
                previousID = itemID
            }
        }
        for itemText in remainingItems {
            let parsed = ConceptMentionToken.parse(itemText)
            let inserted = viewModel.insertItem(
                document: parsed.document,
                plainText: parsed.plainText,
                inSection: type,
                afterItemID: previousID,
                linkedConnectionUUID: parsed.soleConnectionLink?.entityUUID
            )
            previousID = inserted?.id ?? previousID
        }

        if items.isEmpty {
            let noun = coveredItemIDs.count == 1 ? "item" : "items"
            return result(operation, .applied, "Removed \(coveredItemIDs.count) \(noun) from \(type.displayName)")
        }
        return result(operation, .applied, "Updated \(type.displayName) (\(editedCount) edited, \(max(items.count - editedCount, 0)) added)")
    }

    // MARK: - Helpers

    private func currentModel() -> ConnectionSurfaceModel {
        let state = viewModel?.state
        return ConnectionSurfaceSerializer.serialize(
            title: titleProvider(),
            conceptType: state?.conceptType ?? .mentalModel,
            sections: state?.sections ?? [],
            media: state?.media ?? [],
            mediaAtoms: viewModel?.mediaAtoms ?? [:]
        )
    }

    private func result(
        _ operation: CosmoAssistantProposalOperation,
        _ status: CosmoProposalStatus,
        _ message: String
    ) -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: status, message: message)
    }

    // MARK: - Window actions

    var availableActions: [CosmoWindowAction] {
        guard let viewModel else { return [] }

        func action(
            id: String,
            name: String,
            section: ConnectionSectionType
        ) -> CosmoWindowAction {
            CosmoWindowAction(
                id: id,
                name: name,
                description: "Add a new item to \(section.displayName).",
                modelTier: .balanced
            ) { prompt in
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "Nothing added." }
                let document = RichDocument.migrateLegacy(trimmed)
                await MainActor.run {
                    viewModel.addItem(document: document, plainText: trimmed, toSection: section)
                }
                return "Added to \(section.displayName.lowercased())."
            }
        }

        return [
            action(id: "connection-goal", name: "Insert into Goal", section: .goal),
            action(id: "connection-problems", name: "Insert into Problems", section: .problems),
            action(id: "connection-process", name: "Insert into Process", section: .process)
        ]
    }
}
