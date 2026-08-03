import Foundation

enum RichDocumentField {
    case title
    case body
    case draft

    var metadataKey: String {
        switch self {
        case .title:
            return RichDocumentMetadataKeys.titleDocument
        case .body:
            return RichDocumentMetadataKeys.bodyDocument
        case .draft:
            return RichDocumentMetadataKeys.contentDraftDocument
        }
    }
}

enum RichDocumentPersistence {
    private static let noteLagTolerance = 5

    static func loadAtomDocument(
        field: RichDocumentField,
        metadata: String?,
        fallbackPlainText: String?,
        preferFallbackPlainTextWhenRicher: Bool = false,
        atomUUID: String? = nil
    ) -> RichDocument {
        let fallbackDocument = RichDocument.migrateLegacy(fallbackPlainText ?? "")
        let metadataDocument = RichDocumentMetadataStorage.readDocument(from: metadata, key: field.metadataKey, atomUUID: atomUUID)
        let document = preferredDocument(
            field: field,
            metadataDocument: metadataDocument,
            fallbackDocument: fallbackDocument,
            fallbackPlainText: fallbackPlainText,
            preferFallbackPlainTextWhenRicher: preferFallbackPlainTextWhenRicher
        )
        return field == .title ? normalizedTitleDocument(document) : document
    }

    static func loadBlockDocument(
        key: String,
        metadata: [String: String],
        fallbackPlainText: String?,
        preferFallbackPlainTextWhenRicher: Bool = false,
        atomUUID: String? = nil
    ) -> RichDocument {
        let metadataDocument: RichDocument?
        if let encoded = metadata[key] {
            // Memoized: block documents re-decode at every mount otherwise
            // (a thinkspace switch mounts every visible note in one frame).
            metadataDocument = RichDocumentDecodeCache.shared.document(source: encoded, metadataKey: key, atomUUID: atomUUID) {
                guard let data = encoded.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(RichDocument.self, from: data)
            }
        } else {
            metadataDocument = nil
        }
        let fallbackDocument = RichDocument.migrateLegacy(fallbackPlainText ?? "")
        let field: RichDocumentField = key == RichDocumentMetadataKeys.titleDocument ? .title : .body
        let document = preferredDocument(
            field: field,
            metadataDocument: metadataDocument,
            fallbackDocument: fallbackDocument,
            fallbackPlainText: fallbackPlainText,
            preferFallbackPlainTextWhenRicher: preferFallbackPlainTextWhenRicher
        )
        return key == RichDocumentMetadataKeys.titleDocument ? normalizedTitleDocument(document) : document
    }

    static func writeAtomDocuments(
        existingMetadata: String?,
        titleDocument: RichDocument? = nil,
        bodyDocument: RichDocument? = nil,
        draftDocument: RichDocument? = nil
    ) -> (title: String?, body: String?, metadata: String?) {
        var metadata = existingMetadata
        let normalizedTitleDocument = titleDocument.map(normalizedTitleDocument(_:))

        if let normalizedTitleDocument {
            metadata = RichDocumentMetadataStorage.writeDocument(normalizedTitleDocument, into: metadata, key: RichDocumentField.title.metadataKey)
        }
        if let bodyDocument {
            metadata = RichDocumentMetadataStorage.writeDocument(bodyDocument, into: metadata, key: RichDocumentField.body.metadataKey)
        }
        if let draftDocument {
            metadata = RichDocumentMetadataStorage.writeDocument(draftDocument, into: metadata, key: RichDocumentField.draft.metadataKey)
        }

        let titleText = normalizedTitleDocument.map(titlePlainText(from:))
        let bodyText = bodyDocument?.plainText ?? draftDocument?.plainText

        return (
            title: titleText.flatMap(nilIfEmpty),
            body: bodyText.flatMap(nilIfEmpty),
            metadata: metadata
        )
    }

