// CosmoOS/Voice/Pipeline/PatternMatcher.swift
// Tier 0: Fast regex-based pattern matching for common commands

import Foundation

// MARK: - Pattern Matcher

/// Fast pattern-based command parsing for Tier 0.
/// Handles ~60% of voice commands in <50ms with no model invocation.
actor PatternMatcher {
    static let shared = PatternMatcher()

    // MARK: - Pattern Definitions

    /// All registered patterns, ordered by priority.
    /// Level System, Deep Work, and Journal patterns are added at the beginning for priority.
    private lazy var patterns: [CommandPattern] = Self.levelSystemPatterns + Self.deepWorkPatterns + Self.journalPatterns + [
        // ===== SINGLE-WORD NAVIGATION SHORTCUTS (Tier 0 - Instant) =====
        // These must come FIRST for priority - they are the fastest path
        CommandPattern(
            regex: #"^(plan|planirium|plannerum|planning)$"#,
            action: .navigate,
            extractor: { _ in
                PatternMatchResult(
                    action: .navigate,
                    title: nil,
                    matchedPattern: "shortcut_plannerum",
                    confidence: 0.98
                )
            },
            destinationExtractor: { _ in "plannerum" }
        ),
        CommandPattern(
            regex: #"^(canvas|think|thinkspace|think\s*space)$"#,
            action: .navigate,
            extractor: { _ in
                PatternMatchResult(
                    action: .navigate,
                    title: nil,
                    matchedPattern: "shortcut_thinkspace",
                    confidence: 0.98
                )
            },
            destinationExtractor: { _ in "thinkspace" }
        ),
        CommandPattern(
            regex: #"^sanctuary$"#,
            action: .navigate,
            extractor: { _ in
                PatternMatchResult(
                    action: .navigate,
                    title: nil,
                    matchedPattern: "shortcut_sanctuary",
                    confidence: 0.98
                )
            },
            destinationExtractor: { _ in "sanctuary" }
        ),
        CommandPattern(
            regex: #"^(home|inbox|today)$"#,
            action: .navigate,
            extractor: { match in
                PatternMatchResult(
                    action: .navigate,
                    title: nil,
                    matchedPattern: "shortcut_home",
                    confidence: 0.98
                )
            },
            destinationExtractor: { match in match[1].lowercased() }
        ),
        CommandPattern(
            regex: #"^(projects?|ideas?|tasks?|settings|research|focus)$"#,
            action: .navigate,
            extractor: { match in
                let destination = match[1].lowercased()
                    .replacingOccurrences(of: "s$", with: "", options: .regularExpression)
                return PatternMatchResult(
                    action: .navigate,
                    title: nil,
                    matchedPattern: "shortcut_section",
                    confidence: 0.95
                )
            },
            destinationExtractor: { match in
                match[1].lowercased()
                    .replacingOccurrences(of: "s$", with: "", options: .regularExpression)
            }
        ),

        // ===== NAVIGATION =====
        CommandPattern(
            regex: #"^(go to|open|show|show me)\s+(projects?|ideas?|tasks?|schedule|today|settings|home|research|focus)"#,
            action: .navigate,
            extractor: { match in
                let destination = match[2].lowercased()
                    .replacingOccurrences(of: "s$", with: "", options: .regularExpression)
                return PatternMatchResult(
                    action: .navigate,
                    title: nil,
                    matchedPattern: "navigation",
                    confidence: 0.95
                )
            },
            destinationExtractor: { match in
                match[2].lowercased()
                    .replacingOccurrences(of: "s$", with: "", options: .regularExpression)
            }
        ),

        // ===== SANCTUARY NAVIGATION =====
        CommandPattern(
            regex: #"^(go to|open|show|show me)\s+(plannerum|planning|thinkspace|canvas|sanctuary)"#,
            action: .navigate,
            extractor: { match in
                PatternMatchResult(
                    action: .navigate,
                    title: nil,
                    matchedPattern: "sanctuary_navigation",
                    confidence: 0.95
                )
            },
            destinationExtractor: { match in
                let raw = match[2].lowercased()
                // Normalize alternative names
                switch raw {
                case "planning": return "plannerum"
                case "canvas": return "thinkspace"
                default: return raw
                }
            }
        ),
        CommandPattern(
            regex: #"^(return to|go back to|back to)\s+sanctuary"#,
            action: .navigate,
            extractor: { _ in
                PatternMatchResult(
                    action: .navigate,
                    title: nil,
                    matchedPattern: "sanctuary_return",
                    confidence: 0.95
                )
            },
            destinationExtractor: { _ in "sanctuary" }
        ),

        // ===== DELETE =====
        CommandPattern(
            regex: #"^(delete|remove|cancel|get rid of)\s+(this|that|it)$"#,
            action: .delete,
            extractor: { match in
                PatternMatchResult(
                    action: .delete,
                    matchedPattern: "delete_context",
                    confidence: 0.95
                )
            }
        ),
        CommandPattern(
            regex: #"^never\s*mind$"#,
            action: .delete,
            extractor: { _ in
                PatternMatchResult(
                    action: .delete,
                    matchedPattern: "nevermind",
                    confidence: 0.9
                )
            }
        ),

        // ===== STATUS UPDATES =====
        CommandPattern(
            regex: #"^(mark\s+as\s+|mark\s+)?complete[d]?$"#,
            action: .update,
            extractor: { _ in
                PatternMatchResult(
                    action: .update,
                    matchedPattern: "complete",
                    confidence: 0.95
                )
            },
            metadataExtractor: { _ in ["status": VoiceAnyCodable("completed")] }
        ),
        CommandPattern(
            regex: #"^done$"#,
            action: .update,
            extractor: { _ in
                PatternMatchResult(
                    action: .update,
                    matchedPattern: "done",
                    confidence: 0.95
                )
            },
            metadataExtractor: { _ in ["status": VoiceAnyCodable("completed")] }
        ),
        CommandPattern(
            regex: #"^(that's|thats|it's|its)\s+done$"#,
            action: .update,
            extractor: { _ in
                PatternMatchResult(
                    action: .update,
                    matchedPattern: "thats_done",
                    confidence: 0.95
                )
            },
            metadataExtractor: { _ in ["status": VoiceAnyCodable("completed")] }
        ),
        CommandPattern(
            regex: #"^finish(ed)?\s+(this|that)$"#,
            action: .update,
            extractor: { _ in
                PatternMatchResult(
                    action: .update,
                    matchedPattern: "finish_this",
                    confidence: 0.95
                )
            },
            metadataExtractor: { _ in ["status": VoiceAnyCodable("completed")] }
        ),

        // ===== SIMPLE IDEA CREATION =====
        // NOTE: Project-specific patterns like "idea for Michael" are handled by the fine-tuned 0.5B model
        CommandPattern(
            regex: #"^(new\s+)?idea\s+(about\s+)?(.+)$"#,
            action: .create,
            atomType: .idea,
            extractor: { match in
                let fullMatch = match[0]
                // Pass through to LLM if contains project reference (e.g., "idea for Michael")
                if containsProjectReference(fullMatch) { return nil }
                let title = match[3].trimmingCharacters(in: .whitespaces)
                return PatternMatchResult(
                    action: .create,
                    atomType: .idea,
                    title: title.capitalized,
                    matchedPattern: "idea_simple",
                    confidence: 0.9
                )
            }
        ),
        CommandPattern(
            regex: #"^create\s+idea\s+(called\s+|about\s+|for\s+)?(.+)$"#,
            action: .create,
            atomType: .idea,
            extractor: { match in
                let fullMatch = match[0]
                if containsProjectReference(fullMatch) { return nil }
                let title = match[2].trimmingCharacters(in: .whitespaces)
                return PatternMatchResult(
                    action: .create,
                    atomType: .idea,
                    title: title.capitalized,
                    matchedPattern: "create_idea",
                    confidence: 0.95
                )
            }
        ),
        CommandPattern(
            regex: #"^(note|thought)\s+(about\s+|for\s+)?(.+)$"#,
            action: .create,
            atomType: .idea,
            extractor: { match in
                let fullMatch = match[0]
                if containsProjectReference(fullMatch) { return nil }
                let title = match[3].trimmingCharacters(in: .whitespaces)
                return PatternMatchResult(
                    action: .create,
                    atomType: .idea,
                    title: title.capitalized,
                    matchedPattern: "note_thought",
                    confidence: 0.85
                )
            }
        ),

        // ===== SIMPLE TASK CREATION =====
        // NOTE: Project-specific patterns like "task for Michael" are handled by the fine-tuned 0.5B model
        CommandPattern(
            regex: #"^(new\s+)?task\s+(to\s+|for\s+)?(.+)$"#,
            action: .create,
            atomType: .task,
            extractor: { match in
                let fullMatch = match[0]
                // Pass through to LLM if contains project or time reference
                if containsProjectReference(fullMatch) { return nil }
                let title = match[3].trimmingCharacters(in: .whitespaces)
                if containsTimeExpression(title) { return nil }
                return PatternMatchResult(
                    action: .create,
                    atomType: .task,
                    title: title.capitalized,
                    matchedPattern: "task_simple",
                    confidence: 0.9
                )
            }
        ),
        CommandPattern(
            regex: #"^create\s+task\s+(to\s+|called\s+|for\s+)?(.+)$"#,
            action: .create,
            atomType: .task,
            extractor: { match in
                let fullMatch = match[0]
                if containsProjectReference(fullMatch) { return nil }
                let title = match[2].trimmingCharacters(in: .whitespaces)
                if containsTimeExpression(title) { return nil }
                return PatternMatchResult(
                    action: .create,
                    atomType: .task,
                    title: title.capitalized,
                    matchedPattern: "create_task",
                    confidence: 0.95
                )
            }
        ),
        CommandPattern(
            regex: #"^add\s+task\s+(to\s+|for\s+)?(.+)$"#,
            action: .create,
            atomType: .task,
            extractor: { match in
                let fullMatch = match[0]
                if containsProjectReference(fullMatch) { return nil }
                let title = match[2].trimmingCharacters(in: .whitespaces)
                if containsTimeExpression(title) { return nil }
                return PatternMatchResult(
                    action: .create,
                    atomType: .task,
                    title: title.capitalized,
                    matchedPattern: "add_task",
                    confidence: 0.9
                )
            }
        ),

        // ===== PROJECT CREATION =====
        CommandPattern(
            regex: #"^(create|new|start)\s+project\s+(called\s+|for\s+)?(.+)$"#,
            action: .create,
            atomType: .project,
            extractor: { match in
                let title = match[3].trimmingCharacters(in: .whitespaces)
                return PatternMatchResult(
                    action: .create,
                    atomType: .project,
                    title: title.capitalized,
                    matchedPattern: "create_project",
                    confidence: 0.95
                )
            }
        ),

        // ===== THINKSPACE CREATION =====
        // "new thinkspace called Ideas"
        CommandPattern(
            regex: #"^(create|new|start)\s+(think\s*space|canvas)\s+(called\s+|named\s+)?(.+)$"#,
            action: .create,
            atomType: .thinkspace,
            extractor: { match in
                let title = match[4].trimmingCharacters(in: .whitespaces)
                return PatternMatchResult(
                    action: .create,
                    atomType: .thinkspace,
                    title: title.capitalized,
                    matchedPattern: "create_thinkspace",
                    confidence: 0.95
                )
            }
        ),
        // "add to [project] thinkspace" - creates block in project's root ThinkSpace
        // NOTE: Project matching handled by LLM for fuzzy matching
        CommandPattern(
            regex: #"^add\s+(this\s+)?to\s+(.+?)\s*(think\s*space|canvas)$"#,
            action: .create,
            atomType: .note,
            extractor: { match in
                let projectName = match[2].trimmingCharacters(in: .whitespaces)
                return PatternMatchResult(
                    action: .create,
                    atomType: .note,
                    title: nil,
                    matchedPattern: "add_to_thinkspace",
                    confidence: 0.85,
                    metadata: ["targetProject": projectName, "destination": "thinkspace"]
                )
            }
        ),
        // "open thinkspace" / "go to thinkspace"
        CommandPattern(
            regex: #"^(open|go to|show)\s+(think\s*space|canvas)$"#,
            action: .navigate,
            extractor: { _ in
                PatternMatchResult(
                    action: .navigate,
                    title: nil,
                    matchedPattern: "open_thinkspace",
                    confidence: 0.95
                )
            },
            destinationExtractor: { _ in "thinkspace" }
        ),
        // "open [name] thinkspace" - opens specific thinkspace
        CommandPattern(
            regex: #"^(open|go to|show)\s+(.+?)\s*(think\s*space|canvas)$"#,
            action: .navigate,
            extractor: { match in
                let thinkspaceName = match[2].trimmingCharacters(in: .whitespaces)
                return PatternMatchResult(
                    action: .navigate,
                    title: thinkspaceName.capitalized,
                    matchedPattern: "open_named_thinkspace",
                    confidence: 0.9,
                    metadata: ["thinkspaceName": thinkspaceName]
                )
            },
            destinationExtractor: { _ in "thinkspace" }
        ),

        // ===== PRIORITY UPDATES =====
        CommandPattern(
            regex: #"^(make\s+)?(this\s+)?(high|urgent|important)\s*(priority)?$"#,
            action: .update,
            extractor: { _ in
                PatternMatchResult(
                    action: .update,
                    matchedPattern: "high_priority",
                    confidence: 0.9
                )
            },
            metadataExtractor: { _ in ["priority": VoiceAnyCodable("high")] }
        ),
        CommandPattern(
            regex: #"^(make\s+)?(this\s+)?low\s*priority$"#,
            action: .update,
            extractor: { _ in
                PatternMatchResult(
                    action: .update,
                    matchedPattern: "low_priority",
                    confidence: 0.9
                )
            },
            metadataExtractor: { _ in ["priority": VoiceAnyCodable("low")] }
        ),

        // ===== SIMPLE SEARCH =====
        CommandPattern(
            regex: #"^(find|search|search for|look for)\s+(.+)$"#,
            action: .search,
            extractor: { match in
                let query = match[2].trimmingCharacters(in: .whitespaces)
                return PatternMatchResult(
                    action: .search,
                    title: query,
                    matchedPattern: "search_simple",
                    confidence: 0.85
                )
            }
        ),
    ]

    // MARK: - Matching

    /// Attempt to match a transcript against all patterns.
    /// Returns nil if no pattern matches.
    func match(_ transcript: String) -> ParsedAction? {
        let normalized = normalizeTranscript(transcript)

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.regex, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(normalized.startIndex..., in: normalized)
            guard let match = regex.firstMatch(in: normalized, options: [], range: range) else {
                continue
            }

            // Extract capture groups
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                if let range = Range(match.range(at: i), in: normalized) {
                    groups.append(String(normalized[range]))
                } else {
                    groups.append("")
                }
            }

            // Try to extract result
            guard let result = pattern.extractor(groups) else {
                continue
            }

            // Build ParsedAction
            let metadata = pattern.metadataExtractor?(groups)
            let destination = pattern.destinationExtractor?(groups)

            return ParsedAction(
                action: result.action,
                atomType: result.atomType,
                title: result.title,
                metadata: metadata,
                target: .context,
                query: result.action == .search ? result.title : nil,
                destination: destination
            )
        }

        return nil
    }

    // MARK: - Helpers

    /// Normalize transcript for matching
    private func normalizeTranscript(_ transcript: String) -> String {
        transcript
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

// MARK: - Command Pattern

/// A regex-based command pattern with extractors.
struct CommandPattern {
    let regex: String
    let action: ParsedAction.ActionType
    let atomType: AtomType?
    let extractor: ([String]) -> PatternMatchResult?
    let metadataExtractor: (([String]) -> [String: VoiceAnyCodable]?)?
    let destinationExtractor: (([String]) -> String?)?

    init(
        regex: String,
        action: ParsedAction.ActionType,
        atomType: AtomType? = nil,
        extractor: @escaping ([String]) -> PatternMatchResult?,
        metadataExtractor: (([String]) -> [String: VoiceAnyCodable]?)? = nil,
        destinationExtractor: (([String]) -> String?)? = nil
    ) {
        self.regex = regex
        self.action = action
        self.atomType = atomType
        self.extractor = extractor
        self.metadataExtractor = metadataExtractor
        self.destinationExtractor = destinationExtractor
    }
}

// MARK: - Time Expression Detection

/// Check if text contains a time expression (should be handled by LLM instead)
private func containsTimeExpression(_ text: String) -> Bool {
    let timePatterns = [
        #"\b\d{1,2}(:\d{2})?\s*(am|pm|AM|PM)\b"#,       // 2pm, 2:30pm
        #"\b\d{1,2}\s*o'?clock\b"#,                      // 2 o'clock
        #"\bat\s+\d{1,2}\b"#,                            // at 2
        #"\b(tomorrow|today|tonight|this\s+evening)\b"#, // relative
        #"\b(next|this)\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#,
        #"\b(morning|afternoon|evening|noon)\b"#,
        #"\bfrom\s+\d{1,2}\s*(to|until|-)\s*\d{1,2}\b"#, // from 2 to 4
        #"\bin\s+\d+\s+(hour|minute|min)s?\b"#,          // in 2 hours
    ]

    let lowered = text.lowercased()
    for pattern in timePatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(lowered.startIndex..., in: lowered)
            if regex.firstMatch(in: lowered, options: [], range: range) != nil {
                return true
            }
        }
    }

    return false
}

