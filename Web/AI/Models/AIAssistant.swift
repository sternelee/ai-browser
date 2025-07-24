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
    private let mlxModelService: MLXModelService
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
        self.privacyManager = PrivacyManager()
        self.conversationHistory = ConversationHistory()
        self.contextManager = ContextManager.shared
        self.memoryMonitor = SystemMemoryMonitor.shared
        self.tabManager = tabManager
        
        // Get optimal configuration for current hardware
        self.aiConfiguration = HardwareDetector.getOptimalAIConfiguration()
        
        // Initialize MLX service and Gemma service after super.init equivalent
        self.mlxModelService = MLXModelService()
        self.gemmaService = GemmaService(
            configuration: aiConfiguration,
            mlxWrapper: mlxWrapper,
            privacyManager: privacyManager,
            mlxModelService: mlxModelService
        )
        
        // Set up bindings - will be called async in initialize
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
            
            // Model checking for MLX models
            updateStatus("Checking MLX AI model availability...")
            if !(await mlxModelService.isAIReady()) {
                updateStatus("MLX AI model not found - preparing download...")
                
                let downloadInfo = await mlxModelService.getDownloadInfo()
                NSLog("🔽 MLX AI model needs to be downloaded: \(downloadInfo.formattedSize)")
                
                try await mlxModelService.initializeAI()
            }
            
            // Wait for MLX model to be ready
            updateStatus("Loading MLX AI model...")
            
            // Wait without timeout since MLX handles downloads internally
            while !(await mlxModelService.isAIReady()) {
                // Check if download failed
                if case .failed(let error) = await mlxModelService.downloadState {
                    throw MLXModelError.downloadFailed("MLX model download failed: \(error)")
                }
                
                // Update UI with progress
                let progress = await mlxModelService.downloadProgress
                if progress > 0 {
                    updateStatus("Loading MLX AI model... (\(Int(progress * 100))%)")
                } else {
                    updateStatus("Loading MLX AI model...")
                }
                
                // Brief wait - check every 0.5 seconds for more responsive UI
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            NSLog("✅ AI model is ready")
            
            // SAFE PARALLEL: Run independent framework tasks in parallel AFTER model is secured
            await withTaskGroup(of: Void.self) { group in
                
                // Parallel Task 1: Initialize MLX (Apple Silicon only)
                if aiConfiguration.framework == .mlx {
                    group.addTask { [weak self] in
                        guard let self = self else { return }
                        do {
                            self.updateStatus("Initializing MLX framework...")
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
                        self.updateStatus("Setting up privacy protection...")
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
            
            // Setup bindings now that everything is initialized
            Task { @MainActor in
                self.setupBindings()
            }
            
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
                    let fullResponseBox = Box("")
                    
                    for try await chunk in stream {
                        fullResponseBox.value += chunk
                        fullResponse = fullResponseBox.value
                        
                        // Update UI streaming text
                        await MainActor.run {
                            streamingText = fullResponseBox.value
                        }
                        
                        continuation.yield(chunk)
                    }
                    
                    // FIX: Update the empty message with the final streamed content
                    conversationHistory.updateMessage(id: aiMessage.id, newContent: fullResponse)
                    
                    // Clear unified animation state when done
                    await MainActor.run {
                        animationState = .idle
                        streamingText = ""
                        // Ensure processing flag resets so UI updates status correctly
                        self.isProcessing = false
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
    
    /// Generate TL;DR summary of current page content without affecting conversation history
    func generatePageTLDR() async throws -> String {
        guard await isInitialized else {
            throw AIError.notInitialized
        }
        
        // CONCURRENCY SAFETY: Check if AI is already processing to avoid conflicts
        let currentlyProcessing = await MainActor.run { isProcessing }
        guard !currentlyProcessing else {
            throw AIError.inferenceError("AI is currently busy with another task")
        }
        
        // MEMORY SAFETY: Check if AI operations are safe to perform
        guard memoryMonitor.isAISafeToRun() else {
            let memoryStatus = memoryMonitor.getCurrentMemoryStatus()
            throw AIError.memoryPressure("AI operations suspended due to \(memoryStatus.pressureLevel.rawValue.lowercased()) memory pressure (\(String(format: "%.1f", memoryStatus.availableMemory))GB available)")
        }
        
        // Extract context from current webpage
        let webpageContext = await extractCurrentContext()
        guard let context = webpageContext, !context.text.isEmpty else {
            throw AIError.contextProcessingFailed("No content available to summarize")
        }
        
        // Create clean, direct TL;DR prompt with sentiment analysis
        let tldrPrompt = """
        Analyze the following webpage **without returning any HTML or code** and reply ONLY with:
        1. A single sentiment emoji that best represents the overall content (📰 news, 🔬 tech, 💼 business, 🎬 entertainment, ⚠️ controversial, 😊 positive, 😐 neutral, 😟 negative)
        2. Two-to-three concise bullet points (max 30 words each) describing the key take-aways.

        Output **format** (plain text):
        [EMOJI]\n• point 1\n• point 2\n• point 3 (optional)

        Title: \(context.title)
        Content: \(context.text.prefix(1500))
        """

        do {
            // Use RAW prompt generation to avoid chat template noise
            let cleanResponse = try await gemmaService.generateRawResponse(prompt: tldrPrompt).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // VALIDATION: Check for repetitive or broken output
            if isInvalidTLDRResponse(cleanResponse) {
                NSLog("⚠️ Invalid TL;DR response detected, retrying with simplified prompt")
                
                // Fallback with simpler prompt
                let fallbackPrompt = "Summarize this webpage in 2-3 bullet points (plain text, no HTML):\n\n\(context.title)\n\(context.text.prefix(800))"
                let fallbackClean = try await gemmaService.generateRawResponse(prompt: fallbackPrompt).trimmingCharacters(in: .whitespacesAndNewlines)

                // If fallback is still invalid, attempt a final post-processing pass that collapses
                // repeated phrases to salvage the summary before giving up.
                if isInvalidTLDRResponse(fallbackClean) {
                    let salvaged = gemmaService.postProcessForTLDR(fallbackClean)
                    return isInvalidTLDRResponse(salvaged) ? "Unable to generate summary" : salvaged
                }

                return fallbackClean
            }
            
            return cleanResponse

        } catch {
            NSLog("❌ TL;DR generation failed: \(error)")
            throw AIError.inferenceError("Failed to generate TL;DR: \(error.localizedDescription)")
        }
    }
    
    /// Check if TL;DR response contains repetitive or invalid patterns
    private func isInvalidTLDRResponse(_ response: String) -> Bool {
        let lowercased = response.lowercased()
        
        // Check for repetitive patterns that indicate model confusion
        let badPatterns = [
            "understand",
            "i'll help",
            "please provide",
            "let me know",
            "what can i do"
        ]
        
        // If response is too short or contains too many repetitive words
        if response.count < 20 {
            return true
        }
        
        // Detect obvious HTML or code fragments which indicate a bad summary
        if lowercased.contains("<html") || lowercased.contains("<div") || lowercased.contains("<span") {
            return true
        }

        // Detect repeated adjacent words (e.g. "it it", "you you") which are a signal
        // of token duplication errors during generation.
        if lowercased.range(of: "\\b(\\w+)(\\s+\\1)+\\b", options: .regularExpression) != nil {
            return true
        }

        // NEW: Detect **phrase**-level repetition where a 3-6-word chunk is repeated
        // three or more times consecutively (e.g. "The provided text" pattern).
        // This catches progressive prefix repetition that isn't matched by the
        // simple duplicate-word regex above.
        do {
            let phrasePattern = "(\\b(?:\\w+\\s+){2,5}\\w+\\b)(?:\\s+\\1){2,}"
            if lowercased.range(of: phrasePattern, options: [.regularExpression]) != nil {
                return true
            }
        }
        catch {
            NSLog("⚠️ Regex error in phrase repetition detection: \(error)")
        }

        // Check for excessive repetition of bad patterns
        for pattern in badPatterns {
            let occurrences = lowercased.components(separatedBy: pattern).count - 1
            if occurrences > 2 {
                return true
            }
        }
        
        return false
    }
    
    /// Clear conversation history and context
    func clearConversation() {
        conversationHistory.clear()
        
        // OPTIMIZATION: Also reset MLXRunner conversation state
        Task {
            await SimplifiedMLXRunner.shared.resetConversation()
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
    
    @MainActor
    private func setupBindings() {
        // Bind conversation history changes - SwiftUI automatically handles UI updates for @Published properties
        conversationHistory.$messageCount
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // SwiftUI automatically triggers UI updates when @Published properties change
                // Removed manual objectWillChange.send() to prevent unnecessary re-renders
            }
            .store(in: &cancellables)
        
        // Bind MLX model status  
        mlxModelService.$isModelReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                Task { @MainActor [weak self] in
                    if !isReady && self?.isInitialized == true {
                        self?.isInitialized = false
                    }
                }
                if !isReady {
                    self?.updateStatus("MLX AI model not available")
                }
            }
            .store(in: &cancellables)
        
        // Bind download progress for status updates
        mlxModelService.$downloadProgress
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] progress in
                if progress > 0 && progress < 1.0 {
                    NSLog("🎯 MLX DOWNLOAD DEBUG: Model download progress: \(progress * 100)% - updating status")
                    self?.updateStatus("Downloading MLX AI model: \(Int(progress * 100))%")
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