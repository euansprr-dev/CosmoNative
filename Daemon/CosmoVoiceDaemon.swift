// CosmoOS/Daemon/CosmoVoiceDaemon.swift
// XPC daemon keeping ML models hot in RAM
// Hosts: FunctionGemma 270M (primary), Hermes 3 (fallback), nomic-embed-text-v1.5, WhisperKit ASR
// Also handles AXContextService for "God Mode" context capture
// macOS 26+ optimized
// Model change: Qwen 0.5B + Hermes 3B → FunctionGemma 270M (6x RAM reduction, <300ms latency)

import Foundation
import MLX
import MLXNN
import MLXRandom
import MLXLLM
import MLXLMCommon
import MLXEmbedders
import WhisperKit

// MARK: - Thread-safe Chunk Buffer (Actor)
/// Actor-based buffer for ASR chunks - avoids NSLock issues in async contexts
actor ChunkBuffer {
    private var chunks: [L1TranscriptChunk] = []

    func append(_ chunk: L1TranscriptChunk) {
        chunks.append(chunk)
    }

    func takeAll() -> [L1TranscriptChunk] {
        let result = chunks
        chunks.removeAll()
        return result
    }

    func clear() {
        chunks.removeAll()
    }
}

// MARK: - File Logger for Daemon
// Since XPC service output goes to system log, write to a file for debugging
private let daemonLogFile = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/CosmoVoiceDaemon.log")

private func daemonLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] \(message)\n"

    // Print to stdout (goes to system log)
    print(message)

    // Also write to file for debugging
    if let data = logMessage.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: daemonLogFile.path) {
            if let handle = try? FileHandle(forWritingTo: daemonLogFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: daemonLogFile)
        }
    }
}

// MARK: - XPC Protocol

@objc public protocol CosmoVoiceDaemonProtocol {
    // MARK: - LLM Operations

    /// Generate JSON output from Hermes 3 with GBNF grammar enforcement
    func generateJSON(
        prompt: String,
        systemPrompt: String,
        schema: Data,
        maxTokens: Int,
        reply: @escaping @Sendable (Data?, Error?) -> Void
    )

    /// Stream JSON generation (for speculative UI)
    func generateJSONStreaming(
        prompt: String,
        systemPrompt: String,
        schema: Data,
        maxTokens: Int,
        partialHandler: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Data?, Error?) -> Void
    )

    /// Generate tool call using Hermes 3 tool calling format
    /// Returns parsed tool call with function name and arguments
    func generateToolCall(
        prompt: String,
        systemPrompt: String,
        tools: Data,  // Array of tool definitions
        maxTokens: Int,
        reply: @escaping @Sendable (Data?, Error?) -> Void
    )

    /// Stream tool call generation with partial updates
    func generateToolCallStreaming(
        prompt: String,
        systemPrompt: String,
        tools: Data,
        maxTokens: Int,
        partialHandler: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Data?, Error?) -> Void
    )

    /// Quick entity extraction using Qwen 0.5B (<200ms target)
    /// Used for fast fallback when pattern matching has low confidence
    /// DEPRECATED: Use generateFunctionGemmaCall instead
    func quickExtractEntities(
        transcript: String,
        intent: String,
        reply: @escaping @Sendable (Data?, Error?) -> Void
    )

    // MARK: - FunctionGemma Operations (Micro-Brain)

    /// Generate a function call using FunctionGemma 270M (<300ms target)
    /// Primary method for voice command processing in the Micro-Brain architecture
    /// Returns FunctionCall JSON with name and parameters
    func generateFunctionGemmaCall(
        transcript: String,
        contextSection: String,
        contextDate: String,
        reply: @escaping @Sendable (Data?, Error?) -> Void
    )

    /// Check if FunctionGemma is loaded and ready
    func isFunctionGemmaReady(reply: @escaping @Sendable (Bool) -> Void)

    // MARK: - Embedding Operations

    /// Embed single text
    func embed(text: String, reply: @escaping @Sendable (Data?, Error?) -> Void)

    /// Batch embed multiple texts (more efficient)
    func embedBatch(texts: [String], reply: @escaping @Sendable (Data?, Error?) -> Void)

    // MARK: - ASR Operations (Tiered)

    /// Start L1 streaming ASR (Qwen3-ASR-Flash)
    /// Note: Chunks are retrieved via pollL1ASRChunks - XPC doesn't support multiple closure blocks
    func startL1ASRStream(
        audioFormat: Data,  // Serialized audio format
        reply: @escaping @Sendable (Error?) -> Void
    )

    /// Poll for available L1 ASR chunks since last poll
    /// Returns array of L1TranscriptChunk encoded as JSON
    func pollL1ASRChunks(reply: @escaping @Sendable (Data?, Error?) -> Void)

    /// Send audio chunk to L1 ASR
    func sendAudioChunk(samples: Data, reply: @escaping @Sendable (Error?) -> Void)

    /// Stop L1 ASR stream
    func stopL1ASRStream(reply: @escaping @Sendable (Data?, Error?) -> Void)  // Final transcript

    /// Transcribe with L2 Whisper (on-demand, batch)
    func transcribeL2(
        audioSamples: Data,
        language: String?,
        reply: @escaping @Sendable (Data?, Error?) -> Void
    )

    /// Check if L2 Whisper is loaded
    func isL2Loaded(reply: @escaping @Sendable (Bool) -> Void)

    /// Pre-load L2 Whisper for dictation mode
    func preloadL2(reply: @escaping @Sendable (Error?) -> Void)

    /// Unload L2 Whisper to save RAM
    func unloadL2(reply: @escaping @Sendable () -> Void)

    // MARK: - Context Capture (God Mode)

    /// Capture active window context via Accessibility API
    func captureActiveWindowContext(reply: @escaping @Sendable (Data?, Error?) -> Void)

    // MARK: - Health & Management

    /// Health check with RAM usage
    func healthCheck(reply: @escaping @Sendable (Bool, Int64) -> Void)  // (alive, ramUsageMB)

    /// Get detailed status
    func getStatus(reply: @escaping @Sendable (Data?) -> Void)

    /// Flush KV cache (emergency memory)
    func flushKVCache(reply: @escaping @Sendable () -> Void)

    /// Unload embedding model (emergency memory)
    func unloadEmbeddingModel(reply: @escaping @Sendable () -> Void)

    /// Unload LLM entirely (last resort)
    func unloadLLM(reply: @escaping @Sendable () -> Void)
}

// MARK: - Daemon Status

public struct DaemonStatus: Codable, Sendable {
    public let isRunning: Bool
    public let llmLoaded: Bool
    public let quickLLMLoaded: Bool  // Qwen 0.5B for fast commands (DEPRECATED)
    public let functionGemmaLoaded: Bool  // FunctionGemma 270M - primary Micro-Brain
    public let embeddingLoaded: Bool
    public let asrL1Loaded: Bool
    public let asrL2Loaded: Bool
    public let ramUsageMB: Int64
    public let kvCacheSizeMB: Int64
    public let uptime: TimeInterval
    public let lastHealthCheck: Date

    public init(
        isRunning: Bool,
        llmLoaded: Bool,
        quickLLMLoaded: Bool = false,
        functionGemmaLoaded: Bool = false,
        embeddingLoaded: Bool,
        asrL1Loaded: Bool,
        asrL2Loaded: Bool,
        ramUsageMB: Int64,
        kvCacheSizeMB: Int64,
        uptime: TimeInterval,
        lastHealthCheck: Date
    ) {
        self.isRunning = isRunning
        self.llmLoaded = llmLoaded
        self.quickLLMLoaded = quickLLMLoaded
        self.functionGemmaLoaded = functionGemmaLoaded
        self.embeddingLoaded = embeddingLoaded
        self.asrL1Loaded = asrL1Loaded
        self.asrL2Loaded = asrL2Loaded
        self.ramUsageMB = ramUsageMB
        self.kvCacheSizeMB = kvCacheSizeMB
        self.uptime = uptime
        self.lastHealthCheck = lastHealthCheck
    }
}

// MARK: - Daemon Implementation

