// CosmoOS/AI/WritingAnalyzer.swift
// Pure algorithmic writing analysis using Apple's NaturalLanguage framework
// Zero AI, runs instantly on-device for Hemingway-style readability feedback
// February 2026

import Foundation
import NaturalLanguage

// MARK: - Writing Analysis Result

/// Complete analysis of a piece of writing, including readability scores,
/// sentence complexity, passive voice detection, and adverb density.
struct WritingAnalysis {
    /// Flesch-Kincaid readability score (0-100, higher = easier to read)
    let fleschKincaidScore: Double
    /// Gunning Fog grade level
    let gradeLevel: Double
    /// Total number of sentences
    let sentenceCount: Int
    /// Average words per sentence
    let avgSentenceLength: Double
    /// Percentage of sentences using passive voice (0-100)
    let passiveVoicePercent: Double
    /// Adverb density as percentage of total words (0-100)
    let adverbDensity: Double
    /// Ranges of complex sentences (15-25 words)
    let complexSentenceRanges: [NSRange]
    /// Ranges of very complex sentences (>25 words)
    let veryComplexSentenceRanges: [NSRange]
    /// Ranges of passive voice constructions
    let passiveVoiceRanges: [NSRange]
    /// Ranges of adverbs
    let adverbRanges: [NSRange]
    /// Total word count
    let wordCount: Int
    /// Unique word count (vocabulary diversity)
    let uniqueWordCount: Int

    /// Readability rating based on Flesch-Kincaid score
    var readabilityRating: ReadabilityRating {
        if fleschKincaidScore >= 60 { return .good }
        if fleschKincaidScore >= 30 { return .moderate }
        return .difficult
    }
}

/// Readability classification for UI display
enum ReadabilityRating {
    case good       // 60-100: Easy to read
    case moderate   // 30-59: Somewhat difficult
    case difficult  // 0-29: Very difficult

    var label: String {
        switch self {
        case .good: return "Easy"
        case .moderate: return "Moderate"
        case .difficult: return "Difficult"
        }
    }
}

// MARK: - Writing Analyzer

/// Singleton analyzer that performs pure algorithmic text analysis
/// using Apple's NaturalLanguage framework. No AI calls, runs instantly.
final class WritingAnalyzer {
    static let shared = WritingAnalyzer()

    // Common auxiliary verbs that signal passive voice
    private let auxiliaryVerbs: Set<String> = [
        "is", "are", "was", "were", "be", "been", "being",
        "has been", "have been", "had been",
        "will be", "shall be", "would be", "could be",
        "might be", "must be", "should be"
    ]

    // Common past participle patterns for passive detection
    private let pastParticipleEndings = ["ed", "en", "wn", "ht", "nt", "pt"]

    private init() {}

    // MARK: - Main Analysis

    /// Analyze text and return a complete WritingAnalysis
    func analyze(text: String) -> WritingAnalysis {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return WritingAnalysis(
                fleschKincaidScore: 100,
                gradeLevel: 0,
                sentenceCount: 0,
                avgSentenceLength: 0,
                passiveVoicePercent: 0,
                adverbDensity: 0,
                complexSentenceRanges: [],
                veryComplexSentenceRanges: [],
                passiveVoiceRanges: [],
                adverbRanges: [],
                wordCount: 0,
                uniqueWordCount: 0
            )
        }

        let nsText = text as NSString

        // 1. Tokenize sentences with ranges
        let sentenceRanges = tokenizeSentences(text: text)
        let sentenceCount = max(sentenceRanges.count, 1)

        // 2. Tokenize words with ranges
        let wordTokens = tokenizeWords(text: text)
        let wordCount = wordTokens.count
        let uniqueWords = Set(wordTokens.map { nsText.substring(with: $0).lowercased() })
        let uniqueWordCount = uniqueWords.count

