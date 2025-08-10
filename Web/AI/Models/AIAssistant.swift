import Combine
import Foundation

/// Main AI Assistant coordinator managing local AI capabilities
/// Integrates MLX framework with context management and conversation handling
@MainActor
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
    private let providerManager = AIProviderManager.shared

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
        await updateStatus("Initializing AI system...")

        do {
            // Branch initialization by current provider type
            guard let provider = providerManager.currentProvider else {
                throw AIError.inferenceError("No AI provider available")
            }

            if provider.providerType == .local {
                // Preserve existing detailed MLX initialization for local models
                await updateStatus("Validating hardware compatibility...")
                try validateHardware()

                await updateStatus("Checking MLX AI model availability...")
                if !(await mlxModelService.isAIReady()) {
                    await updateStatus("MLX AI model not found - preparing download...")
                    let downloadInfo = await mlxModelService.getDownloadInfo()
                    NSLog("🔽 MLX AI model needs to be downloaded: \(downloadInfo.formattedSize)")
                    try await mlxModelService.initializeAI()
                }

                await updateStatus("Loading MLX AI model...")
                while !(await mlxModelService.isAIReady()) {
                    if case .failed(let error) = mlxModelService.downloadState {
                        throw MLXModelError.downloadFailed("MLX model download failed: \(error)")
                    }
                    let progress = mlxModelService.downloadProgress
                    if progress > 0 {
                        await updateStatus("Loading MLX AI model... (\(Int(progress * 100)))")
                    } else {
                        await updateStatus("Loading MLX AI model...")
                    }
                    try await Task.sleep(nanoseconds: 500_000_000)
                }

                // Initialize frameworks and services required for local
                await withTaskGroup(of: Void.self) { group in
                    if aiConfiguration.framework == .mlx {
                        group.addTask { [weak self] in
                            guard let self else { return }
                            do {
                                await self.updateStatus("Initializing MLX framework...")
                                try await self.mlxWrapper.initialize()
                            } catch {
                                NSLog("❌ MLX initialization failed: \(error)")
                            }
                        }
                    }
                    group.addTask { [weak self] in
                        guard let self else { return }
                        do {
                            await self.updateStatus("Setting up privacy protection...")
                            try await self.privacyManager.initialize()
                        } catch {
                            NSLog("❌ Privacy manager initialization failed: \(error)")
                        }
                    }
                }

                await updateStatus("Starting AI inference engine...")
                try await gemmaService.initialize()
            } else {
                // External provider (BYOK): let provider handle its own initialization
                await updateStatus("Initializing \(provider.displayName)...")
                try await provider.initialize()
            }

            // Observe provider changes to reinitialize when switching
            setupProviderBindingsOnce()

            Task { @MainActor in
                isInitialized = true
                lastError = nil
            }
            await updateStatus("AI Assistant ready")
            NSLog("✅ AI Assistant initialization completed successfully (OPTIMIZED)")

        } catch {
            let errorMessage = "AI initialization failed: \(error.localizedDescription)"
            await updateStatus("Initialization failed")
            Task { @MainActor in
                lastError = errorMessage
                isInitialized = false
            }
            NSLog("❌ \(errorMessage)")
        }
    }

    /// Process a user query with current context and optional history
    func processQuery(_ query: String, includeContext: Bool = true, includeHistory: Bool = true)
        async throws -> AIResponse
    {
        guard await isInitialized else {
            throw AIError.notInitialized
        }

        NSLog(
            "💬 AI Chat: Processing query '\(query.prefix(100))...' (includeContext: \(includeContext))"
        )

        // MEMORY SAFETY: Check if AI operations are safe to perform
        guard memoryMonitor.isAISafeToRun() else {
            let memoryStatus = memoryMonitor.getCurrentMemoryStatus()
            throw AIError.memoryPressure(
                "AI operations suspended due to \(memoryStatus.pressureLevel.rawValue.lowercased()) memory pressure (\(String(format: "%.1f", memoryStatus.availableMemory))GB available)"
            )
        }

        Task { @MainActor in isProcessing = true }
        defer { Task { @MainActor in isProcessing = false } }

        do {
            // Extract context from current webpage with optional history
            let webpageContext = await extractCurrentContext()
            if let webpageContext = webpageContext {
                NSLog(
                    "💬 AI Chat: Extracted webpage context: \(webpageContext.text.count) chars, quality: \(webpageContext.contentQuality)"
                )
                if includeContext && isContentTooGarbled(webpageContext.text) {
                    NSLog("💬 AI Chat: Content detected as garbage, using title-only context")
                }
            } else {
                NSLog("💬 AI Chat: No webpage context extracted")
            }

            let context =
                includeContext
                ? await contextManager.getFormattedContext(
                    from: webpageContext, includeHistory: includeHistory) : nil
            if let context = context {
                NSLog("💬 AI Chat: Using formatted context: \(context.count) characters")
            } else {
                NSLog("💬 AI Chat: No context provided to model")
            }

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
            guard let provider = providerManager.currentProvider else {
                throw AIError.inferenceError("No AI provider available")
            }
            let response = try await provider.generateResponse(
                query: query,
                context: context,
                conversationHistory: conversationHistory.getRecentMessages(limit: 10),
                model: provider.selectedModel
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
    func processStreamingQuery(
        _ query: String, includeContext: Bool = true, includeHistory: Bool = true
    ) -> AsyncThrowingStream<String, Error> {
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
                    if let webpageContext = webpageContext {
                        NSLog(
                            "🔍 AIAssistant streaming extracted webpage context: \(webpageContext.text.count) chars, quality: \(webpageContext.contentQuality)"
                        )
                    } else {
                        NSLog("⚠️ AIAssistant streaming: No webpage context extracted")
                    }

                    let context = await self.contextManager.getFormattedContext(
                        from: webpageContext, includeHistory: includeHistory && includeContext)
                    if let context = context {
                        NSLog(
                            "🔍 AIAssistant streaming formatted context: \(context.count) characters"
                        )
                    } else {
                        NSLog("⚠️ AIAssistant streaming: No formatted context returned")
                    }

                    // Process with current provider
                    guard let provider = providerManager.currentProvider else {
                        throw AIError.inferenceError("No AI provider available")
                    }
                    let stream = try await provider.generateStreamingResponse(
                        query: query,
                        context: context,
                        conversationHistory: conversationHistory.getRecentMessages(limit: 10),
                        model: provider.selectedModel
                    )

                    // Add user message first
                    let userMessage = ConversationMessage(
                        role: .user,
                        content: query,
                        timestamp: Date(),
                        contextData: context
                    )
                    conversationHistory.addMessage(userMessage)

                    // CRITICAL FIX: Add empty AI message for UI streaming but will be updated
                    let aiMessage = ConversationMessage(
                        role: .assistant,
                        content: "",  // Start empty for streaming
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

                    // Update the empty message with the final streamed content
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
                            newContent:
                                "Sorry, there was an error generating the response: \(error.localizedDescription)"
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
        guard let provider = providerManager.currentProvider else {
            throw AIError.inferenceError("No AI provider available")
        }
        return try await provider.summarizeConversation(messages, model: provider.selectedModel)
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
            throw AIError.memoryPressure(
                "AI operations suspended due to \(memoryStatus.pressureLevel.rawValue.lowercased()) memory pressure (\(String(format: "%.1f", memoryStatus.availableMemory))GB available)"
            )
        }

        // Extract context from current webpage
        let webpageContext = await extractCurrentContext()
        guard let context = webpageContext, !context.text.isEmpty else {
            NSLog(
                "⚠️ TL;DR: No context available - webpageContext: \(webpageContext != nil ? "exists but empty" : "nil")"
            )
            throw AIError.contextProcessingFailed("No content available to summarize")
        }

        // Check for low-quality content that would confuse the model
        if isContentTooGarbled(context.text) {
            NSLog(
                "⚠️ TL;DR: Content appears to be garbled JavaScript/HTML, attempting simplified extraction"
            )
            return
                "📄 Page content detected but contains mostly code/markup. Unable to generate meaningful summary."
        }

        NSLog(
            "🔍 TL;DR: Using context with \(context.text.count) characters, quality: \(context.contentQuality)"
        )

        // Create clean, direct TL;DR prompt - simplified for better model performance
        let cleanedContent = cleanContentForTLDR(context.text)
        let tldrPrompt = """
            Summarize this webpage in 3 bullet points:

            Title: \(context.title)
            Content: \(cleanedContent)

            Format:
            • point 1
            • point 2  
            • point 3
            """

        do {
            // Use current provider RAW prompt generation to avoid chat template noise
            guard let provider = providerManager.currentProvider else {
                throw AIError.inferenceError("No AI provider available")
            }
            let cleanResponse = try await provider.generateRawResponse(
                prompt: tldrPrompt, model: provider.selectedModel
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            // VALIDATION: Check for repetitive or broken output
            if isInvalidTLDRResponse(cleanResponse) {
                NSLog("⚠️ Invalid TL;DR response detected, retrying with simplified prompt")

                // Fallback with simpler prompt
                let simplifiedContent = cleanContentForTLDR(context.text)
                let fallbackPrompt =
                    "Summarize this webpage in 2-3 bullet points:\n\nTitle: \(context.title)\nContent: \(simplifiedContent)"
                let fallbackClean = try await provider.generateRawResponse(
                    prompt: fallbackPrompt, model: provider.selectedModel
                ).trimmingCharacters(in: .whitespacesAndNewlines)

                // If fallback is still invalid, attempt a final post-processing pass that collapses
                // repeated phrases to salvage the summary before giving up.
                if isInvalidTLDRResponse(fallbackClean) {
                    NSLog("⚠️ Fallback response also invalid, attempting post-processing")
                    let salvaged = gemmaService.postProcessForTLDR(fallbackClean)
                    if isInvalidTLDRResponse(salvaged) {
                        NSLog("❌ All TL;DR generation attempts failed")
                        // IMPROVED: Give a more informative message instead of generic error
                        return
                            "📄 Page content detected but summary generation encountered issues. Try refreshing the page."
                    }
                    return salvaged
                }

                return fallbackClean
            } else {
                NSLog("✅ TL;DR generation successful on first attempt")
            }

            return cleanResponse

        } catch {
            NSLog("❌ TL;DR generation failed: \(error)")
            throw AIError.inferenceError("Failed to generate TL;DR: \(error.localizedDescription)")
        }
    }

    /// Generate TL;DR summary of current page content with streaming support
    /// This provides real-time feedback like chat messages for better UX
    func generatePageTLDRStreaming() -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
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
                        throw AIError.memoryPressure(
                            "AI operations suspended due to \(memoryStatus.pressureLevel.rawValue.lowercased()) memory pressure (\(String(format: "%.1f", memoryStatus.availableMemory))GB available)"
                        )
                    }

                    // Extract context from current webpage
                    let webpageContext = await extractCurrentContext()
                    guard let context = webpageContext, !context.text.isEmpty else {
                        NSLog(
                            "⚠️ TL;DR Streaming: No context available - webpageContext: \(webpageContext != nil ? "exists but empty" : "nil")"
                        )
                        throw AIError.contextProcessingFailed("No content available to summarize")
                    }

                    NSLog(
                        "🌊 TL;DR Streaming: Using context with \(context.text.count) characters, quality: \(context.contentQuality)"
                    )

                    // Create clean, direct TL;DR prompt - simplified for better streaming performance
                    let cleanedContent = cleanContentForTLDR(context.text)
                    let tldrPrompt = """
                        Summarize this webpage in 3 bullet points:

                        Title: \(context.title)
                        Content: \(cleanedContent)

                        Format:
                        • point 1
                        • point 2  
                        • point 3
                        """

                    // Log full TLDR prompt for debugging
                    NSLog("📜 FULL TLDR PROMPT FOR DEBUGGING:\n\(tldrPrompt)")

                    // Use current provider streaming response with post-processing for TL;DR
                    guard let provider = providerManager.currentProvider else {
                        throw AIError.inferenceError("No AI provider available")
                    }
                    let stream = try await provider.generateStreamingResponse(
                        query: tldrPrompt,
                        context: nil,
                        conversationHistory: [],
                        model: provider.selectedModel
                    )

                    var accumulatedResponse = ""
                    var hasYieldedContent = false

                    // Stream the response with real-time updates
                    for try await chunk in stream {
                        accumulatedResponse += chunk
                        hasYieldedContent = true

                        // Yield each chunk for real-time display
                        continuation.yield(chunk)
                    }

                    // Post-process the final accumulated response
                    let finalResponse = accumulatedResponse.trimmingCharacters(
                        in: .whitespacesAndNewlines)

                    // If we got a response but it's invalid, try to salvage it
                    if !finalResponse.isEmpty && isInvalidTLDRResponse(finalResponse) {
                        NSLog("⚠️ TL;DR Streaming: Invalid response detected, post-processing...")
                        let salvaged = gemmaService.postProcessForTLDR(finalResponse)

                        if !isInvalidTLDRResponse(salvaged) && salvaged != finalResponse {
                            // Send the difference as a correction
                            let correction = salvaged.replacingOccurrences(
                                of: finalResponse, with: "")
                            if !correction.isEmpty {
                                continuation.yield(correction)
                            }
                        }
                    }

                    // If no content was streamed, provide a helpful fallback
                    if !hasYieldedContent {
                        NSLog("⚠️ TL;DR Streaming: No content streamed, providing fallback")
                        continuation.yield(
                            "📄 Page content detected but summary generation is processing...")
                    }

                    continuation.finish()
                    NSLog("✅ TL;DR Streaming completed: \(accumulatedResponse.count) characters")

                } catch {
                    NSLog("❌ TL;DR Streaming failed: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Check if content is too garbled with JavaScript/HTML to be useful
    private func isContentTooGarbled(_ content: String) -> Bool {
        let lowercased = content.lowercased()
        let totalLength = content.count

        NSLog("🔍 Garbage detection for content (\(totalLength) chars): '\(content.prefix(100))...'")

        // Check for high ratio of JavaScript/HTML artifacts - be more aggressive
        let jsPatterns = [
            "function", "var ", "let ", "const ", "document.", "window.", "console.",
            ".js", "(){", "});", "@keyframes", "html[", "div>", "span>",
            "}.}", "@media", "Date()", "google=", "window=", "getElementById",
            "innerHTML", "addEventListener", "querySelector", "textContent",
        ]

        var jsCount = 0
        var detectedPatterns: [String] = []

        for pattern in jsPatterns {
            let count = lowercased.components(separatedBy: pattern).count - 1
            if count > 0 {
                jsCount += count
                detectedPatterns.append("\(pattern)(\(count))")
            }
        }

        // Also check for excessive punctuation that indicates code
        let punctuationChars = content.filter { "{}();.,=[]".contains($0) }
        let punctuationRatio = Double(punctuationChars.count) / Double(max(totalLength, 1))

        // Check for lack of readable words
        let words = content.components(separatedBy: .whitespacesAndNewlines)
            .filter { word in
                let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
                return trimmed.count >= 3 && trimmed.rangeOfCharacter(from: .letters) != nil
            }
        let readableWordsRatio = Double(words.count * 5) / Double(max(totalLength, 1))  // Avg word length

        let jsRatio = Double(jsCount * 8) / Double(max(totalLength, 1))  // Multiply by avg pattern length

        // More aggressive thresholds
        let isGarbage =
            jsRatio > 0.08  // Reduced from 0.15 to 0.08
            || punctuationRatio > 0.3 || readableWordsRatio < 0.2 || totalLength < 50  // Reduced from 100

        NSLog("🔍 Garbage analysis:")
        NSLog("   - JS patterns detected: \(detectedPatterns.joined(separator: ", "))")
        NSLog("   - JS ratio: \(jsRatio) (threshold: 0.08)")
        NSLog("   - Punctuation ratio: \(punctuationRatio) (threshold: 0.3)")
        NSLog("   - Readable words ratio: \(readableWordsRatio) (threshold: 0.2)")
        NSLog("   - Length: \(totalLength) (min: 50)")
        NSLog("   - Is garbage: \(isGarbage)")

        return isGarbage
    }

    /// Clean and prepare content specifically for TLDR generation
    private func cleanContentForTLDR(_ content: String) -> String {
        var cleaned = content

        NSLog("🧹 Content cleaning input: '\(content.prefix(200))...' (\(content.count) chars)")

        // AGGRESSIVE cleaning for the specific garbage we're seeing
        let aggressivePatterns = [
            // Remove the specific garbage patterns we see in logs
            ("\\}\\.[\\}\\w]+", ""),  // }.} patterns
            ("html\\[dir='[^']*'\\]", ""),  // html[dir='rtl']
            ("@keyframes[^\\s]*", ""),  // @keyframes
            ("\\(\\)[\\;\\)\\{\\}]*", ""),  // ()(); patterns
            ("document\\([^\\)]*\\)", ""),  // document() calls
            ("Date\\(\\)[\\;\\}]*", ""),  // Date(); patterns
            ("@media[^\\}]*\\}", ""),  // CSS @media rules
            ("\\{[^\\}]*\\}", ""),  // Any remaining {...} blocks
            ("\\([^\\)]*\\)\\s*\\{", ""),  // function() { patterns
            ("var\\s+[^\\;\\s]*", ""),  // var declarations
            ("function\\s*[^\\{]*\\{", ""),  // function declarations
            ("window\\s*=\\s*[^\\;]*", ""),  // window assignments
            ("google\\s*=\\s*[^\\;]*", ""),  // google assignments
            ("[\\w]+\\[\\w+\\]\\s*=", ""),  // array/object assignments
            ("\\s*;\\s*", " "),  // semicolons
            ("\\s*,\\s*", " "),  // commas
            ("\\&[a-zA-Z]+;", ""),  // HTML entities
            ("<[^>]*>", ""),  // HTML tags - CRITICAL FIX
            ("trackPageView\\(\\)", ""),  // tracking functions
        ]

        var removedCount = 0
        for (pattern, replacement) in aggressivePatterns {
            let before = cleaned.count
            cleaned = cleaned.replacingOccurrences(
                of: pattern, with: replacement, options: .regularExpression)
            let removed = before - cleaned.count
            if removed > 0 {
                removedCount += removed
                NSLog("🧹 Pattern '\(pattern)' removed \(removed) chars")
            }
        }

        NSLog("🧹 Total aggressive cleaning removed: \(removedCount) characters")

        // Clean up multiple spaces and normalize
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Filter to actual readable words only
        let words = cleaned.components(separatedBy: .whitespacesAndNewlines)
            .filter { word in
                let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
                // Keep words that are mostly letters and at least 2 chars
                return trimmed.count >= 2 && trimmed.rangeOfCharacter(from: .letters) != nil
                    && !trimmed.contains("{") && !trimmed.contains("}") && !trimmed.contains("(")
                    && !trimmed.contains(")") && !trimmed.contains("=") && !trimmed.contains(";")
            }

        cleaned = words.joined(separator: " ")

        NSLog("🧹 After word filtering: '\(cleaned.prefix(200))...' (\(cleaned.count) chars)")

        // Limit length for better model performance
        if cleaned.count > 600 {  // Reduced from 800 for better performance
            cleaned = String(cleaned.prefix(600))
            NSLog("🧹 Truncated to 600 characters")
        }

        NSLog("🧹 Final cleaned content: '\(cleaned.prefix(100))...' (\(cleaned.count) chars)")
        return cleaned
    }

    /// Check if TL;DR response contains repetitive or invalid patterns
    private func isInvalidTLDRResponse(_ response: String) -> Bool {
        let lowercased = response.lowercased()

        NSLog(
            "🔍 TLDR Validation: Checking response (\(response.count) chars): '\(response.prefix(100))...'"
        )

        // Check for repetitive patterns that indicate model confusion
        let badPatterns = [
            "understand",
            "i'll help",
            "please provide",
            "let me know",
            "what can i do",
        ]

        // If response is too short (but allow shorter responses)
        if response.count < 5 {
            NSLog("⚠️ TLDR Validation: Response too short (\(response.count) chars)")
            return true
        }

        // Detect obvious HTML or code fragments which indicate a bad summary
        if lowercased.contains("<html") || lowercased.contains("<div")
            || lowercased.contains("<span")
        {
            return true
        }

        // IMPROVED: Only flag as invalid if there are MANY repeated adjacent words
        // Allow some repetition but catch excessive cases
        let wordRepetitionPattern = "\\b(\\w+)(\\s+\\1){3,}\\b"  // 4+ repetitions instead of 2+
        if lowercased.range(of: wordRepetitionPattern, options: .regularExpression) != nil {
            NSLog("⚠️ TL;DR rejected due to excessive word repetition")
            return true
        }

        // IMPROVED: Only flag phrase repetition if it's very excessive (5+ times instead of 3+)
        // This allows some natural repetition while catching obvious loops
        let phrasePattern = "(\\b(?:\\w+\\s+){2,5}\\w+\\b)(?:\\s+\\1){4,}"  // 5+ repetitions instead of 3+
        if lowercased.range(of: phrasePattern, options: [.regularExpression]) != nil {
            NSLog("⚠️ TL;DR rejected due to excessive phrase repetition")
            return true
        }

        // NEW: Check if response is ONLY repetitive content (more than 80% repetitive)
        let words = lowercased.components(separatedBy: .whitespacesAndNewlines).filter {
            !$0.isEmpty
        }
        if words.count > 5 {
            let uniqueWords = Set(words)
            let repetitionRatio = Double(words.count - uniqueWords.count) / Double(words.count)
            if repetitionRatio > 0.8 {
                NSLog("⚠️ TL;DR rejected due to high repetition ratio: \(repetitionRatio)")
                return true
            }
        }

        // Check for excessive repetition of bad patterns (only if multiple patterns present)
        var badPatternCount = 0
        for pattern in badPatterns {
            if lowercased.contains(pattern) {
                badPatternCount += 1
            }
        }
        if badPatternCount >= 2 {  // Only reject if multiple bad patterns present
            NSLog("⚠️ TL;DR rejected due to multiple bad patterns: \(badPatternCount)")
            return true
        }

        NSLog("✅ TLDR Validation: Response passed all checks")
        return false
    }

    /// Clear conversation history and context
    func clearConversation() {
        conversationHistory.clear()

        // OPTIMIZATION: Also reset MLXRunner conversation state
        Task {
            await providerManager.currentProvider?.resetConversation()
        }

        NSLog("🗑️ Conversation cleared")
    }

    /// Reset AI conversation state to recover from errors
    func resetConversationState() async {
        // Clear conversation history
        conversationHistory.clear()

        // Reset provider conversation state to prevent KV cache issues
        await providerManager.currentProvider?.resetConversation()

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
        if errorMessage.contains("inconsistent sequence positions")
            || errorMessage.contains("KV cache") || errorMessage.contains("decode")
        {
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
    @MainActor
    func configureHistoryContext(enabled: Bool, scope: HistoryContextScope) {
        contextManager.configureHistoryContext(enabled: enabled, scope: scope)
        NSLog(
            "🔍 AI Assistant history context configured: enabled=\(enabled), scope=\(scope.displayName)"
        )
    }

    /// Get current history context status
    @MainActor
    func getHistoryContextStatus() -> (enabled: Bool, scope: HistoryContextScope) {
        return (contextManager.isHistoryContextEnabled, contextManager.historyContextScope)
    }

    /// Clear history context for privacy
    @MainActor
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
            contextTokenCount: 0,  // Context processing will be added in Phase 11
            conversationLength: conversationHistory.messageCount,
            hardwareInfo: HardwareDetector.processorType.description,
            historyContextEnabled: historyContextInfo.enabled,
            historyContextScope: historyContextInfo.scope.displayName
        )
    }

    // MARK: - Private Methods
    private var hasSetupProviderBinding = false
    private func setupProviderBindingsOnce() {
        guard !hasSetupProviderBinding else { return }
        hasSetupProviderBinding = true
        providerManager.$currentProvider
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.isInitialized = false
                Task { await self.initialize() }
            }
            .store(in: &cancellables)
    }

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
                    Task { await self?.updateStatus("MLX AI model not available") }
                }
            }
            .store(in: &cancellables)

        // Bind download progress for status updates
        mlxModelService.$downloadProgress
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] progress in
                if progress > 0 && progress < 1.0 {
                    NSLog(
                        "🎯 MLX DOWNLOAD DEBUG: Model download progress: \(progress * 100)% - updating status"
                    )
                    Task {
                        await self?.updateStatus(
                            "Downloading MLX AI model: \(Int(progress * 100))%")
                    }
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
                    Task { await self?.updateStatus("MLX framework not available") }
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatus(_ status: String) async {
        initializationStatus = status
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
    let memoryUsage: Int  // MB
    let inferenceSpeed: Double  // tokens/second
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
