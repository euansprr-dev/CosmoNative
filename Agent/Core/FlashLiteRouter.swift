import Foundation

/// Routes Telegram messages to direct tool execution via Gemini Flash-Lite classification.
/// Replaces keyword-based intent classification for simple single-shot operations.
/// Complex operations (drafting, brainstorming, strategy) fall through to the full agent.
final class FlashLiteRouter {
    static let shared = FlashLiteRouter()

    private let model = "google/gemini-3.1-flash-lite-preview"

    static func shouldForceAgentFallback(_ text: String) -> Bool {
        ExplicitLessonCaptureParser.shouldForceAgentFallback(text)
    }

    private let systemPrompt = """
    You route Telegram messages to tools. Return ONLY valid JSON, no markdown.

    TOOLS:
    - capture_to_inbox(text, title?) — capture a general thought, note, observation, or reflection to the inbox for triage. Use ONLY for non-actionable musings, journal-like reflections, or "save this to my inbox". Do NOT use for anything the user frames as an "idea" — those MUST use create_idea instead.
    - capture_swipe(url, hook?, notes?, clientName?) — save URL as swipe file
    - capture_swipe_with_idea(url, title?, ideaContext?, clientName?, hook?) — save URL + create linked idea. Use title for user-specified idea name
    - capture_research(title, url?, body?) — save research/bookmark
    - create_idea(title, body?) — new idea
    - create_task(title, intent?, dueDate?, priority?) — new task
    - create_block(title, startTime, endTime, intent?) — schedule time block
    - create_content(title, platform?, clientName?) — new content piece
    - search_ideas(query, limit?) — find ideas
    - search_swipes(query, limit?) — find swipes
    - list_all_swipes(limit?) — browse all swipes
    - search_by_client(clientName, entityType?) — find items for client
    - get_calendar_blocks(date?) — show schedule (date format: YYYY-MM-DD)
    - get_content_pipeline(phase?) — content status
    - get_swipe_stats() — swipe library stats
    - get_unscheduled_tasks() — unscheduled tasks
    - filter_swipes_by_taxonomy(hookType?, frameworkType?, emotion?, platform?, format?)
    - find_similar_swipes(query, limit?)
    - advance_pipeline_phase(uuid, notes?) — move content forward
    - update_idea(uuid, title?, body?, status?) — modify idea
    - complete_block(uuid) — mark block done
    - delete_block(uuid) — remove block

    If the message maps to ONE tool call, return:
    {"action":"tool_call","toolName":"...","arguments":{...},"clientName":"name or null","metadata":{"format":"reel|thread|carousel|post|longForm|youtube|newsletter or null","platform":"youtube|instagram|x|threads|linkedin|tiktok|newsletter or null"}}

    If the message contains MULTIPLE URLs to capture, return:
    {"action":"multi_capture","urls":["url1","url2"],"clientName":"name or null"}

    If the message contains MULTIPLE items to create (numbered lists, comma-separated ideas, multiple tasks), return:
    {"action":"multi_create","items":[{"toolName":"create_idea","arguments":{"title":"exact title 1"}},{"toolName":"create_idea","arguments":{"title":"exact title 2"}}],"clientName":"name or null","metadata":{"format":"reel|thread|etc or null","platform":"instagram|youtube|etc or null"}}

    If the message needs multi-turn reasoning (drafting, brainstorming, rewriting, revision, strategy, analysis, feedback, complex questions, conversation), return:
    {"action":"agent"}

    RULES:
    - PRESERVE titles EXACTLY as the user wrote them. Never paraphrase, shorten, or interpret placeholders like $X, $5K, etc. Copy verbatim.
    - Numbered lists of ideas/tasks → multi_create (one item per list entry)
    - "Some ideas for [client]:" followed by a list → multi_create with clientName
    - Extract client names from context ("for josh" → clientName: "josh")
    - Extract format/platform mentions into metadata
    - For idea+URL combos, use capture_swipe_with_idea. When the user says "called", "named", or "titled" followed by a phrase, that phrase is the TITLE parameter — extract it verbatim into "title", not "ideaContext"
    - Dates: "tomorrow" → next day ISO, "today" → current date
    - If the user says "idea", "idea for", "idea about", or anything framed as an idea → ALWAYS use create_idea, NEVER capture_to_inbox
    - If ambiguous, prefer "agent"
    - capture_swipe and capture_swipe_with_idea REQUIRE a URL in the message. If no URL is present, do NOT use capture tools.
    - If the message references taking action on, creating content from, or writing based on an existing idea or swipe, return {"action":"agent"}
    - If the message gives creative direction (hook style, content adaptation, "make the hook like...", "similar to..."), return {"action":"agent"}
    - If the message uses referential language ("this idea", "that swipe", "using the") about previously discussed items, return {"action":"agent"}
    - If the message asks to save a lesson, remember a rule, learn something for future reference, or store a writing principle, return {"action":"agent"}
    """

