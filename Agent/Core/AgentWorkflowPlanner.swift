// CosmoOS/Agent/Core/AgentWorkflowPlanner.swift
// Multi-step workflow planning and execution for complex agent requests

import Foundation

@MainActor
class AgentWorkflowPlanner {
    static let shared = AgentWorkflowPlanner()

    private let toolExecutor = AgentToolExecutor.shared

    /// Active workflows keyed by conversation/chat ID
    var activeWorkflows: [String: WorkflowPlan] = [:]

    /// Progress callback: (chatId, stepIndex, totalSteps, message) -> Void
    var onStepProgress: ((String, Int, Int, String) async -> Void)?

    /// Confirmation callback: (chatId, stepDescription) -> Void
    /// Called when a step requires user confirmation before proceeding.
    var onConfirmationNeeded: ((String, String) async -> Void)?

    private init() {}

    // MARK: - Plan Workflow

    /// Use the LLM to decompose a complex request into ordered WorkflowSteps.
    func planWorkflow(
        request: String,
        conversation: AgentConversation,
        provider: LLMProvider,
        model: String
    ) async -> WorkflowPlan {
        let systemPrompt = buildPlanningPrompt()

        // Build context from conversation history (last 10 messages for planning context)
        var contextSnippet = ""
        let recentMessages = conversation.messages.suffix(10)
        for msg in recentMessages {
            let role = msg.role == .user ? "User" : "Assistant"
            let preview = String(msg.content.prefix(300))
            contextSnippet += "\(role): \(preview)\n"
        }

        let userPrompt = """
        CONVERSATION CONTEXT:
        \(contextSnippet)

        USER REQUEST:
        \(request)

        Decompose this request into a workflow plan. Return ONLY valid JSON.
        """

        let messages: [AgentMessage] = [
            .system(systemPrompt),
            .user(userPrompt)
        ]

        do {
            let response = try await provider.complete(
                messages: messages,
                tools: nil,
                model: model
            )

            let content = response.content ?? ""
            return parseWorkflowPlan(from: content, originalRequest: request)
        } catch {
            // On failure, return a single-step fallback plan
            let fallbackStep = WorkflowStep(
                index: 0,
                action: "direct_execution",
                description: "Execute the request directly: \(request)",
                tools: [],
                confirmationRequired: false
            )
            return WorkflowPlan(
                summary: "Fallback: execute request directly (planning failed: \(error.localizedDescription))",
                steps: [fallbackStep]
            )
        }
    }

    // MARK: - Execute Workflow

    /// Execute an approved workflow plan step by step.
    /// Mutates the plan in place and returns a final summary string.
    func executeWorkflow(_ plan: inout WorkflowPlan, chatId: String?) async -> String {
        let workflowId = chatId ?? plan.id
        plan.status = .executing
        activeWorkflows[workflowId] = plan

        var results: [String] = []
        let totalSteps = plan.steps.count

        for i in 0..<plan.steps.count {
            // Check if the workflow was cancelled externally
            if let active = activeWorkflows[workflowId], active.status == .cancelled {
                plan.status = .cancelled
                results.append("Workflow cancelled at step \(i + 1).")
                break
            }

            plan.steps[i].status = .running
            activeWorkflows[workflowId] = plan

            // Report progress
            let progressMessage = "Step \(i + 1)/\(totalSteps): \(plan.steps[i].description)"
            if let chatId = chatId {
                await onStepProgress?(chatId, i + 1, totalSteps, progressMessage)
            }

            // Check for confirmation requirement
            if plan.steps[i].confirmationRequired {
                plan.steps[i].status = .awaitingConfirmation
                plan.status = .paused
                activeWorkflows[workflowId] = plan

                if let chatId = chatId {
                    await onConfirmationNeeded?(chatId, plan.steps[i].description)
                }

                // Wait for external approval (the caller must call resumeWorkflow)
                results.append("Paused at step \(i + 1) -- awaiting confirmation: \(plan.steps[i].description)")
                return results.joined(separator: "\n")
            }

            // Execute the step
            let (success, output) = await executeStep(plan.steps[i])

            if success {
                plan.steps[i].status = .completed
                results.append("Step \(i + 1) completed: \(plan.steps[i].action) -- \(output)")
            } else {
                plan.steps[i].status = .failed
                plan.status = .paused
                activeWorkflows[workflowId] = plan
                results.append("Step \(i + 1) FAILED: \(plan.steps[i].action) -- \(output)")
                results.append("Workflow paused due to failure. You can retry or cancel.")
                return results.joined(separator: "\n")
            }

            activeWorkflows[workflowId] = plan
        }

        // All steps done
        if plan.isComplete {
            plan.status = .completed
            activeWorkflows.removeValue(forKey: workflowId)
        }

        let summary = buildExecutionSummary(plan: plan, results: results)
        return summary
    }

