// CosmoOS/Daemon/DaemonXPCClient.swift
// App-side XPC client for communicating with CosmoVoiceDaemon
// Provides async/await wrappers and automatic reconnection
// macOS 26+ optimized

import Foundation

// MARK: - XPC Service Identifier

private let kDaemonServiceName = "com.cosmo.voicedaemon"

// MARK: - Daemon XPC Client

@MainActor
public final class DaemonXPCClient: ObservableObject, DaemonXPCClientProtocol, Sendable {
    // MARK: - Singleton

    public static let shared = DaemonXPCClient()

    // MARK: - Published State

    @Published public private(set) var isConnected = false
    @Published public private(set) var lastStatus: DaemonStatus?
    @Published public private(set) var lastError: Error?

    // MARK: - XPC Connection

    private var connection: NSXPCConnection?
    private var reconnectTask: Task<Void, Never>?
    private let reconnectDelay: Duration = .seconds(5)
    private let maxReconnectAttempts = 2  // Reduced - daemon may not be installed
    private var reconnectAttempts = 0
    private var daemonUnavailable = false  // Stop trying if daemon doesn't exist

    // MARK: - Callbacks for streaming

    private var asrChunkHandler: ((L1TranscriptChunk) -> Void)?
    private var isASRStreamActive = false  // Prevent double XPC calls

    // MARK: - Initialization

    private init() {
        setupConnection()
    }

    // MARK: - Connection Management

