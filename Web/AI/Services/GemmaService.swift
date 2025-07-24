import Foundation
import MLX
import MLXLLM
import MLXLMCommon
// MLXRunner included via Web.AI.Runners
// SystemMemoryMonitor included via Web.AI.Utils

/// Gemma AI service for local inference with MLX-Swift
/// Handles model initialization, text generation, and response streaming using MLX models from Hugging Face
class GemmaService {
    
    // MARK: - Properties
    
    private let configuration: AIConfiguration
    private let mlxWrapper: MLXWrapper
    private let privacyManager: PrivacyManager
    private let mlxModelService: MLXModelService
    
    private var isModelLoaded: Bool = false
    // MLX handles model weights and tokenization internally
    
    // No remote fallbacks - we use MLX models from Hugging Face community only
    // Model download and management handled by MLXModelService
    
    // MARK: - Initialization
    
    init(
        configuration: AIConfiguration,
        mlxWrapper: MLXWrapper,
        privacyManager: PrivacyManager,
        mlxModelService: MLXModelService
    ) {
        self.configuration = configuration
        self.mlxWrapper = mlxWrapper
        self.privacyManager = privacyManager
        self.mlxModelService = mlxModelService
        
        // Memory monitoring removed - was causing unnecessary complexity
        
        NSLog("🔮 Gemma Service initialized with MLX-Swift and \(configuration.modelVariant)")
    }
    
    // MARK: - Public Interface
    
    /// Initialize the Gemma model and tokenizer
    func initialize() async throws {
        guard !isModelLoaded else {
            NSLog("✅ Gemma model already loaded")
            return
        }
        
        do {
            // Initialize MLX model service and ensure model is available
            try await mlxModelService.initializeAI()
            
            guard await mlxModelService.isAIReady() else {
                throw GemmaError.modelNotAvailable("MLX model initialization did not complete successfully")
            }
            
            isModelLoaded = true
            NSLog("✅ MLX Gemma model loaded successfully")
            
        } catch {
            NSLog("❌ Failed to initialize Gemma model: \(error)")
            throw GemmaError.initializationFailed(error.localizedDescription)
        }
    }
    
