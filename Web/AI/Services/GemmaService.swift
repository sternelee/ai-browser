import Foundation
import MLXLLM
// MLXGemmaRunner included via Web.AI.Runners

/// Gemma AI service for local inference with Apple MLX optimization
/// Handles model initialization, text generation, and response streaming
class GemmaService {
    
    // MARK: - Properties
    
    private let configuration: AIConfiguration
    private let mlxWrapper: MLXWrapper
    private let privacyManager: PrivacyManager
    private let onDemandModelService: OnDemandModelService
    
    private var isModelLoaded: Bool = false
    private var modelWeights: [String: Any]? = nil
    private var tokenizer: SimpleTokenizer?
    
    // MARK: - Initialization
    
    init(
        configuration: AIConfiguration,
        mlxWrapper: MLXWrapper,
        privacyManager: PrivacyManager,
        onDemandModelService: OnDemandModelService
    ) {
        self.configuration = configuration
        self.mlxWrapper = mlxWrapper
        self.privacyManager = privacyManager
        self.onDemandModelService = onDemandModelService
        
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
            // Get model path from shared on-demand service
            guard let modelPath = onDemandModelService.getModelPath() else {
                throw GemmaError.modelNotAvailable("AI model file not found - needs download")
            }
            
            NSLog("📂 Loading Gemma model from \(modelPath.lastPathComponent)")
            
            // Load model weights
            modelWeights = try await mlxWrapper.loadModelWeights(from: modelPath)
            
            // Initialize simple tokenizer
            tokenizer = SimpleTokenizer()
            NSLog("✅ Simple tokenizer initialized")
            
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
            
            if context != nil {
                responseBuilder.setContextUsed(true)
            }
            
            guard let tokenizer = tokenizer else {
                throw GemmaError.tokenizerNotAvailable
            }

            // Fast-path: If MLX is ready, generate real text via MLXGemmaRunner and avoid placeholder logic
            if mlxWrapper.isInitialized, let modelPath = onDemandModelService.getModelPath() {
                responseBuilder.addProcessingStep(ProcessingStep(name: "mlx_inference", duration: 0, description: "Running MLX LLM"))
                let generatedText = try await MLXGemmaRunner.shared.generate(prompt: prompt, modelPath: modelPath)
                let encoded = try tokenizer.encode(generatedText)
                let cleaned = postProcessResponse(generatedText)
                mlxWrapper.updateInferenceMetrics(tokensGenerated: encoded.count)
                return responseBuilder.setText(cleaned).setMemoryUsage(Int(mlxWrapper.memoryUsage)).build()
            }

            // Step 2: Tokenize input
            responseBuilder.addProcessingStep(ProcessingStep(
                name: "tokenization",
                duration: 0.05,
                description: "Tokenizing input text"
            ))
            
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
        // Check if model is loaded
        guard let model = modelWeights else {
            throw GemmaError.modelNotLoaded
        }
        
        // For now, check if MLX is available
        if mlxWrapper.isInitialized {
            // Use MLX inference when available
            return try await runMLXInference(inputTokens: inputTokens, model: model)
        } else {
            // Fallback to CPU inference
            NSLog("⚠️ MLX not available, using CPU fallback inference")
            return try await runCPUFallbackInference(inputTokens: inputTokens)
        }
    }
    
    private func runStreamingInference(inputTokens: [Int]) async throws -> AsyncThrowingStream<Int, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Check if model is loaded
                    guard let model = modelWeights else {
                        continuation.finish(throwing: GemmaError.modelNotLoaded)
                        return
                    }
                    
                    if mlxWrapper.isInitialized {
                        // Use MLX streaming inference when available
                        try await streamMLXInference(inputTokens: inputTokens, model: model, continuation: continuation)
                    } else {
                        // Fallback to CPU streaming inference
                        NSLog("⚠️ MLX not available, using CPU fallback streaming")
                        try await streamCPUFallbackInference(inputTokens: inputTokens, continuation: continuation)
                    }
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - MLX Inference Implementation
    
    private func runMLXInference(inputTokens: [Int], model: [String: Any]) async throws -> [Int] {
        // Start performance timing
        mlxWrapper.startInferenceTimer()

        // If we have a tokenizer, generate a friendly placeholder response so the
        // user sees meaningful text instead of raw token identifiers. This will
        // be replaced with real MLX inference output once the Gemma model is
        // wired up.
        if let tokenizer = self.tokenizer {
            let responseText = "Hello! I'm your local AI assistant running fully on-device. How can I help you today?"
            let encoded = try tokenizer.encode(responseText)
            mlxWrapper.updateInferenceMetrics(tokensGenerated: encoded.count)
            NSLog("🚀 Placeholder inference completed – returning human-readable response")
            return encoded
        }

        // Fallback to the old numeric token stub
        let outputLength = min(max(inputTokens.count, 10), 100)
        let inferenceTimeMs = outputLength * 50
        try await Task.sleep(nanoseconds: UInt64(inferenceTimeMs * 1_000_000))
        var outputTokens: [Int] = []
        for i in 0..<outputLength {
            outputTokens.append(1000 + (i % 1000))
        }
        mlxWrapper.updateInferenceMetrics(tokensGenerated: outputTokens.count)
        NSLog("🚀 MLX numeric stub inference completed: \(inputTokens.count) → \(outputTokens.count)")
        return outputTokens
    }