public final class CosmoVoiceDaemon: NSObject, CosmoVoiceDaemonProtocol, @unchecked Sendable {
    // MARK: - Singleton (for daemon process)

    public static let shared = CosmoVoiceDaemon()

    // MARK: - Model State

    private var llmEngine: HermesLLMEngine?
    private var quickLLMEngine: QuickLLMEngine?  // Qwen 0.5B for fast entity extraction (DEPRECATED)
    private var functionGemmaEngine: DaemonMLXFunctionGemmaEngine?  // FunctionGemma 270M - primary Micro-Brain
    private var embeddingEngine: NomicEmbeddingEngine?
    private var asrL1Engine: Qwen3ASREngine?
    private var asrL2Engine: WhisperL2Engine?
    private var axContextService: AXContextService?

    // MARK: - State Tracking

    private var startTime = Date()
    private var lastHealthCheck = Date()
    private var isL1Streaming = false
    private let chunkBuffer = ChunkBuffer()  // Actor-based thread-safe buffer

    // MARK: - Initialization

    private override init() {
        super.init()
        daemonLog("CosmoVoiceDaemon: Initializing...")
    }

    public func initialize() async {
        daemonLog("CosmoVoiceDaemon: Loading models...")

        // Load models in parallel
        // Micro-Brain Architecture:
        // - FunctionGemma 270M: Primary function calling (~550MB)
        // - Embedding: nomic-embed-text-v1.5 (~0.5GB)
        // - ASR: WhisperKit (streaming transcription)
        // NOTE: Hermes 3B removed - no longer needed, saves ~2GB RAM
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadFunctionGemma() }  // Primary: FunctionGemma 270M (~550MB)
            // group.addTask { await self.loadLLM() }         // REMOVED: Hermes 3B (~2GB) - FunctionGemma handles all function calls
            // group.addTask { await self.loadQuickLLM() }    // DEPRECATED: Qwen 0.5B
            group.addTask { await self.loadEmbedding() }
            group.addTask { await self.loadASRL1() }
            group.addTask { await self.loadAXContext() }
        }

        daemonLog("CosmoVoiceDaemon: Ready")
    }

    // MARK: - Model Loading

    private func loadLLM() async {
        do {
            daemonLog("CosmoVoiceDaemon: Starting Hermes 3 Llama 3.2 3B download (this may take several minutes on first run)...")
            let engine = try await MLXHermesLLMEngine()
            llmEngine = engine
            daemonLog("CosmoVoiceDaemon: Hermes 3 Llama 3.2 3B-4bit loaded (~2GB)")
        } catch {
            daemonLog("CosmoVoiceDaemon: Failed to load Hermes LLM: \(error)")
            llmEngine = nil
        }
    }

    private func loadQuickLLM() async {
        do {
            let engine = try await MLXQuickLLMEngine()
            quickLLMEngine = engine
            daemonLog("CosmoVoiceDaemon: Qwen 2.5-0.5B-4bit loaded (~300MB)")
        } catch {
            daemonLog("CosmoVoiceDaemon: Failed to load Quick LLM: \(error)")
            quickLLMEngine = nil
        }
    }

    private func loadEmbedding() async {
        do {
            let engine = try await MLXNomicEmbeddingEngine()
            // Validate the model actually works by doing a test embedding
            daemonLog("CosmoVoiceDaemon: Validating embedding model...")
            let testEmbedding = try await engine.embed(text: "test")
            guard testEmbedding.count == 256 else {
                daemonLog("CosmoVoiceDaemon: Embedding model validation failed - wrong dimension: \(testEmbedding.count)")
                return
            }
            embeddingEngine = engine
            daemonLog("CosmoVoiceDaemon: nomic-embed-text-v1.5 loaded and validated (~0.5GB)")
        } catch {
            daemonLog("CosmoVoiceDaemon: Failed to load embedding model: \(error)")
            // Ensure engine is nil so status reports correctly
            embeddingEngine = nil
        }
    }

    private func loadASRL1() async {
        do {
            daemonLog("CosmoVoiceDaemon: Starting WhisperKit download...")
            let engine = try await WhisperKitASREngine()
            asrL1Engine = engine
            daemonLog("CosmoVoiceDaemon: WhisperKit (base) loaded for streaming ASR")
        } catch {
            daemonLog("CosmoVoiceDaemon: Failed to load ASR L1: \(error)")
            asrL1Engine = nil
        }
    }

    private func loadAXContext() async {
        axContextService = AXContextService()
        daemonLog("CosmoVoiceDaemon: AXContextService ready")
    }

    private func loadFunctionGemma() async {
        do {
            daemonLog("CosmoVoiceDaemon: Starting FunctionGemma 270M download (~550MB)...")
            let engine = try await DaemonMLXFunctionGemmaEngine()
            functionGemmaEngine = engine
            daemonLog("CosmoVoiceDaemon: FunctionGemma 270M loaded - primary Micro-Brain ready")
        } catch {
            daemonLog("CosmoVoiceDaemon: Failed to load FunctionGemma: \(error)")
            functionGemmaEngine = nil
        }
    }

    // MARK: - LLM Operations

    public func generateJSON(
        prompt: String,
        systemPrompt: String,
        schema: Data,
        maxTokens: Int,
        reply: @escaping @Sendable (Data?, Error?) -> Void
    ) {
        Task { @Sendable in
            guard let engine = llmEngine else {
                reply(nil, DaemonError.modelNotLoaded("Hermes LLM"))
                return
            }

            do {
                let result = try await engine.generate(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    schema: schema,
                    maxTokens: maxTokens
                )
                reply(result, nil)
            } catch {
                reply(nil, error)
            }
        }
    }

    public func generateJSONStreaming(
        prompt: String,
        systemPrompt: String,
        schema: Data,
        maxTokens: Int,
        partialHandler: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Data?, Error?) -> Void
    ) {
        Task { @Sendable in
            guard let engine = llmEngine else {
                completion(nil, DaemonError.modelNotLoaded("Hermes LLM"))
                return
            }

            do {
                let result = try await engine.generateStreaming(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    schema: schema,
                    maxTokens: maxTokens,
                    onPartial: partialHandler
                )
                completion(result, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    public func generateToolCall(
        prompt: String,
        systemPrompt: String,
        tools: Data,
        maxTokens: Int,
        reply: @escaping @Sendable (Data?, Error?) -> Void
    ) {
        Task { @Sendable in
            guard let engine = llmEngine else {
                reply(nil, DaemonError.modelNotLoaded("Hermes LLM"))
                return
            }

            do {
                let result = try await engine.generateToolCall(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    tools: tools,
                    maxTokens: maxTokens
                )
                reply(result, nil)
            } catch {
                reply(nil, error)
            }
        }
    }

    public func generateToolCallStreaming(
        prompt: String,
        systemPrompt: String,
        tools: Data,
        maxTokens: Int,
        partialHandler: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Data?, Error?) -> Void
    ) {
        Task { @Sendable in
            guard let engine = llmEngine else {
                completion(nil, DaemonError.modelNotLoaded("Hermes LLM"))
                return
            }

            do {
                let result = try await engine.generateToolCallStreaming(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    tools: tools,
                    maxTokens: maxTokens,
                    onPartial: partialHandler
                )
                completion(result, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    public func quickExtractEntities(
        transcript: String,
        intent: String,
        reply: @escaping @Sendable (Data?, Error?) -> Void
    ) {
        Task { @Sendable in
            // Try quick LLM first (Qwen 0.5B - ~150ms)
            if let quickEngine = quickLLMEngine {
                do {
                    let result = try await quickEngine.extractEntities(
                        transcript: transcript,
                        intent: intent
                    )
                    reply(result, nil)
                    return
                } catch {
                    daemonLog("CosmoVoiceDaemon: Quick LLM failed, falling back to Hermes: \(error)")
                    // Fall through to Hermes
                }
            }

            // Fallback to Hermes 3 if quick LLM unavailable or failed
            guard let engine = llmEngine else {
                reply(nil, DaemonError.modelNotLoaded("No LLM available"))
                return
            }

            do {
                // Use Hermes with minimal prompt
                let prompt = """
                Extract entities from this voice command:
                Intent: \(intent)
                Command: "\(transcript)"

                Return JSON with: title, startTime (HH:MM), endTime (HH:MM), persons (array), destination
                """

                let schema = """
                {"type":"object","properties":{"title":{"type":"string"},"startTime":{"type":"string"},"endTime":{"type":"string"},"persons":{"type":"array","items":{"type":"string"}},"destination":{"type":"string"}}}
                """.data(using: .utf8)!

                let result = try await engine.generate(
                    prompt: prompt,
                    systemPrompt: "Extract entities from voice commands. Output only JSON.",
                    schema: schema,
                    maxTokens: 80
                )
                reply(result, nil)
            } catch {
                reply(nil, error)
            }
        }
    }

    // MARK: - FunctionGemma Operations (Micro-Brain)

    public func generateFunctionGemmaCall(
        transcript: String,
        contextSection: String,
        contextDate: String,
        reply: @escaping @Sendable (Data?, Error?) -> Void
    ) {
        Task { @Sendable in
            guard let engine = functionGemmaEngine else {
                // Fallback: try Hermes 3 for backwards compatibility
                daemonLog("CosmoVoiceDaemon: FunctionGemma not loaded, falling back to Hermes")
                await self.fallbackToHermes(transcript: transcript, reply: reply)
                return
            }

            let startTime = Date()

            do {
                let result = try await engine.generateFunctionCall(
                    transcript: transcript,
                    contextSection: contextSection,
                    contextDate: contextDate
                )

                let inferenceMs = Date().timeIntervalSince(startTime) * 1000
                daemonLog("CosmoVoiceDaemon: FunctionGemma call in \(String(format: "%.0f", inferenceMs))ms")

                reply(result, nil)
            } catch {
                daemonLog("CosmoVoiceDaemon: FunctionGemma error: \(error), falling back to Hermes")
                await self.fallbackToHermes(transcript: transcript, reply: reply)
            }
        }
    }

    public func isFunctionGemmaReady(reply: @escaping @Sendable (Bool) -> Void) {
        reply(functionGemmaEngine != nil)
    }

    /// Fallback to Hermes 3 when FunctionGemma is unavailable
    private func fallbackToHermes(
        transcript: String,
        reply: @escaping @Sendable (Data?, Error?) -> Void
    ) async {
        guard let engine = llmEngine else {
            reply(nil, DaemonError.modelNotLoaded("No LLM available (FunctionGemma or Hermes)"))
            return
        }

        // Build a tool calling prompt for Hermes that mimics FunctionGemma output
        let tools = """
        [
            {"name": "create_atom", "parameters": {"atom_type": "string", "title": "string", "body": "string", "metadata": "object", "links": "array"}},
            {"name": "update_atom", "parameters": {"target": "string", "title": "string", "metadata": "object"}},
            {"name": "delete_atom", "parameters": {"target": "string"}},
            {"name": "query_level_system", "parameters": {"query_type": "string"}},
            {"name": "navigate", "parameters": {"destination": "string"}},
            {"name": "start_deep_work", "parameters": {"duration_minutes": "integer"}},
            {"name": "stop_deep_work", "parameters": {}},
            {"name": "batch_create", "parameters": {"items": "array"}}
        ]
        """

        do {
            let result = try await engine.generateToolCall(
                prompt: transcript,
                systemPrompt: "Interpret the user's voice command and call the appropriate function.",
                tools: tools.data(using: .utf8)!,
                maxTokens: 200
            )
            reply(result, nil)
        } catch {
            reply(nil, error)
        }
    }

    // MARK: - Embedding Operations

    public func embed(text: String, reply: @escaping @Sendable (Data?, Error?) -> Void) {
        Task { @Sendable in
            guard let engine = embeddingEngine else {
                reply(nil, DaemonError.modelNotLoaded("nomic embedding"))
                return
            }

            do {
                let embedding = try await engine.embed(text: text)
                let data = try JSONEncoder().encode(embedding)
                reply(data, nil)
            } catch {
                reply(nil, error)
            }
        }
    }

    public func embedBatch(texts: [String], reply: @escaping @Sendable (Data?, Error?) -> Void) {
        Task { @Sendable in
            guard let engine = embeddingEngine else {
                reply(nil, DaemonError.modelNotLoaded("nomic embedding"))
                return
            }

            do {
                let embeddings = try await engine.embedBatch(texts: texts)
                let data = try JSONEncoder().encode(embeddings)
                reply(data, nil)
            } catch {
                reply(nil, error)
            }
        }
    }

    // MARK: - ASR Operations

    public func startL1ASRStream(
        audioFormat: Data,
        reply: @escaping @Sendable (Error?) -> Void
    ) {
        Task { @Sendable in
            guard let engine = asrL1Engine else {
                reply(DaemonError.modelNotLoaded("Qwen3-ASR-Flash"))
                return
            }

            // Clear any pending chunks from previous session
            await chunkBuffer.clear()

            do {
                isL1Streaming = true
                try await engine.startStreaming(
                    formatData: audioFormat,
                    onChunk: { [weak self] chunk in
                        // Accumulate chunks for polling instead of callback
                        guard let buffer = self?.chunkBuffer else { return }
                        let chunkCopy = chunk
                        Task { @MainActor [buffer] in
                            await buffer.append(chunkCopy)
                        }
                    }
                )
                reply(nil)
            } catch {
                isL1Streaming = false
                reply(error)
            }
        }
    }

    public func pollL1ASRChunks(reply: @escaping @Sendable (Data?, Error?) -> Void) {
        // Return all accumulated chunks and clear the buffer
        Task {
            let chunks = await chunkBuffer.takeAll()
            do {
                let data = try JSONEncoder().encode(chunks)
                reply(data, nil)
            } catch {
                reply(nil, error)
            }
        }
    }

    public func sendAudioChunk(samples: Data, reply: @escaping @Sendable (Error?) -> Void) {
        Task { @Sendable in
            guard let engine = asrL1Engine, isL1Streaming else {
                reply(DaemonError.notStreaming)
                return
            }

            do {
                try await engine.processAudioChunk(samples: samples)
                reply(nil)
            } catch {
                reply(error)
            }
        }
    }

    public func stopL1ASRStream(reply: @escaping @Sendable (Data?, Error?) -> Void) {
        Task { @Sendable in
            guard let engine = asrL1Engine else {
                reply(nil, DaemonError.modelNotLoaded("Qwen3-ASR-Flash"))
                return
            }

            do {
                let finalTranscript = try await engine.stopStreaming()
                isL1Streaming = false
                let data = try JSONEncoder().encode(finalTranscript)
                reply(data, nil)
            } catch {
                isL1Streaming = false
                reply(nil, error)
            }
        }
    }

    public func transcribeL2(
        audioSamples: Data,
        language: String?,
        reply: @escaping @Sendable (Data?, Error?) -> Void
    ) {
        Task { @Sendable in
            // Lazy-load L2 if needed
            if asrL2Engine == nil {
                do {
                    asrL2Engine = try await WhisperKitL2Engine()
                    daemonLog("CosmoVoiceDaemon: WhisperKit large-v3 loaded on-demand (~3GB)")
                } catch {
                    reply(nil, error)
                    return
                }
            }

            do {
                let result = try await asrL2Engine!.transcribe(
                    audioSamples: audioSamples,
                    language: language
                )
                let data = try JSONEncoder().encode(result)
                reply(data, nil)
            } catch {
                reply(nil, error)
            }
        }
    }

    public func isL2Loaded(reply: @escaping @Sendable (Bool) -> Void) {
        reply(asrL2Engine != nil)
    }

    public func preloadL2(reply: @escaping @Sendable (Error?) -> Void) {
        Task { @Sendable in
            if asrL2Engine != nil {
                reply(nil)
                return
            }

            do {
                asrL2Engine = try await WhisperKitL2Engine()
                daemonLog("CosmoVoiceDaemon: WhisperKit large-v3 pre-loaded (~3GB)")
                reply(nil)
            } catch {
                reply(error)
            }
        }
    }

    public func unloadL2(reply: @escaping @Sendable () -> Void) {
        asrL2Engine = nil
        daemonLog("CosmoVoiceDaemon: Whisper L2 unloaded (saved ~1.5GB)")
        reply()
    }

    // MARK: - Context Capture

    public func captureActiveWindowContext(reply: @escaping @Sendable (Data?, Error?) -> Void) {
        Task { @Sendable in
            guard let service = axContextService else {
                reply(nil, DaemonError.serviceNotInitialized("AXContextService"))
                return
            }

            do {
                let context = await service.captureActiveWindowContext()
                let data = try JSONEncoder().encode(context)
                reply(data, nil)
            } catch {
                reply(nil, error)
            }
        }
    }

    // MARK: - Health & Management

    public func healthCheck(reply: @escaping @Sendable (Bool, Int64) -> Void) {
        lastHealthCheck = Date()

        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }

        let ramMB: Int64
        if result == KERN_SUCCESS {
            ramMB = Int64(info.phys_footprint / (1024 * 1024))
        } else {
            ramMB = -1
        }

        reply(true, ramMB)
    }

    public func getStatus(reply: @escaping @Sendable (Data?) -> Void) {
        Task { @Sendable in
            var ramUsageMB: Int64 = 0
            var kvCacheSizeMB: Int64 = 0

            // Get RAM usage
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

            let result = withUnsafeMutablePointer(to: &info) { infoPtr in
                infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
                }
            }

            if result == KERN_SUCCESS {
                ramUsageMB = Int64(info.phys_footprint / (1024 * 1024))
            }

            // Get KV cache size if LLM is loaded
            if let engine = llmEngine {
                kvCacheSizeMB = await engine.getKVCacheSizeMB()
            }

            let status = DaemonStatus(
                isRunning: true,
                llmLoaded: llmEngine != nil,
                quickLLMLoaded: quickLLMEngine != nil,
                functionGemmaLoaded: functionGemmaEngine != nil,
                embeddingLoaded: embeddingEngine != nil,
                asrL1Loaded: asrL1Engine != nil,
                asrL2Loaded: asrL2Engine != nil,
                ramUsageMB: ramUsageMB,
                kvCacheSizeMB: kvCacheSizeMB,
                uptime: Date().timeIntervalSince(startTime),
                lastHealthCheck: lastHealthCheck
            )

            let data = try? JSONEncoder().encode(status)
            reply(data)
        }
    }

    public func flushKVCache(reply: @escaping @Sendable () -> Void) {
        Task { @Sendable in
            await llmEngine?.flushKVCache()
            daemonLog("CosmoVoiceDaemon: KV cache flushed")
            reply()
        }
    }

    public func unloadEmbeddingModel(reply: @escaping @Sendable () -> Void) {
        embeddingEngine = nil
        daemonLog("CosmoVoiceDaemon: Embedding model unloaded (saved ~0.5GB)")
        reply()
    }

    public func unloadLLM(reply: @escaping @Sendable () -> Void) {
        Task { @Sendable in
            await llmEngine?.shutdown()
            llmEngine = nil
            daemonLog("CosmoVoiceDaemon: Hermes LLM unloaded (saved ~2GB)")
            reply()
        }
    }
}

// MARK: - Daemon Errors

public enum DaemonError: LocalizedError, Sendable {
    case modelNotLoaded(String)
    case notStreaming
    case serviceNotInitialized(String)
    case invalidInput(String)
    case inferenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded(let model):
            return "Model not loaded: \(model)"
        case .notStreaming:
            return "Not currently streaming"
        case .serviceNotInitialized(let service):
            return "Service not initialized: \(service)"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .inferenceFailed(let message):
            return "Inference failed: \(message)"
        }
    }
}

// MARK: - Engine Protocols

protocol HermesLLMEngine {
    init() async throws
    func generate(prompt: String, systemPrompt: String, schema: Data, maxTokens: Int) async throws -> Data
    func generateStreaming(prompt: String, systemPrompt: String, schema: Data, maxTokens: Int, onPartial: @escaping (String) -> Void) async throws -> Data
    func generateToolCall(prompt: String, systemPrompt: String, tools: Data, maxTokens: Int) async throws -> Data
    func generateToolCallStreaming(prompt: String, systemPrompt: String, tools: Data, maxTokens: Int, onPartial: @escaping (String) -> Void) async throws -> Data
    func getKVCacheSizeMB() async -> Int64
    func flushKVCache() async
    func shutdown() async
}

protocol NomicEmbeddingEngine {
    init() async throws
    func embed(text: String) async throws -> [Float]
    func embedBatch(texts: [String]) async throws -> [[Float]]
}

protocol Qwen3ASREngine {
    init() async throws
    func startStreaming(formatData: Data, onChunk: @escaping (L1TranscriptChunk) -> Void) async throws
    func processAudioChunk(samples: Data) async throws
    func stopStreaming() async throws -> String
}

protocol WhisperL2Engine {
    init() async throws
    func transcribe(audioSamples: Data, language: String?) async throws -> DaemonWhisperResult
}

/// Quick LLM engine for fast entity extraction (Qwen 2.5-0.5B)
/// Used for simple voice commands when fast path has low confidence
/// Target: <200ms inference on M3/M4/M5
/// DEPRECATED: Use FunctionGemmaEngine instead
protocol QuickLLMEngine {
    init() async throws
    func extractEntities(transcript: String, intent: String) async throws -> Data
    func shutdown() async
}

/// FunctionGemma 270M engine protocol - the Micro-Brain dispatcher
/// Interprets voice commands and outputs function calls
/// Target: <300ms inference, ~550MB RAM
/// Note: The actual actor implementation is in AI/MicroBrain/FunctionGemmaEngine.swift
protocol DaemonFunctionGemmaEngine {
    init() async throws
    func generateFunctionCall(transcript: String, contextSection: String, contextDate: String) async throws -> Data
    func shutdown() async
}

// MARK: - Daemon Whisper Result (L2)

/// Whisper result returned by daemon via XPC
public struct DaemonWhisperResult: Codable, Sendable {
    public let text: String
    public let segments: [DaemonTranscriptSegment]
    public let language: String
    public let duration: TimeInterval

    public init(text: String, segments: [DaemonTranscriptSegment], language: String, duration: TimeInterval) {
        self.text = text
        self.segments = segments
        self.language = language
        self.duration = duration
    }
}

/// Transcript segment returned by daemon
public struct DaemonTranscriptSegment: Codable, Sendable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let confidence: Double

    public init(text: String, start: TimeInterval, end: TimeInterval, confidence: Double) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

// MARK: - Real MLX LLM Engine (Hermes 3 Llama 3.2 3B)

/// Hermes 3 LLM engine using mlx-swift-lm
/// Hermes 3 achieves 91% function calling accuracy with special <tool_call> tokens
final class MLXHermesLLMEngine: HermesLLMEngine {
    private var modelContainer: MLXLMCommon.ModelContainer?
    private var chatSession: ChatSession?
    private var cache: [KVCache] = []

    // Early stopping pattern for tool calls
    private let toolCallEndPattern = "</tool_call>"

    /// Model configuration - Hermes 3 Llama 3.2 3B Instruct (4-bit quantized)
    /// ~2GB RAM vs ~4.5GB for Qwen 2.5-7B
    /// Optimized for tool calling with <tool_call> format
    private static let modelConfig = ModelConfiguration(
        id: "mlx-community/Hermes-3-Llama-3.2-3B-4bit",
        defaultPrompt: "You are a helpful AI assistant."
    )

    /// Hermes 3 tool calling system prompt template
    private static let toolCallingSystemPrompt = """
    You are a function calling AI model. You are provided with function signatures within <tools></tools> XML tags. \
    You may call one or more functions to assist with the user query. Don't make assumptions about what values to plug into functions. \
    Here are the available tools:
    <tools>
    %TOOLS%
    </tools>

    For each function call return a json object with function name and arguments within <tool_call></tool_call> XML tags as follows:
    <tool_call>
    {"name": <function-name>, "arguments": <args-dict>}
    </tool_call>
    """

    init() async throws {
        daemonLog("MLXHermesLLMEngine: Starting Hermes 3 Llama 3.2 3B download (~2GB)...")
        daemonLog("MLXHermesLLMEngine: Model will be cached at ~/Library/Caches/models/mlx-community/")

        // Load the model container
        modelContainer = try await LLMModelFactory.shared.loadContainer(
            configuration: Self.modelConfig
        ) { progress in
            // Log at 25%, 50%, 75%, 100%
            let percent = Int(progress.fractionCompleted * 100)
            if percent == 25 || percent == 50 || percent == 75 || percent == 100 {
                daemonLog("MLXHermesLLMEngine: Download progress: \(percent)%")
            }
        }

        // Create chat session for generation
        if let container = modelContainer {
            chatSession = ChatSession(
                container,
                instructions: "You are a helpful AI assistant that outputs JSON responses.",
                generateParameters: GenerateParameters(maxTokens: 512, temperature: 0.3)
            )
        }

        daemonLog("MLXHermesLLMEngine: Hermes 3 Llama 3.2 3B loaded successfully")
    }

    func generate(prompt: String, systemPrompt: String, schema: Data, maxTokens: Int) async throws -> Data {
        guard let container = modelContainer else {
            throw DaemonError.modelNotLoaded("Hermes LLM")
        }

        // Build the prompt with system message and JSON schema
        let schemaStr = String(data: schema, encoding: .utf8) ?? "{}"
        let promptWithSchema = "\(prompt)\n\nRespond with valid JSON matching this schema:\n\(schemaStr)"

        // Create a new chat session with the system prompt for each generation
        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.3)
        )

        let response = try await session.respond(to: promptWithSchema)

        // Extract JSON from response
        if let jsonData = extractJSON(from: response) {
            return jsonData
        }

        // Fallback: try to encode the raw response
        return response.data(using: .utf8) ?? Data()
    }

    func generateStreaming(prompt: String, systemPrompt: String, schema: Data, maxTokens: Int, onPartial: @escaping (String) -> Void) async throws -> Data {
        guard let container = modelContainer else {
            throw DaemonError.modelNotLoaded("Hermes LLM")
        }

        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.3)
        )

        var fullResponse = ""
        for try await chunk in session.streamResponse(to: prompt) {
            fullResponse += chunk
            onPartial(chunk)
        }

        if let jsonData = extractJSON(from: fullResponse) {
            return jsonData
        }

        return fullResponse.data(using: .utf8) ?? Data()
    }

    func generateToolCall(prompt: String, systemPrompt: String, tools: Data, maxTokens: Int) async throws -> Data {
        guard let container = modelContainer else {
            throw DaemonError.modelNotLoaded("Hermes LLM")
        }

        // Build Hermes 3 tool calling prompt
        let toolsStr = String(data: tools, encoding: .utf8) ?? "[]"
        let hermesSystemPrompt = Self.toolCallingSystemPrompt.replacingOccurrences(of: "%TOOLS%", with: toolsStr)
        let fullSystemPrompt = systemPrompt.isEmpty ? hermesSystemPrompt : "\(systemPrompt)\n\n\(hermesSystemPrompt)"

        let session = ChatSession(
            container,
            instructions: fullSystemPrompt,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.1) // Lower temp for tool calls
        )

        let response = try await session.respond(to: prompt)

        // Extract tool call from <tool_call></tool_call> tags
        if let toolCallData = extractToolCall(from: response) {
            return toolCallData
        }

        // Fallback: try to extract raw JSON
        if let jsonData = extractJSON(from: response) {
            return jsonData
        }

        throw DaemonError.inferenceFailed("No valid tool call found in response")
    }

    func generateToolCallStreaming(prompt: String, systemPrompt: String, tools: Data, maxTokens: Int, onPartial: @escaping (String) -> Void) async throws -> Data {
        guard let container = modelContainer else {
            throw DaemonError.modelNotLoaded("Hermes LLM")
        }

        // Build Hermes 3 tool calling prompt
        let toolsStr = String(data: tools, encoding: .utf8) ?? "[]"
        let hermesSystemPrompt = Self.toolCallingSystemPrompt.replacingOccurrences(of: "%TOOLS%", with: toolsStr)
        let fullSystemPrompt = systemPrompt.isEmpty ? hermesSystemPrompt : "\(systemPrompt)\n\n\(hermesSystemPrompt)"

        let session = ChatSession(
            container,
            instructions: fullSystemPrompt,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.1)
        )

        var fullResponse = ""
        var earlyStop = false

        for try await chunk in session.streamResponse(to: prompt) {
            fullResponse += chunk
            onPartial(chunk)

            // Early stopping: once we have a complete tool call, stop generating
            // This can save significant time (e.g., stop at 50 tokens instead of 100)
            if fullResponse.contains(toolCallEndPattern) {
                earlyStop = true
                break
            }
        }

        if earlyStop {
            daemonLog("MLXHermesLLMEngine: Early stop triggered on </tool_call>")
        }

        // Extract tool call from response
        if let toolCallData = extractToolCall(from: fullResponse) {
            return toolCallData
        }

        if let jsonData = extractJSON(from: fullResponse) {
            return jsonData
        }

        throw DaemonError.inferenceFailed("No valid tool call found in streaming response")
    }

    func getKVCacheSizeMB() async -> Int64 {
        // Estimate based on model size and cache state
        return Int64(cache.count * 30) // ~30MB per cache layer estimate for 3B model
    }

    func flushKVCache() async {
        cache.removeAll()
        // Recreate chat session to clear internal cache
        if let container = modelContainer {
            chatSession = ChatSession(
                container,
                instructions: "You are a helpful AI assistant.",
                generateParameters: GenerateParameters(maxTokens: 512, temperature: 0.3)
            )
        }
        daemonLog("MLXHermesLLMEngine: KV cache flushed")
    }

    func shutdown() async {
        cache.removeAll()
        chatSession = nil
        modelContainer = nil
        daemonLog("MLXHermesLLMEngine: Shutdown complete")
    }

    // MARK: - Parsing Helpers

    /// Extract JSON object from LLM response
    private func extractJSON(from text: String) -> Data? {
        // Try to find JSON in the response
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            let jsonString = String(text[start...end])
            if let data = jsonString.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
        }
        return nil
    }

    /// Extract tool call from Hermes 3 <tool_call></tool_call> tags
    private func extractToolCall(from text: String) -> Data? {
        // Match <tool_call>...</tool_call> pattern
        let pattern = "<tool_call>\\s*([\\s\\S]*?)\\s*</tool_call>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let jsonString = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse and validate JSON
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["name"] != nil else {
            return nil
        }

        // Re-encode to ensure clean JSON
        return try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }

    /// Extract multiple tool calls (for brain dump scenarios)
    func extractAllToolCalls(from text: String) -> [Data] {
        let pattern = "<tool_call>\\s*([\\s\\S]*?)\\s*</tool_call>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))

        return matches.compactMap { match -> Data? in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            let jsonString = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["name"] != nil else {
                return nil
            }

            return try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        }
    }
}

