// CosmoOS/Navigation/CommandHub/CommandHubCaptureController.swift
// Paste-to-Research capture controller for Command Hub
// Owns the capture state machine + dedupe + live progress mapping

import Foundation
import GRDB

@MainActor
final class CommandHubCaptureController: ObservableObject {
    enum State: Equatable {
        case idle
        case validating(url: String)
        case duplicate(existingResearchId: Int64, url: String)
        case capturing(Capture)
        case failed(Failure)
    }

    struct Capture: Equatable {
        var researchId: Int64
        var url: String
        var urlType: URLType

        var titleHint: String
        var stepLabel: String
        var progress: Double

        var startedAt: Date
        var completedAt: Date?
    }

    struct Failure: Equatable {
        var url: String
        var urlType: URLType
        var titleHint: String
        var message: String
        var canRetry: Bool
    }

    @Published private(set) var state: State = .idle

    private let database = CosmoDatabase.shared
    private var observers: [NSObjectProtocol] = []

    init() {
        installNotificationObservers()
    }

    @MainActor
    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Public API

    /// Handles raw pasted string. If it’s a valid URL and not already saved, begins capture.
    func handlePaste(_ pasted: String) {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.looksLikeURL, let urlType = URLClassifier.classify(trimmed) else { return }

        Task {
            await beginCapture(urlString: trimmed, urlType: urlType)
        }
    }

    func retry() {
        guard case .failed(let failure) = state else { return }
        Task {
            await beginCapture(urlString: failure.url, urlType: failure.urlType)
        }
    }

    func clear() {
        state = .idle
    }

    // MARK: - Capture flow

    private func beginCapture(urlString: String, urlType: URLType) async {
        let normalized = normalize(urlString: urlString, urlType: urlType)
        let titleHint = URLClassifier.suggestedTitle(from: URL(string: normalized) ?? URL(string: urlString)!)

        state = .validating(url: normalized)

        // Dedupe by canonical URL (and YouTube videoId if applicable)
        if let existingId = await findExistingResearchId(normalizedURL: normalized, urlType: urlType) {
            state = .duplicate(existingResearchId: existingId, url: normalized)
            return
        }

        // Create pending record immediately and start background processing.
        do {
            let pending = try await ResearchProcessor.shared.createPendingResearch(urlString: normalized, type: urlType)

            guard let pendingId = pending.id else {
                throw ProcessingError.saveFailed
            }

            state = .capturing(Capture(
                researchId: pendingId,
                url: normalized,
                urlType: urlType,
                titleHint: titleHint,
                stepLabel: "Starting…",
                progress: 0.05,
                startedAt: Date(),
                completedAt: nil
            ))

            // Kick off processing, updating the same row.
            guard let url = URL(string: normalized) else {
                throw ProcessingError.invalidURL
            }

            Task.detached { [pendingId] in
                do {
                    try await ResearchProcessor.shared.processURL(into: pendingId, url: url, type: urlType)
                } catch {
                    NotificationCenter.default.post(
                        name: .researchProcessingFailed,
                        object: nil,
                        userInfo: [
                            "researchId": pendingId,
                            "url": normalized,
                            "message": error.localizedDescription
                        ]
                    )
                }
            }
        } catch {
            state = .failed(Failure(
                url: normalized,
                urlType: urlType,
                titleHint: titleHint,
                message: error.localizedDescription,
                canRetry: true
            ))
        }
    }

    private func findExistingResearchId(normalizedURL: String, urlType: URLType) async -> Int64? {
        // Primary: exact URL match - search in metadata JSON
        if let existing = try? await database.asyncRead({ db in
            try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("is_deleted") == false)
                .filter(Column("metadata").like("%\"\(normalizedURL)\"%"))
                .fetchOne(db)
                .map { ResearchWrapper(atom: $0) }
        }), let id = existing.id {
            return id
        }

        // Secondary: YouTube videoId match inside structured_data (covers alternate URL formats)
        if case .youtube(let videoId) = urlType {
            let needle = "\"videoId\":\"\(videoId)\""
            if let existing = try? await database.asyncRead({ db in
                try Atom
                    .filter(Column("type") == AtomType.research.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("structured_data").like("%\(needle)%"))
                    .fetchOne(db)
                    .map { ResearchWrapper(atom: $0) }
            }), let id = existing.id {
                return id
            }
        }

        return nil
    }

    private func normalize(urlString: String, urlType: URLType) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        switch urlType {
        case .youtube(let videoId):
            return "https://www.youtube.com/watch?v=\(videoId)"
        default:
            // Lightweight canonicalization: drop a trailing slash.
            if trimmed.hasSuffix("/") {
                return String(trimmed.dropLast())
            }
            return trimmed
        }
    }

    // MARK: - Live progress mapping

    private func installNotificationObservers() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(forName: .researchProcessingProgress, object: nil, queue: .main) { [weak self] note in
            let researchId = note.userInfo?["researchId"] as? Int64
            let step = note.userInfo?["step"] as? String
            let progress = note.userInfo?["progress"] as? Double
            Task { @MainActor [self] in
            guard let self else { return }
                guard let researchId, let step, let progress else { return }

            guard case .capturing(var capture) = self.state, capture.researchId == researchId else { return }

            capture.stepLabel = step
            capture.progress = min(max(progress, 0), 1)
            self.state = .capturing(capture)
            }
        })

        observers.append(center.addObserver(forName: .researchProcessingComplete, object: nil, queue: .main) { [weak self] note in
            let research = note.userInfo?["research"] as? Research
            let id = research?.id
            Task { @MainActor [self] in
            guard let self else { return }
                guard research != nil, let id else { return }
            guard case .capturing(var capture) = self.state, capture.researchId == id else { return }

            capture.stepLabel = "Complete"
            capture.progress = 1.0
            capture.completedAt = Date()
            self.state = .capturing(capture)
            }
        })

        observers.append(center.addObserver(forName: .researchProcessingFailed, object: nil, queue: .main) { [weak self] note in
            let researchId = note.userInfo?["researchId"] as? Int64
            let url = note.userInfo?["url"] as? String
            let message = note.userInfo?["message"] as? String
            Task { @MainActor [self] in
            guard let self else { return }
                guard let researchId, let url, let message else { return }

            guard case .capturing(let capture) = self.state, capture.researchId == researchId else { return }

            self.state = .failed(Failure(
                url: url,
                urlType: capture.urlType,
                titleHint: capture.titleHint,
                message: message,
                canRetry: true
            ))
            }
        })
    }
}

// MARK: - Notifications (progress/failure)
extension Notification.Name {
    static let researchProcessingProgress = Notification.Name("researchProcessingProgress")
    static let researchProcessingFailed = Notification.Name("researchProcessingFailed")
}

