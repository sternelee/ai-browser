import Foundation
import LLM
// LLMRunner included via Web.AI.Runners

/// Gemma AI service for local inference with LLM.swift
/// Handles model initialization, text generation, and response streaming using GGUF models
class GemmaService {
    
    // MARK: - Properties
    
    private let configuration: AIConfiguration
    private let mlxWrapper: MLXWrapper
    private let privacyManager: PrivacyManager
    private let onDemandModelService: OnDemandModelService
    
    private var isModelLoaded: Bool = false
    private var modelWeights: [String: Any]? = nil
    private var tokenizer: SimpleTokenizer?
    
    // No remote fallbacks - we use local GGUF models only
    
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
            // Check for local GGUF model
            guard let modelPath = onDemandModelService.getModelPath() else {
                throw GemmaError.modelNotAvailable("AI model is being prepared. Please wait for the download to complete.")
            }
            
            NSLog("📂 Found GGUF model: \(modelPath.lastPathComponent)")
            
            // Validate model file exists
            guard FileManager.default.fileExists(atPath: modelPath.path) else {
                throw GemmaError.modelNotAvailable("GGUF model file not found at path: \(modelPath.path)")
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
                let _ = responseBuilder.setContextUsed(true)
            }
            
            guard let tokenizer = tokenizer else {
                throw GemmaError.tokenizerNotAvailable
            }

            // Use LLM.swift for local GGUF inference
            let _ = responseBuilder.addProcessingStep(ProcessingStep(name: "llm_inference", duration: 0, description: "Running LLM.swift GGUF inference"))

            // Get local GGUF model path
            guard let modelPath = onDemandModelService.getModelPath() else {
                throw GemmaError.modelNotAvailable("AI model is being prepared for inference")
            }

            do {
                let generatedText = try await LLMRunner.shared.generate(prompt: prompt, modelPath: modelPath)
                let encoded = try tokenizer.encode(generatedText)
                let cleaned = postProcessResponse(generatedText)
                mlxWrapper.updateInferenceMetrics(tokensGenerated: encoded.count)
                return responseBuilder.setText(cleaned).setMemoryUsage(Int(mlxWrapper.memoryUsage)).build()
            } catch {
                NSLog("❌ LLM inference failed: \(error)")
                throw GemmaError.inferenceError("LLM inference failed: \(error.localizedDescription)")
            }

            // All inference handled above by LLMRunner
            
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
                    
                    guard tokenizer != nil else {
                        throw GemmaError.tokenizerNotAvailable
                    }
                    
                    // Get local GGUF model path
                    guard let modelPath = onDemandModelService.getModelPath() else {
                        throw GemmaError.modelNotAvailable("AI model is still being prepared for streaming")
                    }
                    
                    // Use LLMRunner for streaming
                    let textStream = LLMRunner.shared.generateStream(prompt: prompt, modelPath: modelPath)
                    
                    for try await textChunk in textStream {
                        let cleanedChunk = postProcessResponse(textChunk)
                        if !cleanedChunk.isEmpty {
                            continuation.yield(cleanedChunk)
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
    
    // All inference now handled by LLMRunner using local GGUF models
    
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