// MARK: - Quick MLX LLM Engine (Qwen 2.5-0.5B)

/// Fast LLM engine using Qwen 2.5-0.5B for quick entity extraction
/// ~300MB RAM, targets <100ms inference for simple commands
/// Used as fallback when fast path has low confidence but doesn't need full Hermes 3
///
/// Optimizations for instant feel:
/// 1. Model weights pre-loaded at daemon startup (hot loaded)
/// 2. System prompt KV cache pre-computed via warmup inference
/// 3. Fresh session per call to avoid context accumulation
/// 4. Minimal prompt template for fast tokenization
final class MLXQuickLLMEngine: QuickLLMEngine {
    private var modelContainer: MLXLMCommon.ModelContainer?
    private var isWarmedUp = false

    /// Model configuration - Qwen 2.5-0.5B Instruct (4-bit quantized)
    /// ~300MB RAM, very fast inference (~50-100ms on M3/M4 after warmup)
    private static let modelConfig = ModelConfiguration(
        id: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
        defaultPrompt: "Extract entities from voice commands."
    )

    /// Minimal system prompt - shorter = faster tokenization + smaller KV cache
    private static let extractionSystemPrompt = """
    Parse voice command to JSON. Fields: title, startTime (HH:MM), endTime (HH:MM), durationMinutes, persons[], destination (inbox/schedule/floating). Omit missing fields.
    """