    // MARK: - Execute Single Step

    /// Execute a single workflow step by calling the appropriate tools.
    func executeStep(_ step: WorkflowStep) async -> (success: Bool, output: String) {
        guard !step.tools.isEmpty else {
            // No tools specified -- step is informational or manual
            return (true, "No tools to execute for this step.")
        }

        var outputs: [String] = []
        var allSucceeded = true

        for toolName in step.tools {
            // Build arguments from the step description context
            let arguments = buildToolArguments(toolName: toolName, stepDescription: step.description)

            do {
                let result = try await toolExecutor.execute(toolName: toolName, arguments: arguments)

                // Check if the tool returned an error
                if let data = result.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String {
                    outputs.append("\(toolName): ERROR -- \(error)")
                    allSucceeded = false
                } else {
                    outputs.append("\(toolName): OK")

                    // Extract key info from result for summary
                    if let data = result.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let message = json["message"] as? String {
                            outputs.append("  -> \(message)")
                        }
                        if let uuid = json["uuid"] as? String {
                            outputs.append("  -> UUID: \(uuid)")
                        }
                    }
                }
            } catch {
                outputs.append("\(toolName): EXCEPTION -- \(error.localizedDescription)")
                allSucceeded = false
            }
        }

        return (allSucceeded, outputs.joined(separator: "\n"))
    }

    // MARK: - Resume / Cancel

    /// Resume a paused workflow after user confirms a step.
    func resumeWorkflow(workflowId: String) async -> String? {
        guard var plan = activeWorkflows[workflowId] else { return nil }

        // Find the step that was awaiting confirmation and mark it as running
        if let pausedIndex = plan.steps.firstIndex(where: { $0.status == .awaitingConfirmation }) {
            plan.steps[pausedIndex].status = .pending
        }

        plan.status = .executing
        activeWorkflows[workflowId] = plan

        return await executeWorkflow(&plan, chatId: workflowId)
    }

    /// Cancel an active workflow.
    func cancelWorkflow(workflowId: String) {
        if var plan = activeWorkflows[workflowId] {
            plan.status = .cancelled
            // Mark remaining pending steps as skipped
            for i in 0..<plan.steps.count {
                if plan.steps[i].status == .pending || plan.steps[i].status == .awaitingConfirmation {
                    plan.steps[i].status = .skipped
                }
            }
            activeWorkflows.removeValue(forKey: workflowId)
        }
    }

    /// Skip the current step in a paused workflow and continue.
    func skipCurrentStep(workflowId: String) async -> String? {
        guard var plan = activeWorkflows[workflowId] else { return nil }

        if let pausedIndex = plan.steps.firstIndex(where: {
            $0.status == .awaitingConfirmation || $0.status == .failed
        }) {
            plan.steps[pausedIndex].status = .skipped
        }

        plan.status = .executing
        activeWorkflows[workflowId] = plan

        return await executeWorkflow(&plan, chatId: workflowId)
    }

    // MARK: - Telegram Formatting

    /// Format a workflow plan as a Telegram-friendly numbered list.
    func formatPlanForTelegram(_ plan: WorkflowPlan) -> String {
        var lines: [String] = []
        lines.append("WORKFLOW PLAN")
        lines.append(plan.summary)
        lines.append("")

        for step in plan.steps {
            let statusIcon: String
            switch step.status {
            case .pending: statusIcon = "[ ]"
            case .running: statusIcon = "[..]"
            case .completed: statusIcon = "[OK]"
            case .failed: statusIcon = "[X]"
            case .skipped: statusIcon = "[--]"
            case .awaitingConfirmation: statusIcon = "[??]"
            }

            let confirmTag = step.confirmationRequired ? " (requires confirmation)" : ""
            lines.append("\(step.index + 1). \(statusIcon) \(step.action)\(confirmTag)")
            lines.append("   \(step.description)")

            if !step.tools.isEmpty {
                lines.append("   Tools: \(step.tools.joined(separator: ", "))")
            }
        }

        lines.append("")
        lines.append("Steps: \(plan.steps.count) | Estimated time: ~\(plan.steps.count * 5)s")

        return lines.joined(separator: "\n")
    }

    /// Build inline keyboard buttons for Telegram plan approval.
    func telegramApprovalButtons(planId: String) -> [[[String: String]]] {
        return [
            [
                ["text": "Approve", "callback_data": "workflow_approve:\(planId)"],
                ["text": "Edit", "callback_data": "workflow_edit:\(planId)"],
                ["text": "Cancel", "callback_data": "workflow_cancel:\(planId)"]
            ]
        ]
    }

    // MARK: - Private: Planning Prompt

    private func buildPlanningPrompt() -> String {
        return """
        You are a workflow planner for CosmoOS, a creative OS. Your job is to decompose a complex \
        user request into a sequence of discrete, executable steps.

        AVAILABLE TOOLS:
        - search_ideas: Search ideas by keyword
        - get_idea: Get idea details by UUID
        - create_idea: Create a new idea
        - update_idea: Update an existing idea
        - activate_idea: Promote idea to content pipeline
        - search_swipes: Search swipe file library
        - get_swipe_analysis: Get swipe analysis details
        - find_similar_swipes: Find similar swipes
        - get_swipe_stats: Get swipe library statistics
        - capture_swipe: Capture a URL or text as swipe file
        - capture_research: Capture research/notes
        - get_content_pipeline: Get content pipeline status
        - advance_pipeline_phase: Advance content to next phase
        - create_content: Create new content piece
        - create_note: Create a new note atom/document
        - get_content: Get content details
        - create_thinkspace: Create a new thinkspace
        - get_calendar_blocks: Get schedule blocks for a date
        - create_block: Create a schedule block
        - update_block: Update a schedule block
        - delete_block: Delete a schedule block (destructive)
        - complete_block: Mark block as completed
        - get_unscheduled_tasks: Get unscheduled tasks
        - create_task: Create a new task
        - get_dimension_xp: Get dimension XP data
        - store_preference: Store a user preference
        - search_by_client: Search items for a specific client

        RULES:
        - Break the request into 3-8 steps. Each step should use 1-3 tools.
        - Order steps logically: gather data first, then create/modify, then verify.
        - Mark steps that involve deletion or significant changes as confirmationRequired: true.
        - Each step should have a clear, concise action name and a longer description.
        - Return ONLY a JSON object with this structure:

        {
          "summary": "Brief description of the overall workflow",
          "steps": [
            {
              "action": "short_action_name",
              "description": "What this step does and why",
              "tools": ["tool_name_1", "tool_name_2"],
              "confirmationRequired": false
            }
          ]
        }

        Do NOT include any text outside the JSON object. Do NOT use markdown code fences.
        """
    }

    // MARK: - Private: Parse LLM Response

    private func parseWorkflowPlan(from content: String, originalRequest: String) -> WorkflowPlan {
        // Strip markdown code fences if present
        var jsonStr = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonStr.hasPrefix("```json") {
            jsonStr = String(jsonStr.dropFirst(7))
        } else if jsonStr.hasPrefix("```") {
            jsonStr = String(jsonStr.dropFirst(3))
        }
        if jsonStr.hasSuffix("```") {
            jsonStr = String(jsonStr.dropLast(3))
        }
        jsonStr = jsonStr.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Fallback: single step
            let step = WorkflowStep(
                index: 0,
                action: "direct_execution",
                description: originalRequest,
                tools: []
            )
            return WorkflowPlan(summary: "Could not parse plan -- executing directly", steps: [step])
        }

        let summary = json["summary"] as? String ?? "Multi-step workflow"
        let rawSteps = json["steps"] as? [[String: Any]] ?? []

        var steps: [WorkflowStep] = []
        for (index, rawStep) in rawSteps.prefix(8).enumerated() {
            let action = rawStep["action"] as? String ?? "step_\(index)"
            let description = rawStep["description"] as? String ?? ""
            let tools = rawStep["tools"] as? [String] ?? []
            let confirmationRequired = rawStep["confirmationRequired"] as? Bool ?? false

            steps.append(WorkflowStep(
                index: index,
                action: action,
                description: description,
                tools: tools,
                confirmationRequired: confirmationRequired
            ))
        }

        if steps.isEmpty {
            let fallback = WorkflowStep(
                index: 0,
                action: "direct_execution",
                description: originalRequest,
                tools: []
            )
            steps = [fallback]
        }

        return WorkflowPlan(summary: summary, steps: steps)
    }

    // MARK: - Private: Build Tool Arguments

    /// Attempt to extract sensible arguments for a tool from the step description.
    /// This is a best-effort heuristic -- the LLM planning step should have provided
    /// enough context in the description for the tool executor.
    private func buildToolArguments(toolName: String, stepDescription: String) -> [String: Any] {
        var args: [String: Any] = [:]

        // Extract quoted strings as potential titles/queries
        let quotedPattern = #""([^"]+)""#
        let quotedMatches = extractMatches(pattern: quotedPattern, from: stepDescription)

        // Extract UUIDs
        let uuidPattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        let uuidMatches = extractMatches(pattern: uuidPattern, from: stepDescription)

        switch toolName {
        case "search_ideas", "search_swipes", "find_similar_swipes":
            args["query"] = quotedMatches.first ?? stepDescription
            args["limit"] = 5

        case "get_idea", "get_content", "get_swipe_analysis":
            if let uuid = uuidMatches.first {
                args["uuid"] = uuid
            }

        case "create_idea":
            args["title"] = quotedMatches.first ?? "Untitled Idea"
            if quotedMatches.count > 1 {
                args["body"] = quotedMatches[1]
            }

        case "create_task":
            args["title"] = quotedMatches.first ?? "Untitled Task"

        case "create_content":
            args["title"] = quotedMatches.first ?? "Untitled Content"

        case "create_note":
            args["title"] = quotedMatches.first ?? "Untitled Note"
            if quotedMatches.count > 1 {
                args["body"] = quotedMatches[1]
            }

        case "create_block":
            args["title"] = quotedMatches.first ?? "Untitled Block"
            // Attempt to extract ISO times from description
            let isoPattern = #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}"#
            let isoMatches = extractMatches(pattern: isoPattern, from: stepDescription)
            if isoMatches.count >= 2 {
                args["startTime"] = isoMatches[0]
                args["endTime"] = isoMatches[1]
            }

        case "update_idea", "update_block", "advance_pipeline_phase", "complete_block", "delete_block", "activate_idea":
            if let uuid = uuidMatches.first {
                args["uuid"] = uuid
            }

        case "capture_swipe":
            // Look for URLs in the description
            let urlPattern = #"https?://[^\s]+"#
            let urlMatches = extractMatches(pattern: urlPattern, from: stepDescription)
            args["url"] = urlMatches.first ?? quotedMatches.first ?? stepDescription

        case "capture_research":
            args["title"] = quotedMatches.first ?? "Research Note"
            if quotedMatches.count > 1 {
                args["body"] = quotedMatches[1]
            }

        case "get_calendar_blocks":
            // Look for date patterns
            let datePattern = #"\d{4}-\d{2}-\d{2}"#
            let dateMatches = extractMatches(pattern: datePattern, from: stepDescription)
            if let date = dateMatches.first {
                args["date"] = date
            }

        case "store_preference":
            if quotedMatches.count >= 2 {
                args["key"] = quotedMatches[0]
                args["value"] = quotedMatches[1]
            }

        case "search_by_client":
            args["clientName"] = quotedMatches.first ?? stepDescription

        default:
            break
        }

        return args
    }

    private func extractMatches(pattern: String, from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match -> String? in
            // Return the first capture group if available, otherwise the full match
            let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            guard let swiftRange = Range(captureRange, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    // MARK: - Private: Execution Summary

    private func buildExecutionSummary(plan: WorkflowPlan, results: [String]) -> String {
        let completedCount = plan.steps.filter { $0.status == .completed }.count
        let failedCount = plan.steps.filter { $0.status == .failed }.count
        let skippedCount = plan.steps.filter { $0.status == .skipped }.count

        var summary = "WORKFLOW COMPLETE: \(plan.summary)\n"
        summary += "Results: \(completedCount) succeeded"
        if failedCount > 0 { summary += ", \(failedCount) failed" }
        if skippedCount > 0 { summary += ", \(skippedCount) skipped" }
        summary += "\n\n"
        summary += results.joined(separator: "\n")

        return summary
    }
}
