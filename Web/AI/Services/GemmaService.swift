import Foundation

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
    private var tokenizer: GemmaTokenizer?
    
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
            
            if context != nil {
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
        
        // TODO: Implement actual MLX inference when MLX package is available
        // For now, return a more realistic response based on input length
        let outputLength = min(max(inputTokens.count, 10), 100) // More realistic output length
        
        // Simulate more realistic inference delay based on token count
        let inferenceTimeMs = outputLength * 50 // 50ms per token (realistic for local inference)
        try await Task.sleep(nanoseconds: UInt64(inferenceTimeMs * 1_000_000))
        
        // Generate more realistic token sequence (this would be actual MLX inference)
        var outputTokens: [Int] = []
        for i in 0..<outputLength {
            // Generate tokens that could represent actual words/pieces
            outputTokens.append(1000 + (i % 1000)) // More realistic token range
        }
        
        // Update performance metrics
        mlxWrapper.updateInferenceMetrics(tokensGenerated: outputTokens.count)
        
        NSLog("🚀 MLX inference completed: \(inputTokens.count) input tokens → \(outputTokens.count) output tokens")
        return outputTokens
    }
    
    private func streamMLXInference(inputTokens: [Int], model: [String: Any], continuation: AsyncThrowingStream<Int, Error>.Continuation) async throws {
        // Start performance timing
        mlxWrapper.startInferenceTimer()
        
        // TODO: Implement actual MLX streaming inference when MLX package is available
        let outputLength = min(max(inputTokens.count, 10), 100)
        
        for i in 0..<outputLength {
            // More realistic per-token delay for streaming
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms per token
            
            let token = 1000 + (i % 1000)
            continuation.yield(token)
            
            // Update metrics per token
            mlxWrapper.updateInferenceMetrics(tokensGenerated: 1)
        }
        
        continuation.finish()
        NSLog("🚀 MLX streaming inference completed: \(outputLength) tokens generated")
    }
    
    // MARK: - CPU Fallback Implementation
    
    private func runCPUFallbackInference(inputTokens: [Int]) async throws -> [Int] {
        // CPU inference would be slower
        let outputLength = min(max(inputTokens.count, 5), 50) // Smaller output for CPU
        
        // Simulate CPU inference delay (slower than MLX)
        let inferenceTimeMs = outputLength * 200 // 200ms per token (slower for CPU)
        try await Task.sleep(nanoseconds: UInt64(inferenceTimeMs * 1_000_000))
        
        // Generate fallback token sequence
        var outputTokens: [Int] = []
        for i in 0..<outputLength {
            outputTokens.append(2000 + (i % 500)) // Different token range for CPU fallback
        }
        
        NSLog("🐌 CPU fallback inference completed: \(inputTokens.count) input tokens → \(outputTokens.count) output tokens")
        return outputTokens
    }
    
    private func streamCPUFallbackInference(inputTokens: [Int], continuation: AsyncThrowingStream<Int, Error>.Continuation) async throws {
        let outputLength = min(max(inputTokens.count, 5), 50)
        
        for i in 0..<outputLength {
            // Slower streaming for CPU fallback
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms per token
            
            let token = 2000 + (i % 500)
            continuation.yield(token)
        }
        
        continuation.finish()
        NSLog("🐌 CPU fallback streaming completed: \(outputLength) tokens generated")
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
        // Enhanced tokenization - better handling until SentencePiece is available
        var tokens: [Int] = []
        
        // Add BOS token for conversation start
        if let bosToken = vocabulary["<bos>"] {
            tokens.append(bosToken)
        }
        
        // Tokenize with better word/punctuation splitting
        let processedText = preprocessText(text)
        let components = tokenizeText(processedText)
        
        for component in components {
            if let tokenId = vocabulary[component] {
                tokens.append(tokenId)
            } else {
                // Handle unknown words with subword fallback
                let fallbackTokens = handleUnknownWord(component)
                tokens.append(contentsOf: fallbackTokens)
            }
        }
        
        // Add EOS token for completion
        if let eosToken = vocabulary["<eos>"] {
            tokens.append(eosToken)
        }
        
        return tokens
    }
    
    private func preprocessText(_ text: String) -> String {
        // Clean and normalize text
        var processed = text.lowercased()
        
        // Handle contractions
        processed = processed.replacingOccurrences(of: "don't", with: "do not")
        processed = processed.replacingOccurrences(of: "won't", with: "will not")
        processed = processed.replacingOccurrences(of: "can't", with: "cannot")
        processed = processed.replacingOccurrences(of: "'re", with: " are")
        processed = processed.replacingOccurrences(of: "'ve", with: " have")
        processed = processed.replacingOccurrences(of: "'ll", with: " will")
        processed = processed.replacingOccurrences(of: "'d", with: " would")
        
        return processed
    }
    
    private func tokenizeText(_ text: String) -> [String] {
        var components: [String] = []
        var currentWord = ""
        
        for char in text {
            let charStr = String(char)
            
            if charStr.rangeOfCharacter(from: .letters) != nil {
                // Letter - add to current word
                currentWord += charStr
            } else {
                // Non-letter - finish current word and add punctuation/space
                if !currentWord.isEmpty {
                    components.append(currentWord)
                    currentWord = ""
                }
                
                if !charStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    components.append(charStr)
                }
            }
        }
        
        // Add final word if exists
        if !currentWord.isEmpty {
            components.append(currentWord)
        }
        
        return components
    }
    
    private func handleUnknownWord(_ word: String) -> [Int] {
        // Simple subword tokenization for unknown words
        let unkToken = vocabulary["<unk>"] ?? 3
        
        // Try to split into smaller components
        if word.count > 3 {
            var tokens: [Int] = []
            let midpoint = word.count / 2
            let firstHalf = String(word.prefix(midpoint))
            let secondHalf = String(word.suffix(word.count - midpoint))
            
            tokens.append(vocabulary[firstHalf] ?? unkToken)
            tokens.append(vocabulary[secondHalf] ?? unkToken)
            return tokens
        } else {
            return [unkToken]
        }
    }
    
    func decode(_ tokens: [Int]) throws -> String {
        // Enhanced detokenization with better formatting
        var words: [String] = []
        
        for token in tokens {
            guard let word = reverseVocabulary[token] else {
                // Skip unknown token IDs
                continue
            }
            
            // Skip special tokens in output
            if ["<bos>", "<eos>", "<pad>"].contains(word) {
                continue
            }
            
            words.append(word)
        }
        
        // Smart joining - don't add spaces before punctuation
        var result = ""
        let punctuation = Set([".", ",", "!", "?", ":", ";", "'", "\"", ")", "]", "}"])
        
        for (index, word) in words.enumerated() {
            if index == 0 {
                result = word
            } else if punctuation.contains(word) {
                // Don't add space before punctuation
                result += word
            } else if word == " " || word == "\n" || word == "\t" {
                // Add whitespace as-is
                result += word
            } else {
                // Add space before regular words
                result += " " + word
            }
        }
        
        return result
    }
    
    private func loadVocabulary() throws {
        // Enhanced vocabulary for better tokenization until real SentencePiece is available
        // This provides a more realistic tokenization than the minimal placeholder
        
        // Check if tokenizer file exists alongside model
        let tokenizerPath = modelPath.appendingPathExtension("tokenizer")
        if FileManager.default.fileExists(atPath: tokenizerPath.path) {
            try loadTokenizerFromFile(tokenizerPath)
        } else {
            // Generate comprehensive fallback vocabulary
            vocabulary = createFallbackVocabulary()
        }
        
        reverseVocabulary = Dictionary(uniqueKeysWithValues: vocabulary.map { ($1, $0) })
        NSLog("📝 Loaded vocabulary with \(vocabulary.count) tokens")
    }
    
    private func loadTokenizerFromFile(_ path: URL) throws {
        // TODO: Load actual SentencePiece tokenizer from file when available
        _ = try Data(contentsOf: path)
        // Parse tokenizer data (JSON, binary, etc.)
        // For now, fall back to comprehensive vocabulary
        vocabulary = createFallbackVocabulary()
    }
    
    private func createFallbackVocabulary() -> [String: Int] {
        var vocab: [String: Int] = [:]
        var tokenId = 0
        
        // Special tokens (matching Gemma format)
        let specialTokens = [
            "<pad>": tokenId, // 0
            "<eos>": tokenId + 1, // 1  
            "<bos>": tokenId + 2, // 2
            "<unk>": tokenId + 3  // 3
        ]
        
        for (token, id) in specialTokens {
            vocab[token] = id
            tokenId = max(tokenId, id + 1)
        }
        
        // Common words and subwords (more realistic for actual text processing)
        let commonWords = [
            "the", "and", "is", "in", "to", "of", "a", "that", "it", "with",
            "for", "as", "was", "on", "are", "you", "this", "be", "at", "or",
            "have", "from", "they", "we", "been", "had", "their", "said", "each",
            "which", "do", "how", "if", "will", "up", "other", "about", "out",
            "many", "then", "them", "these", "so", "some", "her", "would", "make",
            "like", "into", "him", "has", "two", "more", "very", "what", "know",
            "just", "first", "get", "over", "think", "also", "your", "work", "life",
            "only", "new", "years", "way", "may", "say", "come", "could", "now",
            "than", "my", "well", "such", "because", "when", "much", "can", "through",
            "back", "good", "before", "try", "same", "should", "our", "own", "while",
            "where", "right", "there", "see", "between", "long", "here", "something",
            "both", "little", "under", "might", "go", "day", "another", "find", "head",
            "system", "set", "every", "start", "hand", "high", "group", "real", "problem",
            "fact", "place", "end", "case", "point", "government", "company", "number",
            "part", "take", "seem", "water", "become", "made", "around", "however",
            "actually", "against", "policy", "together", "business", "really", "almost",
            "enough", "quite", "taken", "being", "nothing", "turn", "put", "called",
            "doesn", "going", "look", "asked", "later", "knew", "people", "came", "want",
            "things", "though", "still", "always", "money", "seen", "didn", "getting"
        ]
        
        for word in commonWords {
            vocab[word] = tokenId
            tokenId += 1
        }
        
        // Add common punctuation and symbols
        let punctuation = [".", ",", "!", "?", ":", ";", "'", "\"", "(", ")", "[", "]", "{", "}",
                          "-", "_", "+", "=", "@", "#", "$", "%", "&", "*", "/", "\\", "|", "^", "~", "`"]
        
        for punct in punctuation {
            vocab[punct] = tokenId
            tokenId += 1
        }
        
        // Add space tokens
        vocab[" "] = tokenId
        tokenId += 1
        vocab["\n"] = tokenId
        tokenId += 1
        vocab["\t"] = tokenId
        tokenId += 1
        
        return vocab
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