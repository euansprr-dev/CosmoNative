// CosmoOS/UI/FocusMode/CosmoAI/CosmoAIFocusModeViewModel.swift
// Extended conversation state for Cosmo AI Focus Mode
// Manages multi-turn conversation, mode routing, context loading, and surfaced atoms

import SwiftUI
import Combine

@MainActor
final class CosmoAIFocusModeViewModel: ObservableObject {
    // MARK: - Published State
    @Published var messages: [AIMessage] = []
    @Published var surfacedAtoms: [Atom] = []
    @Published var isGenerating = false
    @Published var currentMode: CosmoMode = .think
    @Published var connectedAtomUUIDs: [String] = []
    @Published var contextSources: [ContextSource] = []
    @Published var inputText = ""

    // MARK: - Properties
    let atom: Atom

    // MARK: - Init
    init(atom: Atom) {
        self.atom = atom
        loadConversationHistory()
        loadConnectedContext()
    }

    // MARK: - Message Types
    struct AIMessage: Identifiable {
        let id = UUID()
        let role: MessageRole
        let content: String
        let timestamp: Date
        let mode: CosmoMode
        var recallResults: [RecallResult]?
        var actionResults: [ActionResult]?
        var sources: [ResearchFinding]?
    }

    enum MessageRole: String {
        case user
        case assistant
        case system
    }

    // MARK: - Send Message
    func sendMessage() async {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        let inferredMode = CosmoMode.infer(from: query)
        currentMode = inferredMode
        inputText = ""

        let userMsg = AIMessage(role: .user, content: query, timestamp: Date(), mode: inferredMode)
        messages.append(userMsg)

        isGenerating = true

        switch inferredMode {
        case .think:
            await performThink(query: query)
        case .research:
            await performResearch(query: query)
        case .recall:
            await performRecall(query: query)
        case .act:
            await performAct(query: query)
        }

        isGenerating = false
        saveConversationHistory()

        await autoSurfaceRelated(query: query)
    }

    // MARK: - Think Mode
    private func performThink(query: String) async {
        do {
            var contextText = ""
            for source in contextSources {
                contextText += "[\(source.type.rawValue.uppercased()): \(source.title)] \(source.bodyPreview)\n\n"
            }

            let result = try await ResearchService.shared.performResearch(
                query: contextText.isEmpty ? query : "\(query)\n\nContext:\n\(contextText)",
                searchType: .web,
                maxResults: 3
            )

            let response = AIMessage(
                role: .assistant,
                content: result.summary,
                timestamp: Date(),
                mode: .think,
                sources: result.findings
            )
            messages.append(response)
        } catch {
            let errorMsg = AIMessage(role: .assistant, content: "Error: \(error.localizedDescription)", timestamp: Date(), mode: .think)
            messages.append(errorMsg)
        }
    }

    // MARK: - Research Mode
    private func performResearch(query: String) async {
        do {
            let result = try await ResearchService.shared.performResearch(
                query: query,
                searchType: .web,
                maxResults: 5
            )

            let response = AIMessage(
                role: .assistant,
                content: result.summary,
                timestamp: Date(),
                mode: .research,
                sources: result.findings
            )
            messages.append(response)
        } catch {
            let errorMsg = AIMessage(role: .assistant, content: "Research failed: \(error.localizedDescription)", timestamp: Date(), mode: .research)
            messages.append(errorMsg)
        }
    }

    // MARK: - Recall Mode
    private func performRecall(query: String) async {
        do {
            // VectorDatabase.search returns [VectorSearchResult] with entityUUID (String?)
            let vectorResults = try await VectorDatabase.shared.search(query: query, limit: 8, minSimilarity: 0.3)
            let keywordResults = try await AtomRepository.shared.search(query: query, limit: 8)

            var seen = Set<String>()
            var results: [RecallResult] = []

            for vr in vectorResults {
                if let uuid = vr.entityUUID, !seen.contains(uuid) {
                    seen.insert(uuid)
                    if let atom = try await AtomRepository.shared.fetch(uuid: uuid) {
                        results.append(RecallResult(atom: atom, similarity: vr.similarity, source: "vector"))
                    }
                }
            }
            for atom in keywordResults {
                if !seen.contains(atom.uuid) {
                    seen.insert(atom.uuid)
                    results.append(RecallResult(atom: atom, similarity: nil, source: "keyword"))
                }
            }

            let response = AIMessage(
                role: .assistant,
                content: "Found \(results.count) related items in your knowledge base.",
                timestamp: Date(),
                mode: .recall,
                recallResults: results
            )
            messages.append(response)
        } catch {
            let errorMsg = AIMessage(role: .assistant, content: "Recall failed: \(error.localizedDescription)", timestamp: Date(), mode: .recall)
            messages.append(errorMsg)
        }
    }

