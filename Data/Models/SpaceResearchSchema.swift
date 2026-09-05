import Foundation
import CryptoKit

/// Wire-level helpers shared with iPhone. Mutate only owned JSON keys so newer
/// research fields survive edits from either device.
public enum SpaceResearchSchema {
    public enum Failure: Error, LocalizedError {
        case unreadable, missing, emptyTitle, changed
        public var errorDescription: String? {
            switch self {
            case .changed: "This item changed since your last action. Your newer work has been kept."
            case .unreadable: "This research contains unreadable data. Your saved work has not been changed."
            case .missing: "This item is no longer available."
            case .emptyTitle: "Enter a question to explore."
            }
        }
    }
    public static func object(_ value: String?) throws -> [String: Any] {
        guard let value, !value.isEmpty else { return [:] }
        guard let data = value.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.unreadable }
        return object
    }
    public static func json(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }
    /// Stable across devices; simultaneous migration cannot create two documents.
    public static func stableID(_ key: String) -> String {
        let hex = SHA256.hash(data: Data(("cosmo.space.v2:" + key).utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        let chars = Array(hex)
        return [String(chars[0..<8]), String(chars[8..<12]), String(chars[12..<16]), String(chars[16..<20]), String(chars[20..<32])].joined(separator: "-").uppercased()
    }
    public static func questionKey(_ title: String) -> String {
        title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "?!.,;:"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    public static func bootstrap(questionID: String, title: String, now: String) -> [String: Any] {
        let rootID = stableID("root:" + questionID)
        return ["researchTree": ["rootNodeId": rootID, "nodes": [rootID: node(id: rootID, kind: "question", atomID: questionID, title: title, now: now)]]]
    }
    public static func node(id: String, kind: String, atomID: String, title: String, now: String, parent: String? = nil, order: Int = 0) -> [String: Any] {
        var result: [String: Any] = ["id": id, "kind": kind, "atomUUID": atomID, "childNodeIds": [String](), "createdAt": now, "branchOrder": order,
            "meta": ["label": title, "aiSuggested": false, "accepted": true, "isPlaceholder": false]]
        if let parent { result["parentNodeId"] = parent }
        return result
    }
    public static func append(_ atomID: String, kind: String, title: String, to structured: inout [String: Any], now: String) throws {
        guard var tree = structured["researchTree"] as? [String: Any], let rootID = tree["rootNodeId"] as? String,
              var nodes = tree["nodes"] as? [String: [String: Any]], var root = nodes[rootID] else { throw Failure.unreadable }
        if nodes.values.contains(where: { $0["atomUUID"] as? String == atomID && $0["kind"] as? String == kind }) { return }
        let id = stableID(kind + ":" + atomID)
        var children = root["childNodeIds"] as? [String] ?? []
        nodes[id] = node(id: id, kind: kind, atomID: atomID, title: title, now: now, parent: rootID, order: children.count)
        children.append(id); root["childNodeIds"] = children; nodes[rootID] = root
        tree["nodes"] = nodes; structured["researchTree"] = tree
    }
    public static func sourceIDs(_ structured: [String: Any]) -> [String] {
        var ids = (structured["sourceTabs"] as? [[String: Any]] ?? []).compactMap { $0["sourceUUID"] as? String }
        ids += (structured["sourceRefs"] as? [[String: Any]] ?? []).compactMap { $0["sourceUUID"] as? String }
        let tree = structured["researchTree"] as? [String: Any] ?? [:]
        ids += (tree["nodes"] as? [String: [String: Any]] ?? [:]).values.filter { $0["kind"] as? String == "source" }.compactMap { $0["atomUUID"] as? String }
        var seen = Set<String>(); return ids.filter { seen.insert($0).inserted }
    }
    public static func attachSource(id: String, title: String, url: String?, to structured: inout [String: Any], now: String) throws {
        try append(id, kind: "source", title: title, to: &structured, now: now)
        var tabs = structured["sourceTabs"] as? [[String: Any]] ?? []
        if !tabs.contains(where: { $0["sourceUUID"] as? String == id }) {
            var tab: [String: Any] = ["id": stableID("source-tab:" + id), "kind": "internal", "sourceUUID": id, "title": title,
                "scrollPosition": 0, "lastReadAt": now, "pinned": false, "highlightCount": 0]
            if let url { tab["url"] = url }
            tabs.append(tab); structured["sourceTabs"] = tabs
        }
        let tree = structured["researchTree"] as? [String: Any] ?? [:]
        let rootID = tree["rootNodeId"] as? String ?? ""
        let root = (tree["nodes"] as? [String: [String: Any]])?[rootID]
        var refs = structured["sourceRefs"] as? [[String: Any]] ?? []
        if !refs.contains(where: { $0["sourceUUID"] as? String == id }) {
            var ref: [String: Any] = ["sourceUUID": id, "tabId": stableID("source-tab:" + id), "title": title, "sourceType": "internal",
                "status": "saved", "primaryNodeId": rootID, "openedAt": now, "lastOpenedAt": now, "extractCount": 0, "noteCount": 0, "addedByUser": true]
            ref["primaryQuestionUUID"] = root?["atomUUID"]; ref["url"] = url
            refs.append(ref); structured["sourceRefs"] = refs
        }
    }
    /// Apply only this editor's changes to the latest row. Identity-keyed
    /// arrays retain objects appended on another device while a session is open.
    public static func mergingChanges(base: [String: Any], incoming: [String: Any], current: [String: Any]) -> [String: Any] {
        var result = current
        for key in Set(base.keys).union(incoming.keys) {
            guard !same(base[key], incoming[key]) else { continue }
            if let value = incoming[key] { result[key] = mergeValue(base[key], value, current[key]) }
            else if same(base[key], current[key]) { result.removeValue(forKey: key) }
        }
        return result
    }
    private static func same(_ lhs: Any?, _ rhs: Any?) -> Bool {
        if lhs == nil && rhs == nil { return true }
        guard let lhs = lhs as? NSObject, let rhs = rhs as? NSObject else { return false }
        return lhs.isEqual(rhs)
    }
    private static func mergeValue(_ base: Any?, _ incoming: Any, _ current: Any?) -> Any {
        if let incoming = incoming as? [String: Any] {
            return mergingChanges(base: base as? [String: Any] ?? [:], incoming: incoming, current: current as? [String: Any] ?? [:])
        }
        if let incoming = incoming as? [[String: Any]], let current = current as? [[String: Any]] {
            let base = base as? [[String: Any]] ?? []
            let all = base + incoming + current
            if let key = ["id", "sourceUUID"].first(where: { key in !all.isEmpty && all.allSatisfy { $0[key] as? String != nil } }) {
                let previous = Dictionary(base.map { ($0[key] as! String, $0) }, uniquingKeysWith: { _, last in last })
                let edited = Dictionary(incoming.map { ($0[key] as! String, $0) }, uniquingKeysWith: { _, last in last })
                var rows = current.filter { row in
                    let id = row[key] as! String
                    return previous[id] == nil || edited[id] != nil || !same(previous[id], row)
                }
                for item in incoming {
                    let id = item[key] as! String
                    if let index = rows.firstIndex(where: { $0[key] as? String == id }) {
                        rows[index] = mergingChanges(base: previous[id] ?? [:], incoming: item, current: rows[index])
                    } else if previous[id] == nil { rows.append(item) }
                }
                return rows
            }
            if incoming.isEmpty && base.isEmpty { return current }
        }
        if let incoming = incoming as? [String], let current = current as? [String] {
            let old = Set(base as? [String] ?? [])
            var seen = Set<String>()
            return (incoming + current.filter { !old.contains($0) }).filter { seen.insert($0).inserted }
        }
        return incoming
    }

    public static func understandingText(_ structured: [String: Any]) -> String {
        guard let value = structured["currentUnderstanding"] as? [String: Any] else { return "" }
        var paragraphs: [String] = []
        for key in ["narrative", "oneSentenceModel"] {
            if let text = value[key] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { paragraphs.append(text) }
        }
        for (key, title) in [("corePrinciples", "Core principles"), ("whatIBelieve", "What I believe"), ("whatImUnsureAbout", "Open uncertainties")] {
            let texts = (value[key] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.filter { !$0.isEmpty }
            if !texts.isEmpty { paragraphs.append(title + "\n" + texts.map { "• " + $0 }.joined(separator: "\n")) }
        }
        for (key, title) in [("explainSimply", "In simple terms"), ("explainExpertly", "In depth")] {
            if let text = value[key] as? String, !text.isEmpty { paragraphs.append(title + "\n" + text) }
        }
        return paragraphs.joined(separator: "\n\n")
    }
}