    /// Generate a response for the given query and context
    func generateResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage]
    ) async throws -> AIResponse {
        
        guard isModelLoaded else {
            throw GemmaError.modelNotLoaded
        }
        
        // Memory pressure checks removed - were causing unnecessary complexity
        
        let responseBuilder = AIResponseBuilder()
        let _ = Date() // Track timing but not used in current implementation
        
        do {
            // Step 1: Prepare the prompt
            let _ = responseBuilder.addProcessingStep(ProcessingStep(
                name: "prompt_preparation",
                duration: 0.1,
                description: "Preparing input prompt with context"
            ))
            
            let prompt = try buildPrompt(
                query: query,
                context: context,
                conversationHistory: conversationHistory
            )
            
            if context != nil {
                let _ = responseBuilder.setContextUsed(true)
            }
            
            // MLX handles tokenization internally - no separate tokenizer needed

            // Use MLX-Swift for local inference
            let _ = responseBuilder.addProcessingStep(ProcessingStep(name: "mlx_inference", duration: 0, description: "Running MLX-Swift inference"))

            do {
                // Use consistent prompt-based approach (conversation context already included in prompt)
                let generatedText = try await SimplifiedMLXRunner.shared.generateWithPrompt(prompt: prompt, modelId: "gemma3_2B_4bit")
                let cleaned = postProcessResponse(generatedText)
                // Estimate token count for metrics (MLX handles tokenization internally)
                let estimatedTokens = Int(Double(generatedText.count) / 3.5)
                mlxWrapper.updateInferenceMetrics(tokensGenerated: estimatedTokens)
                return responseBuilder.setText(cleaned).setMemoryUsage(Int(mlxWrapper.memoryUsage)).build()
            } catch {
                NSLog("❌ MLX inference failed: \(error)")
                throw GemmaError.inferenceError("MLX inference failed: \(error.localizedDescription)")
            }

            // All inference handled above by MLXRunner
            
        } catch {
            NSLog("❌ Response generation failed: \(error)")
            throw error
        }
    }
    
    /// Generate a streaming response with real-time token updates
    func generateStreamingResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        
        guard isModelLoaded else {
            throw GemmaError.modelNotLoaded
        }
        
        // Memory pressure checks removed - were causing unnecessary complexity
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Prepare prompt
                    let prompt = try buildPrompt(
                        query: query,
                        context: context,
                        conversationHistory: conversationHistory
                    )
                    
                    // MLX handles tokenization internally
                    
                    // Use MLXRunner for streaming with pre-built prompt that includes conversation context
                    let textStream = await SimplifiedMLXRunner.shared.generateStreamWithPrompt(prompt: prompt, modelId: "gemma3_2B_4bit")
                    
                    var hasYieldedContent = false
                    var accumulatedResponse = ""
                    
                    do {
                        for try await textChunk in textStream {
                            let cleanedChunk = postProcessResponse(textChunk, trimWhitespace: false)
                            if !cleanedChunk.isEmpty {
                                accumulatedResponse += cleanedChunk
                                hasYieldedContent = true
                                continuation.yield(cleanedChunk)
                            }
                        }
                        
                        // If no content was streamed, provide a helpful fallback
                        if !hasYieldedContent {
                            NSLog("⚠️ No content streamed, providing fallback response")
                            let fallbackResponse = "I'm ready to help you with questions about the current webpage content."
                            continuation.yield(fallbackResponse)
                        }
                        
                        continuation.finish()
                        NSLog("✅ Streaming completed successfully: \(accumulatedResponse.count) characters")
                        
                    } catch {
                        NSLog("❌ Streaming error: \(error)")
                        
                        // Provide error recovery with helpful message
                        if !hasYieldedContent {
                            let recoveryMessage: String
                            if error.localizedDescription.contains("memory") {
                                recoveryMessage = "Memory constraints prevented AI response. Try a shorter query or restart the app."
                            } else if error.localizedDescription.contains("timeout") {
                                recoveryMessage = "AI response timed out. Please try a more specific question."
                            } else {
                                recoveryMessage = "AI service temporarily unavailable. Please try again in a moment."
                            }
                            continuation.yield(recoveryMessage)
                        }
                        
                        continuation.finish()
                    }
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Summarize a conversation
    func summarizeConversation(_ messages: [ConversationMessage]) async throws -> String {
        let conversationText = messages.map { "\($0.role.description): \($0.content)" }.joined(separator: "\n")
        
        let summaryPrompt = """
        Summarize the following conversation in 2-3 sentences, focusing on the main topics and outcomes:
        
        \(conversationText)
        
        Summary:
        """
        
        let response = try await generateResponse(
            query: summaryPrompt,
            context: nil,
            conversationHistory: []
        )
        
        return response.text
    }
    
    // MARK: - Private Methods
    
    private func buildPrompt(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage]
    ) throws -> String {
        
        // ENHANCED: Build proper multi-turn conversation prompt with conversation history
        var promptParts: [String] = []
        
        // System prompt as first user turn
        promptParts.append("<start_of_turn>user")
        promptParts.append("You are a helpful AI assistant. Answer questions based on the provided webpage content when available. Be concise and direct.")
        
        // Add context if available 
        if let context = context, !context.isEmpty {
            let cleanContext = String(context.prefix(6000))  // ENHANCED: Increased from 2000 to 6000 for comprehensive content analysis
                .replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            promptParts.append("\nWebpage content:\n\(cleanContext)")
        }
        
        promptParts.append("<end_of_turn>")
        
        // Assistant acknowledges 
        promptParts.append("<start_of_turn>model")
        promptParts.append("I understand. I'll help you with questions about the webpage content.")
        promptParts.append("<end_of_turn>")
        
        // ENHANCED: Add recent conversation history for continuity
        let recentHistory = Array(conversationHistory.suffix(6))  // Last 3 exchanges (6 messages)
        for message in recentHistory {
            if message.role == .user {
                promptParts.append("<start_of_turn>user")
                promptParts.append(message.content)
                promptParts.append("<end_of_turn>")
            } else if message.role == .assistant {
                promptParts.append("<start_of_turn>model")
                promptParts.append(message.content)
                promptParts.append("<end_of_turn>")
            }
        }
        
        // Current user question
        promptParts.append("<start_of_turn>user")
        promptParts.append(query)
        promptParts.append("<end_of_turn>")
        
        // Assistant response start
        promptParts.append("<start_of_turn>model")
        
        let fullPrompt = promptParts.joined(separator: "\n")
        
        NSLog("📝 Built MLX Gemma prompt (\(fullPrompt.count) chars): \(String(fullPrompt.prefix(300)))...")
        
        return fullPrompt
    }
    
    /// Reset conversation state to prevent KV cache issues
    func resetConversation() async {
        // Reset the MLX runner's conversation state
        await SimplifiedMLXRunner.shared.resetConversation()
        NSLog("🔄 GemmaService conversation reset completed")
    }
    
    // Memory pressure handling removed - was overcomplicating the system
    
    // All inference now handled by MLXRunner using MLX models from Hugging Face
    
    /// Post-processes raw output from the model to remove artifacts.
    ///
    /// - Parameters:
    ///   - text: Raw text emitted by the model.
    ///   - trimWhitespace: When true (default) leading/trailing whitespace and newline characters are trimmed. For streaming output we set this to **false** so that legitimate leading spaces between tokens are preserved.  
    ///                     This prevents issues where streamed tokens like "Hello" "world" are concatenated into "Helloworld" when whitespace is stripped on every chunk.
    private func postProcessResponse(_ text: String, trimWhitespace: Bool = true) -> String {
        // Clean up the response
        var cleaned = text
        
        // Remove common artifacts and Gemma-specific tokens
        cleaned = cleaned.replacingOccurrences(of: "<|endoftext|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|user|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|assistant|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<start_of_turn>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<end_of_turn>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<bos>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<eos>", with: "")
        
        // Stop generation at repetitive patterns
        if cleaned.contains("I am sorry, I do not have access") {
            // Find first occurrence and truncate there
            if let range = cleaned.range(of: "I am sorry, I do not have access") {
                let beforeRepetition = cleaned[..<range.lowerBound]
                if !beforeRepetition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    cleaned = String(beforeRepetition)
                } else {
                    // If the response starts with repetition, give a simple answer
                    cleaned = "I can help you with questions about the current webpage content."
                }
            }
        }
        
        // Remove excessive repetition by looking for identical sentences
        let sentences = cleaned.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        var uniqueSentences: [String] = []
        var seenSentences = Set<String>()
        
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !seenSentences.contains(trimmed) {
                uniqueSentences.append(sentence)
                seenSentences.insert(trimmed)
            }
        }
        
        if uniqueSentences.count < sentences.count {
            cleaned = uniqueSentences.joined(separator: ".")
        }
        
        // Dynamic response length based on memory availability
        let memoryPressure = ProcessInfo.processInfo.thermalState
        let maxResponseLength: Int
        
        switch memoryPressure {
        case .critical:
            maxResponseLength = 1000  // Shorter responses under critical memory pressure
        case .serious:
            maxResponseLength = 2500  // Medium responses under serious memory pressure
        case .fair:
            maxResponseLength = 4000  // Longer responses when memory is fair
        case .nominal:
            maxResponseLength = 6000  // Full responses when memory is good
        @unknown default:
            maxResponseLength = 2500  // Safe default
        }
        
        // Only limit if significantly over the threshold (25% buffer)
        if cleaned.count > Int(Double(maxResponseLength) * 1.25) {
            // Find a good stopping point near the limit
            if let range = cleaned.range(of: ".", range: cleaned.startIndex..<cleaned.index(cleaned.startIndex, offsetBy: min(maxResponseLength, cleaned.count))) {
                cleaned = String(cleaned[..<range.upperBound])
            } else {
                cleaned = String(cleaned.prefix(maxResponseLength)) + "..."
            }
            NSLog("📏 Response truncated to \(cleaned.count) chars due to \(memoryPressure) memory pressure")
        }
        
        // Optionally trim whitespace (disabled for streaming so that spaces between tokens are preserved)
        if trimWhitespace {
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return cleaned
    }
    
    // Context reference processing will be added in Phase 11
}

// MARK: - MLX Integration Notes

/// MLX-Swift handles tokenization internally through its model context
/// No separate tokenizer class is needed as MLX provides this functionality

// MARK: - Errors

enum GemmaError: LocalizedError {
    case modelNotAvailable(String)
    case modelNotLoaded
    case initializationFailed(String)
    case mlxNotAvailable
    case promptTooLong(String)
    case inferenceError(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotAvailable(let message):
            return "Model Not Available: \(message)"
        case .modelNotLoaded:
            return "Model not loaded - call initialize() first"
        case .initializationFailed(let message):
            return "Initialization Failed: \(message)"
        case .mlxNotAvailable:
            return "MLX runtime not available"
        case .promptTooLong(let message):
            return "Prompt Too Long: \(message)"
        case .inferenceError(let message):
            return "Inference Error: \(message)"
        }
    }
}