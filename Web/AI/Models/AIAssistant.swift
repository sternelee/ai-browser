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
    private let onDemandModelService: OnDemandModelService
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
        self.onDemandModelService = OnDemandModelService()
        self.privacyManager = PrivacyManager()
        self.conversationHistory = ConversationHistory()
        
        // Get optimal configuration for current hardware
        self.aiConfiguration = HardwareDetector.getOptimalAIConfiguration()
        
        // Initialize Gemma service with configuration and shared services
        self.gemmaService = GemmaService(
            configuration: aiConfiguration,
            mlxWrapper: mlxWrapper,
            privacyManager: privacyManager,
            onDemandModelService: onDemandModelService
        )
        
        // Set up bindings
        setupBindings()
        
        NSLog("🤖 AI Assistant initialized with \(aiConfiguration.framework) framework")
    }
    
    // MARK: - Public Interface
    
    /// Get current conversation messages for UI display
    var messages: [ConversationMessage] {
        conversationHistory.getRecentMessages()
    }
    
    /// Get message count for UI binding
    var messageCount: Int {
        conversationHistory.messageCount
    }
    
    /// FIXED: Initialize the AI system with safe parallel tasks (race condition fixed)
    func initialize() async {
        updateStatus("Initializing AI system...")
        
        do {
            // Step 1: Hardware validation (must be first, synchronous)
            updateStatus("Validating hardware compatibility...")
            try validateHardware()
            
            // CRITICAL FIX: Model checking must be SEQUENTIAL to prevent race conditions
            // Multiple parallel tasks were causing model deletion conflicts
            updateStatus("Checking AI model availability...")
            if !onDemandModelService.isAIReady() {
                updateStatus("AI model not found - preparing download...")
                
                let downloadInfo = onDemandModelService.getDownloadInfo()
                NSLog("🔽 AI model needs to be downloaded: \(downloadInfo.formattedSize)")
                
                try await onDemandModelService.initializeAI()
            }
            
            // Wait for model to be ready with timeout
            updateStatus("Loading AI model...")
            let timeout = 60.0 // 60 second timeout
            let startTime = Date()
            
            while !onDemandModelService.isAIReady() {
                // Check for timeout
                if Date().timeIntervalSince(startTime) > timeout {
                    throw ModelError.downloadFailed("Model loading timed out after \(timeout) seconds")
                }
                
                // Check if download failed
                if case .failed(let error) = onDemandModelService.downloadState {
                    throw ModelError.downloadFailed("Model download failed: \(error)")
                }
                
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second (longer interval)
            }
            NSLog("✅ AI model is ready")
            
            // SAFE PARALLEL: Run independent framework tasks in parallel AFTER model is secured
            await withTaskGroup(of: Void.self) { group in
                
                // Parallel Task 1: Initialize MLX (Apple Silicon only)
                if aiConfiguration.framework == .mlx {
                    group.addTask { [weak self] in
                        guard let self = self else { return }
                        do {
                            await self.updateStatus("Initializing MLX framework...")
                            try await self.mlxWrapper.initialize()
                        } catch {
                            NSLog("❌ MLX initialization failed: \(error)")
                        }
                    }
                }
                
                // Parallel Task 2: Initialize privacy manager (independent)
                group.addTask { [weak self] in
                    guard let self = self else { return }
                    do {
                        await self.updateStatus("Setting up privacy protection...")
                        try await self.privacyManager.initialize()
                    } catch {
                        NSLog("❌ Privacy manager initialization failed: \(error)")
                    }
                }
            }
            
            // SEQUENTIAL: Only Gemma service needs to be sequential (depends on model + privacy)
            updateStatus("Starting AI inference engine...")
            try await gemmaService.initialize()
            
            // Context processing will be added in Phase 11
            
            // Mark as initialized
            isInitialized = true
            updateStatus("AI Assistant ready")
            lastError = nil
            
            NSLog("✅ AI Assistant initialization completed successfully (OPTIMIZED)")
            
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
        
        // OPTIMIZATION: Also reset LLMRunner conversation state
        Task {
            await LLMRunner.shared.resetConversation()
        }
        
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
        // Bind conversation history changes to trigger UI updates
        conversationHistory.$messageCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Trigger UI update by changing a published property
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Bind on-demand model status  
        onDemandModelService.$isModelReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                if !isReady && self?.isInitialized == true {
                    self?.isInitialized = false
                    self?.updateStatus("AI model not available")
                }
            }
            .store(in: &cancellables)
        
        // Bind download progress for status updates
        onDemandModelService.$downloadProgress
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] progress in
                if progress > 0 && progress < 1.0 {
                    self?.updateStatus("Downloading AI model: \(Int(progress * 100))%")
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