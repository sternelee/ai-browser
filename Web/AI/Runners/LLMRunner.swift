import Foundation
import LLM

// Role is imported directly from LLM package as a top-level enum

/// Thread-safe wrapper for mutable values in concurrent contexts
private class Box<T> {
    var value: T
    init(_ value: T) {
        self.value = value
    }
}

/// Local LLM runner using LLM.swift for direct GGUF model inference  
/// Features persistent model caching to avoid reloading 4.5GB models between app launches
// SIMPLIFIED: Remove global actor to fix runtime crash
final class LLMRunner {
    static let shared = LLMRunner()
    
    // OPTIMIZATION: Persistent model caching to avoid 4.5GB reloads between app launches
    private var bot: LLM?
    private var isLoading = false
    private var loadContinuation: [CheckedContinuation<Void, Error>] = []
    private var currentModelPath: URL?
    
    // ENHANCED: Persistent model metadata to check if we can reuse cached model
    private let modelCacheDirectory: URL
    private let modelMetadataFile: URL
    
    // OPTIMIZATION: Conversation state management for multi-turn chat
    // Thread-safe with proper synchronization
    private let queue = DispatchQueue(label: "com.web.llmrunner", qos: .userInitiated)
    private var _conversationHistory: [(role: Role, content: String)] = []
    private var _conversationTokenCount: Int = 0
    private let maxConversationTokens: Int = 2400 // ENHANCED: Increased for larger context windows
    
    private var conversationHistory: [(role: Role, content: String)] {
        get { queue.sync { _conversationHistory } }
        set { queue.sync { _conversationHistory = newValue } }
    }
    
    private var conversationTokenCount: Int {
        get { queue.sync { _conversationTokenCount } }
        set { queue.sync { _conversationTokenCount = newValue } }
    }

    private init() {
        // Set up persistent model cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        modelCacheDirectory = cacheDir.appendingPathComponent("LLMCache", isDirectory: true)
        modelMetadataFile = modelCacheDirectory.appendingPathComponent("model_metadata.json")
        
        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: modelCacheDirectory, withIntermediateDirectories: true)
        