    /// Cached generate parameters for reuse
    private static let generateParams = GenerateParameters(
        maxTokens: 60,      // Reduced from 80 - entity JSON is small
        temperature: 0.0    // Zero temp for deterministic, faster sampling
    )

    init() async throws {
        daemonLog("MLXQuickLLMEngine: Starting Qwen 2.5-0.5B download (~300MB)...")

        // Load the model container
        modelContainer = try await LLMModelFactory.shared.loadContainer(
            configuration: Self.modelConfig
        ) { progress in
            let percent = Int(progress.fractionCompleted * 100)
            if percent == 50 || percent == 100 {
                daemonLog("MLXQuickLLMEngine: Download progress: \(percent)%")
            }
        }

        daemonLog("MLXQuickLLMEngine: Qwen 2.5-0.5B loaded, running warmup...")

        // WARMUP: Pre-compute system prompt KV cache with a dummy inference
        // This makes the first real call instant instead of slow
        await warmup()

        daemonLog("MLXQuickLLMEngine: Qwen 2.5-0.5B ready (warmed up)")
    }

    /// Warmup inference to pre-compute KV cache for system prompt
    /// This eliminates cold-start latency on first real call
    private func warmup() async {
        guard let container = modelContainer else { return }

        let warmupStart = Date()

        // Create session and run minimal inference to cache system prompt
        let session = ChatSession(
            container,
            instructions: Self.extractionSystemPrompt,
            generateParameters: GenerateParameters(maxTokens: 5, temperature: 0.0)
        )

        // Dummy inference - just need to process system prompt
        _ = try? await session.respond(to: "test")

        let warmupMs = Date().timeIntervalSince(warmupStart) * 1000
        daemonLog("MLXQuickLLMEngine: Warmup completed in \(String(format: "%.0f", warmupMs))ms")
        isWarmedUp = true
    }