    static func canonicalNoteBodyDocument(
        bodyDocument: RichDocument,
        plainText: String,
        lagTolerance: Int = noteLagTolerance
    ) -> RichDocument {
        let trimmedPlainText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let documentPlainText = bodyDocument.plainText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedPlainText == documentPlainText {
            return bodyDocument
        }

        if trimmedPlainText.count > documentPlainText.count + lagTolerance || bodyDocument.isPlainTextOnly {
            return RichDocument.migrateLegacy(plainText)
        }

        return bodyDocument
    }

    static func noteSnapshot(
        existingMetadata: String?,
        titleDocument: RichDocument,
        bodyDocument: RichDocument,
        plainBodyText: String
    ) -> NoteDocumentSnapshot {
        let normalizedTitleDocument = normalizedTitleDocument(titleDocument)
        let effectiveBodyDocument = canonicalNoteBodyDocument(
            bodyDocument: bodyDocument,
            plainText: plainBodyText
        )
        let fields = writeAtomDocuments(
            existingMetadata: existingMetadata,
            titleDocument: normalizedTitleDocument,
            bodyDocument: effectiveBodyDocument
        )

        return NoteDocumentSnapshot(
            titleDocument: normalizedTitleDocument,
            bodyDocument: effectiveBodyDocument,
            titlePlainText: titlePlainText(from: normalizedTitleDocument),
            bodyPlainText: effectiveBodyDocument.plainText,
            metadata: fields.metadata
        )
    }

    static func richestPlainText(_ candidates: [String?]) -> String {
        candidates
            .compactMap { candidate in
                guard let candidate else { return nil }
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : candidate
            }
            .max(by: { $0.count < $1.count }) ?? ""
    }

    private static func preferredDocument(
        field: RichDocumentField,
        metadataDocument: RichDocument?,
        fallbackDocument: RichDocument,
        fallbackPlainText: String?,
        preferFallbackPlainTextWhenRicher: Bool
    ) -> RichDocument {
        let document = metadataDocument ?? fallbackDocument

        guard preferFallbackPlainTextWhenRicher,
              field != .title,
              let fallbackPlainText else {
            return document
        }

        let trimmedFallback = fallbackPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDocument = document.plainText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedFallback != trimmedDocument else {
            return document
        }

        return fallbackDocument
    }

    static func writeBlockDocument(
        _ document: RichDocument,
        key: String,
        metadata: [String: String]
    ) -> [String: String] {
        var updated = metadata
        let documentToWrite = key == RichDocumentMetadataKeys.titleDocument
            ? normalizedTitleDocument(document)
            : document
        if let data = try? JSONEncoder().encode(documentToWrite),
           let string = String(data: data, encoding: .utf8) {
            updated[key] = string
        }
        return updated
    }

    static func titlePlainText(from document: RichDocument) -> String {
        normalizedTitleString(
            normalizedTitleInlines(from: document)
                .map(\.plainText)
                .joined()
        )
    }

