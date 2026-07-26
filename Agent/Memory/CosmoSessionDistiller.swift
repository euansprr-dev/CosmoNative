// CosmoOS/Agent/Memory/CosmoSessionDistiller.swift
// Turns finished inline-assistant sessions into durable memory: when a session
// goes idle, one cheap Haiku call reads the turn ledger and extracts 0–3 facts
// worth keeping ("wants slide headers bolded and numbered", "Marcus's audience
// is first-time landlords"). Facts land in archival memory, embedding-deduped,
// and come back through recall on future requests. Never blocks a request;
// failures are silent.

import AppKit
import Foundation

@MainActor
final class CosmoSessionDistiller {
    static let shared = CosmoSessionDistiller()

    /// Minimum NEW turns since the last distillation before another run.
    private let minimumNewTurns = 3

    private var distilledTurnCounts: [String: Int] = [:]
    private var inFlightSurfaceIDs: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// Call once at app start: distills the active session whenever the app
    /// resigns active (the natural "session over for now" signal).
    func activate(store: CosmoInlineAssistantStore = .shared) {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak store] _ in
            guard let self, let store else { return }
            MainActor.assumeIsolated {
                self.distillIfWorthwhile(
                    sessionKey: store.activeSessionSurfaceIDForDistillation,
                    ledger: store.sessionLedger
                )
            }
        })
    }

    /// Fire-and-forget: extracts durable facts from the ledger when the session
    /// accumulated enough new work since the last distillation.
    func distillIfWorthwhile(sessionKey: String, ledger: [CosmoInlineTurnRecord]) {
        let alreadyDistilled = distilledTurnCounts[sessionKey] ?? 0
        guard ledger.count - alreadyDistilled >= minimumNewTurns,
              !inFlightSurfaceIDs.contains(sessionKey) else {
            return
        }
        guard let ledgerBlock = CosmoInlineSessionLedger.promptBlock(records: ledger) else { return }

        inFlightSurfaceIDs.insert(sessionKey)
        let turnCount = ledger.count

        Task(priority: .utility) { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.inFlightSurfaceIDs.remove(sessionKey)
                }
            }

            // A failed call (network, provider, auth) must NOT mark these
            // turns distilled — leaving the count untouched retries them on
            // the next natural trigger. Only a real "nothing durable here"
            // verdict advances the watermark.
            guard let response = try? await CosmoAgentService.shared.summarize(
                messages: [.user(Self.distillationPrompt(ledgerBlock: ledgerBlock))],
                tier: .sensor
            ) else {
                return
            }
            let facts = Self.parseFacts(from: response)
            guard !facts.isEmpty else {
                await MainActor.run { [weak self] in
                    self?.distilledTurnCounts[sessionKey] = turnCount
                }
                return
            }

            var savedCount = 0
            for fact in facts.prefix(3) {
                if await CosmoMemoryService.shared.addArchivalMemoryIfNovel(fact) {
                    savedCount += 1
                }
            }
            if savedCount > 0 {
                print("🧠 [Distiller] saved \(savedCount) durable fact(s) from session \(sessionKey)")
            }

            await MainActor.run { [weak self] in
                self?.distilledTurnCounts[sessionKey] = turnCount
            }
        }
    }

    // MARK: - Prompt

    static func distillationPrompt(ledgerBlock: String) -> String {
        """
        Below is the log of one working session between a user and their inline writing assistant.
        Extract at most 3 DURABLE facts worth remembering across future sessions.

        A durable fact is one of:
        - a stable preference about how the user wants work done (e.g. "Wants slide headers bolded and numbered sequentially")
        - a stable fact about a client, audience, or project (e.g. "Marcus's audience is first-time landlords")
        - a correction the user made that must not be repeated (e.g. "Never rewrite the user's hook wording when asked to only reformat")

        NOT durable — never output these:
        - one-off task details ("edited slide 4 today")
        - the specific text of this session's edits
        - anything the documents themselves already state

        Write each fact on its own line starting with "- ", phrased as a standalone statement that makes sense with no session context.
        If nothing qualifies, write exactly: NONE

        <session_log>
        \(ledgerBlock)
        </session_log>
        """
    }

    static func parseFacts(from response: String) -> [String] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.uppercased() != "NONE" else { return [] }

        return trimmed
            .components(separatedBy: .newlines)
            .compactMap { line in
                let cleaned = line.trimmingCharacters(in: .whitespaces)
                guard cleaned.hasPrefix("- ") else { return nil }
                let fact = String(cleaned.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return (fact.count >= 12 && fact.count <= 300) ? fact : nil
            }
    }
}