    // MARK: - Route

    /// Attempts to route a message to a direct tool call via Flash-Lite classification.
    /// Returns (response, toolName) if handled, nil if the message needs the full agent.
    func tryRoute(_ text: String) async -> (response: String, toolName: String)? {
        // Explicit inbox prefix — zero latency, no LLM needed
        if let inboxText = extractInboxPrefix(text) {
            return await executeInboxCapture(arguments: ["text": inboxText])
        }

        if Self.shouldForceAgentFallback(text) {
            return nil
        }

        do {
            let response = try await ResearchService.shared.analyze(
                prompt: text,
                systemPrompt: systemPrompt,
                model: model,
                maxTokens: 1024,
                temperature: 0.0
            )

            let cleaned = stripCodeFences(response)
            guard let data = cleaned.data(using: .utf8) else { return nil }

            // Parse the route decision
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let action = json["action"] as? String else {
                return nil
            }

            switch action {
            case "tool_call":
                return await executeToolCall(json: json)
            case "multi_capture":
                return await executeMultiCapture(json: json)
            case "multi_create":
                return await executeMultiCreate(json: json)
            default:
                // "agent" or unknown → fall through
                return nil
            }
        } catch {
            // LLM call failed (timeout, API down, no key) → fall through to agent
            print("[FlashLiteRouter] Classification failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Tool Execution

    private func executeToolCall(json: [String: Any]) async -> (response: String, toolName: String)? {
        guard let toolName = json["toolName"] as? String else { return nil }
        var arguments = json["arguments"] as? [String: Any] ?? [:]

        // Inbox capture — handled directly, not via AgentToolExecutor
        if toolName == "capture_to_inbox" {
            return await executeInboxCapture(arguments: arguments)
        }

        let clientName = json["clientName"] as? String
        let metadata = json["metadata"] as? [String: Any]

        // Inject clientName into arguments for tools that accept it
        if let client = clientName, !client.isEmpty {
            if ["capture_swipe", "capture_swipe_with_idea", "create_content", "search_by_client"].contains(toolName) {
                arguments["clientName"] = client
            }
        }

        // Execute the tool
        let result: String
        do {
            result = try await AgentToolExecutor.shared.execute(toolName: toolName, arguments: arguments)
        } catch {
            return nil // Tool execution failed → fall through to agent
        }

        // Post-creation: link to client + set metadata for idea tools
        if toolName == "create_idea" {
            await postProcessIdea(result: result, clientName: clientName, metadata: metadata)
        }

        // Format response
        let formatted = formatResponse(toolName: toolName, result: result, arguments: arguments, clientName: clientName, metadata: metadata)
        return (formatted, toolName)
    }

    private func executeMultiCapture(json: [String: Any]) async -> (response: String, toolName: String)? {
        guard let urls = json["urls"] as? [String], !urls.isEmpty else { return nil }

        var captured: [String] = []
        var failed = 0

        for url in urls {
            do {
                let result = try await AgentToolExecutor.shared.execute(
                    toolName: "capture_swipe",
                    arguments: ["url": url]
                )
                if let data = result.data(using: .utf8),
                   let resultJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   resultJSON["success"] as? Bool == true {
                    let source = resultJSON["source"] as? String ?? "URL"
                    captured.append(source)
                } else {
                    failed += 1
                }
            } catch {
                failed += 1
            }
        }

        guard !captured.isEmpty else {
            return ("Failed to capture \(urls.count == 1 ? "the link" : "any of the links").", "capture_swipe")
        }

        let platformName: (String) -> String = { source in
            source.contains("youtube") ? "YouTube" :
            source.contains("instagram") ? "Instagram" :
            source.contains("twitter") || source.contains("x.com") ? "X" :
            source.contains("threads") ? "Threads" :
            source.contains("tiktok") ? "TikTok" : "Link"
        }

        if captured.count == 1 {
            return ("Captured \(platformName(captured[0])) swipe.", "capture_swipe")
        } else {
            let summary = captured.map { platformName($0) }.joined(separator: ", ")
            var msg = "Captured \(captured.count) swipes: \(summary)"
            if failed > 0 { msg += " (\(failed) failed)" }
            return (msg, "capture_swipe")
        }
    }

    private func executeMultiCreate(json: [String: Any]) async -> (response: String, toolName: String)? {
        guard let items = json["items"] as? [[String: Any]], !items.isEmpty else { return nil }

        let clientName = json["clientName"] as? String
        let metadata = json["metadata"] as? [String: Any]
        var created: [String] = []
        var failed = 0

        for item in items {
            guard let toolName = item["toolName"] as? String,
                  var arguments = item["arguments"] as? [String: Any] else {
                failed += 1
                continue
            }

            // Inject clientName for tools that accept it
            if let client = clientName, !client.isEmpty,
               ["create_idea", "create_content", "create_task"].contains(toolName) {
                arguments["clientName"] = client
            }

            do {
                let result = try await AgentToolExecutor.shared.execute(toolName: toolName, arguments: arguments)

                // Post-process ideas (client linking, metadata)
                if toolName == "create_idea" {
                    await postProcessIdea(result: result, clientName: clientName, metadata: metadata)
                }

                let title = arguments["title"] as? String ?? "Untitled"
                created.append(title)
            } catch {
                failed += 1
            }
        }

        guard !created.isEmpty else {
            return ("Failed to create items.", "multi_create")
        }

        // Format consolidated response
        let clientTag = clientName.map { " for \($0)" } ?? ""
        var lines: [String] = ["Saved \(created.count) idea\(created.count == 1 ? "" : "s")\(clientTag):"]
        for (i, title) in created.enumerated() {
            lines.append("\(i + 1). \"\(title)\"")
        }
        if failed > 0 { lines.append("(\(failed) failed)") }
        return (lines.joined(separator: "\n"), "multi_create")
    }

    // MARK: - Inbox Capture

    /// Detects `inbox:` or `inbox ` prefix for zero-latency inbox capture.
    private func extractInboxPrefix(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        for prefix in ["inbox:", "inbox "] {
            if lower.hasPrefix(prefix) {
                let content = String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                return content.isEmpty ? nil : content
            }
        }
        return nil
    }

    @MainActor
    private func executeInboxCapture(arguments: [String: Any]) async -> (response: String, toolName: String)? {
        let text = arguments["text"] as? String ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ("Nothing to capture.", "capture_to_inbox")
        }

        let userTitle = arguments["title"] as? String

        // Create inbox item
        let item = InboxItem.new(
            source: .telegramText,
            rawText: text,
            title: userTitle
        )

        do {
            let saved = try await InboxRepository.shared.create(item)

            // Classify asynchronously
            let classification = await InboxClassificationEngine.shared.classify(
                text: text,
                source: .telegramText
            )

            try await InboxRepository.shared.updateClassification(
                uuid: saved.uuid,
                classification: classification.classification,
                confidence: classification.confidence,
                title: classification.title,
                mergeTargetUuid: classification.mergeTarget?.atomUuid,
                mergeTargetTitle: classification.mergeTarget?.atomTitle,
                mergeTargetType: classification.mergeTarget?.atomType,
                mergePreview: classification.mergeTarget?.preview,
                placeThinkspaceId: classification.placeTarget?.thinkspaceId,
                placeThinkspaceName: classification.placeTarget?.thinkspaceName,
                placeAtomType: classification.placeTarget?.suggestedAtomType
            )

            // Build response
            let title = classification.title
            var response = "📥 *Captured to inbox*\n\"\(title)\""
            switch classification.classification {
            case .merge:
                if let target = classification.mergeTarget {
                    let pct = Int(classification.confidence * 100)
                    response += "\n\nAI suggests: *Merge with* \"\(target.atomTitle)\" (\(pct)%)"
                }
            case .place:
                if let target = classification.placeTarget {
                    response += "\n\nAI suggests: *Place in* \(target.thinkspaceName)"
                }
            case .new:
                response += "\n\nAI suggests: *Create new*"
            }
            response += "\nOpen CosmoOS to confirm."

            return (response, "capture_to_inbox")
        } catch {
            print("⚠️ [FlashLiteRouter] Inbox capture failed: \(error)")
            return ("Captured thought, but classification failed. Check inbox.", "capture_to_inbox")
        }
    }

    // MARK: - Post-Processing

    private func postProcessIdea(result: String, clientName: String?, metadata: [String: Any]?) async {
        // Extract UUID from tool result
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uuid = json["uuid"] as? String else { return }

        let repo = AtomRepository.shared

        // Resolve client atom if specified
        var resolvedClientAtom: Atom?
        if let client = clientName, !client.isEmpty {
            resolvedClientAtom = try? await repo.fuzzyFindClient(query: client)
        }

        let formatStr = (metadata?["format"] as? String)
        let platformStr = (metadata?["platform"] as? String)
        let hasClientOrMetadata = resolvedClientAtom != nil || formatStr != nil || platformStr != nil

        guard hasClientOrMetadata else { return }

        _ = try? await repo.update(uuid: uuid) { atom in
            // Add client link
            if let clientAtom = resolvedClientAtom {
                let link = AtomLink(type: AtomLinkType.ideaToClient.rawValue, uuid: clientAtom.uuid, entityType: "clientProfile")
                let updated = atom.addingLink(link)
                atom.links = updated.links
            }

            // Set metadata: clientUUID + format + platform
            var ideaMeta = atom.ideaMetadata ?? IdeaMetadata()
            ideaMeta.ideaStatus = ideaMeta.ideaStatus ?? .spark
            if let clientAtom = resolvedClientAtom {
                ideaMeta.clientUUID = clientAtom.uuid
            }
            if let f = formatStr {
                ideaMeta.contentFormat = ContentFormat(rawValue: f)
            }
            if let p = platformStr {
                ideaMeta.platform = IdeaPlatform(rawValue: p)
            }
            if let encoded = try? JSONEncoder().encode(ideaMeta),
               let str = String(data: encoded, encoding: .utf8) {
                atom.metadata = str
            }
        }
    }

    // MARK: - Response Formatting

    private func formatResponse(toolName: String, result: String, arguments: [String: Any], clientName: String?, metadata: [String: Any]?) -> String {
        let resultJSON = parseJSON(result)

        switch toolName {
        // Creation tools — short confirmations
        case "create_idea":
            let title = arguments["title"] as? String ?? "Untitled"
            let client = clientName.map { " for \($0)" } ?? ""
            var extras: [String] = []
            if let f = metadata?["format"] as? String { extras.append(f.capitalized) }
            if let p = metadata?["platform"] as? String { extras.append(p.capitalized) }
            let extraNote = extras.isEmpty ? "" : " [\(extras.joined(separator: ", "))]"
            return "Saved idea\(client): \"\(title)\"\(extraNote)"

        case "capture_swipe":
            let source = resultJSON?["source"] as? String ?? ""
            let title = resultJSON?["title"] as? String
            let platform = source.contains("youtube") ? "YouTube" :
                           source.contains("instagram") ? "Instagram" :
                           source.contains("twitter") || source.contains("x.com") ? "X" :
                           source.contains("threads") ? "Threads" :
                           source.contains("tiktok") ? "TikTok" : "Link"
            if let t = title, !t.isEmpty {
                return "Captured \(platform) swipe: \(t)"
            }
            return "Captured \(platform) swipe."

        case "capture_swipe_with_idea":
            let source = resultJSON?["source"] as? String ?? "Link"
            let ideaTitle = resultJSON?["ideaTitle"] as? String
            let platform = source.contains("youtube") ? "YouTube" :
                           source.contains("instagram") ? "Instagram" : source
            var msg = "Captured \(platform) swipe"
            if let t = ideaTitle { msg += " + idea: \"\(t)\"" }
            return msg

        case "capture_research":
            let title = arguments["title"] as? String ?? "Research"
            return "Saved research: \"\(title)\""

        case "create_task":
            let title = arguments["title"] as? String ?? "Task"
            return "Task created: \"\(title)\""

        case "create_block":
            let title = arguments["title"] as? String ?? "Block"
            return "Scheduled: \"\(title)\""

        case "create_content":
            let title = arguments["title"] as? String ?? "Content"
            let client = clientName.map { " for \($0)" } ?? ""
            return "Content created\(client): \"\(title)\""

        case "advance_pipeline_phase":
            return resultJSON?["message"] as? String ?? "Pipeline advanced."

        case "update_idea":
            return "Idea updated."

        case "complete_block":
            return "Block completed."

        case "delete_block":
            return "Block deleted."

        // Query tools — format the data
        case "search_ideas", "search_swipes", "list_all_swipes", "search_by_client",
             "filter_swipes_by_taxonomy", "find_similar_swipes":
            return formatSearchResults(toolName: toolName, result: result)

        case "get_calendar_blocks":
            return formatCalendarBlocks(result: result)

        case "get_content_pipeline":
            return formatPipeline(result: result)

        case "get_swipe_stats":
            return resultJSON?["summary"] as? String ?? result

        case "get_unscheduled_tasks":
            return formatTaskList(result: result)

        default:
            // Unknown tool — return raw result truncated
            let clean = result.prefix(500)
            return String(clean)
        }
    }

    // MARK: - Query Result Formatters

    private func formatSearchResults(toolName: String, result: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return result
        }

        let items = json["results"] as? [[String: Any]] ?? json["ideas"] as? [[String: Any]] ?? json["swipes"] as? [[String: Any]] ?? []

        if items.isEmpty {
            return "No results found."
        }

        var lines: [String] = []
        let entityType = toolName.contains("idea") ? "idea" : toolName.contains("swipe") ? "swipe" : "item"
        lines.append("Found \(items.count) \(entityType)\(items.count == 1 ? "" : "s"):")
        for (i, item) in items.prefix(10).enumerated() {
            let title = item["title"] as? String ?? "Untitled"
            let status = item["status"] as? String
            let statusTag = status.map { " [\($0)]" } ?? ""
            lines.append("\(i + 1). \(title)\(statusTag)")
        }
        if items.count > 10 {
            lines.append("... and \(items.count - 10) more")
        }
        return lines.joined(separator: "\n")
    }

    private func formatCalendarBlocks(result: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return result
        }

        let blocks = json["blocks"] as? [[String: Any]] ?? []
        if blocks.isEmpty {
            return "No blocks scheduled."
        }

        var lines: [String] = ["Schedule:"]
        for block in blocks {
            let title = block["title"] as? String ?? "Block"
            let start = block["startTime"] as? String ?? ""
            let end = block["endTime"] as? String ?? ""
            // Extract just the time portion
            let startTime = extractTime(from: start)
            let endTime = extractTime(from: end)
            lines.append("  \(startTime)–\(endTime): \(title)")
        }
        return lines.joined(separator: "\n")
    }

