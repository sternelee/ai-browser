import Foundation
import Combine

/// Main AI Assistant coordinator managing local AI capabilities
/// Integrates MLX framework with context management and conversation handling
@MainActor
class AIAssistant: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isInitialized: Bool = false
    @Published var isProcessing: Bool = false
    @Published var initializationStatus: String = "Not initialized"
    @Published var lastError: String?
    
    // MARK: - Dependencies
    
    private let mlxWrapper: MLXWrapper
    private let bundledModelService: BundledModelService
    private let privacyManager: PrivacyManager
    private let conversationHistory: ConversationHistory
    private let gemmaService: GemmaService
    
    // MARK: - Configuration
    
    private let aiConfiguration: AIConfiguration
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        // Initialize dependencies
        self.mlxWrapper = MLXWrapper()
        self.bundledModelService = BundledModelService()
        self.privacyManager = PrivacyManager()
        self.conversationHistory = ConversationHistory()
        
        // Get optimal configuration for current hardware
        self.aiConfiguration = HardwareDetector.getOptimalAIConfiguration()
        
        // Initialize Gemma service with configuration
        self.gemmaService = GemmaService(
            configuration: aiConfiguration,
            mlxWrapper: mlxWrapper,
            privacyManager: privacyManager
        )
        
        // Set up bindings
        setupBindings()
        
        NSLog("🤖 AI Assistant initialized with \(aiConfiguration.framework) framework")
    }
    
    // MARK: - Public Interface
    
    /// Initialize the AI system with model loading and setup
    func initialize() async {
        updateStatus("Initializing AI system...")
        
        do {
            // Step 1: Hardware validation
            updateStatus("Validating hardware compatibility...")
            try validateHardware()
            
            // Step 2: Initialize MLX (Apple Silicon only)
            if aiConfiguration.framework == .mlx {
                updateStatus("Initializing MLX framework...")
                try await mlxWrapper.initialize()
            }
            
            // Step 3: Initialize bundled model (out-of-box experience)
            updateStatus("Loading bundled AI model...")
            // BundledModelService automatically initializes the model
            while !bundledModelService.isModelReady {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                // Wait for model to be ready
            }
            NSLog("✅ Using bundled Gemma 3n model for instant AI")
            
            // Step 4: Initialize Gemma service
            updateStatus("Loading AI model...")
            try await gemmaService.initialize()
            
            // Step 5: Initialize privacy manager
            updateStatus("Setting up privacy protection...")
            try await privacyManager.initialize()
            
            // Context processing will be added in Phase 11
            
            // Mark as initialized
            isInitialized = true
            updateStatus("AI Assistant ready")
            lastError = nil
            
            NSLog("✅ AI Assistant initialization completed successfully")
            
        } catch {
            let errorMessage = "AI initialization failed: \(error.localizedDescription)"
            updateStatus("Initialization failed")
            lastError = errorMessage
            isInitialized = false
            
            NSLog("❌ \(errorMessage)")
        }
    }
    
    /// Process a user query with current context
    func processQuery(_ query: String, includeContext: Bool = true) async throws -> AIResponse {
        guard isInitialized else {
            throw AIError.notInitialized
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            // Context extraction will be implemented in Phase 11
            let context: String? = nil
            
            // Create conversation entry
            let userMessage = ConversationMessage(
                role: .user,
                content: query,
                timestamp: Date(),
                contextData: context
            )
            
            // Add to conversation history
            conversationHistory.addMessage(userMessage)
            
            // Process with Gemma service
            let response = try await gemmaService.generateResponse(
                query: query,
                context: context,
                conversationHistory: conversationHistory.getRecentMessages(limit: 10)
            )
            
            // Create AI response message
            let aiMessage = ConversationMessage(
                role: .assistant,
                content: response.text,
                timestamp: Date(),
                metadata: response.metadata
            )
            
            // Add to conversation history
            conversationHistory.addMessage(aiMessage)
            
            // Return response
            return response
            
        } catch {
            NSLog("❌ Query processing failed: \(error)")
            throw error
        }
    }
    
    /// Process a streaming query with real-time responses
    func processStreamingQuery(_ query: String, includeContext: Bool = true) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard isInitialized else {
                        throw AIError.notInitialized
                    }
                    
                    isProcessing = true
                    defer { isProcessing = false }
                    
                    // Context extraction will be implemented in Phase 11
                    let context: String? = nil
                    
                    // Process with streaming
                    let stream = try await gemmaService.generateStreamingResponse(
                        query: query,
                        context: context,
                        conversationHistory: conversationHistory.getRecentMessages(limit: 10)
                    )
                    
                    var fullResponse = ""
                    
                    for try await chunk in stream {
                        fullResponse += chunk
                        continuation.yield(chunk)
                    }
                    
                    // Save complete conversation
                    let userMessage = ConversationMessage(
                        role: .user,
                        content: query,
                        timestamp: Date(),
                        contextData: context
                    )
                    
                    let aiMessage = ConversationMessage(
                        role: .assistant,
                        content: fullResponse,
                        timestamp: Date()
                    )
                    
                    conversationHistory.addMessage(userMessage)
                    conversationHistory.addMessage(aiMessage)
                    
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Get conversation summary for the current session
    func getConversationSummary() async throws -> String {
        let messages = conversationHistory.getRecentMessages(limit: 20)
        return try await gemmaService.summarizeConversation(messages)
    }
    
    /// Clear conversation history and context
    func clearConversation() {
        conversationHistory.clear()
        NSLog("🗑️ Conversation cleared")
    }
    
    /// Get current system status
    func getSystemStatus() -> AISystemStatus {
        return AISystemStatus(
            isInitialized: isInitialized,
            framework: aiConfiguration.framework,
            modelVariant: aiConfiguration.modelVariant,
            memoryUsage: Int(mlxWrapper.memoryUsage),
            inferenceSpeed: mlxWrapper.inferenceSpeed,
            contextTokenCount: 0, // Context processing will be added in Phase 11
            conversationLength: conversationHistory.messageCount,
            hardwareInfo: HardwareDetector.processorType.description
        )
    }
    
    // MARK: - Private Methods
    
    private func validateHardware() throws {
        switch aiConfiguration.framework {
        case .mlx:
            guard HardwareDetector.isAppleSilicon else {
                throw AIError.unsupportedHardware("MLX requires Apple Silicon")
            }
        case .llamaCpp:
            // Intel Macs supported with llama.cpp
            break
        }
        
        guard HardwareDetector.totalMemoryGB >= 8 else {
            throw AIError.insufficientMemory("Minimum 8GB RAM required")
        }
    }
    
    private func setupBindings() {
        // Bind bundled model status  
        bundledModelService.$isModelReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                if !isReady && self?.isInitialized == true {
                    self?.isInitialized = false
                    self?.updateStatus("Bundled model not available")
                }
            }
            .store(in: &cancellables)
        
        // Bind MLX wrapper status
        mlxWrapper.$isInitialized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mlxInitialized in
                if !mlxInitialized && self?.aiConfiguration.framework == .mlx {
                    self?.isInitialized = false
                    self?.updateStatus("MLX framework not available")
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateStatus(_ status: String) {
        initializationStatus = status
        NSLog("🤖 AI Status: \(status)")
    }
}

// MARK: - Supporting Types

/// AI system status information
struct AISystemStatus {
    let isInitialized: Bool
    let framework: AIConfiguration.Framework
    let modelVariant: AIConfiguration.ModelVariant
    let memoryUsage: Int // MB
    let inferenceSpeed: Double // tokens/second
    let contextTokenCount: Int
    let conversationLength: Int
    let hardwareInfo: String
}

/// AI specific errors
enum AIError: LocalizedError {
    case notInitialized
    case unsupportedHardware(String)
    case insufficientMemory(String)
    case modelNotAvailable
    case contextProcessingFailed(String)
    case inferenceError(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "AI Assistant not initialized"
        case .unsupportedHardware(let message):
            return "Unsupported Hardware: \(message)"
        case .insufficientMemory(let message):
            return "Insufficient Memory: \(message)"
        case .modelNotAvailable:
            return "AI model not available"
        case .contextProcessingFailed(let message):
            return "Context Processing Failed: \(message)"
        case .inferenceError(let message):
            return "Inference Error: \(message)"
        }
    }
}

/// Conversation message roles
enum ConversationRole: String, Codable {
    case user
    case assistant
    case system
}