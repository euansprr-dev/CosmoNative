// CosmoOS/AI/MicroBrain/FunctionCallParser.swift
// Parser for FunctionGemma's specialized output format
// Part of the Micro-Brain architecture

import Foundation
import os.log

// MARK: - Function Call Parser

/// Parses FunctionGemma's output format into FunctionCall objects.
///
/// FunctionGemma uses a specific output format:
/// ```
/// <start_function_call>call:FUNCTION_NAME{param1:<escape>value1<escape>,param2:<escape>value2<escape>}<end_function_call>
/// ```
///
/// This parser handles:
/// - Single function calls
/// - Escaped parameter values
/// - Nested JSON objects in parameters
/// - Validation against known function names
public struct FunctionCallParser {
    private static let logger = Logger(subsystem: "com.cosmo.microbrain", category: "Parser")

    // MARK: - Regex Patterns

    /// Pattern to extract function call from FunctionGemma output
    /// Matches: <start_function_call>call:FUNC_NAME{...}<end_function_call>
    private static let functionCallPattern = #"<start_function_call>call:(\w+)\{([^}]*(?:\{[^}]*\}[^}]*)*)\}<end_function_call>"#

    /// Pattern to extract individual parameters
    /// Matches: key:<escape>value<escape>
    private static let parameterPattern = #"(\w+):<escape>([^<]*)<escape>"#

    /// Alternative: JSON-style parameters (fallback)
    private static let jsonParameterPattern = #"(\w+):\"([^\"]*)\""#

    // MARK: - Public API

    /// Parse FunctionGemma output into a FunctionCall
    /// - Parameter output: Raw output from FunctionGemma
    /// - Returns: Parsed FunctionCall
    /// - Throws: MicroBrainError if parsing fails
    public static func parse(_ output: String) throws -> FunctionCall {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try FunctionGemma format first
        if let call = parseFunctionGemmaFormat(trimmedOutput) {
            logger.debug("Parsed FunctionGemma format: \(call.name)")
            return call
        }

        // Try JSON format as fallback
        if let call = parseJSONFormat(trimmedOutput) {
            logger.debug("Parsed JSON format: \(call.name)")
            return call
        }

        // Try Hermes tool_call format (for backwards compatibility during migration)
        if let call = parseHermesFormat(trimmedOutput) {
            logger.debug("Parsed Hermes format: \(call.name)")
            return call
        }

        logger.error("Failed to parse output: \(trimmedOutput.prefix(200))")
        throw MicroBrainError.parsingFailed("No valid function call format found")
    }

    /// Parse multiple function calls (for batch operations)
    /// - Parameter output: Raw output containing multiple function calls
    /// - Returns: Array of parsed FunctionCalls
    public static func parseMultiple(_ output: String) throws -> [FunctionCall] {
        let regex = try NSRegularExpression(pattern: functionCallPattern, options: [])
        let range = NSRange(output.startIndex..., in: output)
        let matches = regex.matches(in: output, options: [], range: range)

        if matches.isEmpty {
            // Try single parse
            return [try parse(output)]
        }

        return matches.compactMap { match -> FunctionCall? in
            guard let fullRange = Range(match.range, in: output) else { return nil }
            let matchString = String(output[fullRange])
            return try? parse(matchString)
        }
    }

    // MARK: - Format Parsers

    /// Parse FunctionGemma's native format
    private static func parseFunctionGemmaFormat(_ output: String) -> FunctionCall? {
        guard let regex = try? NSRegularExpression(pattern: functionCallPattern, options: []) else {
            return nil
        }

        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, options: [], range: range),
              let nameRange = Range(match.range(at: 1), in: output),
              let paramsRange = Range(match.range(at: 2), in: output) else {
            return nil
        }

        let functionName = String(output[nameRange])
        let paramsString = String(output[paramsRange])

        // Parse parameters
        let parameters = parseEscapedParameters(paramsString)

