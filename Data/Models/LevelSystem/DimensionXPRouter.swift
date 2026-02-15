//
//  DimensionXPRouter.swift
//  CosmoOS
//
//  Routes XP awards to Sanctuary dimensions based on TaskIntent.
//  Supports split routing (e.g., Research -> 70% Cognitive, 30% Knowledge).
//

import Foundation

// MARK: - Dimension XP Allocation

/// A single dimension + XP amount pair from a routing result
struct DimensionXPAllocation: Sendable {
    let dimension: String
    let xp: Int
}

// MARK: - Dimension XP Router

/// Routes session XP to one or more Sanctuary dimensions based on the task's intent.
///
/// Mapping table:
/// | Intent       | Primary     | Secondary  | Split  |
/// |-------------|-------------|------------|--------|
/// | writeContent | creative    | —          | 100%   |
/// | research     | cognitive   | knowledge  | 70/30  |
/// | studySwipes  | creative    | cognitive  | 60/40  |
/// | deepThink    | reflection  | cognitive  | 70/30  |
/// | review       | creative    | behavioral | 50/50  |
/// | general      | behavioral  | —          | 100%   |
/// | custom       | behavioral  | —          | 100%   |
struct DimensionXPRouter {

    /// Route XP based on task intent and focus quality.
    /// - Parameters:
    ///   - intent: The task's intent determining dimension mapping
    ///   - baseXP: Raw XP earned from the session
    ///   - focusScore: Focus quality score (0-100), used for bonus calculation
    /// - Returns: Array of dimension/XP pairs (primary dimension rounded up)
    static func routeXP(
        intent: TaskIntent,
        baseXP: Int,
        focusScore: Double = 100
    ) -> [DimensionXPAllocation] {
        guard baseXP > 0 else { return [] }

        switch intent {
        case .writeContent:
            return [DimensionXPAllocation(dimension: "creative", xp: baseXP)]

        case .research:
            let primary = Int(ceil(Double(baseXP) * 0.7))
            let secondary = baseXP - primary
            var result = [DimensionXPAllocation(dimension: "cognitive", xp: primary)]
            if secondary > 0 {
                result.append(DimensionXPAllocation(dimension: "knowledge", xp: secondary))
            }
            return result

        case .studySwipes:
            let primary = Int(ceil(Double(baseXP) * 0.6))
            let secondary = baseXP - primary
            var result = [DimensionXPAllocation(dimension: "creative", xp: primary)]
            if secondary > 0 {
                result.append(DimensionXPAllocation(dimension: "cognitive", xp: secondary))
            }
            return result

        case .deepThink:
            let primary = Int(ceil(Double(baseXP) * 0.7))
            let secondary = baseXP - primary
            var result = [DimensionXPAllocation(dimension: "reflection", xp: primary)]
            if secondary > 0 {
                result.append(DimensionXPAllocation(dimension: "cognitive", xp: secondary))
            }
            return result

        case .review:
            let primary = Int(ceil(Double(baseXP) * 0.5))
            let secondary = baseXP - primary
            var result = [DimensionXPAllocation(dimension: "creative", xp: primary)]
            if secondary > 0 {
                result.append(DimensionXPAllocation(dimension: "behavioral", xp: secondary))
            }
            return result

        case .general, .custom:
            return [DimensionXPAllocation(dimension: "behavioral", xp: baseXP)]
        }
    }

    /// Format dimension allocations for display in summary card.
    /// Examples: "+25 XP -> Creative" or "+18 XP -> Cognitive, +7 XP -> Knowledge"
    static func formatAllocations(_ allocations: [DimensionXPAllocation]) -> String {
        allocations.map { alloc in
            let dimName = dimensionDisplayName(alloc.dimension)
            return "+\(alloc.xp) XP \u{2192} \(dimName)"
        }.joined(separator: ", ")
    }

    /// Get the display name for a dimension key
    static func dimensionDisplayName(_ key: String) -> String {
        switch key {
        case "cognitive": return "Cognitive"
        case "creative": return "Creative"
        case "physiological": return "Physiological"
        case "behavioral": return "Behavioral"
        case "knowledge": return "Knowledge"
        case "reflection": return "Reflection"
        default: return key.capitalized
        }
    }

    /// Get the display color for a dimension key
    static func dimensionColor(_ key: String) -> (red: Double, green: Double, blue: Double) {
        switch key {
        case "cognitive": return (99/255, 102/255, 241/255)         // indigo
        case "creative": return (245/255, 158/255, 11/255)          // amber
        case "physiological": return (239/255, 68/255, 68/255)      // red
        case "behavioral": return (20/255, 184/255, 166/255)        // teal
        case "knowledge": return (236/255, 72/255, 153/255)         // pink
        case "reflection": return (168/255, 85/255, 247/255)        // purple
        default: return (148/255, 163/255, 184/255)                 // slate
        }
    }
}
