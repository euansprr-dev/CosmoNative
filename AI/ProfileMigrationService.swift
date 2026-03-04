// CosmoOS/AI/ProfileMigrationService.swift
// Migrates legacy ClientProfileMetadata to the new Intelligence Model format.
// Preserves old field values in legacyFields, creates ProfileDocuments from
// existing content, and extracts primaryPlatform.
// February 2026

import Foundation

@MainActor
final class ProfileMigrationService {
    static let shared = ProfileMigrationService()
    private init() {}

    /// Migrate a legacy client profile atom to the new document-based format.
    /// - Returns the updated atom with documents, legacyFields, primaryPlatform set.
    /// - Does NOT generate an Intelligence Model — that requires ClientIntelligenceEngine.
    @discardableResult
    func migrateProfile(_ atom: Atom) async throws -> Atom {
        guard let clientMeta = atom.metadataValue(as: ClientProfileMetadata.self) else {
            throw MigrationError.invalidMetadata
        }

        // Skip if already migrated (has documents or legacyFields)
        if clientMeta.legacyFields != nil || (clientMeta.documents ?? []).count > 0 {
            return atom
        }

        var updatedMeta = clientMeta

        // 1. Extract primaryPlatform (first platform, default .instagram)
        updatedMeta.primaryPlatform = clientMeta.platforms.first ?? .instagram

        // 2. Build legacyFields from all text fields
        var legacy: [String: String] = [:]
        if let v = clientMeta.niche { legacy["niche"] = v }
        if let v = clientMeta.industry { legacy["industry"] = v }
        if let v = clientMeta.targetAudience { legacy["targetAudience"] = v }
        if let v = clientMeta.brandStory { legacy["brandStory"] = v }
        if let v = clientMeta.brandVision { legacy["brandVision"] = v }
        if let v = clientMeta.voiceNotes { legacy["voiceNotes"] = v }
        if let v = clientMeta.uniqueAngle { legacy["uniqueAngle"] = v }
        if let v = clientMeta.notes { legacy["notes"] = v }
        if let beliefs = clientMeta.coreBeliefs, !beliefs.isEmpty {
            legacy["coreBeliefs"] = beliefs.joined(separator: "\n")
        }
        if let phrases = clientMeta.signaturePhrases, !phrases.isEmpty {
            legacy["signaturePhrases"] = phrases.joined(separator: " | ")
        }
        if let patterns = clientMeta.preferredBeatPatterns, !patterns.isEmpty {
            legacy["preferredBeatPatterns"] = patterns.joined(separator: ", ")
        }
        if let formats = clientMeta.bestFormats, !formats.isEmpty {
            legacy["bestFormats"] = formats.joined(separator: ", ")
        }
        if let freq = clientMeta.postingFrequency { legacy["postingFrequency"] = freq }
        updatedMeta.legacyFields = legacy.isEmpty ? nil : legacy

        // 3. Build ProfileDocuments from existing content
        var documents: [ProfileDocument] = updatedMeta.documents ?? []

        // 3a. Story document from brandStory + brandVision + coreBeliefs + uniqueAngle
        let storyParts = [
            clientMeta.brandStory.map { "BRAND STORY:\n\($0)" },
            clientMeta.brandVision.map { "BRAND VISION:\n\($0)" },
            clientMeta.coreBeliefs.flatMap { beliefs in
                beliefs.isEmpty ? nil : "CORE BELIEFS:\n\(beliefs.map { "- \($0)" }.joined(separator: "\n"))"
            },
            clientMeta.uniqueAngle.map { "UNIQUE ANGLE:\n\($0)" }
        ].compactMap { $0 }

        if !storyParts.isEmpty {
            documents.append(ProfileDocument(
                category: .story,
                title: "Brand Story & Positioning",
                content: storyParts.joined(separator: "\n\n")
            ))
        }

        // 3b. Voice guide from voiceNotes + signaturePhrases
        let voiceParts = [
            clientMeta.voiceNotes.map { "VOICE NOTES:\n\($0)" },
            clientMeta.signaturePhrases.flatMap { phrases in
                phrases.isEmpty ? nil : "SIGNATURE PHRASES:\n\(phrases.map { "- \"\($0)\"" }.joined(separator: "\n"))"
            }
        ].compactMap { $0 }

        if !voiceParts.isEmpty {
            documents.append(ProfileDocument(
                category: .voiceGuide,
                title: "Voice & Style Guide",
                content: voiceParts.joined(separator: "\n\n")
            ))
        }

        // 3c. Top performer documents from topPerformingPosts
        // Use heuristic: short content (< 500 chars or < 5 sentences) → .reel, longer → .thread
        if let posts = clientMeta.topPerformingPosts {
            for (i, post) in posts.prefix(30).enumerated() {
                guard !post.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let category = inferCategory(from: post.transcript)
                documents.append(ProfileDocument(
                    category: category,
                    title: "\(category == .reel ? "Reel" : "Thread") #\(i + 1)",
                    content: post.transcript,
                    platform: post.platform.isEmpty ? category.platformTag : post.platform
                ))
            }
        }

        // 3d. Top performer documents from topPerformingTranscripts (fallback)
        if (clientMeta.topPerformingPosts ?? []).isEmpty,
           let transcripts = clientMeta.topPerformingTranscripts {
            for (i, transcript) in transcripts.prefix(30).enumerated() {
                guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let category = inferCategory(from: transcript)
                documents.append(ProfileDocument(
                    category: category,
                    title: "\(category == .reel ? "Reel" : "Thread") #\(i + 1)",
                    content: transcript,
                    platform: category.platformTag
                ))
            }
        }

        updatedMeta.documents = documents

        // 4. Save updated metadata back to atom
        let updatedAtom = atom.withMetadata(updatedMeta)
        return try await AtomRepository.shared.update(updatedAtom)
    }

    /// Migrate all existing client profile atoms.
    /// Returns the count of profiles migrated.
    @discardableResult
    func migrateAllProfiles() async throws -> Int {
        let profiles = try await AtomRepository.shared.fetchAll(type: .clientProfile)
        var migratedCount = 0

        for profile in profiles {
            let meta = profile.metadataValue(as: ClientProfileMetadata.self)
            // Skip already-migrated profiles
            if meta?.legacyFields != nil || (meta?.documents ?? []).count > 0 {
                continue
            }
            _ = try await migrateProfile(profile)
            migratedCount += 1
        }

        if migratedCount > 0 {
            print("ProfileMigrationService: migrated \(migratedCount) profiles to new document format")
        }

        return migratedCount
    }

    /// Check whether a profile needs migration (has old fields but no documents/legacyFields)
    func needsMigration(_ atom: Atom) -> Bool {
        guard let meta = atom.metadataValue(as: ClientProfileMetadata.self) else {
            return false
        }
        // Already migrated
        if meta.legacyFields != nil || (meta.documents ?? []).count > 0 {
            return false
        }
        // Has old content worth migrating
        let hasOldContent = meta.brandStory != nil
            || meta.voiceNotes != nil
            || meta.uniqueAngle != nil
            || (meta.topPerformingPosts ?? []).count > 0
            || (meta.topPerformingTranscripts ?? []).count > 0
            || meta.niche != nil
        return hasOldContent
    }

    // MARK: - Helpers

    /// Infer whether content is a reel (short-form) or thread (long-form) based on length heuristics.
    private func inferCategory(from content: String) -> ProfileDocumentCategory {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentenceCount = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
        // Reels are short: < 500 chars or < 5 sentences
        if trimmed.count < 500 || sentenceCount < 5 {
            return .reel
        }
        return .thread
    }
}

// MARK: - Errors

enum MigrationError: Error, LocalizedError {
    case invalidMetadata

    var errorDescription: String? {
        switch self {
        case .invalidMetadata: return "Profile atom does not contain valid ClientProfileMetadata"
        }
    }
}