/// Check if text contains a project reference pattern (should be handled by LLM for accuracy)
/// Examples: "for Michael", "for Acme project", "to Sarah inbox"
private func containsProjectReference(_ text: String) -> Bool {
    let projectPatterns = [
        #"\bfor\s+[A-Z][a-zA-Z]+\b"#,           // "for Michael", "for Sarah"
        #"\bto\s+[A-Z][a-zA-Z]+\s*inbox\b"#,    // "to Sarah inbox"
        #"\badd\s+to\s+[A-Z][a-zA-Z]+\b"#,      // "add to Michael"
        #"\bin\s+[A-Z][a-zA-Z]+\s*project\b"#,  // "in Marketing project"
        #"\bfor\s+[A-Z][a-zA-Z]+\s*project\b"#, // "for Acme project"
    ]

    for pattern in projectPatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }
    }

    return false
}

// MARK: - Pattern Statistics

extension PatternMatcher {
    /// Get statistics about pattern coverage
    func getStats() -> PatternMatcherStats {
        PatternMatcherStats(
            patternCount: patterns.count,
            creationPatterns: patterns.filter { $0.action == .create }.count,
            updatePatterns: patterns.filter { $0.action == .update }.count,
            searchPatterns: patterns.filter { $0.action == .search }.count,
            navigationPatterns: patterns.filter { $0.action == .navigate }.count,
            deletePatterns: patterns.filter { $0.action == .delete }.count
        )
    }
}

struct PatternMatcherStats: Sendable {
    let patternCount: Int
    let creationPatterns: Int
    let updatePatterns: Int
    let searchPatterns: Int
    let navigationPatterns: Int
    let deletePatterns: Int
}