    // MARK: - Act Mode
    private func performAct(query: String) async {
        let q = query.lowercased()

        do {
            if q.contains("create a note") || q.contains("make a note") {
                let content = extractContent(from: query, removing: ["create a note about", "make a note about"])
                let atom = try await AtomRepository.shared.create(type: .idea, title: content, body: content)

                let result = ActionResult(description: "Created note: \(content)", createdAtomId: atom.id, createdAtomType: .note)
                let response = AIMessage(
                    role: .assistant,
                    content: "Created note: \(content)",
                    timestamp: Date(),
                    mode: .act,
                    actionResults: [result]
                )
                messages.append(response)
            } else if q.contains("should i work on") || q.contains("what should i") {
                let recommendations = try await TaskRecommendationEngine.shared.getRecommendations(
                    currentEnergy: 70,
                    currentFocus: 70,
                    limit: 3
                )
                var text = ""
                if let primary = recommendations.primary {
                    text = "Top recommendation: \(primary.task.title)\n"
                    if !recommendations.alternatives.isEmpty {
                        text += "\nAlternatives:\n"
                        for alt in recommendations.alternatives {
                            text += "- \(alt.task.title)\n"
                        }
                    }
                } else {
                    text = "No pending tasks found."
                }
                let response = AIMessage(role: .assistant, content: text, timestamp: Date(), mode: .act)
                messages.append(response)
            } else {
                let response = AIMessage(
                    role: .assistant,
                    content: "Available actions:\n- Create a note about [topic]\n- What should I work on?\n- Summarize my research on [topic]",
                    timestamp: Date(),
                    mode: .act
                )
                messages.append(response)
            }
        } catch {
            let errorMsg = AIMessage(role: .assistant, content: "Action failed: \(error.localizedDescription)", timestamp: Date(), mode: .act)
            messages.append(errorMsg)
        }
    }

    // MARK: - Auto-Surface Related
    private func autoSurfaceRelated(query: String) async {
        do {
            let results = try await VectorDatabase.shared.search(query: query, limit: 3, minSimilarity: 0.4)
            for result in results {
                if let uuid = result.entityUUID,
                   !surfacedAtoms.contains(where: { $0.uuid == uuid }) {
                    if let atom = try await AtomRepository.shared.fetch(uuid: uuid) {
                        surfacedAtoms.append(atom)
                    }
                }
            }
        } catch {
            // Silent failure for suggestions
        }
    }

    // MARK: - Context Loading
    func loadConnectedContext() {
        Task {
            do {
                let edges = try await GraphQueryEngine().getEdges(for: atom.uuid)
                var sources: [ContextSource] = []
                var uuids: [String] = []

                for edge in edges.prefix(10) {
                    let connectedUUID = edge.sourceUUID == atom.uuid ? edge.targetUUID : edge.sourceUUID
                    if let connectedAtom = try await AtomRepository.shared.fetch(uuid: connectedUUID) {
                        let entityType = EntityType(rawValue: connectedAtom.type.rawValue) ?? .idea
                        sources.append(ContextSource(
                            id: connectedAtom.uuid,
                            title: connectedAtom.title ?? "Untitled",
                            type: entityType,
                            bodyPreview: String((connectedAtom.body ?? "").prefix(200))
                        ))
                        uuids.append(connectedUUID)
                    }
                }

                self.contextSources = sources
                self.connectedAtomUUIDs = uuids
            } catch {
                print("Failed to load connected context: \(error)")
            }
        }
    }

    // MARK: - Persistence
    private func loadConversationHistory() {
        guard let structured = atom.structured,
              let data = structured.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messagesArray = json["messages"] as? [[String: Any]] else { return }

        messages = messagesArray.compactMap { dict in
            guard let roleStr = dict["role"] as? String,
                  let role = MessageRole(rawValue: roleStr),
                  let content = dict["content"] as? String,
                  let modeStr = dict["mode"] as? String,
                  let mode = CosmoMode(rawValue: modeStr) else { return nil }
            let timestamp = (dict["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
            return AIMessage(role: role, content: content, timestamp: timestamp, mode: mode)
        }
    }

    private func saveConversationHistory() {
        let messagesArray: [[String: Any]] = messages.suffix(50).map { msg in
            [
                "role": msg.role.rawValue,
                "content": msg.content,
                "mode": msg.mode.rawValue,
                "timestamp": msg.timestamp.timeIntervalSince1970
            ]
        }

        let json: [String: Any] = ["messages": messagesArray]
        if let data = try? JSONSerialization.data(withJSONObject: json),
           let jsonString = String(data: data, encoding: .utf8) {
            Task {
                var updatedAtom = atom
                updatedAtom.structured = jsonString
                _ = try? await AtomRepository.shared.update(updatedAtom)
            }
        }
    }

    // MARK: - Pin / Unpin Atom
    func pinAtom(_ atom: Atom) {
        if !surfacedAtoms.contains(where: { $0.uuid == atom.uuid }) {
            surfacedAtoms.append(atom)
        }
    }

    func unpinAtom(_ atom: Atom) {
        surfacedAtoms.removeAll { $0.uuid == atom.uuid }
    }

    // MARK: - Helpers
    private func extractContent(from query: String, removing prefixes: [String]) -> String {
        var result = query
        for prefix in prefixes {
            if result.lowercased().hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return result.isEmpty ? query : result
    }
}
