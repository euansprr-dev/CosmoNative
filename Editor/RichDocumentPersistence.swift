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
        if let stored = RichDocumentMetadataStorage.readDocument(from: metadata, key: field.metadataKey) {
            return stored
        }
        return RichDocument.migrateLegacy(fallbackPlainText ?? "")
    }

    static func loadBlockDocument(
        key: String,
        metadata: [String: String],
        fallbackPlainText: String?
    ) -> RichDocument {
        guard let encoded = metadata[key], let data = encoded.data(using: .utf8),
              let document = try? JSONDecoder().decode(RichDocument.self, from: data) else {
            return RichDocument.migrateLegacy(fallbackPlainText ?? "")
        }
        return document
    }

    static func writeAtomDocuments(
        existingMetadata: String?,
        titleDocument: RichDocument? = nil,
        bodyDocument: RichDocument? = nil,
        draftDocument: RichDocument? = nil
    ) -> (title: String?, body: String?, metadata: String?) {
        var metadata = existingMetadata

        if let titleDocument {
            metadata = RichDocumentMetadataStorage.writeDocument(titleDocument, into: metadata, key: RichDocumentField.title.metadataKey)
        }
        if let bodyDocument {
            metadata = RichDocumentMetadataStorage.writeDocument(bodyDocument, into: metadata, key: RichDocumentField.body.metadataKey)
        }
        if let draftDocument {
            metadata = RichDocumentMetadataStorage.writeDocument(draftDocument, into: metadata, key: RichDocumentField.draft.metadataKey)
        }

        let titleText = titleDocument.map(titlePlainText(from:))
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
        if let data = try? JSONEncoder().encode(document),
           let string = String(data: data, encoding: .utf8) {
            updated[key] = string
        }
        return updated
    }

    static func titlePlainText(from document: RichDocument) -> String {
        document.plainText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func nilIfEmpty(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Notification.Name {
    static let richDocumentDidChange = Notification.Name("com.cosmo.richDocumentDidChange")
}