        return FunctionCall(name: functionName, parameters: parameters, rawOutput: output)
    }

    /// Parse escaped parameters from FunctionGemma format
    private static func parseEscapedParameters(_ paramsString: String) -> [String: FunctionParameter] {
        var parameters: [String: FunctionParameter] = [:]

        guard let regex = try? NSRegularExpression(pattern: parameterPattern, options: []) else {
            return parameters
        }

        let range = NSRange(paramsString.startIndex..., in: paramsString)
        let matches = regex.matches(in: paramsString, options: [], range: range)

        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: paramsString),
                  let valueRange = Range(match.range(at: 2), in: paramsString) else {
                continue
            }

            let key = String(paramsString[keyRange])
            let value = String(paramsString[valueRange])

            // Try to parse as JSON first (for nested objects)
            if let jsonValue = parseJSONValue(value) {
                parameters[key] = jsonValue
            } else {
                // Store as string
                parameters[key] = .string(value)
            }
        }

        return parameters
    }

    /// Parse a value that might be JSON
    private static func parseJSONValue(_ value: String) -> FunctionParameter? {
        // Check if it looks like JSON
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            // Try to parse as JSON
            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                return nil
            }
            return FunctionParameter.from(json)
        }

        // Try to parse as number
        if let intValue = Int(trimmed) {
            return .int(intValue)
        }
        if let doubleValue = Double(trimmed) {
            return .double(doubleValue)
        }

        // Check for boolean
        if trimmed.lowercased() == "true" {
            return .bool(true)
        }
        if trimmed.lowercased() == "false" {
            return .bool(false)
        }

        return nil
    }

    /// Parse JSON format (fallback)
    private static func parseJSONFormat(_ output: String) -> FunctionCall? {
        // Try to extract JSON from output
        guard let start = output.firstIndex(of: "{"),
              let end = output.lastIndex(of: "}") else {
            return nil
        }

        let jsonString = String(output[start...end])
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Extract function name
        guard let name = json["name"] as? String ?? json["function"] as? String else {
            return nil
        }

        // Extract parameters
        let args = json["arguments"] as? [String: Any] ?? json["parameters"] as? [String: Any] ?? [:]
        let parameters = args.mapValues { FunctionParameter.from($0) }

        return FunctionCall(name: name, parameters: parameters, rawOutput: output)
    }

    /// Parse Hermes <tool_call> format (backwards compatibility)
    private static func parseHermesFormat(_ output: String) -> FunctionCall? {
        // Match <tool_call>...</tool_call>
        let pattern = #"<tool_call>\s*(\{[\s\S]*?\})\s*</tool_call>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, options: [], range: range),
              let jsonRange = Range(match.range(at: 1), in: output) else {
            return nil
        }

        let jsonString = String(output[jsonRange])
        return parseJSONFormat(jsonString)
    }

    // MARK: - Validation

    /// Validate that a function call has required parameters
    public static func validate(_ call: FunctionCall) throws {
        guard let funcName = FunctionName(rawValue: call.name) else {
            throw MicroBrainError.unknownFunction(call.name)
        }

        switch funcName {
        case .createAtom:
            guard call.string("atom_type") != nil else {
                throw MicroBrainError.invalidParameters("create_atom requires atom_type")
            }
            guard call.string("title") != nil else {
                throw MicroBrainError.invalidParameters("create_atom requires title")
            }

        case .updateAtom:
            guard call.string("target") != nil else {
                throw MicroBrainError.invalidParameters("update_atom requires target")
            }

        case .deleteAtom:
            guard call.string("target") != nil else {
                throw MicroBrainError.invalidParameters("delete_atom requires target")
            }

        case .searchAtoms:
            guard call.string("query") != nil else {
                throw MicroBrainError.invalidParameters("search_atoms requires query")
            }

        case .batchCreate:
            guard call.array("items") != nil else {
                throw MicroBrainError.invalidParameters("batch_create requires items array")
            }

        case .navigate:
            guard call.string("destination") != nil else {
                throw MicroBrainError.invalidParameters("navigate requires destination")
            }

        case .queryLevelSystem:
            guard call.string("query_type") != nil else {
                throw MicroBrainError.invalidParameters("query_level_system requires query_type")
            }

        case .startDeepWork:
            // Optional parameters, no validation needed
            break

        case .stopDeepWork:
            // No parameters needed
            break

        case .extendDeepWork:
            guard call.int("additional_minutes") != nil else {
                throw MicroBrainError.invalidParameters("extend_deep_work requires additional_minutes")
            }

        case .logWorkout:
            guard call.string("workout_type") != nil else {
                throw MicroBrainError.invalidParameters("log_workout requires workout_type")
            }

        case .triggerCorrelationAnalysis:
            guard call.array("dimensions") != nil else {
                throw MicroBrainError.invalidParameters("trigger_correlation_analysis requires dimensions")
            }

        // Sanctuary actions - no required parameters for most
        case .openCognitiveDimension,
             .openCreativeDimension,
             .openPhysiologicalDimension,
             .openBehavioralDimension,
             .openKnowledgeDimension,
             .openReflectionDimension,
             .returnToSanctuaryHome,
             .openPlannerum,
             .openThinkspace,
             .toggleTimelineView,
             .showCorrelationInsights,
             .showPredictionsPanel,
             .openJournalEntry:
            break

        case .zoomKnowledgeGraph:
            guard call.string("direction") != nil else {
                throw MicroBrainError.invalidParameters("zoom_knowledge_graph requires direction")
            }

        case .focusKnowledgeNode:
            guard call.string("node_id") != nil else {
                throw MicroBrainError.invalidParameters("focus_knowledge_node requires node_id")
            }

        case .searchKnowledgeNodes:
            guard call.string("query") != nil else {
                throw MicroBrainError.invalidParameters("search_knowledge_nodes requires query")
            }

        case .showClusterDetail:
            guard call.string("cluster_id") != nil else {
                throw MicroBrainError.invalidParameters("show_cluster_detail requires cluster_id")
            }

        case .expandMetricDetail:
            guard call.string("metric_id") != nil else {
                throw MicroBrainError.invalidParameters("expand_metric_detail requires metric_id")
            }

        case .quickLogMood:
            guard call.string("emoji") != nil else {
                throw MicroBrainError.invalidParameters("quick_log_mood requires emoji")
            }

        case .startMeditationSession:
            // Optional parameters only
            break
        }
    }
}

