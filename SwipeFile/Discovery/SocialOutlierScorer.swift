import Foundation

enum SocialOutlierGrade: String, Codable, Hashable, Sendable {
    case s
    case a
    case b
    case c
    case baseline
    case insufficientData
}

struct SocialOutlierScore: Equatable, Sendable {
    let multiplier: Double?
    let grade: SocialOutlierGrade
    let baselineReach: Int?
    let comparablePostCount: Int
}

enum SocialOutlierScorer {
    private static let minimumComparablePostCount = 5

    static func score(post: SocialPostSnapshot, creatorPosts: [SocialPostSnapshot]) -> SocialOutlierScore {
        let comparableReachValues = creatorPosts
            .filter { candidate in
                candidate.id != post.id
                    && candidate.platform == post.platform
                    && candidate.format == post.format
            }
            .compactMap(comparableReach)

        guard comparableReachValues.count >= minimumComparablePostCount else {
            return SocialOutlierScore(
                multiplier: nil,
                grade: .insufficientData,
                baselineReach: nil,
                comparablePostCount: comparableReachValues.count
            )
        }

        guard let currentReach = comparableReach(post),
              let baselineReach = median(comparableReachValues),
              baselineReach > 0
        else {
            return SocialOutlierScore(
                multiplier: nil,
                grade: .insufficientData,
                baselineReach: nil,
                comparablePostCount: comparableReachValues.count
            )
        }

        let multiplier = Double(currentReach) / Double(baselineReach)
        return SocialOutlierScore(
            multiplier: multiplier,
            grade: grade(for: multiplier),
            baselineReach: baselineReach,
            comparablePostCount: comparableReachValues.count
        )
    }

    private static func comparableReach(_ post: SocialPostSnapshot) -> Int? {
        post.metrics.views ?? post.metrics.impressions ?? post.metrics.likes
    }

    private static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }

        let sorted = values.sorted()
        let midpoint = sorted.count / 2

        if sorted.count.isMultiple(of: 2) {
            return (sorted[midpoint - 1] + sorted[midpoint]) / 2
        }

        return sorted[midpoint]
    }

    private static func grade(for multiplier: Double) -> SocialOutlierGrade {
        switch multiplier {
        case 20...:
            return .s
        case 10..<20:
            return .a
        case 5..<10:
            return .b
        case 2..<5:
            return .c
        default:
            return .baseline
        }
    }
}
