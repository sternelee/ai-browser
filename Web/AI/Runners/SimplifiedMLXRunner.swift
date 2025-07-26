import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Simplified MLX-based LLM runner following WWDC 2025 patterns
/// Uses basic string-based model loading without complex configurations
@MainActor
final class SimplifiedMLXRunner: ObservableObject {
    static let shared = SimplifiedMLXRunner()
    
    @Published var isLoading = false
    @Published var loadProgress: Float = 0.0
    
    private var modelContainer: ModelContainer?
    private var currentModelId: String?
    
    // Use ModelRegistry for predefined configurations
    private let defaultModelId = "gemma3_2B_4bit"
    
    private init() {
        NSLog("🤖 SimplifiedMLXRunner initialized")
    }
    
    /// Ensure model is loaded using ModelRegistry ID
    func ensureLoaded(modelId: String = "gemma3_2B_4bit") async throws {
        // If already loaded with same model, return immediately
        if modelContainer != nil && currentModelId == modelId {
            NSLog("♻️ MLX model already loaded: \(modelId)")
            return
        }
        
        isLoading = true
        loadProgress = 0.0
        defer { 
            isLoading = false
        }
        
        NSLog("🚀 Loading MLX model: \(modelId)")
        
        do {
            // Use MLX-Swift ModelRegistry for predefined models
            let modelConfig: ModelConfiguration
            switch modelId {
            case "llama3_2_1B_4bit":
                modelConfig = LLMRegistry.llama3_2_1B_4bit
            case "llama3_2_3B_4bit":
                modelConfig = LLMRegistry.llama3_2_3B_4bit
            case "gemma3_2B_4bit":
                modelConfig = ModelConfiguration(id: "mlx-community/gemma-2-2b-it-4bit")
            case "gemma3_9B_4bit":
                modelConfig = ModelConfiguration(id: "mlx-community/gemma-2-9b-it-4bit")
            default:
                // Fallback to custom configuration
                modelConfig = ModelConfiguration(id: modelId)
            }
            
            let model = try await LLMModelFactory.shared.loadContainer(
                configuration: modelConfig
            ) { progress in
                Task { @MainActor in
                    self.loadProgress = Float(progress.fractionCompleted)
                    NSLog("📈 MLX model download progress: \(Int(progress.fractionCompleted * 100))%")
                }
            }
            
            self.modelContainer = model
            self.currentModelId = modelId
            self.loadProgress = 1.0
            
            NSLog("✅ MLX model loaded successfully: \(modelId)")
        } catch {
            NSLog("❌ Failed to load MLX model: \(error)")
            throw error
        }
    }
    
