import Foundation

/// Gemma AI service for local inference with Apple MLX optimization
/// Handles model initialization, text generation, and response streaming
class GemmaService {
    
    // MARK: - Properties
    
    private let configuration: AIConfiguration
    private let mlxWrapper: MLXWrapper
    private let privacyManager: PrivacyManager
    
    private var isModelLoaded: Bool = false
    private var modelWeights: [String: Any]? = nil
    private var tokenizer: GemmaTokenizer?
    
    // MARK: - Initialization
    
    init(
        configuration: AIConfiguration,
        mlxWrapper: MLXWrapper,
        privacyManager: PrivacyManager
    ) {
        self.configuration = configuration
        self.mlxWrapper = mlxWrapper
        self.privacyManager = privacyManager
        
        NSLog("🔮 Gemma Service initialized with \(configuration.modelVariant)")
    }
    
    // MARK: - Public Interface
    
    /// Initialize the Gemma model and tokenizer
    func initialize() async throws {
        guard !isModelLoaded else {
            NSLog("✅ Gemma model already loaded")
            return
        }
        
        do {
            // Get model path from on-demand service
            let onDemandService = OnDemandModelService()
            guard let modelPath = onDemandService.getModelPath() else {
                throw GemmaError.modelNotAvailable("AI model file not found - needs download")
            }
            
            NSLog("📂 Loading Gemma model from \(modelPath.lastPathComponent)")
            
            // Load model weights
            modelWeights = try await mlxWrapper.loadModelWeights(from: modelPath)
            
            // Initialize tokenizer
            tokenizer = try GemmaTokenizer(modelPath: modelPath)
            
            // Apply quantization if configured
            if case .int4 = configuration.quantization {
                modelWeights = mlxWrapper.quantizeModel(modelWeights!, bits: 4)
            }
            
            isModelLoaded = true
            NSLog("✅ Gemma model loaded successfully")
            
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
        
        let responseBuilder = AIResponseBuilder()
        let startTime = Date()
        
        do {
            // Step 1: Prepare the prompt
            responseBuilder.addProcessingStep(ProcessingStep(
                name: "prompt_preparation",
                duration: 0.1,
                description: "Preparing input prompt with context"
            ))
            
            let prompt = try buildPrompt(
                query: query,
                context: context,
                conversationHistory: conversationHistory
            )
            
            if let context = context {
                responseBuilder.setContextUsed(true)
            }
            
            // Step 2: Tokenize input
            responseBuilder.addProcessingStep(ProcessingStep(
                name: "tokenization",
                duration: 0.05,
                description: "Tokenizing input text"
            ))
            
            guard let tokenizer = tokenizer else {
                throw GemmaError.tokenizerNotAvailable
            }
            
            let inputTokens = try tokenizer.encode(prompt)
            
            // Step 3: Run inference
            mlxWrapper.startInferenceTimer()
            
            responseBuilder.addProcessingStep(ProcessingStep(
                name: "inference_start",
                duration: 0,
                description: "Starting model inference"
            ))
            
            let outputTokens = try await runInference(inputTokens: inputTokens)
            
            // Step 4: Decode output
            responseBuilder.addProcessingStep(ProcessingStep(
                name: "decoding",
                duration: 0.05,
                description: "Decoding output tokens"
            ))
            
            let responseText = try tokenizer.decode(outputTokens)
            
            // Step 5: Post-process response
            let cleanedResponse = postProcessResponse(responseText)
            
            // Update metrics
            mlxWrapper.updateInferenceMetrics(tokensGenerated: outputTokens.count)
            
            // Context references will be added in Phase 11
            
            return responseBuilder
                .setText(cleanedResponse)
                .setMemoryUsage(Int(mlxWrapper.memoryUsage))
                .build()
            
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
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Prepare prompt
                    let prompt = try buildPrompt(
                        query: query,
                        context: context,
                        conversationHistory: conversationHistory
                    )
                    
                    guard let tokenizer = tokenizer else {
                        throw GemmaError.tokenizerNotAvailable
                    }
                    
                    let inputTokens = try tokenizer.encode(prompt)
                    mlxWrapper.startInferenceTimer()
                    
                    // Stream inference results
                    let tokenStream = try await runStreamingInference(inputTokens: inputTokens)
                    
                    var generatedTokens: [Int] = []
                    
                    for try await token in tokenStream {
                        generatedTokens.append(token)
                        
                        // Decode incrementally for streaming
                        if generatedTokens.count % 5 == 0 { // Decode every 5 tokens
                            let partialText = try tokenizer.decode(generatedTokens)
                            let cleanedText = postProcessResponse(partialText)
                            
                            if !cleanedText.isEmpty {
                                continuation.yield(cleanedText)
                                generatedTokens.removeAll() // Reset for next batch
                            }
                        }
                    }
                    
                    // Final decode for remaining tokens
                    if !generatedTokens.isEmpty {
                        let finalText = try tokenizer.decode(generatedTokens)
                        let cleanedText = postProcessResponse(finalText)
                        if !cleanedText.isEmpty {
                            continuation.yield(cleanedText)
                        }
                    }
                    
                    continuation.finish()
                    
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
        
        var promptParts: [String] = []
        
        // System prompt
        promptParts.append("""
        You are a helpful AI assistant integrated into a web browser. You have access to the user's current browsing context and can help with questions about web pages, research, and general tasks. Always be concise, accurate, and helpful.
        """)
        
        // Add context if available
        if let context = context, !context.isEmpty {
            promptParts.append("Context: \(context)")
        }
        
        // Add conversation history (last few messages)
        if !conversationHistory.isEmpty {
            let historyPrompt = conversationHistory
                .suffix(5) // Last 5 messages
                .map { "\($0.role.description): \($0.content)" }
                .joined(separator: "\n")
            
            promptParts.append("Recent conversation:\n\(historyPrompt)")
        }
        
        // Add current query
        promptParts.append("User: \(query)")
        promptParts.append("Assistant:")
        
        let fullPrompt = promptParts.joined(separator: "\n\n")
        
        // Validate prompt length
        guard let tokenizer = tokenizer else {
            throw GemmaError.tokenizerNotAvailable
        }
        
        let tokenCount = try tokenizer.encode(fullPrompt).count
        
        if tokenCount > configuration.maxContextTokens {
            throw GemmaError.promptTooLong("Prompt exceeds maximum token limit: \(tokenCount) > \(configuration.maxContextTokens)")
        }
        
        return fullPrompt
    }
    
    // Context processing will be added in Phase 11
    
    private func runInference(inputTokens: [Int]) async throws -> [Int] {
        // Placeholder for actual MLX inference
        // In a real implementation, this would use MLX operations
        
        // Simulate inference delay
        try await Task.sleep(nanoseconds: UInt64(Double.random(in: 1...3) * 1_000_000_000))
        
        // Return dummy tokens (in real implementation would be actual model output)
        return Array(1...50) // Placeholder tokens
    }
    
    private func runStreamingInference(inputTokens: [Int]) async throws -> AsyncThrowingStream<Int, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Simulate streaming token generation
                    for i in 1...50 {
                        // Simulate processing delay
                        try await Task.sleep(nanoseconds: 100_000_000) // 100ms per token
                        
                        continuation.yield(i)
                    }
                    
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func postProcessResponse(_ text: String) -> String {
        // Clean up the response
        var cleaned = text
        
        // Remove common artifacts
        cleaned = cleaned.replacingOccurrences(of: "<|endoftext|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|user|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|assistant|>", with: "")
        
        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    // Context reference processing will be added in Phase 11
}

// MARK: - Gemma Tokenizer

/// Simplified tokenizer for Gemma model
class GemmaTokenizer {
    private let modelPath: URL
    private var vocabulary: [String: Int] = [:]
    private var reverseVocabulary: [Int: String] = [:]
    
    init(modelPath: URL) throws {
        self.modelPath = modelPath
        try loadVocabulary()
    }
    
    func encode(_ text: String) throws -> [Int] {
        // Simplified tokenization - in real implementation would use SentencePiece
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        return words.compactMap { vocabulary[$0] ?? vocabulary["<unk>"] }
    }
    
    func decode(_ tokens: [Int]) throws -> String {
        // Simplified detokenization
        let words = tokens.compactMap { reverseVocabulary[$0] }
        return words.joined(separator: " ")
    }
    
    private func loadVocabulary() throws {
        // Placeholder vocabulary - in real implementation would load from model
        vocabulary = [
            "<unk>": 0,
            "<pad>": 1,
            "<bos>": 2,
            "<eos>": 3,
            "the": 4,
            "and": 5,
            "is": 6,
            "in": 7,
            "to": 8,
            "of": 9
            // ... would contain full vocabulary
        ]
        
        reverseVocabulary = Dictionary(uniqueKeysWithValues: vocabulary.map { ($1, $0) })
    }
}

// MARK: - Errors

enum GemmaError: LocalizedError {
    case modelNotAvailable(String)
    case modelNotLoaded
    case initializationFailed(String)
    case tokenizerNotAvailable
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
        case .tokenizerNotAvailable:
            return "Tokenizer not available"
        case .promptTooLong(let message):
            return "Prompt Too Long: \(message)"
        case .inferenceError(let message):
            return "Inference Error: \(message)"
        }
    }
}