    private func streamMLXInference(inputTokens: [Int], model: [String: Any], continuation: AsyncThrowingStream<Int, Error>.Continuation) async throws {
        guard let tokenizer = self.tokenizer else {
            // Fall back to original numeric streaming if tokenizer unavailable
            let outputLength = min(max(inputTokens.count, 10), 100)
            for i in 0..<outputLength {
                try await Task.sleep(nanoseconds: 50_000_000)
                continuation.yield(1000 + (i % 1000))
                mlxWrapper.updateInferenceMetrics(tokensGenerated: 1)
            }
            continuation.finish()
            return
        }

        let responseText = "Sure thing! Let me know what you need and I'll do my best – all without leaving your Mac."
        let tokens = try tokenizer.encode(responseText)
        for token in tokens {
            try await Task.sleep(nanoseconds: 30_000_000) // 30 ms per token for snappier streaming
            continuation.yield(token)
            mlxWrapper.updateInferenceMetrics(tokensGenerated: 1)
        }
        continuation.finish()
    }

    // MARK: - CPU Fallback Implementation

    private func runCPUFallbackInference(inputTokens: [Int]) async throws -> [Int] {
        // Provide the same placeholder response when on CPU fallback.
        if let tokenizer = self.tokenizer {
            let responseText = "Hi! I'm running in a low-power fallback mode right now but I'm still ready to help. Ask me anything!"
            let encoded = try tokenizer.encode(responseText)
            NSLog("🐌 CPU fallback placeholder response generated")
            return encoded
        }

        // Legacy numeric stub as last resort
        let outputLength = min(max(inputTokens.count, 5), 50)
        let inferenceTimeMs = outputLength * 200
        try await Task.sleep(nanoseconds: UInt64(inferenceTimeMs * 1_000_000))
        var outputTokens: [Int] = []
        for i in 0..<outputLength {
            let baseToken = inputTokens.indices.contains(i) ? inputTokens[i] : 1000
            let transformedToken = (baseToken + i * 17) % 50000 + 4
            outputTokens.append(transformedToken)
        }
        NSLog("🐌 CPU fallback numeric stub completed")
        return outputTokens
    }

    private func streamCPUFallbackInference(inputTokens: [Int], continuation: AsyncThrowingStream<Int, Error>.Continuation) async throws {
        guard let tokenizer = self.tokenizer else {
            // Numeric stub streaming
            let outputLength = min(max(inputTokens.count, 5), 50)
            for i in 0..<outputLength {
                try await Task.sleep(nanoseconds: 200_000_000)
                let baseToken = inputTokens.indices.contains(i) ? inputTokens[i] : 1000
                let transformedToken = (baseToken + i * 17) % 50000 + 4
                continuation.yield(transformedToken)
            }
            continuation.finish()
            return
        }

        let responseText = "CPU mode engaged – I'll keep responses short and sweet to save power. What would you like to do?"
        let tokens = try tokenizer.encode(responseText)
        for token in tokens {
            try await Task.sleep(nanoseconds: 120_000_000)
            continuation.yield(token)
        }
        continuation.finish()
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

// MARK: - Simple Tokenizer

/// Simple word-based tokenizer for local AI inference
/// Provides basic tokenization without external dependencies
class SimpleTokenizer {
    
    /// Get the special token IDs used by the tokenizer
    struct SpecialTokens {
        let pad: Int = 0
        let eos: Int = 1
        let bos: Int = 2
        let unk: Int = 3
    }
    
    let specialTokens = SpecialTokens()

    // NEW: Bidirectional vocabulary maps so we can decode tokens back to human-readable words
    // These are shared across all tokenizer instances for the lifetime of the app.
    private static var tokenToWord: [Int: String] = [:]
    private static var wordToToken: [String: Int] = [:]
    private static var nextGeneratedToken: Int = 1000 // Start a bit above the special tokens
    private static let vocabularyLock = NSLock()
    
    init() {
        NSLog("🔧 Simple tokenizer initialized")
    }
    
    func encode(_ text: String) throws -> [Int] {
        // Split text into words and map to token IDs
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        
        var tokens: [Int] = []
        tokens.append(specialTokens.bos)

        for word in words {
            let token: Int
            if let existing = Self.wordToToken[word] {
                token = existing
            } else {
                // Acquire lock for thread-safe vocabulary updates
                Self.vocabularyLock.lock()
                // Re-check in case another thread already added it
                if let existingAfterLock = Self.wordToToken[word] {
                    token = existingAfterLock
                } else {
                    token = Self.nextGeneratedToken
                    Self.nextGeneratedToken += 1
                    Self.wordToToken[word] = token
                    Self.tokenToWord[token] = word
                }
                Self.vocabularyLock.unlock()
            }
            tokens.append(token)
        }

        tokens.append(specialTokens.eos)
        NSLog("📝 Encoded '\(text.prefix(50))...' to \(tokens.count) tokens")
        return tokens
    }
    
    func decode(_ tokens: [Int]) throws -> String {
        var words: [String] = []
        for token in tokens {
            // Skip special tokens
            if token == specialTokens.bos || token == specialTokens.eos || token == specialTokens.pad || token == specialTokens.unk {
                continue
            }
            if let word = Self.tokenToWord[token] {
                words.append(word)
            } else {
                // Fallback – represent unknown token numerically so we can still show something
                words.append("<t\(token)>")
            }
        }

        let reconstructed = words.joined(separator: " ")
        NSLog("📝 Decoded \(tokens.count) tokens to text representation")
        return reconstructed
    }
    
    /// Get vocabulary size (dynamic)
    var vocabularySize: Int {
        return Self.tokenToWord.count + 4 // include special tokens
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