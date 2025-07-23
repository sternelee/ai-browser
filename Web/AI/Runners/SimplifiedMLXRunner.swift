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
    private let defaultModelId = "llama3_2_1B_4bit"
    
    private init() {
        NSLog("🤖 SimplifiedMLXRunner initialized")
    }
    
    /// Ensure model is loaded using ModelRegistry ID
    func ensureLoaded(modelId: String = "llama3_2_1B_4bit") async throws {
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
    func generateWithPrompt(prompt: String, modelId: String = "llama3_2_1B_4bit") async throws -> String {
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
                
                var fullResponse = ""
                
                let _ = try MLXLMCommon.generate(
                    input: input,
                    parameters: parameters,
                    context: modelContext
                ) { tokens in
                    // Decode all tokens to get properly spaced text
                    fullResponse = modelContext.tokenizer.decode(tokens: tokens)
                    return .more
                }
                
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
    nonisolated func generateStreamWithPrompt(prompt: String, modelId: String = "llama3_2_1B_4bit") -> AsyncThrowingStream<String, Error> {
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
                        
                        var lastText = ""
                        
                        let _ = try MLXLMCommon.generate(
                            input: input,
                            parameters: parameters,
                            context: modelContext
                        ) { tokens in
                            // Decode all tokens to get properly spaced text
                            let currentText = modelContext.tokenizer.decode(tokens: tokens)
                            
                            // Only yield the new part
                            if currentText.count > lastText.count {
                                let newText = String(currentText.dropFirst(lastText.count))
                                lastText = currentText
                                continuation.yield(newText)
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