    func extractEntities(transcript: String, intent: String) async throws -> Data {
        guard let container = modelContainer else {
            throw DaemonError.modelNotLoaded("Quick LLM (Qwen 0.5B)")
        }

        let startTime = Date()

        // Minimal prompt - every token counts for latency
        let prompt = "\(intent): \"\(transcript)\" → JSON:"

        // Fresh session each call - avoids context accumulation that slows down
        // The system prompt is short so re-tokenizing is fast
        let session = ChatSession(
            container,
            instructions: Self.extractionSystemPrompt,
            generateParameters: Self.generateParams
        )

        let response = try await session.respond(to: prompt)

        let inferenceMs = Date().timeIntervalSince(startTime) * 1000
        daemonLog("MLXQuickLLMEngine: Extraction in \(String(format: "%.0f", inferenceMs))ms")

        // Extract JSON from response
        if let jsonData = extractJSON(from: response) {
            return jsonData
        }

        // Fallback: return raw response as data
        return response.data(using: .utf8) ?? Data()
    }

    func shutdown() async {
        modelContainer = nil
        isWarmedUp = false
        daemonLog("MLXQuickLLMEngine: Shutdown complete")
    }

    /// Extract JSON object from LLM response
    private func extractJSON(from text: String) -> Data? {
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            let jsonString = String(text[start...end])
            if let data = jsonString.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
        }
        return nil
    }
}