    /// Generate text with simple prompt
    func generateWithPrompt(prompt: String, modelId: String = "gemma3_2B_4bit") async throws -> String {
        try await ensureLoaded(modelId: modelId)
        
        guard let context = modelContainer else {
            throw SimplifiedMLXError.modelNotLoaded
        }
        
        NSLog("🤖 Generating with MLX...")
        
        do {
            // Use MLX-Swift ModelContainer.perform API with ModelContext
            let result = try await context.perform { modelContext in
                let input = try await modelContext.processor.prepare(input: .init(prompt: prompt))
                let parameters = GenerateParameters(
                    maxTokens: 512,
                    temperature: 0.7,
                    topP: 0.9
                )
                
                var allTokens: [Int] = []
                
                var previousTokenCount = 0
                var stagnantCount = 0
                var lastTokenSequence: [Int] = []
                let repetitionDetectionWindow = 10
                
                let _ = try MLXLMCommon.generate(
                    input: input,
                    parameters: parameters,
                    context: modelContext
                ) { tokens in
                    // Removed excessive logging for cleaner output
                    
                    // Store the complete token array - MLX gives us all tokens accumulated so far
                    allTokens = tokens
                    
                    // IMPROVED: Stop if no progress is being made (token count not increasing)
                    if tokens.count == previousTokenCount {
                        stagnantCount += 1
                        if stagnantCount >= 5 {
                            NSLog("🛑 Stopping: no token progress for 5 iterations")
                            return .stop
                        }
                    } else {
                        stagnantCount = 0
                        previousTokenCount = tokens.count
                    }
                    
                    // Stop if we have enough tokens or find EOS
                    if tokens.count >= 512 {
                        NSLog("🛑 Stopping: reached max tokens (\(tokens.count))")
                        return .stop
                    }
                    
                    // IMPROVED: Enhanced EOS token detection with more tokens
                    let eosTokens: Set<Int> = [2, 1, 0, 128001, 128008, 128009] // Include more common EOS tokens
                    if let lastToken = tokens.last, eosTokens.contains(lastToken) {
                        NSLog("🛑 Stopping: found EOS token \(lastToken)")
                        return .stop
                    }
                    
                    // NEW: Detect token sequence repetition to prevent infinite loops
                    if tokens.count >= repetitionDetectionWindow {
                        let recentTokens = Array(tokens.suffix(repetitionDetectionWindow))
                        if recentTokens == lastTokenSequence {
                            NSLog("🛑 Stopping: detected repeated token sequence \(recentTokens)")
                            return .stop
                        }
                        lastTokenSequence = recentTokens
                    }
                    
                    // NEW: Detect if the same token is being repeated excessively
                    if tokens.count >= 5 {
                        let lastFiveTokens = Array(tokens.suffix(5))
                        let uniqueTokens = Set(lastFiveTokens)
                        if uniqueTokens.count == 1 {
                            NSLog("🛑 Stopping: same token repeated 5 times: \(uniqueTokens.first!)")
                            return .stop
                        }
                    }
                    
                    return .more
                }
                
                NSLog("🔤 Decoding \(allTokens.count) total tokens...")
                let fullResponse = modelContext.tokenizer.decode(tokens: allTokens)
                NSLog("📝 Final decoded response: \(fullResponse.count) characters")
                
                return fullResponse
            }
            
            NSLog("✅ MLX response generated: \(result.count) characters")
            return result
        } catch {
            NSLog("❌ MLX generation failed: \(error)")
            throw SimplifiedMLXError.generationFailed(error.localizedDescription)
        }
    }
    
    /// Generate streaming response
    nonisolated func generateStreamWithPrompt(prompt: String, modelId: String = "gemma3_2B_4bit") -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await ensureLoaded(modelId: modelId)
                    
                    guard await modelContainer != nil else {
                        continuation.finish(throwing: SimplifiedMLXError.modelNotLoaded)
                        return
                    }
                    
                    let container = await modelContainer!
                    
                    NSLog("🌊 Starting MLX streaming...")
                    