// MARK: - FunctionCall to ParsedAction Conversion

extension FunctionCall {
    /// Convert FunctionCall to ParsedAction for existing pipeline compatibility
    public func toParsedAction() -> ParsedAction? {
        guard let funcName = FunctionName(rawValue: name) else {
            return nil
        }

        switch funcName {
        case .createAtom:
            guard let atomTypeStr = string("atom_type"),
                  let atomType = AtomType(rawValue: atomTypeStr) else {
                return nil
            }

            var metadata: [String: VoiceAnyCodable]?
            if let metadataObj = object("metadata") {
                metadata = metadataObj.mapValues { param -> VoiceAnyCodable in
                    VoiceAnyCodable(param.jsonValue)
                }
            }

            var links: [AtomLinkQuery]?
            if let linksArray = array("links") {
                links = linksArray.compactMap { param -> AtomLinkQuery? in
                    guard let obj = param.objectValue,
                          let type = obj["type"]?.stringValue else {
                        return nil
                    }
                    return AtomLinkQuery(
                        type: type,
                        uuid: obj["uuid"]?.stringValue,
                        query: obj["query"]?.stringValue,
                        entityType: obj["entity_type"]?.stringValue
                    )
                }
            }

            return ParsedAction(
                action: .create,
                atomType: atomType,
                title: string("title"),
                body: string("body"),
                metadata: metadata,
                links: links
            )

        case .updateAtom:
            let targetStr = string("target") ?? "context"
            let target = ParsedAction.TargetReference(rawValue: targetStr) ?? .context

            var metadata: [String: VoiceAnyCodable]?
            if let metadataObj = object("metadata") {
                metadata = metadataObj.mapValues { VoiceAnyCodable($0.jsonValue) }
            }

            return ParsedAction(
                action: .update,
                title: string("title"),
                body: string("body"),
                metadata: metadata,
                target: target
            )

        case .deleteAtom:
            let targetStr = string("target") ?? "context"
            let target = ParsedAction.TargetReference(rawValue: targetStr) ?? .context

            return ParsedAction(
                action: .delete,
                target: target
            )

        case .searchAtoms:
            var types: [AtomType]?
            if let typesArray = array("types") {
                types = typesArray.compactMap { param -> AtomType? in
                    guard let str = param.stringValue else { return nil }
                    return AtomType(rawValue: str)
                }
            }

            return ParsedAction(
                action: .search,
                query: string("query"),
                types: types
            )

        case .batchCreate:
            guard let itemsArray = array("items") else { return nil }

            let items: [ParsedAction] = itemsArray.compactMap { param -> ParsedAction? in
                guard let obj = param.objectValue,
                      let atomTypeStr = obj["atom_type"]?.stringValue,
                      let atomType = AtomType(rawValue: atomTypeStr) else {
                    return nil
                }

                var metadata: [String: VoiceAnyCodable]?
                if let metaObj = obj["metadata"]?.objectValue {
                    metadata = metaObj.mapValues { VoiceAnyCodable($0.jsonValue) }
                }

                return ParsedAction(
                    action: .create,
                    atomType: atomType,
                    title: obj["title"]?.stringValue,
                    body: obj["body"]?.stringValue,
                    metadata: metadata
                )
            }

            return ParsedAction(
                action: .batch,
                items: items
            )

        case .navigate:
            return ParsedAction(
                action: .navigate,
                destination: string("destination")
            )

        case .queryLevelSystem:
            let queryTypeStr = string("query_type") ?? "level_status"
            let queryType = ParsedAction.QueryType(rawValue: queryTypeStr) ?? .levelStatus

            return ParsedAction(
                action: .query,
                queryType: queryType,
                dimension: string("dimension")
            )

        case .startDeepWork:
            return ParsedAction(
                action: .create,
                atomType: .scheduleBlock,
                title: "Deep Work",
                metadata: [
                    "blockType": VoiceAnyCodable("focus"),
                    "durationMinutes": VoiceAnyCodable(int("duration_minutes") ?? 60),
                    "pomodoroMode": VoiceAnyCodable(bool("pomodoro_mode") ?? false),
                    "startNow": VoiceAnyCodable(true)
                ]
            )

        case .stopDeepWork:
            return ParsedAction(
                action: .update,
                metadata: [
                    "status": VoiceAnyCodable("completed"),
                    "endNow": VoiceAnyCodable(true)
                ],
                target: .context
            )

        case .extendDeepWork:
            return ParsedAction(
                action: .update,
                metadata: [
                    "extendMinutes": VoiceAnyCodable(int("additional_minutes") ?? 30)
                ],
                target: .context
            )

        case .logWorkout:
            return ParsedAction(
                action: .create,
                atomType: .workout,
                title: "Workout",
                metadata: [
                    "workoutType": VoiceAnyCodable(string("workout_type") ?? "other"),
                    "durationMinutes": int("duration_minutes").map { VoiceAnyCodable($0) },
                    "distanceKm": double("distance_km").map { VoiceAnyCodable($0) },
                    "exercise": string("exercise").map { VoiceAnyCodable($0) },
                    "reps": int("reps").map { VoiceAnyCodable($0) },
                    "sets": int("sets").map { VoiceAnyCodable($0) },
                    "source": VoiceAnyCodable("voice")
                ].compactMapValues { $0 }
            )

        case .triggerCorrelationAnalysis:
            // This doesn't map to ParsedAction - handled separately
            return nil

        // Sanctuary actions - handled by ToolExecutor directly, not ParsedAction
        case .openCognitiveDimension,
             .openCreativeDimension,
             .openPhysiologicalDimension,
             .openBehavioralDimension,
             .openKnowledgeDimension,
             .openReflectionDimension,
             .returnToSanctuaryHome,
             .openPlannerum,
             .openThinkspace,
             .zoomKnowledgeGraph,
             .focusKnowledgeNode,
             .searchKnowledgeNodes,
             .showClusterDetail,
             .toggleTimelineView,
             .showCorrelationInsights,
             .showPredictionsPanel,
             .expandMetricDetail,
             .quickLogMood,
             .startMeditationSession,
             .openJournalEntry:
            return nil
        }
    }
}