// MARK: - Real MLX Embedding Engine (nomic-embed-text-v1.5)

/// Real embedding engine using mlx-swift-lm MLXEmbedders
final class MLXNomicEmbeddingEngine: NomicEmbeddingEngine {
    private var modelContainer: MLXEmbedders.ModelContainer?

    /// Matryoshka dimension (256 for efficient storage, 768 for full)
    private let embeddingDimension = 256

    init() async throws {
        daemonLog("MLXNomicEmbeddingEngine: Starting nomic-embed-text-v1.5 download...")
        daemonLog("MLXNomicEmbeddingEngine: Model will be cached at ~/Library/Caches/models/")

        // Load the nomic embedding model
        let config = MLXEmbedders.ModelConfiguration.nomic_text_v1_5
        modelContainer = try await MLXEmbedders.loadModelContainer(
            configuration: config
        ) { progress in
            // Log at 25%, 50%, 75%, 100%
            let percent = Int(progress.fractionCompleted * 100)
            if percent == 25 || percent == 50 || percent == 75 || percent == 100 {
                daemonLog("MLXNomicEmbeddingEngine: Download progress: \(percent)%")
            }
        }

        daemonLog("MLXNomicEmbeddingEngine: nomic-embed-text-v1.5 loaded successfully")
    }

    func embed(text: String) async throws -> [Float] {
        guard let container = modelContainer else {
            throw DaemonError.modelNotLoaded("nomic embedding")
        }

        // Generate embedding using the model container
        let embedding = await container.perform { model, tokenizer, pooler in
            // Tokenize input
            let tokens = tokenizer.encode(text: text)
            let inputArray = MLXArray(tokens).expandedDimensions(axis: 0)

            // Create attention mask (all 1s for valid tokens)
            let attentionMask = MLXArray.ones([1, tokens.count])

            // Run through model with all required parameters
            let output = model(
                inputArray,
                positionIds: nil,
                tokenTypeIds: nil,
                attentionMask: attentionMask
            )

            // Apply pooling - pass EmbeddingModelOutput directly, normalize
            let pooled = pooler(output, mask: attentionMask, normalize: true)

            // Evaluate and convert to Float array
            eval(pooled)

            // Get the embedding values - truncate to Matryoshka dimension (256)
            let fullEmbedding = pooled.asArray(Float.self)
            return Array(fullEmbedding.prefix(256))
        }

        return embedding
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        // For batch embedding, process sequentially to avoid memory issues
        // Could be optimized with true batching if needed
        var embeddings: [[Float]] = []
        for text in texts {
            let embedding = try await embed(text: text)
            embeddings.append(embedding)
        }
        return embeddings
    }

    /// L2 normalize an embedding vector
    private func l2Normalize(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            return vector.map { $0 / norm }
        }
        return vector
    }
}

// MARK: - Real WhisperKit ASR Engine

/// Real ASR engine using WhisperKit for on-device speech recognition
final class WhisperKitASREngine: Qwen3ASREngine {
    private var whisperKit: WhisperKit?
    private var isStreaming = false
    private var accumulatedSamples: [Float] = []      // Rolling buffer for streaming transcription
    private var fullSessionSamples: [Float] = []      // Full audio for final transcription
    private var onChunkCallback: ((L1TranscriptChunk) -> Void)?
    private var streamStartTime: Date?

    init() async throws {
        daemonLog("WhisperKitASREngine: Loading WhisperKit...")

        // Load WhisperKit with a fast model suitable for streaming
        // Using "base" for balance of speed and accuracy
        whisperKit = try await WhisperKit(
            model: "base",
            verbose: false,
            logLevel: .error
        )

        daemonLog("WhisperKitASREngine: WhisperKit loaded successfully")
    }

    func startStreaming(formatData: Data, onChunk: @escaping (L1TranscriptChunk) -> Void) async throws {
        guard !isStreaming else {
            throw DaemonError.invalidInput("Already streaming")
        }

        isStreaming = true
        accumulatedSamples = []
        fullSessionSamples = []  // Reset full audio buffer
        audioChunksReceived = 0
        onChunkCallback = onChunk
        streamStartTime = Date()

        daemonLog("WhisperKitASREngine: Started streaming ASR")
    }

    private var audioChunksReceived = 0

    func processAudioChunk(samples: Data) async throws {
        guard isStreaming else {
            throw DaemonError.notStreaming
        }

        // Convert Data to Float samples
        let floatSamples = samples.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }

        audioChunksReceived += 1

