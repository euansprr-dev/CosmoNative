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
    static func loadAtomDocument(
        field: RichDocumentField,
        metadata: String?,
        fallbackPlainText: String?
    ) -> RichDocument {
        let document = RichDocumentMetadataStorage.readDocument(from: metadata, key: field.metadataKey)
            ?? RichDocument.migrateLegacy(fallbackPlainText ?? "")
        return field == .title ? normalizedTitleDocument(document) : document
    }

    static func loadBlockDocument(
        key: String,
        metadata: [String: String],
        fallbackPlainText: String?
    ) -> RichDocument {
        let document: RichDocument
        if let encoded = metadata[key],
           let data = encoded.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(RichDocument.self, from: data) {
            document = decoded
        } else {
            document = RichDocument.migrateLegacy(fallbackPlainText ?? "")
        }
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
        document.blocks
            .compactMap { block in
                switch block.kind {
                case .divider, .image:
                    return nil
                default:
                    let text = block.inlines.map(\.plainText).joined()
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
            }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedTitleDocument(_ document: RichDocument) -> RichDocument {
        let title = titlePlainText(from: document)
        return title.isEmpty ? .empty : RichDocument(blocks: [.paragraph(title)])
    }

    static func nilIfEmpty(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Notification.Name {
    static let richDocumentDidChange = Notification.Name("com.cosmo.richDocumentDidChange")
}