        // 3. Count syllables
        var totalSyllables = 0
        var complexWordCount = 0 // 3+ syllables for Gunning Fog
        for range in wordTokens {
            let word = nsText.substring(with: range)
            let syllables = syllableCount(for: word)
            totalSyllables += syllables
            if syllables >= 3 {
                complexWordCount += 1
            }
        }

        // 4. Compute readability scores
        let fkScore = fleschKincaid(
            totalSyllables: totalSyllables,
            totalWords: wordCount,
            totalSentences: sentenceCount
        )
        let fogGrade = gunningFog(
            totalWords: wordCount,
            totalSentences: sentenceCount,
            complexWords: complexWordCount
        )

        // 5. Classify sentence complexity
        var complexRanges: [NSRange] = []
        var veryComplexRanges: [NSRange] = []
        let avgSentenceLength: Double = wordCount > 0 ? Double(wordCount) / Double(sentenceCount) : 0

        for sentenceRange in sentenceRanges {
            let sentenceWordsCount = countWords(in: text, range: sentenceRange)
            if sentenceWordsCount > 25 {
                veryComplexRanges.append(sentenceRange)
            } else if sentenceWordsCount >= 15 {
                complexRanges.append(sentenceRange)
            }
        }

        // 6. POS tagging for passive voice and adverbs
        let (passiveRanges, adverbRanges) = detectPOSPatterns(text: text)

        let passiveVoicePercent: Double = sentenceCount > 0
            ? Double(passiveRanges.count) / Double(sentenceCount) * 100.0
            : 0
        let adverbDensity: Double = wordCount > 0
            ? Double(adverbRanges.count) / Double(wordCount) * 100.0
            : 0

