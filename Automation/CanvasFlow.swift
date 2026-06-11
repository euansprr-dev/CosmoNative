// CosmoOS/Automation/CanvasFlow.swift
// A Flow is a drawn, visible piece of behavior on the canvas: an ink line
// from a cluster (where knowledge gathers) to a point where something should
// happen, with one verb chip at its midpoint. Geometry persists with the
// thinkspace; running a flow executes its verb over the cluster's atoms.

import SwiftUI

// MARK: - Verb

enum FlowVerb: String, Codable, CaseIterable, Identifiable, Sendable {
    case distill
    case draft

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .distill: return "Distill"
        case .draft: return "Draft"
        }
    }

    var icon: String {
        switch self {
        case .distill: return "drop"
        case .draft: return "doc.text"
        }
    }

    /// One-line plain-language description shown in the verb picker.
    var pickerDescription: String {
        switch self {
        case .distill: return "Summarize what's here into a sourced note"
        case .draft: return "Turn this cluster into a content draft"
        }
    }

    /// The natural-language rule sentence shown in the flow inspector.
    func sentence(clusterName: String) -> String {
        switch self {
        case .distill:
            return "When you run this flow, Cosmo distills everything in \(clusterName) into a sourced note beside it."
        case .draft:
            return "When you run this flow, Cosmo turns \(clusterName) into a content draft in your pipeline."
        }
    }

    /// Chips are tinted by what the verb *produces*.
    @MainActor
    var outputTint: Color {
        switch self {
        case .distill: return DS.entityNote
        case .draft: return DS.entityContent
        }
    }

    var outputAtomType: AtomType {
        switch self {
        case .distill: return .note
        case .draft: return .content
        }
    }
}

// MARK: - Run Mode

enum FlowRunMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case onArrival
    case daily

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .onArrival: return "On arrival"
        case .daily: return "Daily"
        }
    }

    var icon: String {
        switch self {
        case .manual: return "hand.tap"
        case .onArrival: return "tray.and.arrow.down"
        case .daily: return "clock"
        }
    }
}

// MARK: - Flow

struct CanvasFlow: Codable, Equatable, Identifiable, Sendable {
    let uuid: String
    var verb: FlowVerb
    /// CanvasCluster id (UUID string) the flow draws from.
    var sourceClusterId: String
    /// Canvas-space end point — where output blocks land and the arrow points.
    var endX: Double
    var endY: Double
    var lastRunAt: Date?
    var runCount: Int

    /// How the flow fires. Anything beyond manual compiles to an
    /// AutomationRule (the engine stays the single source of behavior).
    var runMode: FlowRunMode = .manual

    /// Output awaiting approval from an autonomous run — autonomous flows
    /// propose; they never place blocks without you.
    var pendingOutputAtomUUID: String?

    var id: String { uuid }

    var endPoint: CGPoint {
        get { CGPoint(x: endX, y: endY) }
        set { endX = newValue.x; endY = newValue.y }
    }

    init(verb: FlowVerb, sourceClusterId: String, end: CGPoint) {
        self.uuid = UUID().uuidString
        self.verb = verb
        self.sourceClusterId = sourceClusterId
        self.endX = end.x
        self.endY = end.y
        self.lastRunAt = nil
        self.runCount = 0
        self.runMode = .manual
        self.pendingOutputAtomUUID = nil
    }

    enum CodingKeys: String, CodingKey {
        case uuid, verb, sourceClusterId, endX, endY, lastRunAt, runCount
        case runMode, pendingOutputAtomUUID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        verb = try container.decode(FlowVerb.self, forKey: .verb)
        sourceClusterId = try container.decode(String.self, forKey: .sourceClusterId)
        endX = try container.decode(Double.self, forKey: .endX)
        endY = try container.decode(Double.self, forKey: .endY)
        lastRunAt = try container.decodeIfPresent(Date.self, forKey: .lastRunAt)
        runCount = try container.decodeIfPresent(Int.self, forKey: .runCount) ?? 0
        runMode = try container.decodeIfPresent(FlowRunMode.self, forKey: .runMode) ?? .manual
        pendingOutputAtomUUID = try container.decodeIfPresent(String.self, forKey: .pendingOutputAtomUUID)
    }

    /// The rule as one plain sentence, mode-aware.
    func sentence(clusterName: String) -> String {
        let action: String
        switch verb {
        case .distill: action = "distills everything in \(clusterName) into a sourced note"
        case .draft: action = "turns \(clusterName) into a content draft for your pipeline"
        }
        switch runMode {
        case .manual:
            return "When you run this flow, Cosmo \(action) beside it."
        case .onArrival:
            return "When something new lands in \(clusterName), Cosmo \(action) — staged for your approval."
        case .daily:
            return "Every day, Cosmo \(action) — staged for your approval."
        }
    }
}