        // Log audio stats periodically
        if audioChunksReceived == 1 || audioChunksReceived % 20 == 0 {
            let rms = sqrt(floatSamples.reduce(0) { $0 + $1 * $1 } / Float(max(1, floatSamples.count)))
            let maxSample = floatSamples.map { abs($0) }.max() ?? 0
            daemonLog("🔊 Daemon received chunk #\(audioChunksReceived): \(floatSamples.count) samples, RMS=\(String(format: "%.4f", rms)), max=\(String(format: "%.4f", maxSample)), total accumulated: \(accumulatedSamples.count + floatSamples.count)")
        }

        accumulatedSamples.append(contentsOf: floatSamples)
        fullSessionSamples.append(contentsOf: floatSamples)  // Keep full audio for final transcription

        // Process when we have enough samples (~1 second at 16kHz = 16000 samples)
        // This is for streaming feedback - final result uses full audio
        if accumulatedSamples.count >= 16000 {
            await transcribeAccumulated(isFinal: false)
        }
    }

    func stopStreaming() async throws -> String {
        guard isStreaming else {
            throw DaemonError.notStreaming
        }

        defer {
            isStreaming = false
            onChunkCallback = nil
            streamStartTime = nil
        }

        // Transcribe the FULL session audio for accurate final result
        var finalTranscript = ""
        if !fullSessionSamples.isEmpty {
            let rms = sqrt(fullSessionSamples.reduce(0) { $0 + $1 * $1 } / Float(max(1, fullSessionSamples.count)))
            let maxSample = fullSessionSamples.map { abs($0) }.max() ?? 0
            let durationSec = Double(fullSessionSamples.count) / 16000.0
            daemonLog("WhisperKitASREngine: Final transcription of \(fullSessionSamples.count) samples (\(String(format: "%.1f", durationSec))s, RMS=\(String(format: "%.4f", rms)), max=\(String(format: "%.4f", maxSample)))")

            if let whisperKit = whisperKit {
                do {
                    let results = try await whisperKit.transcribe(audioArray: fullSessionSamples)
                    finalTranscript = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    daemonLog("WhisperKitASREngine: Final transcription error: \(error)")
                }
            }
        }

        accumulatedSamples = []
        fullSessionSamples = []

        daemonLog("WhisperKitASREngine: Stopped streaming ASR - final transcript: \"\(finalTranscript)\"")
        return finalTranscript
    }

    @discardableResult
    private func transcribeAccumulated(isFinal: Bool) async -> String {
        guard let whisperKit = whisperKit, !accumulatedSamples.isEmpty else {
            daemonLog("WhisperKitASREngine: transcribeAccumulated called with empty samples or no WhisperKit")
            return ""
        }

        // Log audio stats before transcription
        let rms = sqrt(accumulatedSamples.reduce(0) { $0 + $1 * $1 } / Float(max(1, accumulatedSamples.count)))
        let maxSample = accumulatedSamples.map { abs($0) }.max() ?? 0
        daemonLog("WhisperKitASREngine: Transcribing \(accumulatedSamples.count) samples (RMS=\(String(format: "%.4f", rms)), max=\(String(format: "%.4f", maxSample)), isFinal=\(isFinal))")

        do {
            // Transcribe the accumulated audio
            let results = try await whisperKit.transcribe(audioArray: accumulatedSamples)

            // Debug: log each segment's details
            for (idx, result) in results.enumerated() {
                let segmentTexts = result.segments.map { "\($0.text) [prob:\(String(format: "%.2f", $0.avgLogprob))]" }.joined(separator: ", ")
                if results.count > 1 || !result.text.isEmpty {
                    daemonLog("WhisperKitASREngine: Result \(idx): text=\"\(result.text)\", language=\(result.language), segments=[\(segmentTexts)]")
                }
            }

            let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            daemonLog("WhisperKitASREngine: Transcription result: \"\(text)\" (segments: \(results.count))")

            if !text.isEmpty {
                let timestamp = Date().timeIntervalSince(streamStartTime ?? Date())
                let chunk = L1TranscriptChunk(
                    text: text,
                    isFinal: isFinal,
                    confidence: 0.9, // WhisperKit doesn't provide confidence, estimate
                    timestamp: timestamp
                )
                onChunkCallback?(chunk)
            }

            // Clear samples after processing (keep rolling for streaming)
            if !isFinal {
                // Keep last 0.75 seconds for context overlap (12000 samples)
                // This ensures words at chunk boundaries aren't lost
                let keepSamples = min(12000, accumulatedSamples.count)
                accumulatedSamples = Array(accumulatedSamples.suffix(keepSamples))
            }

            return text
        } catch {
            daemonLog("WhisperKitASREngine: Transcription error: \(error)")
            return ""
        }
    }
}

/// Real WhisperKit L2 Engine for high-accuracy batch transcription
final class WhisperKitL2Engine: WhisperL2Engine {
    private var whisperKit: WhisperKit?

    init() async throws {
        daemonLog("WhisperKitL2Engine: Loading WhisperKit (large model)...")

        // Load WhisperKit with a larger model for accuracy
        // Using "large-v3" for maximum accuracy
        whisperKit = try await WhisperKit(
            model: "large-v3",
            verbose: false,
            logLevel: .error
        )

        daemonLog("WhisperKitL2Engine: WhisperKit large-v3 loaded successfully")
    }

    func transcribe(audioSamples: Data, language: String?) async throws -> DaemonWhisperResult {
        guard let whisperKit = whisperKit else {
            throw DaemonError.modelNotLoaded("WhisperKit L2")
        }

        // Convert Data to Float samples
        let floatSamples = audioSamples.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }

        let startTime = Date()

        // Configure transcription options
        var options = DecodingOptions()
        if let lang = language {
            options.language = lang
        }

        // Transcribe
        let results = try await whisperKit.transcribe(
            audioArray: floatSamples,
            decodeOptions: options
        )

        let duration = Date().timeIntervalSince(startTime)

        // Convert results to daemon format
        let segments = results.flatMap { result in
            result.segments.map { segment in
                DaemonTranscriptSegment(
                    text: segment.text,
                    start: Double(segment.start),
                    end: Double(segment.end),
                    confidence: Double(segment.avgLogprob > -1 ? 0.9 : 0.7) // Estimate confidence
                )
            }
        }

        let fullText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedLanguage = results.first?.language ?? language ?? "en"

        return DaemonWhisperResult(
            text: fullText,
            segments: segments,
            language: detectedLanguage,
            duration: duration
        )
    }
}

// MARK: - MLX FunctionGemma Engine (Micro-Brain)

/// FunctionGemma 270M engine for CosmoOS voice command dispatch
/// This is the "Micro-Brain" - it interprets voice commands and outputs function calls
/// It never reasons or generates text, only function calls in the FunctionGemma format
///
/// Output format: <start_function_call>call:FUNC_NAME{params}<end_function_call>
///
/// Target metrics:
/// - RAM: ~550MB
/// - Latency: <300ms
/// - Accuracy: >90% with fine-tuning
final class DaemonMLXFunctionGemmaEngine: DaemonFunctionGemmaEngine {
    private var modelContainer: MLXLMCommon.ModelContainer?
    private var isWarmedUp = false

    /// Model configuration - FunctionGemma 270M (CosmoOS fine-tuned)
    /// Uses the fine-tuned model if available, otherwise falls back to base model
    private static let modelConfig = ModelConfiguration(
        id: "mlx-community/functiongemma-270m-it-mlx",  // Base model - will be replaced with fine-tuned
        defaultPrompt: "You are FunctionGemma, the CosmoOS Micro-Brain."
    )

    /// System prompt for FunctionGemma - defines its role as a pure dispatcher
    private static let systemPrompt = """
    You are FunctionGemma, the CosmoOS Micro-Brain. You interpret user voice commands and output exactly ONE function call.
    You NEVER reason, explain, or generate text. You ONLY output function calls in the format:
    <start_function_call>call:FUNCTION_NAME{param1:<escape>value1<escape>,param2:<escape>value2<escape>}<end_function_call>

    Available functions:
    - create_atom: Create idea, task, project, journal entry, etc.
    - update_atom: Update existing item (status, time, priority)
    - delete_atom: Delete an item
    - search_atoms: Search for items
    - batch_create: Create multiple items (brain dump)
    - navigate: Go to app section
    - query_level_system: Query XP, streaks, badges, health
    - start_deep_work: Start focus session
    - stop_deep_work: End focus session
    - extend_deep_work: Extend focus session
    - log_workout: Log exercise
    - trigger_correlation_analysis: Trigger Claude analysis
    """