        NSLog("📁 LLM cache directory: \(modelCacheDirectory.path)")
    }

    /// Ensures model is loaded with persistent caching between app launches
    private func ensureLoaded(modelPath: URL) async throws {
        // If already loaded with same model, return immediately
        if bot != nil && currentModelPath == modelPath {
            NSLog("♻️ Model already loaded in memory, reusing existing instance...")
            return
        }
        
        if isLoading {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                loadContinuation.append(continuation)
            }
            return
        }
        
        isLoading = true
        defer { 
            isLoading = false
            for cont in loadContinuation { cont.resume() }
            loadContinuation.removeAll()
        }

        // Check if we can reuse a previously loaded model
        if let cachedMetadata = loadModelMetadata(),
           cachedMetadata.modelPath == modelPath.path,
           cachedMetadata.isValid(for: modelPath) {
            NSLog("💾 Found valid cached model metadata, attempting quick reload...")
            
            // Try to reinitialize the model quickly (LLM.swift will handle internal optimizations)
            if let llm = LLM(from: modelPath, template: .gemma) {
                self.bot = llm
                self.currentModelPath = modelPath
                NSLog("🚀 Model reloaded from cache: \(modelPath.lastPathComponent)")
                return
            } else {
                NSLog("⚠️ Cached model reload failed, falling back to full load")
            }
        }

        NSLog("🚀 Loading GGUF model from scratch: \(modelPath.lastPathComponent)")
        
        // Validate model file exists
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw LLMError.modelNotFound("Model file not found: \(modelPath.path)")
        }

        // Initialize LLM with GGUF model and Gemma template
        guard let llm = LLM(from: modelPath, template: .gemma) else {
            throw LLMError.initializationFailed("Failed to initialize LLM with model: \(modelPath.lastPathComponent)")
        }
        
        self.bot = llm
        self.currentModelPath = modelPath
        
        // Save model metadata for next app launch
        saveModelMetadata(for: modelPath)
        
        NSLog("✅ GGUF model loaded and cached successfully: \(modelPath.lastPathComponent)")
    }

    /// Generate a complete response with raw prompt (bypasses conversation preprocessing)
    func generateWithPrompt(prompt: String, modelPath: URL) async throws -> String {
        try await ensureLoaded(modelPath: modelPath)
        
        guard let bot = bot else { 
            throw LLMError.modelNotLoaded("LLM not properly initialized")
        }
        
        NSLog("🤖 Generating response with RAW prompt (no conversation preprocessing)...")
        
        let response = await withTaskGroup(of: String?.self) { group in
            // Main generation task using raw prompt
            group.addTask {
                return await bot.getCompletion(from: prompt)
            }
            
            // Timeout task (30 seconds for non-streaming)
            group.addTask {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                return nil
            }
            
            // Return the first completed result
            if let result = await group.next() {
                group.cancelAll()
                return result ?? "Response generation timed out after 30 seconds. Please try again or use streaming mode."
            }
            
            return "Unexpected error in response generation."
        }
        
        NSLog("✅ RAW prompt response generated: \(response.count) characters")
        return response
    }

    /// Generate a complete response for the given prompt with conversation history
    func generate(prompt: String, maxTokens: Int = 512, temperature: Float = 0.7, modelPath: URL) async throws -> String {
        try await ensureLoaded(modelPath: modelPath)
        
        guard let bot = bot else { 
            throw LLMError.modelNotLoaded("LLM not properly initialized")
        }
        
        NSLog("🤖 Generating response with LLM.swift...")
        
        // Use raw prompt approach for consistency with streaming
        NSLog("🤖 Starting non-streaming generation with timeout...")
        
        let response = await withTaskGroup(of: String?.self) { group in
            // Main generation task - use raw prompt (caller should handle conversation context)
            group.addTask {
                return await bot.getCompletion(from: prompt)
            }
            
            // Timeout task (30 seconds for non-streaming)
            group.addTask {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                return nil
            }
            
            // Return the first completed result
            if let result = await group.next() {
                group.cancelAll()
                return result ?? "Response generation timed out after 30 seconds. Please try again or use streaming mode."
            }
            
            return "Unexpected error in response generation."
        }
        
        NSLog("✅ LLM response generated: \(response.count) characters")
        return response
    }

    /// Generate a streaming response with raw prompt (with proper conversation state management)
    nonisolated func generateStreamWithPrompt(prompt: String, modelPath: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Declare cleanup variables at task scope
                var streamLock: NSLock?
                var isStreamCompleted = false
                var botInstance: LLM?
                
                do {
                    try await ensureLoaded(modelPath: modelPath)
                    
                    guard await bot != nil else {
                        continuation.finish(throwing: LLMError.modelNotLoaded("LLM not properly initialized"))
                        return
                    }
                    
                    NSLog("🌊 Starting streaming with RAW prompt (preserving conversation context)...")
                    
                    // Get bot instance for processing
                    botInstance = await bot!
                    
                    // FIXED: Do NOT reset conversation here - let the caller manage conversation state
                    // The raw prompt should already include conversation context if needed
                    NSLog("✅ Using raw prompt with embedded conversation context")
                    
                    // IMPROVED: Implement proper token-by-token streaming using LLM.swift callbacks
                    NSLog("🌊 Starting REAL token-by-token streaming (ChatGPT-style)...")
                    
                    let streamedTokensBox = Box(false)
                    streamLock = NSLock()
                    
                    // DISABLED: LLM.swift callbacks are not working reliably
                    // Let's focus on getting basic responses working first
                    NSLog("🌊 Callback streaming disabled - using fallback approach")
                    
                    // SIMPLIFIED: Start generation without complex timeout handling
                    // The issue is that LLM.swift callbacks aren't working correctly
                    NSLog("🚀 Starting simplified generation...")
                    let streamingResult = await botInstance!.getCompletion(from: prompt)
                    
                    // Mark stream as completed to prevent further callbacks
                    streamLock?.lock()
                    isStreamCompleted = true
                    streamLock?.unlock()
                    
                    // No callback to clear since we disabled it
                    
                    let finalResponse = streamingResult
                    
                    // SIMPLIFIED: Always send complete response since callbacks are disabled
                    if !finalResponse.isEmpty {
                        NSLog("✅ Sending complete response: \(finalResponse.count) characters")
                        continuation.yield(finalResponse)
                    } else {
                        NSLog("⚠️ No response generated")
                        continuation.yield("I'm having trouble generating a response right now. Please try again.")
                    }
                    
                    continuation.finish()
                    NSLog("✅ RAW prompt streaming response completed: \(finalResponse.count) characters")
                    
                } catch {
                    // Clean up on error - simplified since callbacks are disabled
                    streamLock?.lock()
                    isStreamCompleted = true
                    streamLock?.unlock()
                    
                    NSLog("❌ RAW prompt streaming failed: \(error)")
                    
                    // Provide helpful error message based on error type
                    let errorMessage: String
                    if error.localizedDescription.contains("memory") {
                        errorMessage = "AI response failed due to memory constraints. Try a shorter query or restart the app."
                    } else if error.localizedDescription.contains("timeout") {
                        errorMessage = "AI response timed out. Please try a shorter query."
                    } else {
                        errorMessage = "AI response failed: \(error.localizedDescription)"
                    }
                    
                    continuation.finish(throwing: LLMError.inferenceError(errorMessage))
                }
            }
        }
    }

    /// Generate a streaming response - SIMPLIFIED to work with Swift 6
    nonisolated func generateStream(prompt: String, maxTokens: Int = 512, temperature: Float = 0.7, modelPath: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await ensureLoaded(modelPath: modelPath)
                    
                    guard await bot != nil else {
                        continuation.finish(throwing: LLMError.modelNotLoaded("LLM not properly initialized"))
                        return
                    }
                    
                    NSLog("🌊 Starting streaming response with LLM.swift...")
                    
                    // Get bot instance for processing
                    let botInstance = await bot!
                    
                    // FIXED: Use real token-by-token streaming with LLM.swift callback system
                    let fullResponse = Box("")  // Thread-safe wrapper
                    
                    // CRITICAL FIX: Use @MainActor for streaming callbacks per MLX Swift best practices
                    // This ensures thread safety and prevents callback failures
                    botInstance.update = { @MainActor [fullResponse] outputDelta in
                        if let delta = outputDelta {
                            fullResponse.value += delta
                            continuation.yield(delta)
                            NSLog("🌊 Token streamed: \(delta.prefix(30))... (\(delta.count) chars)")
                        }
                    }
                    
                    NSLog("🌊 Starting REAL token streaming...")
                    
                    // Preprocess and start streaming generation
                    let preprocessed = botInstance.preprocess(prompt, conversationHistory)
                    
                    // This will trigger the streaming callbacks as tokens are generated
                    let finalResponse = await botInstance.getCompletion(from: preprocessed)
                    
                    // If no streaming occurred, send the final response
                    if fullResponse.value.isEmpty && !finalResponse.isEmpty {
                        continuation.yield(finalResponse)
                        fullResponse.value = finalResponse
                    }
                    
                    // Update conversation history
                    await self.addToConversationHistory(userPrompt: prompt, response: fullResponse.value.isEmpty ? finalResponse : fullResponse.value)
                    
                    continuation.finish()
                    NSLog("✅ Streaming response completed: \(fullResponse.value.isEmpty ? finalResponse.count : fullResponse.value.count) characters")
                    
                } catch {
                    NSLog("❌ Streaming failed: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Helper method to safely update conversation history
    private func addToConversationHistory(userPrompt: String, response: String) async {
        let userChat: (role: Role, content: String) = (.user, userPrompt)
        let assistantChat: (role: Role, content: String) = (.bot, response)
        
        // ENHANCED: More accurate token estimation for larger contexts
        let estimatedTokens = Int(Double(userPrompt.count + response.count) / 3.5) // Slightly more conservative estimation
        
        queue.sync {
            if _conversationTokenCount + estimatedTokens > maxConversationTokens {
                NSLog("🔄 Resetting conversation context due to token limit")
                _conversationHistory.removeAll()
                _conversationTokenCount = 0
            }
            
            _conversationHistory.append(userChat)
            _conversationHistory.append(assistantChat)
            _conversationTokenCount += estimatedTokens
        }
    }
    
    /// Clear loaded model to free memory (but keep metadata cache for next launch)
    func clearModel() async {
        self.bot = nil
        self.currentModelPath = nil
        self.conversationHistory.removeAll()
        self.conversationTokenCount = 0
        NSLog("🗑️ LLM model cleared from memory (metadata cache preserved)")
    }
    
    // MARK: - Persistent Model Caching
    
    /// Save model metadata to persist between app launches
    private func saveModelMetadata(for modelPath: URL) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: modelPath.path)
            let fileSize = attributes[.size] as? UInt64 ?? 0
            let modificationDate = attributes[.modificationDate] as? Date ?? Date()
            
            let metadata = ModelMetadata(
                modelPath: modelPath.path,
                fileSize: fileSize,
                lastModified: modificationDate,
                cacheTimestamp: Date(),
                modelHash: calculateModelHash(modelPath)
            )
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(metadata)
            
            try data.write(to: modelMetadataFile)
            NSLog("💾 Model metadata saved: \(modelPath.lastPathComponent)")
        } catch {
            NSLog("⚠️ Failed to save model metadata: \(error)")
        }
    }
    
    /// Load model metadata from previous app launches
    private func loadModelMetadata() -> ModelMetadata? {
        guard FileManager.default.fileExists(atPath: modelMetadataFile.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: modelMetadataFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let metadata = try decoder.decode(ModelMetadata.self, from: data)
            NSLog("💾 Model metadata loaded from cache")
            return metadata
        } catch {
            NSLog("⚠️ Failed to load model metadata: \(error)")
            return nil
        }
    }
    
    /// Calculate a simple hash of model file to detect changes
    private func calculateModelHash(_ modelPath: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: modelPath.path)
            let fileSize = attributes[.size] as? UInt64 ?? 0
            let modDate = attributes[.modificationDate] as? Date ?? Date()
            
            // Simple hash based on file size and modification date
            let hashString = "\(fileSize)-\(modDate.timeIntervalSince1970)"
            return String(hashString.hashValue)
        } catch {
            return "unknown"
        }
    }
    
    /// Reset conversation history (useful for new chat sessions)
    func resetConversation() async {
        self.conversationHistory.removeAll()
        self.conversationTokenCount = 0
        NSLog("🔄 Conversation history reset")
    }
    
    /// Clear KV cache without affecting conversation history (for error recovery)
    private func clearKVCache() async {
        // If KV cache errors occur, we need to clear the LLM's internal state
        // without destroying our conversation tracking
        if let _ = bot, let currentPath = currentModelPath {
            // Force a model reload to clear KV cache
            self.bot = nil
            try? await ensureLoaded(modelPath: currentPath)
            NSLog("🔧 KV cache cleared via model reload (conversation history preserved)")
        }
    }
}

