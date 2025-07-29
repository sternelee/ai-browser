import Foundation

/// Anthropic Claude provider implementing the AIProvider protocol
/// Supports Claude models with streaming and advanced reasoning
@MainActor
class AnthropicProvider: ExternalAPIProvider {
    
    // MARK: - AIProvider Implementation
    
    override var providerId: String { "anthropic" }
    override var displayName: String { "Anthropic Claude" }
    
    // MARK: - Anthropic Configuration
    
    private let baseURL = "https://api.anthropic.com/v1"
    private let userAgent = "Web-Browser/1.0"
    private let anthropicVersion = "2023-06-01"
    
    // MARK: - Rate Limiting
    
    private var lastRequestTime: Date = Date.distantPast
    private let minimumRequestInterval: TimeInterval = 0.2 // 5 requests per second max
    
    init() {
        super.init(apiProviderType: .anthropic)
    }
    
    // MARK: - Model Management
    
    override func loadAvailableModels() async {
        availableModels = [
            AIModel(
                id: "claude-3-5-sonnet-20241022",
                name: "Claude 3.5 Sonnet",
                description: "Most capable Claude model, excellent for complex tasks and reasoning",
                contextWindow: 200000,
                costPerToken: 0.000015, // $15 per 1M tokens (approximate)
                capabilities: [.textGeneration, .conversation, .summarization, .codeGeneration, .imageAnalysis, .functionCalling],
                provider: providerId,
                isAvailable: true
            ),
            AIModel(
                id: "claude-3-5-haiku-20241022",
                name: "Claude 3.5 Haiku",
                description: "Fastest Claude model, optimized for quick responses",
                contextWindow: 200000,
                costPerToken: 0.000001, // $1 per 1M tokens (approximate)
                capabilities: [.textGeneration, .conversation, .summarization, .codeGeneration],
                provider: providerId,
                isAvailable: true
            ),
            AIModel(
                id: "claude-3-opus-20240229",
                name: "Claude 3 Opus",
                description: "Most powerful Claude model for the most complex tasks",
                contextWindow: 200000,
                costPerToken: 0.000075, // $75 per 1M tokens (approximate)
                capabilities: [.textGeneration, .conversation, .summarization, .codeGeneration, .imageAnalysis, .functionCalling],
                provider: providerId,
                isAvailable: true
            )
        ]
        
        // Set default model
        if selectedModel == nil {
            selectedModel = availableModels.first { $0.id == "claude-3-5-sonnet-20241022" } ?? availableModels.first
        }
        
        NSLog("📋 Loaded \(availableModels.count) Anthropic models")
    }
    
    // MARK: - Configuration Validation
    
    override func validateConfiguration() async throws {
        guard let apiKey = apiKey else {
            throw AIProviderError.missingAPIKey(displayName)
        }
        
        // Test API key with a simple request
        let testPayload: [String: Any] = [
            "model": "claude-3-5-haiku-20241022",
            "max_tokens": 5,
            "messages": [
                ["role": "user", "content": "Hi"]
            ]
        ]
        
        do {
            let _ = try await makeAPIRequest(
                endpoint: "/messages",
                payload: testPayload
            )
            NSLog("✅ Anthropic API key validated")
        } catch {
            throw AIProviderError.authenticationFailed
        }
    }
    
    // MARK: - Core AI Methods
    
