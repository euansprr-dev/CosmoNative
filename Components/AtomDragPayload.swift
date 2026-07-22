// CosmoOS/Components/AtomDragPayload.swift
// The in-app atom drag currency (July 2026). A dragged swipe/research card
// carries its atom uuid; drop targets (concept gallery, section cards)
// resolve the atom themselves. Plain-text fallback exports the cosmo:// URL
// so dragging into text fields still produces something meaningful.

import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// In-app atom reference. Runtime-declared — the payload never leaves
    /// the process as anything but its plain-text proxy.
    static let cosmoAtomRef = UTType(exportedAs: "com.cosmo.atom-ref")
}

struct AtomDragPayload: Codable, Transferable, Sendable {
    let atomUUID: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .cosmoAtomRef)
        ProxyRepresentation(exporting: { payload in
            "cosmo://atom/\(payload.atomUUID)"
        })
    }
}