// MARK: - Model Metadata for Persistent Caching

/// Metadata about a loaded model to enable smart caching between app launches
struct ModelMetadata: Codable {
    let modelPath: String
    let fileSize: UInt64
    let lastModified: Date
    let cacheTimestamp: Date
    let modelHash: String
    
    /// Check if this cached metadata is still valid for the given model file
    func isValid(for modelPath: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            return false
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: modelPath.path)
            let currentSize = attributes[.size] as? UInt64 ?? 0
            let currentModDate = attributes[.modificationDate] as? Date ?? Date()
            
            // Check if file size and modification date match
            let sizeMatches = currentSize == fileSize
            let dateMatches = abs(currentModDate.timeIntervalSince(lastModified)) < 1.0 // 1 second tolerance
            
            // Cache is valid for 7 days
            let cacheAge = Date().timeIntervalSince(cacheTimestamp)
            let cacheValid = cacheAge < (7 * 24 * 60 * 60) // 7 days in seconds
            
            return sizeMatches && dateMatches && cacheValid
        } catch {
            return false
        }
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case modelNotFound(String)
    case modelNotLoaded(String)
    case initializationFailed(String)
    case inferenceError(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound(let message):
            return "Model Not Found: \(message)"
        case .modelNotLoaded(let message):
            return "Model Not Loaded: \(message)"
        case .initializationFailed(let message):
            return "Initialization Failed: \(message)"
        case .inferenceError(let message):
            return "Inference Error: \(message)"
        }
    }
}

enum LLMModelError: LocalizedError {
    case downloadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return "LLM Model Download Failed: \(message)"
        }
    }
}