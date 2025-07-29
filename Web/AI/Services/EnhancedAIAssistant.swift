import Foundation
import Combine

/// Enhanced AI Assistant coordinator supporting multiple providers (local MLX + external APIs)
/// Provides unified interface for both local and external AI services with BYOK support
@MainActor
class EnhancedAIAssistant: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isInitialized: Bool = false
    @Published var isProcessing: Bool = false
    @Published var initializationStatus: String = "Not initialized"
    @Published var lastError: String?
    
    // UNIFIED ANIMATION STATE - prevents conflicts between typing/streaming indicators
    @Published var animationState: AIAnimationState = .idle
    @Published var streamingText: String = ""
    
    // MARK: - Dependencies
    
    private let providerManager = AIProviderManager.shared
    private let conversationHistory: ConversationHistory
    private let contextManager: ContextManager
    private let memoryMonitor: SystemMemoryMonitor
    private weak var tabManager: TabManager?
    
    // MARK: - Configuration
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(tabManager: TabManager? = nil) {
        self.conversationHistory = ConversationHistory()
        self.contextManager = ContextManager.shared
        self.memoryMonitor = SystemMemoryMonitor.shared
        self.tabManager = tabManager
        
        setupBindings()
        
        NSLog("🤖 Enhanced AI Assistant initialized with provider management")
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
    
    /// Get current AI provider information
    var currentProvider: AIProvider? {
        providerManager.currentProvider
    }
    
    /// Get available providers
    var availableProviders: [AIProvider] {
        providerManager.availableProviders
    }
    
    /// Initialize the AI system with current provider
    func initialize() async {
        updateStatus("Initializing AI system...")
        
        guard let currentProvider = providerManager.currentProvider else {
            updateStatus("No AI provider selected")
            await MainActor.run {
                lastError = "No AI provider configured"
                isInitialized = false
            }
            return
        }
        
        do {
            updateStatus("Initializing \(currentProvider.displayName)...")
            
            // Initialize the current provider
            try await currentProvider.initialize()
            
            // Verify provider is ready
            guard await currentProvider.isReady() else {
                throw AIProviderError.invalidConfiguration("\(currentProvider.displayName) is not ready")
            }
            
            await MainActor.run {
                isInitialized = true
                lastError = nil
            }
            updateStatus("AI Assistant ready with \(currentProvider.displayName)")
            
            NSLog("✅ Enhanced AI Assistant initialization completed with \(currentProvider.displayName)")
            
        } catch {
            let errorMessage = "AI initialization failed: \(error.localizedDescription)"
            updateStatus("Initialization failed")
            await MainActor.run {
                lastError = errorMessage
                isInitialized = false
            }
            
            NSLog("❌ \(errorMessage)")
        }
    }
    
    /// Switch to a different AI provider
    func switchProvider(to provider: AIProvider) async throws {
        updateStatus("Switching to \(provider.displayName)...")
        
        try await providerManager.switchProvider(to: provider)
        
        // Re-initialize with new provider
        await initialize()
    }
    
    /// Process a user query with current provider
    func processQuery(_ query: String, includeContext: Bool = true, includeHistory: Bool = true) async throws -> AIResponse {
        guard let currentProvider = providerManager.currentProvider else {
            throw AIProviderError.invalidConfiguration("No AI provider selected")
        }
        
        guard await isInitialized else {
            throw AIProviderError.invalidConfiguration("AI Assistant not initialized")
        }
        
        NSLog("💬 AI Chat: Processing query with \(currentProvider.displayName)")
        
        // MEMORY SAFETY: Check if AI operations are safe to perform
        guard memoryMonitor.isAISafeToRun() else {
            let memoryStatus = memoryMonitor.getCurrentMemoryStatus()
            throw AIProviderError.providerSpecificError("AI operations suspended due to \(memoryStatus.pressureLevel.rawValue.lowercased()) memory pressure")
        }
        
        await MainActor.run { isProcessing = true }
        defer { Task { @MainActor in isProcessing = false } }
        
        do {
            // Extract context from current webpage
            let webpageContext = await extractCurrentContext()
            let context = includeContext ? await contextManager.getFormattedContext(from: webpageContext, includeHistory: includeHistory) : nil
            
            // Create conversation entry
            let userMessage = ConversationMessage(
                role: .user,
                content: query,
                timestamp: Date(),
                contextData: context
            )
            
            // Add to conversation history
            conversationHistory.addMessage(userMessage)
            
            // Process with current provider
            let response = try await currentProvider.generateResponse(
                query: query,
                context: context,
                conversationHistory: conversationHistory.getRecentMessages(limit: 10),
                model: currentProvider.selectedModel
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
            
            return response
            
        } catch {
            NSLog("❌ Query processing failed with \(currentProvider.displayName): \(error)")
            await handleAIError(error)
            throw error
        }
    }
    
    /// Process a streaming query with current provider
    func processStreamingQuery(_ query: String, includeContext: Bool = true, includeHistory: Bool = true) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let currentProvider = providerManager.currentProvider else {
                        throw AIProviderError.invalidConfiguration("No AI provider selected")
                    }
                    
                    guard await isInitialized else {
                        throw AIProviderError.invalidConfiguration("AI Assistant not initialized")
                    }
                    
                    await MainActor.run { isProcessing = true }
                    defer { Task { @MainActor in isProcessing = false } }
                    
                    // Extract context from current webpage
                    let webpageContext = await self.extractCurrentContext()
                    let context = await self.contextManager.getFormattedContext(from: webpageContext, includeHistory: includeHistory && includeContext)
                    
                    // Add user message
                    let userMessage = ConversationMessage(
                        role: .user,
                        content: query,
                        timestamp: Date(),
                        contextData: context
                    )
                    conversationHistory.addMessage(userMessage)
                    
                    // Add empty AI message for streaming updates
                    let aiMessage = ConversationMessage(
                        role: .assistant,
                        content: "",
                        timestamp: Date()
                    )
                    conversationHistory.addMessage(aiMessage)
                    
                    // Set up streaming animation state
                    await MainActor.run {
                        animationState = .streaming(messageId: aiMessage.id)
                        streamingText = ""
                    }
                    
                    // Process with streaming
                    let stream = try await currentProvider.generateStreamingResponse(
                        query: query,
                        context: context,
                        conversationHistory: conversationHistory.getRecentMessages(limit: 10),
                        model: currentProvider.selectedModel
                    )
                    
                    var fullResponse = ""
                    
                    for try await chunk in stream {
                        fullResponse += chunk
                        
                        // Update UI streaming text
                        await MainActor.run {
                            streamingText = fullResponse
                        }
                        
                        continuation.yield(chunk)
                    }
                    
                    // Update the empty message with final content
                    conversationHistory.updateMessage(id: aiMessage.id, newContent: fullResponse)
                    
                    // Clear animation state
                    await MainActor.run {
                        animationState = .idle
                        streamingText = ""
                        isProcessing = false
                    }
                    
                    continuation.finish()
                    
                } catch {
                    NSLog("❌ Streaming error occurred: \(error)")
                    
                    // Clear animation state on error
                    await MainActor.run {
                        animationState = .idle
                        streamingText = ""
                    }
                    
                    await self.handleAIError(error)
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Generate TL;DR summary of current page content
    func generatePageTLDR() async throws -> String {
        guard let currentProvider = providerManager.currentProvider else {
            throw AIProviderError.invalidConfiguration("No AI provider selected")
        }
        
        guard await isInitialized else {
            throw AIProviderError.invalidConfiguration("AI Assistant not initialized")
        }
        
        // Extract context from current webpage
        let webpageContext = await extractCurrentContext()
        guard let context = webpageContext, !context.text.isEmpty else {
            throw AIProviderError.providerSpecificError("No content available to summarize")
        }
        
        // Create TL;DR prompt
        let tldrPrompt = """
        Summarize this webpage in 3 bullet points:

        Title: \(context.title)
        Content: \(context.text.prefix(2000))

        Format:
        • point 1
        • point 2  
        • point 3
        """
        
        return try await currentProvider.generateRawResponse(
            prompt: tldrPrompt,
            model: currentProvider.selectedModel
        )
    }
    
    /// Generate streaming TL;DR summary
    func generatePageTLDRStreaming() -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let tldr = try await generatePageTLDR()
                    continuation.yield(tldr)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Get conversation summary for the current session
    func getConversationSummary() async throws -> String {
        guard let currentProvider = providerManager.currentProvider else {
            throw AIProviderError.invalidConfiguration("No AI provider selected")
        }
        
        let messages = conversationHistory.getRecentMessages(limit: 20)
        return try await currentProvider.summarizeConversation(
            messages,
            model: currentProvider.selectedModel
        )
    }
    
    /// Clear conversation history and reset state
    func clearConversation() {
        conversationHistory.clear()
        
        Task {
            await providerManager.currentProvider?.resetConversation()
        }
        
        NSLog("🗑️ Conversation cleared")
    }
    
    /// Reset AI conversation state to recover from errors
    func resetConversationState() async {
        conversationHistory.clear()
        
        await providerManager.currentProvider?.resetConversation()
        
        await MainActor.run {
            lastError = nil
            isProcessing = false
        }
        
        NSLog("🔄 AI conversation state fully reset")
    }
    
    /// Check if AI system is in a healthy state
    func performHealthCheck() async -> Bool {
        guard let currentProvider = providerManager.currentProvider else {
            return false
        }
        
        do {
            let testQuery = "Hello"
            let _ = try await processQuery(testQuery, includeContext: false)
            return true
        } catch {
            NSLog("⚠️ AI Health check failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Get current system status including provider information
    func getSystemStatus() -> EnhancedAISystemStatus {
        let currentProvider = providerManager.currentProvider
        let stats = currentProvider?.getUsageStatistics()
        
        return EnhancedAISystemStatus(
            isInitialized: isInitialized,
            currentProvider: currentProvider?.displayName ?? "None",
            providerType: currentProvider?.providerType.displayName ?? "Unknown",
            availableProviders: providerManager.availableProviders.map { $0.displayName },
            conversationLength: conversationHistory.messageCount,
            usageStats: stats
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
    
    private func handleAIError(_ error: Error) async {
        let errorMessage = error.localizedDescription
        NSLog("❌ AI Error occurred: \(errorMessage)")
        
        await MainActor.run {
            lastError = errorMessage
            isProcessing = false
        }
    }
    
    private func setupBindings() {
        // Bind conversation history changes
        conversationHistory.$messageCount
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // SwiftUI automatically triggers UI updates for @Published properties
            }
            .store(in: &cancellables)
        
        // Bind provider manager changes
        providerManager.$currentProvider
            .receive(on: DispatchQueue.main)
            .sink { [weak self] provider in
                if let provider = provider {
                    self?.updateStatus("Switched to \(provider.displayName)")
                    // Re-initialize when provider changes
                    Task { @MainActor [weak self] in
                        await self?.initialize()
                    }
                }
            }
            .store(in: &cancellables)
        
        providerManager.$isInitializing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isInitializing in
                if isInitializing {
                    self?.updateStatus("Switching AI provider...")
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateStatus(_ status: String) {
        Task { @MainActor in
            initializationStatus = status
        }
        NSLog("🤖 Enhanced AI Status: \(status)")
    }
}

// MARK: - Enhanced System Status

/// Enhanced AI system status including provider information
struct EnhancedAISystemStatus {
    let isInitialized: Bool
    let currentProvider: String
    let providerType: String
    let availableProviders: [String]
    let conversationLength: Int
    let usageStats: AIUsageStatistics?
}