// CosmoOS/Data/Models/CaptureRequest.swift
// The Mac → iPhone camera relay record. The Mac writes a `.pending` row
// (plus an APNs push at the phone); the iPhone claims it, opens straight
// into the scanner, streams pages up as media_attachments tagged with the
// request's scanSessionId, and settles the status. A synced, local-first
// domain: column names match Supabase `capture_requests` exactly.

import Foundation
import GRDB

extension Notification.Name {
    /// Posted after a capture_requests row changes via realtime — the
    /// digitizing panel refreshes its request status.
    static let cosmoScanRequestUpdated = Notification.Name("cosmoScanRequestUpdated")
}

enum CaptureRequestKind: String, Codable, Sendable {
    case inboxScan = "inbox_scan"
    case inquiryScan = "inquiry_scan"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CaptureRequestKind(rawValue: raw) ?? .inboxScan
    }
}

enum CaptureRequestStatus: String, Codable, Sendable {
    case pending      // Waiting for the phone
    case claimed      // The phone opened the scanner
    case streaming    // Pages are landing
    case fulfilled    // Done — pages all arrived
    case cancelled    // Either side called it off
    case expired      // Nobody answered

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CaptureRequestStatus(rawValue: raw) ?? .expired
    }
}

struct CaptureRequest: Identifiable, Codable, Equatable, Sendable, FetchableRecord, PersistableRecord, Syncable, HasUUID {
    static let databaseTableName = "capture_requests"

    var id: Int64?
    let uuid: String
    var kind: CaptureRequestKind
    var status: CaptureRequestStatus
    var scanSessionId: String

    // Inquiry context (kind == .inquiryScan): where scanned thoughts land.
    var deepDiveUUID: String?
    var sessionUUID: String?
    var questionUUID: String?
    var questionTitle: String?
    var deepDiveTitle: String?

    var pageCount: Int
    var requestedAt: String
    var fulfilledAt: String?

    // Sync bookkeeping
    var isDeleted: Bool
    var syncUpdatedAt: String?
    var localVersion: Int64
    var serverVersion: Int64
    var syncVersion: Int64

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id, uuid, kind, status, scanSessionId
        case deepDiveUUID, sessionUUID, questionUUID, questionTitle, deepDiveTitle
        case pageCount, requestedAt, fulfilledAt
        case isDeleted = "is_deleted"
        case syncUpdatedAt = "updated_at"
        case localVersion = "_local_version"
        case serverVersion = "_server_version"
        case syncVersion = "_sync_version"
    }

    static func new(
        kind: CaptureRequestKind,
        scanSessionId: String,
        deepDiveUUID: String? = nil,
        sessionUUID: String? = nil,
        questionUUID: String? = nil,
        questionTitle: String? = nil,
        deepDiveTitle: String? = nil
    ) -> CaptureRequest {
        let now = ISO8601.string(from: Date())
        return CaptureRequest(
            id: nil,
            uuid: UUID().uuidString,
            kind: kind,
            status: .pending,
            scanSessionId: scanSessionId,
            deepDiveUUID: deepDiveUUID,
            sessionUUID: sessionUUID,
            questionUUID: questionUUID,
            questionTitle: questionTitle,
            deepDiveTitle: deepDiveTitle,
            pageCount: 0,
            requestedAt: now,
            fulfilledAt: nil,
            isDeleted: false,
            syncUpdatedAt: now,
            localVersion: 1,
            serverVersion: 0,
            syncVersion: 0
        )
    }

    /// A request older than this is stale — the phone won't open for it.
    var isFresh: Bool {
        guard let requested = ISO8601.date(from: requestedAt) else { return false }
        return Date().timeIntervalSince(requested) < 15 * 60
    }
}