        return WritingAnalysis(
            fleschKincaidScore: fkScore,
            gradeLevel: fogGrade,
            sentenceCount: sentenceCount,
            avgSentenceLength: avgSentenceLength,
            passiveVoicePercent: min(passiveVoicePercent, 100),
            adverbDensity: min(adverbDensity, 100),
            complexSentenceRanges: complexRanges,
            veryComplexSentenceRanges: veryComplexRanges,
            passiveVoiceRanges: passiveRanges,
            adverbRanges: adverbRanges,
            wordCount: wordCount,
            uniqueWordCount: uniqueWordCount
        )
    }

    // MARK: - Syllable Counting

    /// Count syllables in a word using vowel-group heuristic with English adjustments
    func syllableCount(for word: String) -> Int {
        let lowered = word.lowercased()
        guard !lowered.isEmpty else { return 0 }

        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var count = 0
        var previousWasVowel = false

        for char in lowered {
            let isVowel = vowels.contains(char)
            if isVowel && !previousWasVowel {
                count += 1
            }
            previousWasVowel = isVowel
        }

        // Silent-e adjustment: subtract 1 if word ends in 'e' (but not "le")
        if lowered.hasSuffix("e") && !lowered.hasSuffix("le") && count > 1 {
            count -= 1
        }

        // "-ed" ending: don't count as syllable unless preceded by 'd' or 't'
        if lowered.hasSuffix("ed") && lowered.count > 3 {
            let beforeEd = lowered[lowered.index(lowered.endIndex, offsetBy: -3)]
            if beforeEd != "d" && beforeEd != "t" {
                // Already handled by vowel grouping in most cases
            }
        }

        // "-le" ending adds a syllable if preceded by a consonant
        if lowered.hasSuffix("le") && lowered.count > 2 {
            let beforeLe = lowered[lowered.index(lowered.endIndex, offsetBy: -3)]
            if !vowels.contains(beforeLe) && count == 0 {
                count += 1
            }
        }

        // "-tion", "-sion" count as one syllable (usually already handled)
        // Minimum 1 syllable per word
        return max(count, 1)
    }

    // MARK: - Readability Formulas

    /// Flesch-Kincaid readability score: 206.835 - 1.015*(words/sentences) - 84.6*(syllables/words)
    private func fleschKincaid(totalSyllables: Int, totalWords: Int, totalSentences: Int) -> Double {
        guard totalWords > 0, totalSentences > 0 else { return 100 }
        let score = 206.835
            - 1.015 * (Double(totalWords) / Double(totalSentences))
            - 84.6 * (Double(totalSyllables) / Double(totalWords))
        return min(max(score, 0), 100) // Clamp to 0-100
    }

    /// Gunning Fog grade level: 0.4 * ((words/sentences) + 100*(complexWords/words))
    private func gunningFog(totalWords: Int, totalSentences: Int, complexWords: Int) -> Double {
        guard totalWords > 0, totalSentences > 0 else { return 0 }
        return 0.4 * (
            (Double(totalWords) / Double(totalSentences))
            + 100.0 * (Double(complexWords) / Double(totalWords))
        )
    }

    // MARK: - Tokenization

    /// Tokenize text into sentence ranges using NLTokenizer
    private func tokenizeSentences(text: String) -> [NSRange] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var ranges: [NSRange] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let nsRange = NSRange(tokenRange, in: text)
            // Only include non-empty sentences
            let sentence = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                ranges.append(nsRange)
            }
            return true
        }
        return ranges
    }

    /// Tokenize text into word ranges using NLTokenizer
    private func tokenizeWords(text: String) -> [NSRange] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var ranges: [NSRange] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            ranges.append(NSRange(tokenRange, in: text))
            return true
        }
        return ranges
    }

    /// Count words within a specific NSRange of text
    private func countWords(in text: String, range: NSRange) -> Int {
        guard let swiftRange = Range(range, in: text) else { return 0 }
        let substring = String(text[swiftRange])
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = substring
        var count = 0
        tokenizer.enumerateTokens(in: substring.startIndex..<substring.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    // MARK: - POS Tagging (Passive Voice + Adverbs)

    /// Detect passive voice constructions and adverbs using NLTagger
    private func detectPOSPatterns(text: String) -> (passive: [NSRange], adverbs: [NSRange]) {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let nsText = text as NSString

        var adverbRanges: [NSRange] = []
        var passiveRanges: [NSRange] = []

        // Track tokens for passive voice detection (auxiliary + past participle)
        struct TaggedToken {
            let tag: NLTag
            let range: NSRange
            let word: String
        }
        var recentTokens: [TaggedToken] = []

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace]) { tag, tokenRange in
            guard let tag = tag else { return true }
            let nsRange = NSRange(tokenRange, in: text)
            let word = nsText.substring(with: nsRange).lowercased()

            let token = TaggedToken(tag: tag, range: nsRange, word: word)
            recentTokens.append(token)

            // Detect adverbs
            if tag == .adverb {
                adverbRanges.append(nsRange)
            }

            // Detect passive voice: auxiliary verb + past participle (verb)
            // NLTagger tags past participles as .verb, so we look for
            // patterns like "was written", "is made", "were taken"
            if tag == .verb && recentTokens.count >= 2 {
                // Check if previous token was an auxiliary verb
                let prevIdx = recentTokens.count - 2
                let prevToken = recentTokens[prevIdx]

                let isAuxiliary = prevToken.tag == .verb &&
                    self.auxiliaryVerbs.contains(prevToken.word)

                let looksLikePastParticiple = self.pastParticipleEndings.contains(where: { word.hasSuffix($0) })

                if isAuxiliary && looksLikePastParticiple {
                    // Combine range from auxiliary to past participle
                    let combinedLocation = prevToken.range.location
                    let combinedLength = (nsRange.location + nsRange.length) - combinedLocation
                    passiveRanges.append(NSRange(location: combinedLocation, length: combinedLength))
                }
            }

            // Keep only last 5 tokens to limit memory
            if recentTokens.count > 5 {
                recentTokens.removeFirst()
            }

            return true
        }

        return (passiveRanges, adverbRanges)
    }
}