    private func setupConnection() {
        connection = NSXPCConnection(serviceName: kDaemonServiceName)

        connection?.remoteObjectInterface = NSXPCInterface(with: CosmoVoiceDaemonProtocol.self)

        connection?.interruptionHandler = { [weak self] in
            Task { @MainActor in
                print("DaemonXPCClient: Connection interrupted")
                self?.isConnected = false
                // Reset ASR state since the stream is now dead
                self?.pollingTask?.cancel()
                self?.pollingTask = nil
                self?.isASRStreamActive = false
                self?.asrChunkHandler = nil
                self?.scheduleReconnect()
            }
        }

        connection?.invalidationHandler = { [weak self] in
            Task { @MainActor in
                print("DaemonXPCClient: Connection invalidated")
                self?.isConnected = false
                self?.connection = nil
                // Reset ASR state since the stream is now dead
                self?.pollingTask?.cancel()
                self?.pollingTask = nil
                self?.isASRStreamActive = false
                self?.asrChunkHandler = nil
                self?.scheduleReconnect()
            }
        }

        connection?.resume()
        isConnected = true
        reconnectAttempts = 0
        // Reset ASR state on new connection
        isASRStreamActive = false
        asrChunkHandler = nil
        print("DaemonXPCClient: Connected to daemon")
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        guard reconnectAttempts < maxReconnectAttempts else {
            print("DaemonXPCClient: Max reconnect attempts reached")
            lastError = DaemonClientError.maxReconnectAttemptsReached
            return
        }

        reconnectTask = Task {
            try? await Task.sleep(for: reconnectDelay)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.reconnectAttempts += 1
                print("DaemonXPCClient: Reconnect attempt \(self.reconnectAttempts)")
                self.setupConnection()
                self.reconnectTask = nil
            }
        }
    }

    private func getProxy() throws -> CosmoVoiceDaemonProtocol {
        guard let connection = connection else {
            throw DaemonClientError.notConnected
        }

        guard let proxy = connection.remoteObjectProxy as? CosmoVoiceDaemonProtocol else {
            throw DaemonClientError.invalidProxy
        }

        return proxy
    }

    private func getProxyWithErrorHandler() throws -> CosmoVoiceDaemonProtocol {
        guard let connection = connection else {
            throw DaemonClientError.notConnected
        }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
            Task { @MainActor in
                print("DaemonXPCClient: Proxy error: \(error)")
                self?.lastError = error
            }
        }) as? CosmoVoiceDaemonProtocol else {
            throw DaemonClientError.invalidProxy
        }

        return proxy
    }

    // MARK: - LLM Operations

    /// Generate JSON output from Hermes 3
    public func generateJSON(
        prompt: String,
        systemPrompt: String,
        schema: Data,
        maxTokens: Int = 1024
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let proxy = try getProxyWithErrorHandler()
                proxy.generateJSON(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    schema: schema,
                    maxTokens: maxTokens
                ) { data, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: DaemonClientError.noResponse)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Generate JSON with streaming partial results
    public func generateJSONStreaming(
        prompt: String,
        systemPrompt: String,
        schema: Data,
        maxTokens: Int = 1024,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let proxy = try getProxyWithErrorHandler()
                proxy.generateJSONStreaming(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    schema: schema,
                    maxTokens: maxTokens,
                    partialHandler: onPartial
                ) { data, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: DaemonClientError.noResponse)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Generate tool call using Hermes 3 tool calling format
    /// Returns parsed tool call with function name and arguments
    public func generateToolCall(
        prompt: String,
        systemPrompt: String,
        tools: Data,
        maxTokens: Int = 512
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let proxy = try getProxyWithErrorHandler()
                proxy.generateToolCall(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    tools: tools,
                    maxTokens: maxTokens
                ) { data, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: DaemonClientError.noResponse)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Generate tool call with streaming partial updates
    public func generateToolCallStreaming(
        prompt: String,
        systemPrompt: String,
        tools: Data,
        maxTokens: Int = 512,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let proxy = try getProxyWithErrorHandler()
                proxy.generateToolCallStreaming(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    tools: tools,
                    maxTokens: maxTokens,
                    partialHandler: onPartial
                ) { data, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: DaemonClientError.noResponse)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Embedding Operations

    /// Embed single text (Matryoshka 256d output)
    public func embed(text: String) async throws -> [Float] {
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            do {
                let proxy = try getProxyWithErrorHandler()
                proxy.embed(text: text) { data, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: DaemonClientError.noResponse)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }

        return try JSONDecoder().decode([Float].self, from: data)
    }

    /// Batch embed multiple texts (more efficient)
    public func embedBatch(texts: [String]) async throws -> [[Float]] {
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            do {
                let proxy = try getProxyWithErrorHandler()
                proxy.embedBatch(texts: texts) { data, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: DaemonClientError.noResponse)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }

        return try JSONDecoder().decode([[Float]].self, from: data)
    }

    // MARK: - ASR Operations (Tiered)

    /// Start L1 streaming ASR (Qwen3-ASR-Flash, ~30ms chunks)
    /// Note: Chunks are retrieved via pollL1ASRChunks - XPC doesn't support multiple closure blocks
    public func startL1ASRStream(
        audioFormat: Data,
        onChunk: @escaping @Sendable (L1TranscriptChunk) -> Void
    ) async throws {
        print("🔴 DaemonXPCClient.startL1ASRStream() CALLED - isASRStreamActive: \(isASRStreamActive), isConnected: \(isConnected)")

        // CRITICAL: Block if XPC call is already in-flight
        guard !isASRStreamActive else {
            print("🔴 DaemonXPCClient: ASR stream already in progress, ignoring duplicate call")
            return
        }

        // Ensure we have a valid connection
        guard isConnected, connection != nil else {
            print("🔴 DaemonXPCClient: Not connected, cannot start ASR stream")
            throw DaemonClientError.notConnected
        }

        // Mark as active BEFORE making XPC call
        print("🔴 DaemonXPCClient: Setting isASRStreamActive = true")
        isASRStreamActive = true

        // Store handler for chunk callbacks (used during polling)
        self.asrChunkHandler = onChunk

        // Start the stream on daemon (single reply block - no chunkHandler in XPC)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let proxy = try getProxyWithErrorHandler()
                print("🔴 DaemonXPCClient: About to call proxy.startL1ASRStream")
                proxy.startL1ASRStream(audioFormat: audioFormat) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }

        print("🔴 DaemonXPCClient: startL1ASRStream completed successfully")

        // Start polling for chunks in background
        startChunkPolling()
    }

    /// Poll daemon for ASR chunks (called automatically during streaming)
    private var pollingTask: Task<Void, Never>?

    private func startChunkPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, self?.isASRStreamActive == true {
                await self?.pollForChunks()
                try? await Task.sleep(for: .milliseconds(50))  // Poll every 50ms
            }
            print("🔴 DaemonXPCClient: Chunk polling stopped")
        }
    }

    private func pollForChunks() async {
        guard isASRStreamActive else { return }

        do {
            let chunks = try await pollL1ASRChunks()
            for chunk in chunks {
                asrChunkHandler?(chunk)
            }
        } catch {
            // Polling errors are non-fatal, just log
            print("🔴 DaemonXPCClient: Poll error: \(error)")
        }
    }

    /// Poll for available L1 ASR chunks
    public func pollL1ASRChunks() async throws -> [L1TranscriptChunk] {
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            do {
                let proxy = try getProxyWithErrorHandler()
                proxy.pollL1ASRChunks { data, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }

        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([L1TranscriptChunk].self, from: data)
    }

    /// Check if ASR stream is currently active
    public var isASRActive: Bool {
        isASRStreamActive
    }

    /// Force reset ASR state (for error recovery)
    public func forceResetASRState() {
        pollingTask?.cancel()
        pollingTask = nil
        isASRStreamActive = false
        asrChunkHandler = nil
        print("DaemonXPCClient: ASR state force reset")
    }

    /// Send audio chunk to L1 ASR
    public func sendAudioChunk(samples: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let proxy = try getProxyWithErrorHandler()
                proxy.sendAudioChunk(samples: samples) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Stop L1 ASR stream and get final transcript
    public func stopL1ASRStream() async throws -> String {
        // Stop polling first
        pollingTask?.cancel()
        pollingTask = nil

        defer {
            asrChunkHandler = nil
            isASRStreamActive = false
        }

        // Early return if no stream is active
        guard isASRStreamActive else {
            return ""
        }

        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            do {
                let proxy = try getProxyWithErrorHandler()
                proxy.stopL1ASRStream { data, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: DaemonClientError.noResponse)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }

        return try JSONDecoder().decode(String.self, from: data)
    }

    /// Transcribe with L2 Whisper (on-demand, high accuracy)
    public func transcribeL2(audioSamples: Data, language: String? = nil) async throws -> WhisperResult {
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            do {
                let proxy = try getProxyWithErrorHandler()
                proxy.transcribeL2(audioSamples: audioSamples, language: language) { data, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: DaemonClientError.noResponse)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }

        return try JSONDecoder().decode(WhisperResult.self, from: data)
    }

    /// Check if L2 Whisper is loaded
    public func isL2Loaded() async -> Bool {
        await withCheckedContinuation { continuation in
            do {
                let proxy = try getProxy()
                proxy.isL2Loaded { isLoaded in
                    continuation.resume(returning: isLoaded)
                }
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    /// Pre-load L2 Whisper for dictation mode
    public func preloadL2() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let proxy = try getProxyWithErrorHandler()
                proxy.preloadL2 { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Unload L2 Whisper to save ~1.5GB RAM
    public func unloadWhisperL2() async {
        await withCheckedContinuation { continuation in
            do {
                let proxy = try getProxy()
                proxy.unloadL2 {
                    continuation.resume()
                }
            } catch {
                continuation.resume()
            }
        }
    }

    // MARK: - Context Capture (God Mode)

    /// Capture active window context via Accessibility API
    public func captureActiveWindowContext() async throws -> WindowContext {
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            do {
                let proxy = try getProxyWithErrorHandler()
                proxy.captureActiveWindowContext { data, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: DaemonClientError.noResponse)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }

        return try JSONDecoder().decode(WindowContext.self, from: data)
    }

    // MARK: - Health & Management

    /// Health check with RAM usage
    public func healthCheck() async -> (alive: Bool, ramUsageMB: Int64) {
        await withCheckedContinuation { continuation in
            do {
                let proxy = try getProxy()
                proxy.healthCheck { alive, ramMB in
                    Task { @MainActor in
                        self.isConnected = alive
                    }
                    continuation.resume(returning: (alive, ramMB))
                }
            } catch {
                Task { @MainActor in
                    self.isConnected = false
                }
                continuation.resume(returning: (false, -1))
            }
        }
    }

    /// Get detailed daemon status
    public func getStatus() async -> DaemonStatus? {
        await withCheckedContinuation { continuation in
            do {
                let proxy = try getProxy()
                proxy.getStatus { data in
                    if let data = data,
                       let status = try? JSONDecoder().decode(DaemonStatus.self, from: data) {
                        Task { @MainActor in
                            self.lastStatus = status
                        }
                        continuation.resume(returning: status)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Flush KV cache (emergency memory recovery)
    public func flushKVCache() async {
        await withCheckedContinuation { continuation in
            do {
                let proxy = try getProxy()
                proxy.flushKVCache {
                    print("DaemonXPCClient: KV cache flushed")
                    continuation.resume()
                }
            } catch {
                continuation.resume()
            }
        }
    }

    /// Unload embedding model (saves ~0.5GB)
    public func unloadEmbeddingModel() async {
        await withCheckedContinuation { continuation in
            do {
                let proxy = try getProxy()
                proxy.unloadEmbeddingModel {
                    print("DaemonXPCClient: Embedding model unloaded")
                    continuation.resume()
                }
            } catch {
                continuation.resume()
            }
        }
    }

    /// Unload LLM entirely (saves ~2GB, last resort)
    public func unloadLLM() async {
        await withCheckedContinuation { continuation in
            do {
                let proxy = try getProxy()
                proxy.unloadLLM {
                    print("DaemonXPCClient: LLM unloaded")
                    continuation.resume()
                }
            } catch {
                continuation.resume()
            }
        }
    }

    // MARK: - Lifecycle

    /// Disconnect from daemon
    public func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.invalidate()
        connection = nil
        isConnected = false
    }

    // Note: deinit removed - NSXPCConnection cleanup happens automatically on deallocation
    // Actor-isolated properties can't be accessed from nonisolated deinit in Swift 6
}

// MARK: - Window Context
// Note: WindowContext is defined in Daemon/AXContextService.swift
// The daemon captures context and returns it via XPC

// MARK: - Client Errors

public enum DaemonClientError: LocalizedError, Sendable {
    case notConnected
    case invalidProxy
    case noResponse
    case maxReconnectAttemptsReached
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to daemon"
        case .invalidProxy:
            return "Failed to get daemon proxy"
        case .noResponse:
            return "No response from daemon"
        case .maxReconnectAttemptsReached:
            return "Max reconnect attempts reached"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        }
    }
}

// MARK: - Convenience Extensions

extension DaemonXPCClient {
    /// Wait for daemon to be ready with models loaded (with timeout)
    /// For voice commands to work, we need both embedding AND ASR to be loaded
    public func waitForReady(timeout: Duration = .seconds(30)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        var lastStatus: DaemonStatus?

        print("DaemonXPCClient: Waiting for daemon models to load...")

        while ContinuousClock.now < deadline {
            if let status = await getStatus() {
                lastStatus = status

                // Check if essential models are loaded (need embedding AND ASR for voice)
                if status.embeddingLoaded && status.asrL1Loaded {
                    print("DaemonXPCClient: Daemon ready - embedding and ASR models loaded")
                    return true
                }

                // Log progress every few seconds
                print("DaemonXPCClient: Waiting... (LLM: \(status.llmLoaded), Embedding: \(status.embeddingLoaded), ASR: \(status.asrL1Loaded))")
            }

            try? await Task.sleep(for: .milliseconds(500))
        }

        // Timeout - log final status
        if let status = lastStatus {
            print("DaemonXPCClient: Timeout waiting for models (LLM: \(status.llmLoaded), Embedding: \(status.embeddingLoaded), ASR: \(status.asrL1Loaded))")
            // Return true if at least embedding is loaded, but warn about ASR
            if status.embeddingLoaded && !status.asrL1Loaded {
                print("⚠️ DaemonXPCClient: ASR not loaded - voice commands will use fallback")
            }
        } else {
            print("DaemonXPCClient: Timeout - no status received from daemon")
        }

        return false
    }

    /// Get current RAM usage of daemon
    public func getDaemonRAMUsage() async -> Int64 {
        let (_, ram) = await healthCheck()
        return ram
    }

    /// Check if daemon has enough RAM for L2 Whisper
    public func canLoadL2() async -> Bool {
        guard let status = await getStatus() else { return false }
        // L2 needs ~1.5GB, so check if we're under 10GB total
        return status.ramUsageMB < 10_000
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let daemonConnected = Notification.Name("com.cosmo.daemonConnected")
    static let daemonDisconnected = Notification.Name("com.cosmo.daemonDisconnected")
    static let daemonStatusUpdated = Notification.Name("com.cosmo.daemonStatusUpdated")
}
