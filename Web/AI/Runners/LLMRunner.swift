import Foundation
import LLM

/// Local LLM runner using LLM.swift for direct GGUF model inference
/// Replaces MLXGemmaRunner with proven local inference capabilities
@globalActor
struct LLMActor {
    actor Shared {}
    static let shared = Shared()
}

@LLMActor
final class LLMRunner {
    static let shared = LLMRunner()
    private var bot: LLM?
    private var isLoading = false
    private var loadContinuation: [CheckedContinuation<Void, Error>] = []
    private var currentModelPath: URL?

    private init() {}

    /// Ensures model is loaded (lazy initialization)
    private func ensureLoaded(modelPath: URL) async throws {
        // If already loaded with same model, return
        if bot != nil && currentModelPath == modelPath {
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

        NSLog("🚀 Loading GGUF model: \(modelPath.lastPathComponent)")
        
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
        
        NSLog("✅ GGUF model loaded successfully: \(modelPath.lastPathComponent)")
    }

    /// Generate a complete response for the given prompt
    func generate(prompt: String, maxTokens: Int = 256, temperature: Float = 0.7, modelPath: URL) async throws -> String {
        try await ensureLoaded(modelPath: modelPath)
        
        guard let bot = bot else { 
            throw LLMError.modelNotLoaded("LLM not properly initialized")
        }
        
        NSLog("🤖 Generating response with LLM.swift...")
        
        // Preprocess prompt with conversation history
        let processedPrompt = bot.preprocess(prompt, [])
        
        // Generate completion
        let response = await bot.getCompletion(from: processedPrompt)
        
        NSLog("✅ LLM response generated: \(response.count) characters")
        return response
    }

    /// Generate a streaming response for the given prompt  
    nonisolated func generateStream(prompt: String, maxTokens: Int = 256, temperature: Float = 0.7, modelPath: URL) -> AsyncThrowingStream<String, Error> {
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
                    
                    // Preprocess prompt
                    let processedPrompt = botInstance.preprocess(prompt, [])
                    
                    // For now, get complete response and stream it in chunks
                    // TODO: Implement true streaming when LLM.swift adds streaming API
                    let response = await botInstance.getCompletion(from: processedPrompt)
                    
                    // Stream response in chunks for better UX
                    let chunkSize = max(1, response.count / 20) // Stream in ~20 chunks
                    var currentIndex = response.startIndex
                    
                    while currentIndex < response.endIndex {
                        let endIndex = response.index(currentIndex, offsetBy: chunkSize, limitedBy: response.endIndex) ?? response.endIndex
                        let chunk = String(response[currentIndex..<endIndex])
                        
                        continuation.yield(chunk)
                        currentIndex = endIndex
                        
                        // Small delay for streaming effect
                        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    }
                    
                    continuation.finish()
                    NSLog("✅ Streaming response completed")
                    
                } catch {
                    NSLog("❌ Streaming failed: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Clear loaded model to free memory
    func clearModel() async {
        self.bot = nil
        self.currentModelPath = nil
        NSLog("🗑️ LLM model cleared from memory")
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