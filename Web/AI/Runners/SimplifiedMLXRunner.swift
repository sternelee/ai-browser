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
                
                let _ = try MLXLMCommon.generate(
                    input: input,
                    parameters: parameters,
                    context: modelContext
                ) { tokens in
                    // Accumulate ALL tokens from this callback
                    allTokens.append(contentsOf: tokens)
                    return .more
                }
                
                // Decode all accumulated tokens at the end
                let fullResponse = modelContext.tokenizer.decode(tokens: allTokens)
                
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
                        
                        // Track all generated tokens and only yield new content
                        var allGeneratedTokens: [Int] = []
                        var lastDecodedLength = 0
                        let maxTokens = 512 // Limit to prevent infinite generation
                        
                        let _ = try MLXLMCommon.generate(
                            input: input,
                            parameters: parameters,
                            context: modelContext
                        ) { tokens in
                            // Add new tokens to our collection
                            allGeneratedTokens.append(contentsOf: tokens)
                            
                            // Stop if we've reached the maximum token limit
                            if allGeneratedTokens.count >= maxTokens {
                                NSLog("🛑 Stopping generation: reached max tokens (\(allGeneratedTokens.count))")
                                return .stop
                            }
                            
                            // Check for EOS tokens that indicate generation should stop
                            let eosTokens: Set<Int> = [2, 1, 0] // Common EOS token IDs
                            for token in tokens {
                                if eosTokens.contains(token) {
                                    NSLog("🛑 Stopping generation: found EOS token (\(token))")
                                    return .stop
                                }
                            }
                            
                            // Decode all tokens to get the full text so far
                            let fullText = modelContext.tokenizer.decode(tokens: allGeneratedTokens)
                            
                            // Only yield the new part that we haven't seen before
                            if fullText.count > lastDecodedLength {
                                let newText = String(fullText.suffix(fullText.count - lastDecodedLength))
                                if !newText.isEmpty {
                                    continuation.yield(newText)
                                    lastDecodedLength = fullText.count
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
        NSLog("🔄 MLX conversation reset")
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