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
    
    /// Remote Hugging Face identifier for a pre-converted Gemma model in MLX format.
    /// We use this as a fallback when a local model directory is not yet available –
    /// `LLMModelFactory` will transparently download and cache the model on first use.
    private static let remoteMLXModelID = "hf://mlx-community/gemma-3n-E2B-it-4bit"
    
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
            // Ask OnDemandModelService for a local MLX model (directory). If it returns nil we will
            // operate in "remote-only" mode and let MLX download the weights on first inference.
            if let modelPath = onDemandModelService.getModelPath() {
                NSLog("📂 Loading Gemma model from \(modelPath.lastPathComponent)")

                // If the path is a directory (converted MLX model) we rely entirely on MLXGemmaRunner and do NOT
                // attempt to read it as a single file.
                if (try? modelPath.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    tokenizer = SimpleTokenizer()
                    isModelLoaded = true
                    NSLog("✅ Detected MLX model directory – skipping manual weight load")
                    return
                }

                // Otherwise, load GGUF weights for CPU fallback or quantization.
                modelWeights = try await mlxWrapper.loadModelWeights(from: modelPath)

                // Apply quantisation if required
                if case .int4 = configuration.quantization {
                    modelWeights = mlxWrapper.quantizeModel(modelWeights!, bits: 4)
                }
                NSLog("✅ Local model weights loaded")
            } else {
                NSLog("ℹ️ No local MLX model – will use remote repository \(Self.remoteMLXModelID)")
            }

            // Initialize simple tokenizer
            tokenizer = SimpleTokenizer()
            NSLog("✅ Simple tokenizer initialized")

            isModelLoaded = true
            NSLog("✅ Gemma model loaded successfully (tokenizer ready)")
            
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
        let _ = Date() // Track timing but not used in current implementation
        
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
            if mlxWrapper.isInitialized {
                responseBuilder.addProcessingStep(ProcessingStep(name: "mlx_inference", duration: 0, description: "Running MLX LLM"))

                // Prefer locally converted model; otherwise fall back to remote MLX id.
                let modelURL = onDemandModelService.getModelPath() ?? URL(string: Self.remoteMLXModelID)!

                do {
                    let generatedText = try await MLXGemmaRunner.shared.generate(prompt: prompt, modelPath: modelURL)
                    let encoded = try tokenizer.encode(generatedText)
                    let cleaned = postProcessResponse(generatedText)
                    mlxWrapper.updateInferenceMetrics(tokensGenerated: encoded.count)
                    return responseBuilder.setText(cleaned).setMemoryUsage(Int(mlxWrapper.memoryUsage)).build()
                } catch {
                    NSLog("❌ MLX inference failed: \(error)")
                    throw GemmaError.inferenceError("MLX inference failed: \(error.localizedDescription)")
                }
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
        // Prefer MLX inference whenever the MLX wrapper is initialized, regardless of whether we loaded explicit weights.
        if mlxWrapper.isInitialized {
            return try await runMLXInference(inputTokens: inputTokens, model: modelWeights ?? [:])
        }

        // If MLX is not available we abort – CPU fallback has been disabled.
        throw GemmaError.inferenceError("MLX not available and CPU fallback disabled")
    }
    
    private func runStreamingInference(inputTokens: [Int]) async throws -> AsyncThrowingStream<Int, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    if mlxWrapper.isInitialized {
                        try await streamMLXInference(inputTokens: inputTokens, model: modelWeights ?? [:], continuation: continuation)
                    } else {
                        continuation.finish(throwing: GemmaError.inferenceError("MLX not available and CPU streaming fallback disabled"))
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

        let modelPath = onDemandModelService.getModelPath() ?? URL(string: Self.remoteMLXModelID)!

        // Decode input tokens back to prompt text for MLX
        guard let tokenizer = self.tokenizer else {
            throw GemmaError.tokenizerNotAvailable
        }
        let promptText = try tokenizer.decode(inputTokens)

        // Run real MLX inference
        do {
            let generatedText = try await MLXGemmaRunner.shared.generate(
                prompt: promptText,
                maxTokens: 256,
                temperature: 0.7,
                modelPath: modelPath
            )

            // Encode response back to tokens
            let outputTokens = try tokenizer.encode(generatedText)
            mlxWrapper.updateInferenceMetrics(tokensGenerated: outputTokens.count)
            NSLog("🚀 Real MLX inference completed: \(generatedText.count) chars generated")
            return outputTokens
        } catch {
            throw GemmaError.inferenceError("MLX inference failed: \(error.localizedDescription)")
        }
    }

    private func streamMLXInference(inputTokens: [Int], model: [String: Any], continuation: AsyncThrowingStream<Int, Error>.Continuation) async throws {
        guard let tokenizer = self.tokenizer else {
            continuation.finish(throwing: GemmaError.tokenizerNotAvailable)
            return
        }

        let modelPath = onDemandModelService.getModelPath() ?? URL(string: Self.remoteMLXModelID)!

        // Decode input tokens back to prompt text for MLX
        let promptText = try tokenizer.decode(inputTokens)

        // Use MLXGemmaRunner streaming
        do {
            let stream = await MLXGemmaRunner.shared.generateStream(
                prompt: promptText,
                maxTokens: 256,
                temperature: 0.7,
                modelPath: modelPath
            )

            for try await textChunk in stream {
                // Encode text chunk to tokens for streaming
                let tokens = try tokenizer.encode(textChunk)
                for token in tokens {
                    continuation.yield(token)
                    mlxWrapper.updateInferenceMetrics(tokensGenerated: 1)
                }
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: GemmaError.inferenceError("MLX streaming failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - CPU Fallback Implementation

    private func runCPUFallbackInference(inputTokens: [Int]) async throws -> [Int] {
        throw GemmaError.inferenceError("CPU fallback disabled – MLX model required")
    }

    private func streamCPUFallbackInference(inputTokens: [Int], continuation: AsyncThrowingStream<Int, Error>.Continuation) async throws {
        continuation.finish(throwing: GemmaError.inferenceError("CPU streaming fallback disabled"))
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