    /// Cached generate parameters for consistent, deterministic output
    private static let generateParams = GenerateParameters(
        maxTokens: 256,     // Function calls are short
        temperature: 0.0    // Deterministic for reliable dispatch
    )

    init() async throws {
        daemonLog("MLXFunctionGemmaEngine: Starting FunctionGemma 270M download (~550MB)...")

        // Try to load the fine-tuned CosmoOS model first
        // Fall back to base FunctionGemma if not available
        do {
            // First try the fine-tuned CosmoOS model
            let cosmoConfig = ModelConfiguration(
                id: "local/functiongemma-270m-cosmo-v1",  // Local fine-tuned model
                defaultPrompt: "You are FunctionGemma, the CosmoOS Micro-Brain."
            )

            modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: cosmoConfig
            ) { progress in
                let percent = Int(progress.fractionCompleted * 100)
                if percent == 50 || percent == 100 {
                    daemonLog("MLXFunctionGemmaEngine: Fine-tuned model progress: \(percent)%")
                }
            }

            daemonLog("MLXFunctionGemmaEngine: Loaded fine-tuned CosmoOS model")
        } catch {
            // Fall back to base FunctionGemma
            daemonLog("MLXFunctionGemmaEngine: Fine-tuned model not found, loading base FunctionGemma...")

            modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: Self.modelConfig
            ) { progress in
                let percent = Int(progress.fractionCompleted * 100)
                if percent == 50 || percent == 100 {
                    daemonLog("MLXFunctionGemmaEngine: Base model progress: \(percent)%")
                }
            }
        }

        daemonLog("MLXFunctionGemmaEngine: FunctionGemma loaded, running warmup...")

        // Warmup to pre-compute system prompt KV cache
        await warmup()

        daemonLog("MLXFunctionGemmaEngine: FunctionGemma 270M ready (warmed up)")
    }

    /// Warmup inference to pre-compute KV cache for system prompt
    private func warmup() async {
        guard let container = modelContainer else { return }

        let warmupStart = Date()

        let session = ChatSession(
            container,
            instructions: Self.systemPrompt,
            generateParameters: GenerateParameters(maxTokens: 10, temperature: 0.0)
        )

        // Dummy inference to cache system prompt
        _ = try? await session.respond(to: "test")

        let warmupMs = Date().timeIntervalSince(warmupStart) * 1000
        daemonLog("MLXFunctionGemmaEngine: Warmup completed in \(String(format: "%.0f", warmupMs))ms")
        isWarmedUp = true
    }

    func generateFunctionCall(
        transcript: String,
        contextSection: String,
        contextDate: String
    ) async throws -> Data {
        guard let container = modelContainer else {
            throw DaemonError.modelNotLoaded("FunctionGemma 270M")
        }

        let startTime = Date()

        // Build context-aware prompt
        let contextPrompt = """
        Context:
        - Section: \(contextSection)
        - Date: \(contextDate)

        User command: "\(transcript)"
        """

        // Create fresh session for each call
        let session = ChatSession(
            container,
            instructions: Self.systemPrompt,
            generateParameters: Self.generateParams
        )

        let response = try await session.respond(to: contextPrompt)

        let inferenceMs = Date().timeIntervalSince(startTime) * 1000
        daemonLog("MLXFunctionGemmaEngine: Inference in \(String(format: "%.0f", inferenceMs))ms")

        // Parse the FunctionGemma output format
        let functionCall = parseFunctionGemmaOutput(response)

        // Encode as JSON for XPC transport
        return try JSONEncoder().encode(functionCall)
    }

    func shutdown() async {
        modelContainer = nil
        isWarmedUp = false
        daemonLog("MLXFunctionGemmaEngine: Shutdown complete")
    }

    // MARK: - Parsing

    /// Parse FunctionGemma output format into structured data
    /// Format: <start_function_call>call:FUNC_NAME{params}<end_function_call>
    private func parseFunctionGemmaOutput(_ output: String) -> DaemonFunctionCall {
        // Extract content between markers
        let startMarker = "<start_function_call>"
        let endMarker = "<end_function_call>"

        guard let startRange = output.range(of: startMarker),
              let endRange = output.range(of: endMarker) else {
            daemonLog("MLXFunctionGemmaEngine: No function call markers found")
            return DaemonFunctionCall(name: "unknown", parameters: [:], raw: output)
        }

        let content = String(output[startRange.upperBound..<endRange.lowerBound])

        // Parse call:FUNC_NAME{params}
        guard content.hasPrefix("call:") else {
            daemonLog("MLXFunctionGemmaEngine: Invalid call format")
            return DaemonFunctionCall(name: "unknown", parameters: [:], raw: output)
        }

        let afterCall = content.dropFirst(5) // Remove "call:"

        // Find function name (before the {)
        guard let braceIndex = afterCall.firstIndex(of: "{") else {
            // No parameters
            let funcName = String(afterCall).trimmingCharacters(in: .whitespaces)
            return DaemonFunctionCall(name: funcName, parameters: [:], raw: output)
        }

        let funcName = String(afterCall[..<braceIndex])
        let paramsStr = String(afterCall[braceIndex...])

        // Parse parameters {key:<escape>value<escape>,...}
        let parameters = parseParameters(paramsStr)

        return DaemonFunctionCall(name: funcName, parameters: parameters, raw: output)
    }

    /// Parse parameter string in FunctionGemma format
    /// Format: {key1:<escape>value1<escape>,key2:<escape>value2<escape>}
    private func parseParameters(_ paramsStr: String) -> [String: Any] {
        var params: [String: Any] = [:]

        // Remove outer braces
        var content = paramsStr.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("{") { content = String(content.dropFirst()) }
        if content.hasSuffix("}") { content = String(content.dropLast()) }

        // Split by comma (but be careful with nested objects)
        let escapeMarker = "<escape>"

        // Simple regex-free parsing
        var currentKey = ""
        var currentValue = ""
        var inValue = false
        // Note: depth tracking removed as it's currently unused

        var i = content.startIndex
        while i < content.endIndex {
            let remaining = String(content[i...])

            if remaining.hasPrefix(escapeMarker) {
                // Toggle value mode
                if !inValue {
                    inValue = true
                    i = content.index(i, offsetBy: escapeMarker.count)
                    continue
                } else {
                    inValue = false
                    // End of value - store and reset
                    if !currentKey.isEmpty {
                        // Try to parse as JSON for objects/arrays
                        if let data = currentValue.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) {
                            params[currentKey] = json
                        } else {
                            params[currentKey] = currentValue
                        }
                    }
                    currentKey = ""
                    currentValue = ""
                    i = content.index(i, offsetBy: escapeMarker.count)
                    continue
                }
            }

            if inValue {
                currentValue.append(content[i])
            } else if content[i] == ":" {
                // Key-value separator (outside of escape)
            } else if content[i] == "," {
                // Parameter separator
            } else if content[i] != " " {
                currentKey.append(content[i])
            }

            i = content.index(after: i)
        }

        return params
    }
}

// MARK: - Daemon Function Call Result

/// Function call result from FunctionGemma
/// Transported over XPC as JSON
public struct DaemonFunctionCall: Codable, Sendable {
    public let name: String
    public let parameters: [String: AnyCodable]
    public let raw: String

    public init(name: String, parameters: [String: Any], raw: String) {
        self.name = name
        self.parameters = parameters.mapValues { AnyCodable($0) }
        self.raw = raw
    }
}

/// Type-erased Codable wrapper for function parameters
/// Note: @unchecked Sendable because actual stored values (String, Int, Double, Bool, etc.) are Sendable
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encode(String(describing: value))
        }
    }
}