    private func formatPipeline(result: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return result
        }

        let phases = json["phases"] as? [[String: Any]] ?? []
        if phases.isEmpty {
            return "Content pipeline is empty."
        }

        var lines: [String] = ["Content Pipeline:"]
        for phase in phases {
            let name = phase["name"] as? String ?? "Phase"
            let items = phase["items"] as? [[String: Any]] ?? []
            if !items.isEmpty {
                lines.append("\n\(name) (\(items.count)):")
                for item in items.prefix(5) {
                    let title = item["title"] as? String ?? "Untitled"
                    lines.append("  - \(title)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private func formatTaskList(result: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return result
        }

        let tasks = json["tasks"] as? [[String: Any]] ?? []
        if tasks.isEmpty { return "No unscheduled tasks." }

        var lines: [String] = ["Unscheduled tasks:"]
        for task in tasks.prefix(10) {
            let title = task["title"] as? String ?? "Task"
            let priority = task["priority"] as? String
            let tag = priority.map { " [\($0)]" } ?? ""
            lines.append("- \(title)\(tag)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func stripCodeFences(_ response: String) -> String {
        var s = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let idx = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: idx)...])
            }
            if s.hasSuffix("```") {
                s = String(s.dropLast(3))
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseJSON(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func extractTime(from isoString: String) -> String {
        // Try to extract HH:mm from ISO or time string
        if let tIdx = isoString.firstIndex(of: "T") {
            let timeStr = String(isoString[isoString.index(after: tIdx)...])
            let parts = timeStr.components(separatedBy: ":")
            if parts.count >= 2 {
                return "\(parts[0]):\(parts[1])"
            }
        }
        // Fallback: return as-is
        return isoString
    }
}