    static func normalizedTitleDocument(_ document: RichDocument) -> RichDocument {
        let inlines = normalizedTitleInlines(from: document)
        guard !inlines.isEmpty else { return .empty }

        if var firstBlock = document.blocks.first {
            firstBlock.kind = .paragraph
            firstBlock.inlines = inlines
            firstBlock.checked = nil
            firstBlock.element = nil
            firstBlock.children = []
            return RichDocument(blocks: [firstBlock])
        }

        return RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: inlines)
        ])
    }

    static func normalizedTitleString(_ string: String) -> String {
        string
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func nilIfEmpty(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedTitleInlines(from document: RichDocument) -> [RichInlineNode] {
        var result: [RichInlineNode] = []

        for block in document.blocks {
            guard block.kind != .divider else { continue }
            let blockInlines = normalizedTitleBlockInlines(from: block)
            guard !blockInlines.isEmpty else { continue }

            if !result.isEmpty {
                appendTitleNode(.text(" "), to: &result)
            }

            blockInlines.forEach { appendTitleNode($0, to: &result) }
        }

        return trimmedTitleBoundaryWhitespace(in: result)
    }

    private static func normalizedTitleBlockInlines(from block: RichBlock) -> [RichInlineNode] {
        let nodes = block.inlines.compactMap { node -> RichInlineNode? in
            switch node.kind {
            case .text:
                let normalized = normalizedTitleStringFragment(node.text ?? "")
                guard !normalized.isEmpty else { return nil }
                var updated = node
                updated.text = normalized
                return updated
            case .mention:
                return node
            case .imageRef:
                return nil
            }
        }

        return trimmedTitleBoundaryWhitespace(in: nodes)
    }

    private static func normalizedTitleStringFragment(_ string: String) -> String {
        string.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func appendTitleNode(_ node: RichInlineNode, to nodes: inout [RichInlineNode]) {
        guard node.kind != .imageRef else { return }

        if case let .some(last) = nodes.last,
           last.kind == .text,
           node.kind == .text,
           last.marks == node.marks {
            var merged = last
            merged.text = (last.text ?? "") + (node.text ?? "")
            nodes[nodes.count - 1] = merged
        } else {
            nodes.append(node)
        }
    }

    private static func trimmedTitleBoundaryWhitespace(in nodes: [RichInlineNode]) -> [RichInlineNode] {
        trimTrailingTitleWhitespace(from: trimLeadingTitleWhitespace(from: nodes))
    }

    private static func trimLeadingTitleWhitespace(from nodes: [RichInlineNode]) -> [RichInlineNode] {
        var trimmed = nodes

        while let first = trimmed.first, first.kind == .text {
            let normalized = (first.text ?? "").replacingOccurrences(
                of: #"^\s+"#,
                with: "",
                options: .regularExpression
            )
            if normalized.isEmpty {
                trimmed.removeFirst()
                continue
            }

            if normalized != first.text {
                var updated = first
                updated.text = normalized
                trimmed[0] = updated
            }
            break
        }

        return trimmed
    }

    private static func trimTrailingTitleWhitespace(from nodes: [RichInlineNode]) -> [RichInlineNode] {
        var trimmed = nodes

        while let last = trimmed.last, last.kind == .text {
            let normalized = (last.text ?? "").replacingOccurrences(
                of: #"\s+$"#,
                with: "",
                options: .regularExpression
            )
            if normalized.isEmpty {
                trimmed.removeLast()
                continue
            }

            if normalized != last.text {
                var updated = last
                updated.text = normalized
                trimmed[trimmed.count - 1] = updated
            }
            break
        }

        return trimmed
    }
}

extension Notification.Name {
    static let richDocumentDidChange = Notification.Name("com.cosmo.richDocumentDidChange")
}

struct NoteDocumentSnapshot: Equatable {
    let titleDocument: RichDocument
    let bodyDocument: RichDocument
    let titlePlainText: String
    let bodyPlainText: String
    let metadata: String?

    var atomTitle: String? {
        RichDocumentPersistence.nilIfEmpty(titlePlainText)
    }

    var atomBody: String? {
        RichDocumentPersistence.nilIfEmpty(bodyPlainText)
    }

    func noteFocusStatePayload(atomUUID: String) -> [String: Any] {
        var userInfo: [String: Any] = [
            "atomUUID": atomUUID,
            "title": titlePlainText,
            "body": bodyPlainText
        ]

        if let bodyDocumentData = try? JSONEncoder().encode(bodyDocument),
           let bodyDocumentString = String(data: bodyDocumentData, encoding: .utf8) {
            userInfo["bodyDocumentJSON"] = bodyDocumentString
        }

        if let titleDocumentData = try? JSONEncoder().encode(titleDocument),
           let titleDocumentString = String(data: titleDocumentData, encoding: .utf8) {
            userInfo["titleDocumentJSON"] = titleDocumentString
        }

        return userInfo
    }
}

private extension RichDocument {
    var isPlainTextOnly: Bool {
        blocks.allSatisfy { block in
            block.inlines.allSatisfy { node in
                node.kind == .text
            }
        }
    }
}
