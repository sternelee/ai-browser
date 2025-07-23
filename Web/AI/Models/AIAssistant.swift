import Foundation
import Combine

/// Main AI Assistant coordinator managing local AI capabilities
/// Integrates MLX framework with context management and conversation handling
class AIAssistant: ObservableObject {
    
    // MARK: - Published Properties (Main Actor for UI Updates)
    
    @MainActor @Published var isInitialized: Bool = false
    @MainActor @Published var isProcessing: Bool = false
    @MainActor @Published var initializationStatus: String = "Not initialized"
    @MainActor @Published var lastError: String?
    
    // UNIFIED ANIMATION STATE - prevents conflicts between typing/streaming indicators
    @MainActor @Published var animationState: AIAnimationState = .idle
    @MainActor @Published var streamingText: String = ""
    
    // MARK: - Dependencies
    
    private let mlxWrapper: MLXWrapper
    private let onDemandModelService: OnDemandModelService
    private let privacyManager: PrivacyManager
    private let conversationHistory: ConversationHistory
    private let gemmaService: GemmaService
    private let contextManager: ContextManager
    private let memoryMonitor: SystemMemoryMonitor
    private weak var tabManager: TabManager?
    
    // MARK: - Configuration
    
    private let aiConfiguration: AIConfiguration
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(tabManager: TabManager? = nil) {
        // Initialize dependencies
        self.mlxWrapper = MLXWrapper()
        self.onDemandModelService = OnDemandModelService()
        self.privacyManager = PrivacyManager()
        self.conversationHistory = ConversationHistory()
        self.contextManager = ContextManager.shared
        self.memoryMonitor = SystemMemoryMonitor.shared
        self.tabManager = tabManager
        
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
            
            // CRITICAL FIX: Move model checking OFF main thread to prevent input locking
            updateStatus("Loading AI model...")
            
            // Move the blocking polling loop to background thread
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                Task.detached(priority: .background) { [weak self] in
                    let timeout = 60.0 // 60 second timeout
                    let startTime = Date()
                    
                    while !(self?.onDemandModelService.isAIReady() ?? false) {
                        // Check for timeout
                        if Date().timeIntervalSince(startTime) > timeout {
                            continuation.resume(throwing: ModelError.downloadFailed("Model loading timed out after \(timeout) seconds"))
                            return
                        }
                        
                        // Check if download failed
                        if case .failed(let error) = self?.onDemandModelService.downloadState {
                            continuation.resume(throwing: ModelError.downloadFailed("Model download failed: \(error)"))
                            return
                        }
                        
                        // Sleep in background thread - won't block main thread
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second polling
                        
                        // Update UI periodically from background
                        await MainActor.run {
                            self?.updateStatus("Loading AI model... (\(Int(Date().timeIntervalSince(startTime)))s)")
                        }
                    }
                    
                    // Model is ready - resume continuation
                    continuation.resume()
                }
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
            Task { @MainActor in
                isInitialized = true
                lastError = nil
            }
            updateStatus("AI Assistant ready")
            
            NSLog("✅ AI Assistant initialization completed successfully (OPTIMIZED)")
            
        } catch {
            let errorMessage = "AI initialization failed: \(error.localizedDescription)"
            updateStatus("Initialization failed")
            Task { @MainActor in
                lastError = errorMessage
                isInitialized = false
            }
            
            NSLog("❌ \(errorMessage)")
        }
    }
    
    /// Process a user query with current context and optional history
    func processQuery(_ query: String, includeContext: Bool = true, includeHistory: Bool = true) async throws -> AIResponse {
        guard await isInitialized else {
            throw AIError.notInitialized
        }
        
        // MEMORY SAFETY: Check if AI operations are safe to perform
        guard memoryMonitor.isAISafeToRun() else {
            let memoryStatus = memoryMonitor.getCurrentMemoryStatus()
            throw AIError.memoryPressure("AI operations suspended due to \(memoryStatus.pressureLevel.rawValue.lowercased()) memory pressure (\(String(format: "%.1f", memoryStatus.availableMemory))GB available)")
        }
        
        Task { @MainActor in isProcessing = true }
        defer { Task { @MainActor in isProcessing = false } }
        
        do {
            // Extract context from current webpage with optional history
            let webpageContext = await extractCurrentContext()
            let context = contextManager.getFormattedContext(from: webpageContext, includeHistory: includeHistory && includeContext)
            
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
            await handleAIError(error)
            throw error
        }
    }
    
    /// Process a streaming query with real-time responses and optional history
    func processStreamingQuery(_ query: String, includeContext: Bool = true, includeHistory: Bool = true) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard await isInitialized else {
                        throw AIError.notInitialized
                    }
                    
                    Task { @MainActor in isProcessing = true }
                    defer { Task { @MainActor in isProcessing = false } }
                    
                    // Extract context from current webpage with optional history
                    let webpageContext = await self.extractCurrentContext()
                    let context = self.contextManager.getFormattedContext(from: webpageContext, includeHistory: includeHistory && includeContext)
                    
                    // Process with streaming
                    let stream = try await gemmaService.generateStreamingResponse(
                        query: query,
                        context: context,
                        conversationHistory: conversationHistory.getRecentMessages(limit: 10)
                    )
                    
                    // Add user message first
                    let userMessage = ConversationMessage(
                        role: .user,
                        content: query,
                        timestamp: Date(),
                        contextData: context
                    )
                    conversationHistory.addMessage(userMessage)
                    
                    // Create empty AI message that will be filled during streaming
                    let aiMessage = ConversationMessage(
                        role: .assistant,
                        content: "", // Start empty for streaming
                        timestamp: Date()
                    )
                    conversationHistory.addMessage(aiMessage)
                    
                    // Set up unified streaming animation state
                    await MainActor.run {
                        animationState = .streaming(messageId: aiMessage.id)
                        streamingText = ""
                    }
                    
                    var fullResponse = ""
                    
                    for try await chunk in stream {
                        fullResponse += chunk
                        
                        // Update UI streaming text
                        await MainActor.run {
                            streamingText = fullResponse
                        }
                        
                        continuation.yield(chunk)
                    }
                    
                    // FIX: Update the empty message with the final streamed content
                    conversationHistory.updateMessage(id: aiMessage.id, newContent: fullResponse)
                    
                    // Clear unified animation state when done
                    await MainActor.run {
                        animationState = .idle
                        streamingText = ""
                    }
                    
                    continuation.finish()
                    
                } catch {
                    NSLog("❌ Streaming error occurred: \(error)")
                    
                    // Get the message ID before clearing state
                    let messageId = await animationState.streamingMessageId
                    
                    // Clear unified animation state on error
                    await MainActor.run {
                        animationState = .idle
                        streamingText = ""
                    }
                    
                    // If we have a partially complete message, update it with error info
                    if let messageId = messageId {
                        conversationHistory.updateMessage(
                            id: messageId, 
                            newContent: "Sorry, there was an error generating the response: \(error.localizedDescription)"
                        )
                    }
                    
                    await self.handleAIError(error)
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
    
    /// Reset AI conversation state to recover from errors
    func resetConversationState() async {
        // Clear conversation history
        conversationHistory.clear()
        
        // Reset LLM conversation state to prevent KV cache issues
        await gemmaService.resetConversation()
        
        await MainActor.run {
            lastError = nil
            isProcessing = false
        }
        
        NSLog("🔄 AI conversation state fully reset for error recovery")
    }
    
    /// Handle AI errors with automatic recovery
    private func handleAIError(_ error: Error) async {
        let errorMessage = error.localizedDescription
        NSLog("❌ AI Error occurred: \(errorMessage)")
        
        await MainActor.run {
            lastError = errorMessage
            isProcessing = false
        }
        
        // Auto-recovery for common errors
        if errorMessage.contains("inconsistent sequence positions") ||
           errorMessage.contains("KV cache") ||
           errorMessage.contains("decode") {
            NSLog("🔄 Detected conversation state error, attempting auto-recovery...")
            await resetConversationState()
        }
    }
    
    /// Check if AI system is in a healthy state
    func performHealthCheck() async -> Bool {
        do {
            // Test if the AI system can handle a simple query
            let testQuery = "Hello"
            let _ = try await processQuery(testQuery, includeContext: false)
            return true
        } catch {
            NSLog("⚠️ AI Health check failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Configure history context settings
    func configureHistoryContext(enabled: Bool, scope: HistoryContextScope) {
        contextManager.configureHistoryContext(enabled: enabled, scope: scope)
        NSLog("🔍 AI Assistant history context configured: enabled=\(enabled), scope=\(scope.displayName)")
    }
    
    /// Get current history context status
    func getHistoryContextStatus() -> (enabled: Bool, scope: HistoryContextScope) {
        return (contextManager.isHistoryContextEnabled, contextManager.historyContextScope)
    }
    
    /// Clear history context for privacy
    func clearHistoryContext() {
        contextManager.clearHistoryContextCache()
        NSLog("🗑️ AI Assistant history context cleared")
    }
    
    /// Get current system status
    @MainActor func getSystemStatus() -> AISystemStatus {
        let historyContextInfo = getHistoryContextStatus()
        
        return AISystemStatus(
            isInitialized: isInitialized,
            framework: aiConfiguration.framework,
            modelVariant: aiConfiguration.modelVariant,
            memoryUsage: Int(mlxWrapper.memoryUsage),
            inferenceSpeed: mlxWrapper.inferenceSpeed,
            contextTokenCount: 0, // Context processing will be added in Phase 11
            conversationLength: conversationHistory.messageCount,
            hardwareInfo: HardwareDetector.processorType.description,
            historyContextEnabled: historyContextInfo.enabled,
            historyContextScope: historyContextInfo.scope.displayName
        )
    }
    
    // MARK: - Private Methods
    
    private func extractCurrentContext() async -> WebpageContext? {
        guard let tabManager = tabManager else {
            NSLog("⚠️ TabManager not available for context extraction")
            return nil
        }
        
        return await contextManager.extractCurrentPageContext(from: tabManager)
    }
    
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
        // Bind conversation history changes - SwiftUI automatically handles UI updates for @Published properties
        conversationHistory.$messageCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // SwiftUI automatically triggers UI updates when @Published properties change
                // Removed manual objectWillChange.send() to prevent unnecessary re-renders
            }
            .store(in: &cancellables)
        
        // Bind on-demand model status  
        onDemandModelService.$isModelReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                Task { @MainActor [weak self] in
                    if !isReady && self?.isInitialized == true {
                        self?.isInitialized = false
                    }
                }
                self?.updateStatus("AI model not available")
            }
            .store(in: &cancellables)
        
        // Bind download progress for status updates
        onDemandModelService.$downloadProgress
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] progress in
                if progress > 0 && progress < 1.0 {
                    NSLog("🎯 DOWNLOAD DEBUG: Model download progress: \(progress * 100)% - updating status")
                    self?.updateStatus("Downloading AI model: \(Int(progress * 100))%")
                }
            }
            .store(in: &cancellables)
        
        // Bind MLX wrapper status
        mlxWrapper.$isInitialized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mlxInitialized in
                Task { @MainActor [weak self] in
                    if !mlxInitialized && self?.aiConfiguration.framework == .mlx {
                        self?.isInitialized = false
                    }
                }
                if !mlxInitialized && self?.aiConfiguration.framework == .mlx {
                    self?.updateStatus("MLX framework not available")
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateStatus(_ status: String) {
        Task { @MainActor in
            initializationStatus = status
        }
        NSLog("🤖 AI Status: \(status)")
    }
}

// MARK: - Supporting Types

/// Unified animation state for AI responses to prevent conflicts
enum AIAnimationState: Equatable {
    case idle
    case typing
    case streaming(messageId: String)
    case processing
    
    var isActive: Bool {
        switch self {
        case .idle:
            return false
        case .typing, .streaming, .processing:
            return true
        }
    }
    
    var isStreaming: Bool {
        if case .streaming = self {
            return true
        }
        return false
    }
    
    var streamingMessageId: String? {
        if case .streaming(let messageId) = self {
            return messageId
        }
        return nil
    }
}

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
    let historyContextEnabled: Bool
    let historyContextScope: String
}

/// AI specific errors
enum AIError: LocalizedError {
    case notInitialized
    case unsupportedHardware(String)
    case insufficientMemory(String)
    case memoryPressure(String)
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
        case .memoryPressure(let message):
            return "Memory Pressure: \(message)"
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