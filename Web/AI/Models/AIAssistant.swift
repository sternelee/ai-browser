import Combine
import Foundation
import WebKit

/// Main AI Assistant coordinator managing local AI capabilities
/// Integrates MLX framework with context management and conversation handling
@MainActor
class AIAssistant: ObservableObject {

    // MARK: - Published Properties (Main Actor for UI Updates)

    @MainActor @Published var isInitialized: Bool = false
    @MainActor @Published var isProcessing: Bool = false
    @MainActor @Published var initializationStatus: String = "Not initialized"
    // Agent timeline state (for Agent mode in the sidebar)
    @MainActor @Published var currentAgentRun: AgentRun?
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
        AppLog.debug("AI Assistant init: framework=\(aiConfiguration.framework)")
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
                    AppLog.debug("MLX model needs download: \(downloadInfo.formattedSize)")
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
                                AppLog.error(
                                    "MLX initialization failed: \(error.localizedDescription)")
                            }
                        }
                    }
                    group.addTask { [weak self] in
                        guard let self else { return }
                        do {
                            await self.updateStatus("Setting up privacy protection...")
                            try await self.privacyManager.initialize()
                        } catch {
                            AppLog.error(
                                "Privacy manager init failed: \(error.localizedDescription)")
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
            AppLog.debug("AI Assistant initialization complete")

        } catch {
            let errorMessage = "AI initialization failed: \(error.localizedDescription)"
            await updateStatus("Initialization failed")
            Task { @MainActor in
                lastError = errorMessage
                isInitialized = false
            }
            AppLog.error(errorMessage)
        }
    }

    // MARK: - Agent Planning (M2 minimal)

    /// Plans a sequence of PageAction steps from a natural language query using the current provider.
    func planAgentActions(from query: String) async throws -> [PageAction] {
        guard let provider = providerManager.currentProvider else {
            throw AIError.inferenceError("No AI provider available")
        }

        let schemaSnippet = """
            Output ONLY JSON: an array of objects where each object is a PageAction with keys:
            - type: one of ["navigate","findElements","click","typeText","scroll","select","waitFor","extract"]
            - locator: optional object with keys [role,name,text,css,xpath,near,nth]
            - url: string (for navigate)
            - newTab: boolean (for navigate)
            - text: string (for typeText or waitFor.selector)
            - value: string (for select)
            - direction: string (for scroll; "down"|"up" or "ready" for waitFor.readyState)
            - amountPx: number (for scroll) or delayMs when using waitFor
            - submit: boolean (for typeText)
            - timeoutMs: number (for waitFor)
            Keep actions safe and deterministic. Prefer semantic locators (text/name/role) before css. Do not include prose.
            Example:
            [
              {"type":"navigate","url":"https://www.zara.com","newTab":false},
              {"type":"waitFor","direction":"ready","timeoutMs":8000},
              {"type":"typeText","locator":{"role":"textbox","name":"Search"},"text":"sweater", "submit":true},
              {"type":"waitFor","direction":"ready","timeoutMs":8000},
              {"type":"click","locator":{"text":"Add to cart","nth":0}}
            ]
            """

        let prompt = """
            You are a planning assistant for a browser automation agent. Given the user request, output JSON ONLY containing a PageAction array that is safe and minimal to accomplish the intent on the CURRENT page context. Avoid destructive actions. Prefer steps like waitFor ready-state between navigations and clicks.

            User request:
            \(query)

            \(schemaSnippet)
            """

        let raw = try await provider.generateRawResponse(
            prompt: prompt, model: provider.selectedModel)
        if let plan = Self.decodePlan(from: raw) { return plan }
        throw AIError.inferenceError("Model did not return a valid PageAction JSON plan")
    }

    /// Plans and executes the agent steps with a live timeline.
    func planAndRunAgent(_ query: String) async {
        NSLog("🛰️ Agent: Planning for query: \(query.prefix(200))")
        do {
            // Fast-path: accept dev /plan JSON directly
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            var plan: [PageAction]
            if trimmed.hasPrefix("/plan ") {
                let json = String(trimmed.dropFirst(6))
                if let data = json.data(using: .utf8),
                    let parsed = try? JSONDecoder().decode([PageAction].self, from: data)
                {
                    plan = parsed
                } else {
                    throw AIError.inferenceError("Invalid /plan JSON format")
                }
            } else {
                plan = try await planAgentActions(from: query)
            }
            if plan.isEmpty, let fallback = Self.heuristicPlan(for: query) {
                NSLog(
                    "🛰️ Agent: Model returned empty plan, using heuristic fallback plan (\(fallback.count) steps)"
                )
                plan = fallback
            }
            NSLog("🛰️ Agent: Plan decoded with \(plan.count) steps")
            await MainActor.run {
                var steps: [AgentStep] = []
                // Add a leading pseudo-step to show user's instruction in the timeline
                let userStep = AgentStep(
                    id: UUID(),
                    action: PageAction(type: .askUser, text: query),
                    state: .success,
                    message: nil
                )
                steps.append(userStep)
                steps.append(
                    contentsOf: plan.map {
                        AgentStep(id: $0.id, action: $0, state: .planned, message: nil)
                    })
                self.currentAgentRun = AgentRun(
                    id: UUID(), title: query, steps: steps, startedAt: Date(), finishedAt: nil)
            }

            let (maybeWebView, host) = await MainActor.run { () -> (WKWebView?, String?) in
                (self.tabManager?.activeTab?.webView, self.tabManager?.activeTab?.url?.host)
            }
            guard let webView = maybeWebView else {
                await MainActor.run { self.markTimelineFailureForAll(message: "no webview") }
                return
            }

            let agent = PageAgent(webView: webView)
            for (idx, step) in plan.enumerated() {
                // Policy gate and consent
                let decision = AgentPermissionManager.shared.evaluate(
                    intent: step.type, urlHost: host)
                if !decision.allowed {
                    let consent = await self.callAgentTool(
                        name: "askUser",
                        arguments: [
                            "prompt": "Confirm: \(step.type.rawValue) on \(host ?? "site")?",
                            "choices": ["Allow once", "Cancel"],
                            "default": 1,
                            "timeoutMs": 15000,
                        ])
                    let allowed = consent.ok && ((consent.data?["choiceIndex"]?.value as? Int) == 0)
                    if !allowed {
                        await MainActor.run {
                            self.updateTimelineStep(
                                index: idx, state: .failure, message: decision.reason ?? "blocked")
                            self.currentAgentRun?.finishedAt = Date()
                        }
                        return
                    }
                }

                await MainActor.run { self.updateTimelineStep(index: idx, state: .running) }
                NSLog("🛰️ Agent: Running step \(idx + 1)/\(plan.count): \(step.type.rawValue)")
                let resultArray = await agent.execute(plan: [step])
                let r = resultArray.first
                await MainActor.run {
                    self.updateTimelineStep(
                        index: idx, state: (r?.success == true) ? .success : .failure,
                        message: r?.message)
                }
                NSLog(
                    "🛰️ Agent: Step \(idx + 1) result => success=\(r?.success == true), message=\(r?.message ?? "nil")"
                )
            }
            await MainActor.run { self.currentAgentRun?.finishedAt = Date() }
            NSLog("🛰️ Agent: Finished agent run")
        } catch {
            // Try a heuristic plan if planning failed
            if let fallback = Self.heuristicPlan(for: query) {
                NSLog(
                    "🛰️ Agent: Planning failed (\(error.localizedDescription)). Using heuristic fallback plan (\(fallback.count) steps)"
                )
                await MainActor.run {
                    var steps: [AgentStep] = []
                    let userStep = AgentStep(
                        id: UUID(),
                        action: PageAction(type: .askUser, text: query),
                        state: .success,
                        message: nil
                    )
                    steps.append(userStep)
                    steps.append(
                        contentsOf: fallback.map {
                            AgentStep(id: $0.id, action: $0, state: .planned, message: nil)
                        })
                    self.currentAgentRun = AgentRun(
                        id: UUID(), title: query, steps: steps, startedAt: Date(), finishedAt: nil)
                }
                let (maybeWebView, host) = await MainActor.run { () -> (WKWebView?, String?) in
                    (self.tabManager?.activeTab?.webView, self.tabManager?.activeTab?.url?.host)
                }
                guard let webView = maybeWebView else {
                    await MainActor.run { self.markTimelineFailureForAll(message: "no webview") }
                    return
                }
                let agent = PageAgent(webView: webView)
                for (idx, step) in fallback.enumerated() {
                    let decision = AgentPermissionManager.shared.evaluate(
                        intent: step.type, urlHost: host)
                    if !decision.allowed {
                        await MainActor.run {
                            self.updateTimelineStep(
                                index: idx, state: .failure, message: decision.reason ?? "blocked")
                            self.currentAgentRun?.finishedAt = Date()
                        }
                        return
                    }
                    await MainActor.run { self.updateTimelineStep(index: idx, state: .running) }
                    NSLog(
                        "🛰️ Agent: (fallback) Running step \(idx + 1)/\(fallback.count): \(step.type.rawValue)"
                    )
                    let r = (await agent.execute(plan: [step])).first
                    await MainActor.run {
                        self.updateTimelineStep(
                            index: idx, state: (r?.success == true) ? .success : .failure,
                            message: r?.message)
                    }
                }
                await MainActor.run { self.currentAgentRun?.finishedAt = Date() }
                NSLog("🛰️ Agent: Finished heuristic fallback run")
                return
            }

            NSLog("❌ Agent: Planning failed with error: \(error.localizedDescription)")
            await MainActor.run {
                // Surface a visible failure row instead of an empty timeline
                var failureStep = PageAction(type: .askUser)
                let failure = AgentStep(
                    id: failureStep.id, action: failureStep, state: .failure,
                    message: "planning failed")
                self.currentAgentRun = AgentRun(
                    id: UUID(), title: query, steps: [failure], startedAt: Date(),
                    finishedAt: Date())
            }
        }
    }

    @MainActor private func markTimelineFailureForAll(message: String) {
        guard var run = currentAgentRun else { return }
        for i in run.steps.indices {
            run.steps[i].state = .failure
            run.steps[i].message = message
        }
        run.finishedAt = Date()
        currentAgentRun = run
    }

    @MainActor private func updateTimelineStep(
        index: Int, state: AgentStepState, message: String? = nil
    ) {
        guard var run = currentAgentRun, index < run.steps.count else { return }
        run.steps[index].state = state
        if let message { run.steps[index].message = message }
        currentAgentRun = run
    }

    private static func decodePlan(from raw: String) -> [PageAction]? {
        // Try direct decode
        if let data = raw.data(using: .utf8),
            let plan = try? JSONDecoder().decode([PageAction].self, from: data)
        {
            return plan
        }
        // Strip code fences
        let stripped = raw.replacingOccurrences(of: "```json", with: "").replacingOccurrences(
            of: "```", with: "")
        if let data = stripped.data(using: .utf8),
            let plan = try? JSONDecoder().decode([PageAction].self, from: data)
        {
            return plan
        }
        // Extract first JSON array substring
        if let start = raw.firstIndex(of: "[") {
            if let end = raw.lastIndex(of: "]"), end >= start {
                let slice = raw[start...end]
                if let data = String(slice).data(using: .utf8),
                    let plan = try? JSONDecoder().decode([PageAction].self, from: data)
                {
                    return plan
                }
            }
        }
        return nil
    }

    // MARK: - Heuristic plan (safety-first)
    private static func heuristicPlan(for query: String) -> [PageAction]? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        func mkWait(_ ms: Int) -> PageAction {
            PageAction(
                type: .waitFor, direction: "ready", amountPx: nil, submit: nil, value: nil,
                timeoutMs: ms)
        }
        if q.hasPrefix("search ") || q.hasPrefix("search for ") || q.hasPrefix("enter ")
            || q.hasPrefix("look up ") || q.hasPrefix("find ")
        {
            var term =
                q
                .replacingOccurrences(of: "search for ", with: "")
                .replacingOccurrences(of: "search ", with: "")
                .replacingOccurrences(of: "enter ", with: "")
                .replacingOccurrences(of: "look up ", with: "")
                .replacingOccurrences(of: "find ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if term.isEmpty { return nil }
            let locator = LocatorInput(role: "textbox")
            return [
                PageAction(type: .waitFor, direction: "ready", timeoutMs: 8000),
                PageAction(type: .typeText, locator: locator, text: term, submit: true),
                PageAction(type: .waitFor, direction: "ready", timeoutMs: 8000),
            ]
        }
        if q.hasPrefix("go to ") || q.hasPrefix("open ") || q.hasPrefix("navigate to ") {
            var target =
                q
                .replacingOccurrences(of: "go to ", with: "")
                .replacingOccurrences(of: "open ", with: "")
                .replacingOccurrences(of: "navigate to ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if target.isEmpty { return nil }
            if !target.contains(".") { target += ".com" }
            if !target.hasPrefix("http") { target = "https://" + target }
            return [
                PageAction(type: .navigate, url: target, newTab: false),
                PageAction(type: .waitFor, direction: "ready", timeoutMs: 8000),
            ]
        }
        return nil
    }

    /// Process a user query with current context and optional history
    func processQuery(_ query: String, includeContext: Bool = true, includeHistory: Bool = true)
        async throws -> AIResponse
    {
        guard await isInitialized else {
            throw AIError.notInitialized
        }

        AppLog.debug("AI Chat: Processing query (includeContext=\(includeContext))")

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
                AppLog.debug(
                    "AI Chat: Extracted context: \(webpageContext.text.count) chars, q=\(webpageContext.contentQuality)"
                )
                if includeContext && isContentTooGarbled(webpageContext.text) {
                    AppLog.debug("AI Chat: Page content noisy; using title-only context")
                }
            } else {
                AppLog.debug("AI Chat: No webpage context extracted")
            }

            let context =
                includeContext
                ? await contextManager.getFormattedContext(
                    from: webpageContext, includeHistory: includeHistory) : nil
            if let context = context {
                AppLog.debug("AI Chat: Using formatted context (\(context.count) chars)")
            } else {
                AppLog.debug("AI Chat: No context provided to model")
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
            AppLog.error("Query processing failed: \(error.localizedDescription)")
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
                        AppLog.debug(
                            "Streaming: context=\(webpageContext.text.count) q=\(webpageContext.contentQuality)"
                        )
                    } else {
                        AppLog.debug("Streaming: No webpage context extracted")
                    }

                    let context = await self.contextManager.getFormattedContext(
                        from: webpageContext, includeHistory: includeHistory && includeContext)
                    if let context = context {
                        AppLog.debug("Streaming: formatted context=\(context.count)")
                    } else {
                        AppLog.debug("Streaming: No formatted context returned")
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
                    AppLog.error("Streaming error: \(error.localizedDescription)")

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

    // MARK: - Agent Tool Execution
    /// Execute a provider-agnostic tool call object via `ToolRegistry` against the active tab's webview.
    private func executeToolCall(_ call: ToolRegistry.ToolCall) async
        -> ToolRegistry.ToolObservation
    {
        guard let webView = await MainActor.run(body: { self.tabManager?.activeTab?.webView })
        else {
            return ToolRegistry.ToolObservation(
                name: call.name, ok: false, data: nil, message: "no webview")
        }
        return await ToolRegistry.shared.executeTool(call, webView: webView)
    }

    /// Execute a plan of `PageAction`s through `PageAgent` on the active tab (headed mode).
    /// Includes a minimal permission gate per action.
    func runAgentPlan(_ plan: [PageAction]) async -> [ActionResult] {
        let (maybeWebView, host) = await MainActor.run { () -> (WKWebView?, String?) in
            let currentHost = self.tabManager?.activeTab?.url?.host
            return (self.tabManager?.activeTab?.webView, currentHost)
        }
        guard let webView = maybeWebView else { return [] }

        let agent = PageAgent(webView: webView)
        var gatedPlan: [PageAction] = []
        for step in plan {
            let decision = AgentPermissionManager.shared.evaluate(intent: step.type, urlHost: host)
            if decision.allowed {
                gatedPlan.append(step)
                AgentAuditLog.shared.append(
                    host: host,
                    action: step.type.rawValue,
                    parameters: summarize(step),
                    policyAllowed: true,
                    policyReason: nil,
                    requestedConsent: false,
                    userConsented: nil,
                    outcomeSuccess: nil,
                    outcomeMessage: nil
                )
            } else {
                AgentAuditLog.shared.append(
                    host: host,
                    action: step.type.rawValue,
                    parameters: summarize(step),
                    policyAllowed: false,
                    policyReason: decision.reason,
                    requestedConsent: true,
                    userConsented: nil,
                    outcomeSuccess: nil,
                    outcomeMessage: nil
                )

                let consent = await callAgentTool(
                    name: "askUser",
                    arguments: [
                        "prompt": "Confirm: \(step.type.rawValue) on \(host ?? "site")?",
                        "choices": ["Allow once", "Cancel"],
                        "default": 1,
                        "timeoutMs": 15000,
                    ]
                )
                let userConsented =
                    consent.ok && ((consent.data?["choiceIndex"]?.value as? Int) == 0)
                AgentAuditLog.shared.append(
                    host: host,
                    action: step.type.rawValue,
                    parameters: summarize(step),
                    policyAllowed: false,
                    policyReason: decision.reason,
                    requestedConsent: true,
                    userConsented: userConsented,
                    outcomeSuccess: nil,
                    outcomeMessage: userConsented ? "user allowed" : "user canceled"
                )

                if userConsented {
                    gatedPlan.append(step)
                } else {
                    let failure = ActionResult(
                        actionId: step.id, success: false, message: decision.reason ?? "blocked")
                    var partial: [ActionResult] = []
                    if !gatedPlan.isEmpty {
                        let prior = await agent.execute(plan: gatedPlan)
                        partial.append(contentsOf: prior)
                    }
                    partial.append(failure)
                    return partial
                }
            }
        }
        let results = await agent.execute(plan: gatedPlan)
        for (idx, step) in gatedPlan.enumerated() {
            let r = (idx < results.count) ? results[idx] : nil
            AgentAuditLog.shared.append(
                host: host,
                action: step.type.rawValue,
                parameters: summarize(step),
                policyAllowed: true,
                policyReason: nil,
                requestedConsent: false,
                userConsented: nil,
                outcomeSuccess: r?.success,
                outcomeMessage: r?.message
            )
        }
        return results
    }

    /// Convenience: call an agent tool by name with arguments on the active tab.
    /// Example names: navigate, findElements, click, typeText, select, scroll, waitFor.
    func callAgentTool(name: String, arguments: [String: Any]) async -> ToolRegistry.ToolObservation
    {
        // Minimal intent classification: map tool name to PageActionType for policy check
        let intent: PageActionType? = {
            switch name {
            case "navigate": return .navigate
            case "findElements": return .findElements
            case "click": return .click
            case "typeText": return .typeText
            case "select": return .select
            case "scroll": return .scroll
            case "waitFor": return .waitFor
            case "extract": return .extract
            case "switchTab": return .switchTab
            case "askUser": return .askUser
            default: return nil
            }
        }()

        let host = await MainActor.run { self.tabManager?.activeTab?.url?.host }
        if let intent = intent {
            let decision = AgentPermissionManager.shared.evaluate(intent: intent, urlHost: host)
            guard decision.allowed else {
                return ToolRegistry.ToolObservation(
                    name: name, ok: false, data: nil, message: decision.reason ?? "blocked")
            }
        }

        let wrappedArgs = arguments.mapValues { AnyCodable($0) }
        let call = ToolRegistry.ToolCall(name: name, arguments: wrappedArgs)
        return await executeToolCall(call)
    }

    // MARK: - Helpers
    private func summarize(_ step: PageAction) -> [String: String] {
        var dict: [String: String] = [:]
        if let url = step.url { dict["url"] = url }
        if let t = step.text { dict["text"] = String(t.prefix(80)) }
        if let v = step.value { dict["value"] = v }
        if let dir = step.direction { dict["direction"] = dir }
        if let amt = step.amountPx { dict["amountPx"] = String(amt) }
        if let submit = step.submit { dict["submit"] = submit ? "true" : "false" }
        if let loc = step.locator {
            var l: [String] = []
            if let role = loc.role { l.append("role=\(role)") }
            if let name = loc.name { l.append("name=\(name)") }
            if let text = loc.text { l.append("text=\(text.prefix(40))") }
            if let css = loc.css { l.append("css=\(css.prefix(40))") }
            if let nth = loc.nth { l.append("nth=\(nth)") }
            dict["locator"] = l.joined(separator: " ")
        }
        return dict
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
            AppLog.warn("TL;DR: No context available")
            throw AIError.contextProcessingFailed("No content available to summarize")
        }

        // Check for low-quality content that would confuse the model
        if isContentTooGarbled(context.text) {
            AppLog.debug("TL;DR: Content appears garbled; simplifying")
            return
                "📄 Page content detected but contains mostly code/markup. Unable to generate meaningful summary."
        }

        AppLog.debug(
            "TL;DR: Using context (len=\(context.text.count), q=\(context.contentQuality))")

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
                AppLog.debug("TL;DR: Invalid response; retrying")

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
                    AppLog.debug("TL;DR: Fallback invalid; attempting salvage")
                    let salvaged = gemmaService.postProcessForTLDR(fallbackClean)
                    if isInvalidTLDRResponse(salvaged) {
                        AppLog.debug("TL;DR: All attempts failed; returning fallback message")
                        // IMPROVED: Give a more informative message instead of generic error
                        return
                            "📄 Page content detected but summary generation encountered issues. Try refreshing the page."
                    }
                    return salvaged
                }

                return fallbackClean
            } else {
                AppLog.debug("TL;DR: Success on first attempt")
            }

            return cleanResponse

        } catch {
            AppLog.error("TL;DR generation failed: \(error.localizedDescription)")
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
                        AppLog.warn("TL;DR Streaming: No context available")
                        throw AIError.contextProcessingFailed("No content available to summarize")
                    }

                    AppLog.debug(
                        "TL;DR Streaming: Using context len=\(context.text.count) q=\(context.contentQuality)"
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
                    if AppLog.isVerboseEnabled {
                        AppLog.debug(
                            "FULL TLDR PROMPT (truncated)\n\(String(tldrPrompt.prefix(1200)))")
                    }

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
                        AppLog.debug("TL;DR Streaming: Invalid response; post-processing")
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
                        AppLog.debug("TL;DR Streaming: No content; yielding fallback")
                        continuation.yield(
                            "📄 Page content detected but summary generation is processing...")
                    }

                    continuation.finish()
                    AppLog.debug("TL;DR Streaming completed (len=\(accumulatedResponse.count))")

                } catch {
                    AppLog.error("TL;DR Streaming failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Check if content is too garbled with JavaScript/HTML to be useful
    private func isContentTooGarbled(_ content: String) -> Bool {
        let lowercased = content.lowercased()
        let totalLength = content.count

        if AppLog.isVerboseEnabled {
            AppLog.debug("Garbage detect (len=\(totalLength)): '\(content.prefix(100))…'")
        }

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

        if AppLog.isVerboseEnabled {
            AppLog.debug(
                "Garbage analysis: js=\(jsRatio), punct=\(punctuationRatio), readable=\(readableWordsRatio), len=\(totalLength), patterns=\(detectedPatterns.joined(separator: ", ")), isGarbage=\(isGarbage)"
            )
        }

        return isGarbage
    }

    /// Clean and prepare content specifically for TLDR generation
    private func cleanContentForTLDR(_ content: String) -> String {
        var cleaned = content

        if AppLog.isVerboseEnabled { AppLog.debug("Clean input: len=\(content.count)") }

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
                if AppLog.isVerboseEnabled {
                    AppLog.debug("Pattern removed: \(pattern) -> \(removed)")
                }
            }
        }

        if AppLog.isVerboseEnabled { AppLog.debug("Total removed: \(removedCount)") }

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

        if AppLog.isVerboseEnabled { AppLog.debug("After word filter len=\(cleaned.count)") }

        // Limit length for better model performance
        if cleaned.count > 600 {  // Reduced from 800 for better performance
            cleaned = String(cleaned.prefix(600))
            if AppLog.isVerboseEnabled { AppLog.debug("Truncated to 600 chars") }
        }

        if AppLog.isVerboseEnabled { AppLog.debug("Clean final len=\(cleaned.count)") }
        return cleaned
    }

    /// Check if TL;DR response contains repetitive or invalid patterns
    private func isInvalidTLDRResponse(_ response: String) -> Bool {
        let lowercased = response.lowercased()

        if AppLog.isVerboseEnabled { AppLog.debug("TLDR validation: len=\(response.count)") }

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
            AppLog.debug("TLDR validation: too short (\(response.count))")
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
            AppLog.debug("TLDR validation: word repetition")
            return true
        }

        // IMPROVED: Only flag phrase repetition if it's very excessive (5+ times instead of 3+)
        // This allows some natural repetition while catching obvious loops
        let phrasePattern = "(\\b(?:\\w+\\s+){2,5}\\w+\\b)(?:\\s+\\1){4,}"  // 5+ repetitions instead of 3+
        if lowercased.range(of: phrasePattern, options: [.regularExpression]) != nil {
            AppLog.debug("TLDR validation: phrase repetition")
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
                AppLog.debug("TLDR validation: high repetition ratio \(repetitionRatio)")
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
            AppLog.debug("TLDR validation: multiple bad patterns \(badPatternCount)")
            return true
        }

        if AppLog.isVerboseEnabled { AppLog.debug("TLDR validation: passed") }
        return false
    }

    /// Clear conversation history and context
    func clearConversation() {
        conversationHistory.clear()

        // OPTIMIZATION: Also reset MLXRunner conversation state
        Task {
            await providerManager.currentProvider?.resetConversation()
        }

        AppLog.debug("Conversation cleared")
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

        AppLog.debug("AI conversation state reset")
    }

    /// Handle AI errors with automatic recovery
    private func handleAIError(_ error: Error) async {
        let errorMessage = error.localizedDescription
        AppLog.error("AI Error: \(errorMessage)")

        await MainActor.run {
            lastError = errorMessage
            isProcessing = false
        }

        // Auto-recovery for common errors
        if errorMessage.contains("inconsistent sequence positions")
            || errorMessage.contains("KV cache") || errorMessage.contains("decode")
        {
            AppLog.debug("Detected conversation state error; auto-recover")
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
            AppLog.warn("AI Health check failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Configure history context settings
    @MainActor
    func configureHistoryContext(enabled: Bool, scope: HistoryContextScope) {
        contextManager.configureHistoryContext(enabled: enabled, scope: scope)
        AppLog.debug("History context configured: enabled=\(enabled) scope=\(scope.displayName)")
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
        AppLog.debug("History context cleared")
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
                    if AppLog.isVerboseEnabled {
                        AppLog.debug("MLX download progress: \(progress * 100)%")
                    }
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
        if AppLog.isVerboseEnabled { AppLog.debug("AI Status: \(status)") }
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

// MARK: - Agent timeline models (UI-facing)
enum AgentStepState: String, Codable, Equatable {
    case planned
    case running
    case success
    case failure
}

struct AgentStep: Identifiable, Codable, Equatable {
    let id: UUID
    var action: PageAction
    var state: AgentStepState
    var message: String?
}

struct AgentRun: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var steps: [AgentStep]
    var startedAt: Date
    var finishedAt: Date?
}

extension AgentStep {
    static func == (lhs: AgentStep, rhs: AgentStep) -> Bool {
        return lhs.id == rhs.id && lhs.state == rhs.state && lhs.message == rhs.message
    }
}

extension AgentRun {
    static func == (lhs: AgentRun, rhs: AgentRun) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title && lhs.steps == rhs.steps
            && lhs.finishedAt == rhs.finishedAt
    }
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