    override func generateResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        model: AIModel?
    ) async throws -> AIResponse {
        let startTime = Date()
        let modelId = model?.id ?? selectedModel?.id ?? "claude-3-5-sonnet-20241022"
        
        // Apply rate limiting
        await applyRateLimit()
        
        // Build messages
        let messages = buildMessages(query: query, context: context, history: conversationHistory)
        
        var payload: [String: Any] = [
            "model": modelId,
            "max_tokens": 4096,
            "messages": messages
        ]
        
        // Add system message if we have context
        if let context = context, !context.isEmpty {
            payload["system"] = "You are a helpful assistant. Answer questions based on the provided webpage content:\n\n\(context)"
        }
        
        do {
            let response = try await makeAPIRequest(
                endpoint: "/messages",
                payload: payload
            )
            
            guard let content = response["content"] as? [[String: Any]],
                  let firstContent = content.first,
                  let text = firstContent["text"] as? String else {
                throw AIProviderError.providerSpecificError("Invalid response format from Anthropic")
            }
            
            // Extract usage information
            var tokenCount = 0
            var cost: Double? = nil
            
            if let usage = response["usage"] as? [String: Any] {
                let inputTokens = usage["input_tokens"] as? Int ?? 0
                let outputTokens = usage["output_tokens"] as? Int ?? 0
                tokenCount = inputTokens + outputTokens
                
                if let modelInfo = availableModels.first(where: { $0.id == modelId }),
                   let costPerToken = modelInfo.costPerToken {
                    cost = Double(tokenCount) * costPerToken
                }
            }
            
            let responseTime = Date().timeIntervalSince(startTime)
            updateUsageStats(
                tokenCount: tokenCount,
                responseTime: responseTime,
                cost: cost,
                error: false
            )
            
            // Create metadata for external API response
            let metadata = ResponseMetadata(
                modelVersion: modelId,
                inferenceMethod: .fallback,
                contextUsed: context != nil,
                processingSteps: [],
                memoryUsage: 0,
                energyImpact: responseTime > 5.0 ? .moderate : .low
            )
            
            // Return AIResponse compatible with existing system
            return AIResponse(
                text: text,
                processingTime: responseTime,
                tokenCount: tokenCount,
                metadata: metadata
            )
            
        } catch {
            let responseTime = Date().timeIntervalSince(startTime)
            updateUsageStats(tokenCount: 0, responseTime: responseTime, error: true)
            throw handleAPIError(error)
        }
    }
    
    override func generateStreamingResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        model: AIModel?
    ) async throws -> AsyncThrowingStream<String, Error> {
        let modelId = model?.id ?? selectedModel?.id ?? "claude-3-5-sonnet-20241022"
        
        // Apply rate limiting
        await applyRateLimit()
        
        // Build messages
        let messages = buildMessages(query: query, context: context, history: conversationHistory)
        
        var payload: [String: Any] = [
            "model": modelId,
            "max_tokens": 4096,
            "messages": messages,
            "stream": true
        ]
        
        // Add system message if we have context
        if let context = context, !context.isEmpty {
            payload["system"] = "You are a helpful assistant. Answer questions based on the provided webpage content:\n\n\(context)"
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = try await makeStreamingAPIRequest(
                        endpoint: "/messages",
                        payload: payload
                    )
                    
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: handleAPIError(error))
                }
            }
        }
    }
    
    override func generateRawResponse(
        prompt: String,
        model: AIModel?
    ) async throws -> String {
        let modelId = model?.id ?? selectedModel?.id ?? "claude-3-5-sonnet-20241022"
        
        await applyRateLimit()
        
        let payload: [String: Any] = [
            "model": modelId,
            "max_tokens": 2048,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        
        let response = try await makeAPIRequest(
            endpoint: "/messages",
            payload: payload
        )
        
        guard let content = response["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw AIProviderError.providerSpecificError("Invalid response format from Anthropic")
        }
        
        return text
    }
    
    override func summarizeConversation(
        _ messages: [ConversationMessage],
        model: AIModel?
    ) async throws -> String {
        let conversationText = messages.map { "\($0.role.description): \($0.content)" }.joined(separator: "\n")
        
        let summaryPrompt = """
        Summarize the following conversation in 2-3 sentences, focusing on the main topics and outcomes:
        
        \(conversationText)
        
        Summary:
        """
        
        return try await generateRawResponse(prompt: summaryPrompt, model: model)
    }
    
    // MARK: - API Communication
    
    private func makeAPIRequest(
        endpoint: String,
        payload: [String: Any]
    ) async throws -> [String: Any] {
        guard let apiKey = apiKey else {
            throw AIProviderError.missingAPIKey(displayName)
        }
        
        guard let url = URL(string: baseURL + endpoint) else {
            throw AIProviderError.invalidConfiguration("Invalid API endpoint")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AIProviderError.invalidConfiguration("Failed to serialize request")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.networkError(URLError(.badServerResponse))
        }
        
        // Handle HTTP errors
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw AIProviderError.authenticationFailed
        case 429:
            throw AIProviderError.rateLimitExceeded
        default:
            throw AIProviderError.providerSpecificError("HTTP \(httpResponse.statusCode)")
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AIProviderError.providerSpecificError("Invalid JSON response")
            }
            return json
        } catch {
            throw AIProviderError.providerSpecificError("Failed to parse response")
        }
    }
    
    private func makeStreamingAPIRequest(
        endpoint: String,
        payload: [String: Any]
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let apiKey = apiKey else {
            throw AIProviderError.missingAPIKey(displayName)
        }
        
        guard let url = URL(string: baseURL + endpoint) else {
            throw AIProviderError.invalidConfiguration("Invalid API endpoint")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        throw AIProviderError.networkError(URLError(.badServerResponse))
                    }
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6))
                            
                            if let jsonData = data.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                                
                                // Handle different event types
                                if let type = json["type"] as? String {
                                    switch type {
                                    case "content_block_delta":
                                        if let delta = json["delta"] as? [String: Any],
                                           let text = delta["text"] as? String {
                                            continuation.yield(text)
                                        }
                                    case "message_stop":
                                        // End of stream
                                        break
                                    default:
                                        // Ignore other event types
                                        break
                                    }
                                }
                            }
                        }
                    }
                    
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func buildMessages(
        query: String,
        context: String?,
        history: [ConversationMessage]
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        
        // Recent conversation history (last 10 messages)
        let recentHistory = Array(history.suffix(10))
        for message in recentHistory {
            let role = message.role == .user ? "user" : "assistant"
            messages.append([
                "role": role,
                "content": [
                    ["type": "text", "text": message.content]
                ]
            ])
        }
        
        // Current query
        var queryContent: [[String: Any]] = [
            ["type": "text", "text": query]
        ]
        
        messages.append([
            "role": "user",
            "content": queryContent
        ])
        
        return messages
    }
    
    private func applyRateLimit() async {
        let timeSinceLastRequest = Date().timeIntervalSince(lastRequestTime)
        if timeSinceLastRequest < minimumRequestInterval {
            let delay = minimumRequestInterval - timeSinceLastRequest
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        lastRequestTime = Date()
    }
    
    private func handleAPIError(_ error: Error) -> Error {
        if let urlError = error as? URLError {
            return AIProviderError.networkError(urlError)
        }
        return AIProviderError.providerSpecificError(error.localizedDescription)
    }
    
    // MARK: - Settings
    
    override func getConfigurableSettings() -> [AIProviderSetting] {
        return [
            AIProviderSetting(
                id: "model_selection",
                name: "Model",
                description: "Select the Claude model to use",
                type: .selection(availableModels.map { $0.name }),
                defaultValue: "Claude 3.5 Sonnet",
                currentValue: selectedModel?.name ?? "Claude 3.5 Sonnet",
                isRequired: true
            ),
            AIProviderSetting(
                id: "max_tokens",
                name: "Max Tokens",
                description: "Maximum tokens in response (1-4096)",
                type: .number,
                defaultValue: 4096,
                currentValue: 4096,
                isRequired: false
            )
        ]
    }
}