                    try await container.perform { modelContext in
                        let input = try await modelContext.processor.prepare(input: .init(prompt: prompt))
                        let parameters = GenerateParameters(
                            maxTokens: 512,
                            temperature: 0.7,
                            topP: 0.9
                        )
                        
                        // Track the length of text we've already sent to avoid duplication
                        var sentTextLength = 0
                        let maxTokens = 512
                        var previousTokenCount = 0
                        var stagnantCount = 0
                        var lastTokenSequence: [Int] = []
                        var repetitionDetectionWindow = 10
                        
                        let _ = try MLXLMCommon.generate(
                            input: input,
                            parameters: parameters,
                            context: modelContext
                        ) { tokens in
                            // Removed excessive streaming logs for cleaner output
                            
                            // IMPROVED: Stop if no progress is being made (token count not increasing)
                            if tokens.count == previousTokenCount {
                                stagnantCount += 1
                                if stagnantCount >= 5 {
                                    NSLog("🛑 Stopping streaming: no token progress for 5 iterations")
                                    return .stop
                                }
                            } else {
                                stagnantCount = 0
                                previousTokenCount = tokens.count
                            }
                            
                            // Stop if we've reached the maximum token limit
                            if tokens.count >= maxTokens {
                                NSLog("🛑 Stopping streaming: reached max tokens (\(tokens.count))")
                                return .stop
                            }
                            
                            // IMPROVED: Enhanced EOS token detection with more tokens
                            let eosTokens: Set<Int> = [2, 1, 0, 128001, 128008, 128009] // Include more common EOS tokens
                            if let lastToken = tokens.last, eosTokens.contains(lastToken) {
                                NSLog("🛑 Stopping streaming: found EOS token \(lastToken)")
                                return .stop
                            }
                            
                            // NEW: Detect token sequence repetition to prevent infinite loops
                            if tokens.count >= repetitionDetectionWindow {
                                let recentTokens = Array(tokens.suffix(repetitionDetectionWindow))
                                if recentTokens == lastTokenSequence {
                                    NSLog("🛑 Stopping streaming: detected repeated token sequence \(recentTokens)")
                                    return .stop
                                }
                                lastTokenSequence = recentTokens
                            }
                            
                            // NEW: Detect if the same token is being repeated excessively
                            if tokens.count >= 5 {
                                let lastFiveTokens = Array(tokens.suffix(5))
                                let uniqueTokens = Set(lastFiveTokens)
                                if uniqueTokens.count == 1 {
                                    NSLog("🛑 Stopping streaming: same token repeated 5 times: \(uniqueTokens.first!)")
                                    return .stop
                                }
                            }
                            
                            // Only process if we have new tokens
                            if tokens.count > 0 {
                                // FIXED: Decode the complete token array for proper Unicode/word boundaries
                                let fullText = modelContext.tokenizer.decode(tokens: tokens)
                                
                                // NEW: Check for obvious repetitive text patterns in the decoded output
                                if fullText.count > sentTextLength {
                                    let newText = String(fullText.dropFirst(sentTextLength))
                                    
                                    // Simple repetition check for new text
                                    if newText.count > 20 {
                                        let words = newText.components(separatedBy: .whitespacesAndNewlines)
                                        if words.count >= 4 {
                                            let lastFourWords = Array(words.suffix(4))
                                            let uniqueWords = Set(lastFourWords)
                                            if uniqueWords.count <= 2 && words.count > 6 {
                                                NSLog("🛑 Stopping streaming: detected repetitive text pattern")
                                                return .stop
                                            }
                                        }
                                    }
                                    
                                    // Removed token streaming logs for cleaner output
                                    
                                    if !newText.isEmpty {
                                        continuation.yield(newText)
                                        sentTextLength = fullText.count
                                    }
                                }
                            }
                            
                            return .more
                        }
                    }
                    
                    continuation.finish()
                    NSLog("✅ MLX streaming completed")
                    
                } catch {
                    NSLog("❌ MLX streaming failed: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Reset conversation state
    func resetConversation() async {
        // FIXED: Implement proper conversation state reset
        // For MLX, we need to clear the model's internal state by recreating the model container
        guard let currentModelId = currentModelId else {
            NSLog("🔄 MLX conversation reset: no model loaded")
            return
        }
        
        NSLog("🔄 MLX conversation reset: clearing model state...")
        
        // Clear current model state
        modelContainer = nil
        
        // Reload the model to reset its internal conversation state
        do {
            try await ensureLoaded(modelId: currentModelId)
            NSLog("✅ MLX conversation reset completed successfully")
        } catch {
            NSLog("❌ MLX conversation reset failed: \(error)")
        }
    }
    
    /// Clear model from memory
    func clearModel() async {
        modelContainer = nil
        currentModelId = nil
        NSLog("🗑️ MLX model cleared")
    }
}

/// Simplified MLX errors
enum SimplifiedMLXError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "MLX model not loaded"
        case .generationFailed(let message):
            return "MLX generation failed: \(message)"
        }
    }
}